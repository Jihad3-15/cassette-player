// Informational CI check: can the YouTube extractor still reach audio?
//
// Uses "Big Buck Bunny" by the Blender Foundation (Creative Commons BY 3.0).
// GitHub's servers are sometimes blocked by YouTube, so a failure here does
// not always mean the app is broken on a phone; it's an early warning.
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main() async {
  const id = 'aqz-KE-bpKQ';
  final attempts = <String, List<YoutubeApiClient>?>{
    'default': null,
    'androidVr': [YoutubeApiClient.androidVr],
    'ios': [YoutubeApiClient.ios],
    'tv': [YoutubeApiClient.tv],
  };
  final yt = YoutubeExplode();
  try {
    final video = await yt.videos.get(id);
    stdout.writeln('metadata OK: "${video.title}" by ${video.author}');
  } catch (e) {
    stdout.writeln('metadata FAILED: ${e.runtimeType}: $e');
  }

  for (final entry in attempts.entries) {
    try {
      final manifest =
          await yt.videos.streams.getManifest(id, ytClients: entry.value);
      final audio = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      final listed = audio
          .map((s) =>
              '${s.tag}/${s.container.name}/${s.bitrate.kiloBitsPerSecond.round()}k')
          .join(', ');
      stdout.writeln('${entry.key}: ${audio.length} audio streams [$listed]');
      final aac = audio.where((s) => s.container == StreamContainer.mp4);
      if (aac.isEmpty) continue;
      var received = 0;
      await for (final chunk in yt.videos.streams.get(aac.first)) {
        received += chunk.length;
        if (received > 512 * 1024) break;
      }
      stdout.writeln('${entry.key}: download OK ($received bytes read)');
    } catch (e) {
      stdout.writeln('${entry.key}: FAILED ${e.runtimeType}: $e');
    }
  }
  yt.close();
  exit(0);
}
