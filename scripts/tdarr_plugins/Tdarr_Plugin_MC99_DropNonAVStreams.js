/* eslint-disable */
const details = () => {
  return {
    id: "Tdarr_Plugin_MC99_DropNonAVStreams",
    Stage: "Pre-processing",
    Name: "Drop Non-AV Streams",
    Type: "Video",
    Operation: "Transcode",
    Description: `Force-remux to MKV keeping only video, audio, and valid subtitle streams. Drops bin_data, gpmd and text streams which break MKV muxing. Chapters are kept.`,
    Version: "1.0.0",
    Tags: "pre-processing,ffmpeg",
    Inputs: [],
  };
};

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const plugin = (file, librarySettings, inputs, otherArguments) => {
  const response = {
    processFile: true,                 // always process
    preset: ",-map 0:v -map 0:a -map 0:s? -c copy",
    container: ".mkv",
    handBrakeMode: false,
    FFmpegMode: true,
    reQueueAfter: false,
    infoLog: "Forced safe mapping: video/audio/subtitles only. Dropped non-AV streams.\n",
  };

  return response;
};

module.exports.details = details;
module.exports.plugin = plugin;