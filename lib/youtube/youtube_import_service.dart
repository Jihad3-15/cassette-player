import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/app_paths.dart';
import '../core/models.dart';
import '../data/library_repository.dart';
import '../import/import_service.dart';
import 'mp3_converter.dart';

enum YouTubePhase { lookingUp, downloading, converting, importing, done, failed }

/// One update from [YouTubeImportService.importLink].
class YouTubeProgress {
  final YouTubePhase phase;
  final String message;

  /// Video title once known.
  final String? title;

  /// 0..1 while downloading when the size is known, otherwise null.
  final double? fraction;

  const YouTubeProgress(this.phase, this.message, {this.title, this.fraction});

  bool get finished =>
      phase == YouTubePhase.done || phase == YouTubePhase.failed;
}

/// Downloads the audio of a YouTube video on the phone and hands the file to
/// the normal import pipeline (hash, de-duplicate, copy, tag, insert).
///
/// Saves YouTube's own AAC audio as .m4a (no MP3 re-encode: that would only
/// lose quality). On Android, if no AAC stream exists, the Opus/WebM stream is
/// kept as .webm. Only compiled into builds with kYouTubeImport on.
class YouTubeImportService {
  YouTubeImportService(this._importer, this._repo, this._paths);

  final ImportService _importer;
  final LibraryRepository _repo;
  final AppPaths _paths;

  bool _cancelled = false;

  /// Client sets tried in order. YouTube regularly breaks one client or
  /// another, so if the default fails we fall back to the others.
  static final List<List<YoutubeApiClient>?> _clientAttempts = [
    null, // library default
    [YoutubeApiClient.androidVr],
    [YoutubeApiClient.ios],
    [YoutubeApiClient.tv],
  ];

  /// Returns the video id in [text], or null if it isn't a YouTube video link.
  static String? videoIdFrom(String text) => VideoId.parseVideoId(text.trim());

  /// Stops an in-progress download. The partial file is deleted.
  void cancel() {
    _cancelled = true;
    Mp3Converter.cancel();
  }

  /// With [asMp3] the audio is converted to MP3 before it's added; if the
  /// conversion fails, the original .m4a/.webm is kept instead.
  Stream<YouTubeProgress> importLink(String link, {bool asMp3 = false}) async* {
    _cancelled = false;
    final id = videoIdFrom(link);
    if (id == null) {
      yield const YouTubeProgress(
          YouTubePhase.failed, "That isn't a YouTube video link.");
      return;
    }

    final yt = YoutubeExplode();
    File? file;
    File? mp3File;
    try {
      yield const YouTubeProgress(YouTubePhase.lookingUp, 'Looking up video…');

      Video? fetched;
      Object? lookupError;
      try {
        fetched = await yt.videos.get(id);
      } catch (e) {
        lookupError = e;
      }
      if (fetched == null) {
        yield YouTubeProgress(
            YouTubePhase.failed, _describe(lookupError ?? 'unknown'));
        return;
      }
      final video = fetched;
      final title = video.title;
      if (video.isLive) {
        yield YouTubeProgress(
            YouTubePhase.failed, "Live streams can't be saved.",
            title: title);
        return;
      }

      final tmpDir = Directory(p.join(_paths.root.path, 'youtube_tmp'));
      await tmpDir.create(recursive: true);

      Object? lastError;
      var downloaded = false;
      for (final clients in _clientAttempts) {
        if (_cancelled) break;
        AudioOnlyStreamInfo? info;
        try {
          final manifest =
              await yt.videos.streams.getManifest(id, ytClients: clients);
          info = _pickStream(manifest);
        } catch (e) {
          lastError = e;
          continue;
        }
        if (info == null) continue;

        final ext = info.container == StreamContainer.webM ? 'webm' : 'm4a';
        file = File(p.join(tmpDir.path, '${_fileStem(video)}.$ext'));
        final total = info.size.totalBytes;
        var received = 0;
        var lastShown = -1.0;
        IOSink? sink;
        try {
          sink = file.openWrite();
          yield YouTubeProgress(YouTubePhase.downloading, 'Downloading…',
              title: title, fraction: total > 0 ? 0 : null);
          await for (final chunk in yt.videos.streams.get(info)) {
            if (_cancelled) break;
            sink.add(chunk);
            received += chunk.length;
            final double? fraction =
                total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;
            if (fraction == null || fraction - lastShown >= 0.01) {
              lastShown = fraction ?? lastShown;
              yield YouTubeProgress(
                YouTubePhase.downloading,
                'Downloading… ${_mb(received)}${total > 0 ? ' of ${_mb(total)}' : ''}',
                title: title,
                fraction: fraction,
              );
            }
          }
          await sink.flush();
          await sink.close();
          sink = null;
          if (_cancelled) break;
          // A stream that stops early is a failed download, not a short song.
          if (received == 0 || (total > 0 && received < total * 0.98)) {
            throw const HttpException('Download ended early');
          }
          downloaded = true;
          break;
        } catch (e) {
          lastError = e;
          try {
            await sink?.close();
          } catch (_) {}
          await _deleteQuietly(file);
          file = null;
        }
      }

      if (_cancelled) {
        yield YouTubeProgress(YouTubePhase.failed, 'Cancelled.', title: title);
        return;
      }
      final saved = file;
      if (!downloaded || saved == null) {
        yield YouTubeProgress(
          YouTubePhase.failed,
          lastError == null
              ? 'No audio stream was available for this video.'
              : _describe(lastError),
          title: title,
        );
        return;
      }

      var toImport = saved;
      var note = '';
      if (asMp3) {
        yield YouTubeProgress(
            YouTubePhase.converting, 'Converting to MP3…',
            title: title);
        final (tagTitle, tagArtist) = _splitStem(p.basenameWithoutExtension(saved.path));
        final mp3 = await Mp3Converter.convert(saved,
            title: tagTitle, artist: tagArtist);
        if (_cancelled) {
          if (mp3 != null) await _deleteQuietly(mp3);
          yield YouTubeProgress(YouTubePhase.failed, 'Cancelled.', title: title);
          return;
        }
        if (mp3 != null) {
          toImport = mp3;
          mp3File = mp3;
        } else {
          note = " MP3 conversion failed, so it was kept as .${p.extension(saved.path).replaceFirst('.', '')}.";
        }
      }

      yield YouTubeProgress(YouTubePhase.importing, 'Adding to your library…',
          title: title);
      final hash = (await sha256.bind(toImport.openRead()).first).toString();
      ImportProgress? result;
      await for (final progress in _importer.importFiles([toImport.path])) {
        result = progress;
      }

      if (result != null && result.added > 0) {
        await _saveThumbnail(video, hash);
        yield YouTubeProgress(
            YouTubePhase.done,
            'Added to your library${toImport.path.endsWith('.mp3') ? ' as MP3' : ''}.$note',
            title: title);
      } else if (result != null && result.duplicates > 0) {
        yield YouTubeProgress(
            YouTubePhase.done, 'Already in your library.',
            title: title);
      } else {
        yield YouTubeProgress(YouTubePhase.failed,
            "Downloaded, but the file couldn't be added to the library.",
            title: title);
      }
    } finally {
      await _deleteQuietly(file);
      await _deleteQuietly(mp3File);
      yt.close();
    }
  }

