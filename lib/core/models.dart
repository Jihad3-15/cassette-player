// Shared data types. Every part of the app codes against these.
// Do not change field names or types without updating every caller.

enum RepeatMode { off, all, one }

enum TrackSort { title, artist, album, recentlyAdded }

/// A track as stored in the library database.
class Track {
  final int id;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final int durationMs;

  /// Absolute path to the audio file inside the app's private storage.
  final String filePath;

  /// SHA-256 of the file bytes, hex encoded. Used for de-duplication.
  final String contentHash;

  /// Absolute path to a cached cover image, or null if none.
  final String? artworkPath;
  final DateTime addedAt;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    required this.durationMs,
    required this.filePath,
    required this.contentHash,
    this.artworkPath,
    required this.addedAt,
  });

  Duration get duration => Duration(milliseconds: durationMs);
}

/// A track that has been parsed during import but not yet inserted.
class TrackDraft {
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;
  final int durationMs;
  final String filePath;
  final String contentHash;
  final String? artworkPath;

  const TrackDraft({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    required this.durationMs,
    required this.filePath,
    required this.contentHash,
    this.artworkPath,
  });
}

class AlbumSummary {
  final String album;
  final String artist; // album artist if present, else track artist
  final int trackCount;
  final String? artworkPath;
  const AlbumSummary({
    required this.album,
    required this.artist,
    required this.trackCount,
    this.artworkPath,
  });
}

class ArtistSummary {
  final String name;
  final int trackCount;
  const ArtistSummary({required this.name, required this.trackCount});
}

class Playlist {
  final int id;
  final String name;
  final int trackCount;
  const Playlist({required this.id, required this.name, required this.trackCount});
}

/// Everything needed to restore playback after the app restarts.
class PlaybackSnapshot {
  final List<int> queueTrackIds; // original (unshuffled) order
  final int currentIndex; // index into queueTrackIds
  final int positionMs;
  final bool shuffle;
  final RepeatMode repeat;

  const PlaybackSnapshot({
    required this.queueTrackIds,
    required this.currentIndex,
    required this.positionMs,
    required this.shuffle,
    required this.repeat,
  });
}

/// Progress events emitted while importing.
class ImportProgress {
  final int total;
  final int processed;
  final int added;
  final int duplicates;
  final int failed;
  final String? currentFile; // display name of file being processed
  final bool finished;

  const ImportProgress({
    required this.total,
    required this.processed,
    required this.added,
    required this.duplicates,
    required this.failed,
    this.currentFile,
    this.finished = false,
  });
}
