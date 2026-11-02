import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// Converts a downloaded audio file to MP3 on the phone with FFmpeg (LAME).
///
/// YouTube's audio is already lossy (AAC ~128 kbps or Opus ~160 kbps), so the
/// MP3 can't sound better than the source. VBR quality 2 (~170-210 kbps) keeps
/// the extra loss inaudible for almost everyone while staying a normal size.
class Mp3Converter {
  /// Returns the MP3 file, or null if conversion failed or was cancelled.
  /// [title] and [artist] are written as ID3 tags.
  static Future<File?> convert(
    File input, {
    required String title,
    String? artist,
  }) async {
    final output = File('${input.path.substring(0, input.path.lastIndexOf('.'))}.mp3');
    final args = <String>[
      '-y',
      '-hide_banner',
      '-i', input.path,
      '-vn',
      '-map_metadata', '-1',
      '-c:a', 'libmp3lame',
      '-q:a', '2',
      '-id3v2_version', '3',
      '-metadata', 'title=$title',
      if (artist != null && artist.isNotEmpty) ...['-metadata', 'artist=$artist'],
      output.path,
    ];
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code) && await output.exists() && await output.length() > 0) {
        return output;
      }
    } catch (_) {
      // Fall through: the caller keeps the original file.
    }
    try {
      if (await output.exists()) await output.delete();
    } catch (_) {}
    return null;
  }

  /// Stops any conversion in progress.
  static Future<void> cancel() async {
    try {
      await FFmpegKit.cancel();
    } catch (_) {}
  }
}