  /// Highest-bitrate original-language audio. AAC (.m4a) first since it plays
  /// everywhere; Opus/WebM only on Android, where ExoPlayer can play it.
  AudioOnlyStreamInfo? _pickStream(StreamManifest manifest) {
    final candidates = manifest.audioOnly
        .where((s) => s.audioTrack == null || s.audioTrack!.audioIsDefault)
        .toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    for (final s in candidates) {
      if (s.container == StreamContainer.mp4) return s;
    }
    if (Platform.isAndroid) {
      for (final s in candidates) {
        if (s.container == StreamContainer.webM) return s;
      }
    }
    return null;
  }

  /// The import pipeline reads "Artist - Title" from the file name when a file
  /// has no tags, which YouTube's audio files don't, so the name carries them.
  static String _fileStem(Video video) {
    final title = video.title
        .replaceAll(_noise, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final author = video.author
        .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
        .replaceAll(RegExp(r'VEVO$'), '')
        .trim();
    final stem =
        (title.contains(' - ') || author.isEmpty) ? title : '$author - $title';
    var safe = stem
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (safe.length > 120) safe = safe.substring(0, 120).trim();
    return safe.isEmpty ? video.id.value : safe;
  }

  /// "Artist - Title" (the file stem built by [_fileStem]) back into parts.
  static (String, String?) _splitStem(String stem) {
    final i = stem.indexOf(' - ');
    if (i > 0) {
      return (stem.substring(i + 3).trim(), stem.substring(0, i).trim());
    }
    return (stem, null);
  }

  static final RegExp _noise = RegExp(
    r'\s*[\(\[]\s*(official\s*(music\s*)?(video|audio|visualizer|lyric\s*video)|'
    r'lyrics?(\s*video)?|audio|visualizer|hd|hq|4k)\s*[\)\]]',
    caseSensitive: false,
  );

  Future<void> _saveThumbnail(Video video, String hash) async {
    final urls = [video.thumbnails.maxResUrl, video.thumbnails.highResUrl];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      for (final url in urls) {
        try {
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode != 200) {
            await response.drain<void>();
            continue;
          }
          final bytes = <int>[];
          await for (final chunk in response) {
            bytes.addAll(chunk);
            if (bytes.length > 5 * 1024 * 1024) break;
          }
          if (bytes.length < 1024 || bytes.length > 5 * 1024 * 1024) continue;
          final out = File(p.join(_paths.artworkDir.path, '$hash.jpg'));
          await out.writeAsBytes(bytes, flush: true);
          await _repo.setArtworkForHash(hash, out.path);
          return;
        } catch (_) {
          // Try the next size; artwork is optional.
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  static String _describe(Object e) {
    if (e is VideoRequiresPurchaseException) {
      return 'This video has to be bought on YouTube.';
    }
    if (e is VideoUnavailableException) {
      return 'This video is unavailable (private, removed or blocked in your region).';
    }
    if (e is VideoUnplayableException) {
      return "YouTube won't allow this video to be saved (age-restricted, members-only or similar).";
    }
    if (e is RequestLimitExceededException) {
      return 'YouTube is limiting requests right now. Try again later.';
    }
    if (e is SocketException) {
      return 'No internet connection.';
    }
    return 'YouTube blocked the download. The downloader may need an update.';
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
