'use strict';

/*
 * Tdarr flow plugin: convert WebVTT subtitle tracks in an MKV to SRT.
 *
 * Tdarr's ffmpeg cannot copy S_TEXT/WEBVTT tracks ("Subtitle codec 0 is not supported"), which fails every
 * later ffmpeg step in a flow. Plain ffmpeg conversion is not safe either: these files pack many cues
 * without blank lines between them, so ffmpeg merges the cues and leaves timestamps in the text.
 *
 * This plugin parses on timestamp lines, muxes with mkvmerge into the work folder, and checks the result.
 * The original file is never written. Any failed check throws, which takes the flow's error edge.
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const WEBVTT_CODEC = 'S_TEXT/WEBVTT';
const DURATION_TOLERANCE = 0.005;
const MAX_STDOUT_BYTES = 64 * 1024 * 1024;
const MAX_IDENTIFIER_WORDS = 3;

const STAMP = /^\s*((?:\d+:)?\d{2}:\d{2})\.(\d{3})\s+-->\s+((?:\d+:)?\d{2}:\d{2})\.(\d{3})(?:\s.*)?$/;
const ENTITIES = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&nbsp;': ' ', '&lrm;': '', '&rlm;': '',
};

const details = () => ({
  name: 'Convert WebVTT Subtitles to SRT',
  description: 'Converts WebVTT tracks in an MKV to SRT with mkvmerge and checks every cue and word. '
    + 'WebVTT tracks in other languages are removed. Files without WebVTT pass through untouched.',
  style: { borderColor: 'orange' },
  tags: 'subtitle,mkvmerge',
  isStartPlugin: false,
  pType: '',
  requiresVersion: '2.11.01',
  sidebarPosition: -1,
  icon: 'faClosedCaptioning',
  inputs: [
    {
      label: 'Languages to keep',
      name: 'keepLanguages',
      type: 'string',
      defaultValue: 'eng',
      inputUI: { type: 'text' },
      tooltip: 'Comma separated ISO-639-2 codes. WebVTT tracks in these languages, or with no language, are '
        + 'converted. Other WebVTT tracks are removed. Other subtitle formats are left alone.',
    },
  ],
  outputs: [
    { number: 1, tooltip: 'Continue. File has no WebVTT, or was converted and passed its checks.' },
  ],
});

const pad = (stamp) => (stamp.split(':').length === 2 ? `00:${stamp}` : stamp);

// Removes WebVTT-only markup and keeps the tags SRT players understand.
const cleanText = (line) => line
  .replace(/<(?!\/?[ibu]>)[^>]*>/g, '')
  .replace(/&(?:amp|lt|gt|quot|apos|nbsp|lrm|rlm);/g, (entity) => ENTITIES[entity]);

const countWords = (text) => (text.match(/[\p{L}\p{N}']+/gu) || []).length;

const looksLikeIdentifier = (lines, index) => {
  const previous = index === 0 ? '' : lines[index - 1];
  return previous.trim() === ''
    && index + 1 < lines.length
    && STAMP.test(lines[index + 1])
    && countWords(lines[index]) <= MAX_IDENTIFIER_WORDS;
};

// Returns { srt, stats }. Throws if a line could not be accounted for.
const convertVttText = (source) => {
  const lines = source.replace(/^﻿/, '').replace(/\r/g, '').split('\n');
  const cues = [];
  let current = null;
  let skippingBlock = false;
  let stamps = 0;
  let identifiers = 0;
  let sourceWords = 0;

  lines.forEach((line, index) => {
    const blank = line.trim() === '';
    const previousBlank = index === 0 || lines[index - 1].trim() === '';

    if (blank) {
      skippingBlock = false;
      return;
    }
    if (skippingBlock) return;

    const match = line.match(STAMP);
    if (match) {
      stamps += 1;
      current = { start: `${pad(match[1])},${match[2]}`, end: `${pad(match[3])},${match[4]}`, text: [] };
      cues.push(current);
      return;
    }

    if (previousBlank && /^(WEBVTT|NOTE|STYLE|REGION)(\s|$)/.test(line)) {
      skippingBlock = true;
      return;
    }
    if (looksLikeIdentifier(lines, index)) {
      identifiers += 1;
      return;
    }
    if (!current) return;

    const text = cleanText(line);
    sourceWords += countWords(text);
    if (text.trim()) current.text.push(text);
  });

  const kept = cues.filter((cue) => cue.text.length > 0);
  const keptWords = kept.reduce((sum, cue) => sum + countWords(cue.text.join(' ')), 0);
  const arrowsInText = kept.filter((cue) => cue.text.some((line) => line.includes('-->'))).length;
  let outOfOrder = 0;
  for (let i = 1; i < kept.length; i += 1) {
    if (kept[i].start < kept[i - 1].start) outOfOrder += 1;
  }

  if (arrowsInText > 0) throw new Error(`${arrowsInText} cues still contain a timestamp`);
  if (keptWords !== sourceWords) throw new Error(`Word count changed: ${sourceWords} became ${keptWords}`);

  const srt = kept
    .map((cue, i) => `${i + 1}\n${cue.start} --> ${cue.end}\n${cue.text.join('\n')}\n`)
    .join('\n');

  return {
    srt,
    stats: {
      stamps, cues: kept.length, emptyDropped: stamps - kept.length, identifiers, words: keptWords, outOfOrder,
    },
  };
};

const run = (command, commandArgs) => new Promise((resolve, reject) => {
  const child = spawn(command, commandArgs);
  const stdout = [];
  let stdoutBytes = 0;
  let stderr = '';
  child.stdout.on('data', (chunk) => {
    stdoutBytes += chunk.length;
    if (stdoutBytes <= MAX_STDOUT_BYTES) stdout.push(chunk);
  });
  child.stderr.on('data', (chunk) => { stderr = (stderr + chunk).slice(-4000); });
  child.on('error', reject);
  child.on('close', (code) => resolve({ code, stdout: Buffer.concat(stdout).toString('utf8'), stderr }));
});

// mkvmerge and mkvextract exit 1 for warnings and 2 for errors.
const runMkvTool = async (command, commandArgs) => {
  const result = await run(command, commandArgs);
  if (result.code !== 0 && result.code !== 1) {
    throw new Error(`${command} exited with ${result.code}: ${(result.stdout + result.stderr).slice(-500)}`);
  }
  return result;
};

const identify = async (file) => JSON.parse((await runMkvTool('mkvmerge', ['-J', file])).stdout);

const tracksOfType = (info, type) => info.tracks.filter((track) => track.type === type);

const durationOf = (info) => Number((info.container && info.container.properties
  && info.container.properties.duration) || 0);

const packetCounts = async (file) => {
  const result = await run('ffprobe', ['-v', 'error', '-select_streams', 's', '-count_packets',
    '-show_entries', 'stream=nb_read_packets', '-of', 'csv=p=0', file]);
  if (result.code !== 0) throw new Error(`ffprobe exited with ${result.code}: ${result.stderr.slice(-500)}`);
  return result.stdout.split('\n').map((row) => row.replace(/[^\d]/g, '')).filter(Boolean).map(Number);
};

const languageOf = (track) => (track.properties.language || 'und').toLowerCase();

const shouldKeep = (track, keep) => {
  const language = languageOf(track);
  return language === 'und' || keep.includes(language);
};

const trackOptions = (track) => {
  const { properties } = track;
  const options = ['--language', `0:${languageOf(track)}`];
  if (properties.track_name) options.push('--track-name', `0:${properties.track_name}`);
  options.push('--default-track-flag', `0:${properties.default_track ? 'yes' : 'no'}`);
  options.push('--forced-display-flag', `0:${properties.forced_track ? 'yes' : 'no'}`);
  return options;
};

const verify = async (input, output, inputInfo, converted, expectedOtherSubs) => {
  const outputInfo = await identify(output);
  ['video', 'audio'].forEach((type) => {
    const before = tracksOfType(inputInfo, type).length;
    const after = tracksOfType(outputInfo, type).length;
    if (before !== after) throw new Error(`${type} tracks changed: ${before} became ${after}`);
  });

  const leftover = outputInfo.tracks.filter((track) => track.properties.codec_id === WEBVTT_CODEC).length;
  if (leftover > 0) throw new Error(`${leftover} WebVTT tracks are still in the output`);

  const subs = tracksOfType(outputInfo, 'subtitles');
  if (subs.length !== expectedOtherSubs + converted.length) {
    throw new Error(`Expected ${expectedOtherSubs + converted.length} subtitle tracks, found ${subs.length}`);
  }

  const before = durationOf(inputInfo);
  const after = durationOf(outputInfo);
  if (!before || !after || Math.abs(after - before) / before > DURATION_TOLERANCE) {
    throw new Error(`Duration changed: ${before} became ${after}`);
  }

  // Converted tracks are appended after the existing subtitles, so their packets are the last rows.
  const packets = await packetCounts(output);
  converted.forEach((track, index) => {
    const actual = packets[expectedOtherSubs + index];
    if (actual !== track.stats.cues) {
      throw new Error(`Track ${track.id}: ${track.stats.cues} cues became ${actual} packets`);
    }
  });
};

const plugin = async (args) => {
  const inputPath = args.inputFileObj._id;
  const passThrough = {
    outputFileObj: args.inputFileObj,
    outputNumber: 1,
    variables: args.variables,
  };

  if (path.extname(inputPath).toLowerCase() !== '.mkv') {
    args.jobLog('Not an MKV, skipping WebVTT check');
    return passThrough;
  }

  const inputInfo = await identify(inputPath);
  const allSubs = tracksOfType(inputInfo, 'subtitles');
  const vttTracks = allSubs.filter((track) => track.properties.codec_id === WEBVTT_CODEC);
  if (vttTracks.length === 0) {
    args.jobLog('No WebVTT tracks');
    return passThrough;
  }

  const keep = String(args.inputs.keepLanguages || 'eng')
    .split(',').map((language) => language.trim().toLowerCase()).filter(Boolean);
  const toConvert = vttTracks.filter((track) => shouldKeep(track, keep));
  args.jobLog(`WebVTT tracks: ${vttTracks.map((t) => `${t.id}:${languageOf(t)}`).join(' ')}. `
    + `Converting ${toConvert.length}, removing ${vttTracks.length - toConvert.length}.`);

  const workDir = path.join(args.workDir, `webvtt-${Date.now()}`);
  fs.mkdirSync(workDir, { recursive: true });

  const converted = [];
  if (toConvert.length > 0) {
    const targets = toConvert.map((track) => `${track.id}:${path.join(workDir, `${track.id}.vtt`)}`);
    await runMkvTool('mkvextract', [inputPath, 'tracks', ...targets]);
    toConvert.forEach((track) => {
      const vttPath = path.join(workDir, `${track.id}.vtt`);
      const { srt, stats } = convertVttText(fs.readFileSync(vttPath, 'utf8'));
      if (stats.cues === 0) throw new Error(`Track ${track.id} produced no cues`);
      const srtPath = path.join(workDir, `${track.id}.srt`);
      fs.writeFileSync(srtPath, srt, 'utf8');
      args.jobLog(`Track ${track.id}: ${JSON.stringify(stats)}`);
      converted.push({
        id: track.id, stats, srtPath, options: trackOptions(track),
      });
    });
  }

  const otherSubs = allSubs.filter((track) => track.properties.codec_id !== WEBVTT_CODEC);
  const outputPath = path.join(workDir, `${path.parse(inputPath).name}.mkv`);
  const removeIds = vttTracks.map((track) => track.id).join(',');
  const mergeArgs = ['-q', '-o', outputPath, '--subtitle-tracks', `!${removeIds}`, inputPath];
  converted.forEach((track) => mergeArgs.push(...track.options, track.srtPath));

  args.updateWorker({ CLIType: 'mkvmerge', preset: mergeArgs.join(' ') });
  await runMkvTool('mkvmerge', mergeArgs);
  await verify(inputPath, outputPath, inputInfo, converted, otherSubs.length);

  args.jobLog(`Converted ${converted.length} WebVTT tracks and all checks passed`);
  return {
    outputFileObj: { _id: outputPath },
    outputNumber: 1,
    variables: args.variables,
  };
};

module.exports.details = details;
module.exports.plugin = plugin;
module.exports.convertVttText = convertVttText;
