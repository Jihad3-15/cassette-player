/// Compile-time feature switches.
///
/// "Add from YouTube link" is only compiled into builds made with
/// `--dart-define=YOUTUBE_IMPORT=true`. The public release never sets it, so
/// that build has no YouTube code paths and no network access at all.
const bool kYouTubeImport = bool.fromEnvironment('YOUTUBE_IMPORT');
