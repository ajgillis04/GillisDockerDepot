'use strict';

// Run with: node --test scripts/tdarr_plugins/tests/convertWebVttToSrt.test.js

const assert = require('node:assert');
const { test } = require('node:test');
const { convertVttText } = require('../LocalFlowPlugins/subtitle/convertWebVttToSrt/1.0.0/index.js');

test('splits packed cues that have no blank lines between them', () => {
  const { srt, stats } = convertVttText(
    'WEBVTT\n\n00:01.000 --> 00:02.000\nOne\n00:03.000 --> 00:04.000\nTwo\n00:05.000 --> 00:06.000\nThree\n',
  );
  assert.strictEqual(stats.cues, 3);
  assert.strictEqual(srt, '1\n00:00:01,000 --> 00:00:02,000\nOne\n\n'
    + '2\n00:00:03,000 --> 00:00:04,000\nTwo\n\n3\n00:00:05,000 --> 00:00:06,000\nThree\n');
});

test('keeps a numeric line of dialogue in a packed cue', () => {
  const { srt } = convertVttText('WEBVTT\n\n00:01.000 --> 00:02.000\n1984\n00:03.000 --> 00:04.000\nTwo\n');
  assert.match(srt, /00:02,000\n1984\n/);
});

test('drops a cue identifier that follows a blank line', () => {
  const { srt, stats } = convertVttText('WEBVTT\n\n7\n00:01.000 --> 00:02.000\nOne\n\n8\n00:03.000 --> 00:04.000\nTwo\n');
  assert.strictEqual(stats.identifiers, 2);
  assert.ok(!/^[78]$/m.test(srt));
});

test('skips header, NOTE and STYLE blocks', () => {
  const { srt, stats } = convertVttText(
    'WEBVTT - title\nKind: captions\n\nSTYLE\n::cue { color: red }\n\nNOTE a comment\nmore comment\n\n'
    + '00:01.000 --> 00:02.000\nOne\n\nNOTE between\n\n00:03.000 --> 00:04.000\nTwo\n',
  );
  assert.strictEqual(stats.cues, 2);
  assert.ok(!/comment|between|color|captions/.test(srt));
});

test('ignores cue settings and keeps hours', () => {
  const { srt } = convertVttText('WEBVTT\n\n01:02:03.004 --> 01:02:05.006 line:90% align:center\nOne\n');
  assert.match(srt, /^1\n01:02:03,004 --> 01:02:05,006\nOne\n$/);
});

test('keeps italics, strips other markup, decodes entities', () => {
  const { srt } = convertVttText(
    'WEBVTT\n\n00:01.000 --> 00:02.000\n<i>Tom</i> &amp; <c.yellow>Jerry</c> <v Bob>&lt;hi&gt;\n',
  );
  assert.match(srt, /<i>Tom<\/i> & Jerry <hi>/);
});

test('keeps multi-line cues and non-English words', () => {
  const { srt, stats } = convertVttText('﻿WEBVTT\r\n\r\n00:01.000 --> 00:02.000\r\n¿Qué pasó?\r\nAdiós\r\n');
  assert.match(srt, /¿Qué pasó\?\nAdiós\n$/);
  assert.strictEqual(stats.words, 3);
});

test('drops empty cues and counts them', () => {
  const { stats } = convertVttText('WEBVTT\n\n00:01.000 --> 00:02.000\n\n00:03.000 --> 00:04.000\nTwo\n');
  assert.strictEqual(stats.stamps, 2);
  assert.strictEqual(stats.cues, 1);
  assert.strictEqual(stats.emptyDropped, 1);
});

test('rejects a malformed timestamp left in the text', () => {
  assert.throws(
    () => convertVttText('WEBVTT\n\n00:01.000 --> 00:02.000\nOne\n00:03,000 --> 00:04,000\nTwo\n'),
    /still contain a timestamp/,
  );
});
