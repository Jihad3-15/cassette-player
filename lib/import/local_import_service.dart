import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/models.dart';
import '../data/library_repository.dart';
import 'import_service.dart';
import 'tag_reader.dart';

/// Audio formats we accept (lower-case, no dot). ALAC lives inside .m4a.
const Set<String> supportedAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'wav',
  'ogg',
  'oga',
  'opus',
  'webm',
};

/// Imports user-picked files into app-private storage. Everything happens on
/// the device; nothing touches the network.
class LocalImportService implements ImportService {
  final LibraryRepository repo;
  final AppPaths paths;

  LocalImportService(this.repo, this.paths);

  static const int _batchSize = 50;
  static const int _maxArtworkBytes = 5 * 1024 * 1024;

  @override
  Future<List<String>> pickAudioFiles() async {
    try {
      final FilePickerResult? result;
      if (Platform.isIOS) {
        // On iOS FileType.audio opens the Music-library picker
        // (MPMediaPickerController), not the Files app. Use extension filters
        // so the user browses Files / iCloud Drive / On My iPhone instead.
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: supportedAudioExtensions.toList(),
          allowMultiple: true,
        );
      } else {
        // Android maps FileType.audio to the "audio/*" MIME filter.
        result = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: true,
        );
      }
      if (result == null) return <String>[];
      return result.files
          .map((f) => f.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();
    } on PlatformException {
      return <String>[];
    } on Exception {
      return <String>[];
    }
  }

  @override
  Stream<ImportProgress> importFiles(List<String> sourcePaths) async* {
    final total = sourcePaths.length;
    var processed = 0;
    var added = 0;
    var duplicates = 0;
    var failed = 0;

    final pending = <_PendingTrack>[];
    final seenThisRun = <String>{};
    final insertedHashes = <String>[];

    try {
      await paths.musicDir.create(recursive: true);
    } catch (_) {
      // If this fails, every copy below fails and is counted as failed.
    }

    // Inserts the pending batch and updates the counters.
    Future<void> flush() async {
      if (pending.isEmpty) return;
      final batch = List<_PendingTrack>.of(pending);
      pending.clear();
      try {
        final inserted = await repo.insertTracks(
          batch.map((t) => t.draft).toList(),
        );
        final int clamped = inserted < 0
            ? 0
            : (inserted > batch.length ? batch.length : inserted);
        added += clamped;
        // Anything the repo skipped already had its hash in the library.
        duplicates += batch.length - clamped;
        insertedHashes.addAll(batch.map((t) => t.draft.contentHash));
      } catch (_) {
        failed += batch.length;
        for (final t in batch) {
          seenThisRun.remove(t.draft.contentHash);
          if (t.copiedThisRun) {
            await _deleteQuietly(t.draft.filePath);
          }
        }
      }
    }

    for (final sourcePath in sourcePaths) {
      final name = p.basename(sourcePath);
      final outcome = await _prepareOne(sourcePath, seenThisRun);
      switch (outcome.kind) {
        case _OutcomeKind.ready:
          pending.add(outcome.track!);
        case _OutcomeKind.duplicate:
          duplicates++;
        case _OutcomeKind.failed:
          failed++;
      }
      processed++;

      if (pending.length >= _batchSize) {
        await flush();
      }

      yield ImportProgress(
        total: total,
        processed: processed,
        added: added,
        duplicates: duplicates,
        failed: failed,
        currentFile: name,
      );
    }

    await flush();

    // Second pass: cover art for the tracks we just inserted.
    if (insertedHashes.isNotEmpty) {
      try {
        await paths.artworkDir.create(recursive: true);
      } catch (_) {
        // Artwork is optional.
      }
      for (final hash in insertedHashes) {
        await _extractArtwork(hash);
      }
    }

    yield ImportProgress(
      total: total,
      processed: processed,
      added: added,
      duplicates: duplicates,
      failed: failed,
      finished: true,
    );
  }

  @override
  Future<void> deleteTrack(int trackId) async {
    final track = await repo.deleteTrack(trackId);
    if (track == null) return;
    await _deleteQuietly(track.filePath);
    final art = track.artworkPath;
    // Content hashes are unique in the library, so no other track shares
    // this artwork file.
    if (art != null) {
      await _deleteQuietly(art);
    }
  }

  // ---------------------------------------------------------------------------

  /// Validates, hashes, de-duplicates, copies and parses one file.
  /// Never throws.
  Future<_Outcome> _prepareOne(
    String sourcePath,
    Set<String> seenThisRun,
  ) async {
    String? copiedPath;
    try {
      final ext = _extensionOf(sourcePath);
      if (ext == null || !supportedAudioExtensions.contains(ext)) {
        return const _Outcome.failed();
      }

      final source = File(sourcePath);
      if (!await source.exists()) return const _Outcome.failed();
      final sourceLength = await source.length();
      if (sourceLength <= 0) return const _Outcome.failed();

      final hash = await _sha256OfFile(source);
      if (seenThisRun.contains(hash) || await repo.hasHash(hash)) {
        return const _Outcome.duplicate();
      }

      final destPath = p.join(paths.musicDir.path, '$hash.$ext');
      final dest = File(destPath);
      var copiedThisRun = false;
      final alreadyThere =
          await dest.exists() && await dest.length() == sourceLength;
      if (!alreadyThere) {
        // Copy to a temp name and rename, so a crash never leaves a
        // truncated file under the final name.
        final tmpPath = '$destPath.part';
        copiedPath = tmpPath;
        await source.copy(tmpPath);
        await File(tmpPath).rename(destPath);
        copiedPath = destPath;
        copiedThisRun = true;
      }

      final tags = readTags(dest, sourcePath);
      seenThisRun.add(hash);

      return _Outcome.ready(
        _PendingTrack(
          TrackDraft(
            title: tags.title,
            artist: tags.artist,
            album: tags.album,
            albumArtist: tags.albumArtist,
            trackNumber: tags.trackNumber,
            discNumber: tags.discNumber,
            year: tags.year,
            genre: tags.genre,
            durationMs: tags.durationMs,
            filePath: destPath,
            contentHash: hash,
          ),
          copiedThisRun,
        ),
      );
    } catch (_) {
      final leftover = copiedPath;
      if (leftover != null) {
        await _deleteQuietly(leftover);
      }
      return const _Outcome.failed();
    }
  }

  /// Streams the file through SHA-256; never holds the whole file in memory.
  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Writes embedded cover art for [hash]'s audio file and records it.
  /// Never throws.
  Future<void> _extractArtwork(String hash) async {
    try {
      final audio = await _findAudioFileForHash(hash);
      if (audio == null) return;

      final art = readArtwork(audio, maxBytes: _maxArtworkBytes);
      if (art == null) return;

      final artPath = p.join(paths.artworkDir.path, '$hash.${art.extension}');
      final artFile = File(artPath);
      await artFile.writeAsBytes(art.bytes, flush: true);
      try {
        await repo.setArtworkForHash(hash, artPath);
      } catch (_) {
        await _deleteQuietly(artPath);
      }
    } catch (_) {
      // Artwork never fails an import.
    }
  }

  Future<File?> _findAudioFileForHash(String hash) async {
    for (final ext in supportedAudioExtensions) {
      final f = File(p.join(paths.musicDir.path, '$hash.$ext'));
      if (await f.exists()) return f;
    }
    return null;
  }

  static String? _extensionOf(String path) {
    final ext = p.extension(path);
    if (ext.length < 2) return null;
    return ext.substring(1).toLowerCase();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Best effort.
    }
  }
}

class _PendingTrack {
  final TrackDraft draft;

  /// True if this run wrote the audio file (so a failed insert should
  /// remove it).
  final bool copiedThisRun;

  const _PendingTrack(this.draft, this.copiedThisRun);
}

enum _OutcomeKind { ready, duplicate, failed }

class _Outcome {
  final _OutcomeKind kind;
  final _PendingTrack? track;

  const _Outcome.ready(_PendingTrack this.track) : kind = _OutcomeKind.ready;
  const _Outcome.duplicate()
      : kind = _OutcomeKind.duplicate,
        track = null;
  const _Outcome.failed()
      : kind = _OutcomeKind.failed,
        track = null;
}
