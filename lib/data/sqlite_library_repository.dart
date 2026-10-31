import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import 'library_repository.dart';

/// SQLite-backed [LibraryRepository]. Everything is stored in a single
/// database file in app-private storage; nothing leaves the device.
class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(this.databasePath);

  /// Absolute path of the database file.
  final String databasePath;

  static const int _schemaVersion = 1;

  /// Max number of `?` placeholders per statement. Old Android SQLite builds
  /// cap this at 999, so stay well below.
  static const int _maxVariables = 500;

  static const String _unknownTitle = 'Unknown Title';
  static const String _unknownArtist = 'Unknown Artist';
  static const String _unknownAlbum = 'Unknown Album';

  /// Album grouping key: album artist if present, else track artist.
  static const String _albumArtistExpr =
      "COALESCE(NULLIF(album_artist, ''), artist)";

  static const String _albumTrackOrder =
      'disc_number IS NULL, disc_number, '
      'track_number IS NULL, track_number, '
      'title COLLATE NOCASE';

  Database? _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('SqliteLibraryRepository.open() must be awaited first');
    }
    return db;
  }

  void _notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> open() async {
    if (_db != null) return;
    _db = await openDatabase(
      databasePath,
      version: _schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    _createSchemaV1(batch);
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Only version 1 exists. Future migrations go here, e.g.
    // if (oldVersion < 2) { ... }
  }

  static void _createSchemaV1(Batch batch) {
    batch.execute('''
CREATE TABLE tracks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT NOT NULL,
  album_artist TEXT,
  track_number INTEGER,
  disc_number INTEGER,
  year INTEGER,
  genre TEXT,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  file_path TEXT NOT NULL,
  content_hash TEXT NOT NULL UNIQUE,
  artwork_path TEXT,
  added_at INTEGER NOT NULL
)''');
    batch.execute('CREATE INDEX idx_tracks_album ON tracks (album)');
    batch.execute('CREATE INDEX idx_tracks_artist ON tracks (artist)');
    batch.execute(
      'CREATE INDEX idx_tracks_album_artist ON tracks (album_artist)',
    );
    batch.execute('CREATE INDEX idx_tracks_added_at ON tracks (added_at)');

    // Full-text search. FTS4 (not FTS5) because Android's system SQLite
    // reliably ships FTS3/FTS4 only. External-content table: the text lives
    // in `tracks`; the FTS index is kept in sync by the triggers below.
    batch.execute('''
CREATE VIRTUAL TABLE tracks_fts USING fts4(
  content="tracks",
  title, artist, album, album_artist, genre
)''');
    batch.execute('''
CREATE TRIGGER tracks_fts_ai AFTER INSERT ON tracks BEGIN
  INSERT INTO tracks_fts (docid, title, artist, album, album_artist, genre)
  VALUES (new.id, new.title, new.artist, new.album, new.album_artist, new.genre);
END''');
    batch.execute('''
CREATE TRIGGER tracks_fts_bd BEFORE DELETE ON tracks BEGIN
  DELETE FROM tracks_fts WHERE docid = old.id;
END''');
    batch.execute('''
CREATE TRIGGER tracks_fts_bu
BEFORE UPDATE OF title, artist, album, album_artist, genre ON tracks BEGIN
  DELETE FROM tracks_fts WHERE docid = old.id;
END''');
    batch.execute('''
CREATE TRIGGER tracks_fts_au
AFTER UPDATE OF title, artist, album, album_artist, genre ON tracks BEGIN
  INSERT INTO tracks_fts (docid, title, artist, album, album_artist, genre)
  VALUES (new.id, new.title, new.artist, new.album, new.album_artist, new.genre);
END''');

    batch.execute('''
CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
)''');
    // Own surrogate key so positions can be renumbered without transient
    // unique-constraint collisions.
    batch.execute('''
CREATE TABLE playlist_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id INTEGER NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE
)''');
    batch.execute(
      'CREATE INDEX idx_playlist_entries_playlist '
      'ON playlist_entries (playlist_id, position)',
    );
    batch.execute(
      'CREATE INDEX idx_playlist_entries_track ON playlist_entries (track_id)',
    );

    batch.execute('''
CREATE TABLE playback_state (
  id INTEGER PRIMARY KEY CHECK (id = 0),
  queue_ids TEXT NOT NULL,
  current_index INTEGER NOT NULL,
  position_ms INTEGER NOT NULL,
  shuffle INTEGER NOT NULL,
  repeat TEXT NOT NULL
)''');
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) {
      await db.close();
    }
    await _changes.close();
  }

  // ---------------------------------------------------------------------------
  // Import support
  // ---------------------------------------------------------------------------

  @override
  Future<bool> hasHash(String contentHash) async {
    final rows = await _database.rawQuery(
      'SELECT 1 FROM tracks WHERE content_hash = ? LIMIT 1',
      [contentHash],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> insertTracks(List<TrackDraft> drafts) async {
    if (drafts.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final inserted = await _database.transaction<int>((txn) async {
      final before = await _countTracks(txn);
      final batch = txn.batch();
      for (final d in drafts) {
        batch.rawInsert(
          'INSERT OR IGNORE INTO tracks (title, artist, album, album_artist, '
          'track_number, disc_number, year, genre, duration_ms, file_path, '
          'content_hash, artwork_path, added_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            _orDefault(d.title, _unknownTitle),
            _orDefault(d.artist, _unknownArtist),
            _orDefault(d.album, _unknownAlbum),
            _nullIfBlank(d.albumArtist),
            d.trackNumber,
            d.discNumber,
            d.year,
            _nullIfBlank(d.genre),
            d.durationMs,
            d.filePath,
            d.contentHash,
            d.artworkPath,
            now,
          ],
        );
      }
      await batch.commit(noResult: true);
      final after = await _countTracks(txn);
      return after - before;
    });
    if (inserted > 0) _notify();
    return inserted;
  }

  @override
  Future<void> setArtworkForHash(String contentHash, String artworkPath) async {
    await _database.rawUpdate(
      'UPDATE tracks SET artwork_path = ? WHERE content_hash = ?',
      [artworkPath, contentHash],
    );
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Browsing
  // ---------------------------------------------------------------------------

  @override
  Future<List<Track>> allTracks({TrackSort sort = TrackSort.title}) async {
    final rows = await _database.rawQuery(
      'SELECT * FROM tracks ORDER BY ${_orderFor(sort)}',
    );
    return rows.map(_trackFromRow).toList();
  }

  static String _orderFor(TrackSort sort) {
    switch (sort) {
      case TrackSort.title:
        return 'title COLLATE NOCASE, artist COLLATE NOCASE, id';
      case TrackSort.artist:
        return 'artist COLLATE NOCASE, album COLLATE NOCASE, '
            '$_albumTrackOrder, id';
      case TrackSort.album:
        return 'album COLLATE NOCASE, $_albumArtistExpr COLLATE NOCASE, '
            '$_albumTrackOrder, id';
      case TrackSort.recentlyAdded:
        return 'added_at DESC, id DESC';
    }
  }

  @override
  Future<Track?> trackById(int id) async {
    final rows = await _database.rawQuery(
      'SELECT * FROM tracks WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return _trackFromRow(rows.first);
  }

  @override
  Future<List<Track>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final unique = ids.toSet().toList();
    final byId = <int, Track>{};
    for (var start = 0; start < unique.length; start += _maxVariables) {
      final end = (start + _maxVariables < unique.length)
          ? start + _maxVariables
          : unique.length;
      final chunk = unique.sublist(start, end);
      final rows = await _database.rawQuery(
        'SELECT * FROM tracks WHERE id IN (${_placeholders(chunk.length)})',
        chunk,
      );
      for (final row in rows) {
        final t = _trackFromRow(row);
        byId[t.id] = t;
      }
    }
    final result = <Track>[];
    for (final id in ids) {
      final t = byId[id];
      if (t != null) result.add(t);
    }
    return result;
  }

  @override
  Future<List<AlbumSummary>> albums() async {
    final rows = await _database.rawQuery(
      'SELECT album, $_albumArtistExpr AS group_artist, '
      'COUNT(*) AS track_count, MAX(artwork_path) AS artwork '
      'FROM tracks '
      'GROUP BY album, $_albumArtistExpr '
      'ORDER BY album COLLATE NOCASE, group_artist COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => AlbumSummary(
            album: _orDefault(r['album'] as String?, _unknownAlbum),
            artist: _orDefault(r['group_artist'] as String?, _unknownArtist),
            trackCount: _asInt(r['track_count']) ?? 0,
            artworkPath: r['artwork'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<List<Track>> tracksForAlbum(String album, String artist) async {
    final rows = await _database.rawQuery(
      'SELECT * FROM tracks WHERE album = ? AND $_albumArtistExpr = ? '
      'ORDER BY $_albumTrackOrder, id',
      [album, artist],
    );
    return rows.map(_trackFromRow).toList();
  }

  @override
  Future<List<ArtistSummary>> artists() async {
    final rows = await _database.rawQuery(
      'SELECT artist, COUNT(*) AS track_count FROM tracks '
      'GROUP BY artist ORDER BY artist COLLATE NOCASE',
    );
    return rows
        .map(
          (r) => ArtistSummary(
            name: _orDefault(r['artist'] as String?, _unknownArtist),
            trackCount: _asInt(r['track_count']) ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<List<Track>> tracksForArtist(String artist) async {
    final rows = await _database.rawQuery(
      'SELECT * FROM tracks WHERE artist = ? '
      'ORDER BY album COLLATE NOCASE, $_albumTrackOrder, id',
      [artist],
    );
    return rows.map(_trackFromRow).toList();
  }

  @override
  Future<List<Track>> search(String query, {int limit = 50}) async {
    final match = buildFtsMatchQuery(query);
    if (match == null || limit <= 0) return const [];
    try {
      final rows = await _database.rawQuery(
        'SELECT * FROM tracks WHERE id IN '
        '(SELECT docid FROM tracks_fts WHERE tracks_fts MATCH ?) '
        'ORDER BY title COLLATE NOCASE, id LIMIT ?',
        [match, limit],
      );
      return rows.map(_trackFromRow).toList();
    } on DatabaseException {
      // Malformed MATCH expression or FTS error: treat as no results.
      return const [];
    }
  }

  /// Turns free text into a safe FTS4 MATCH expression, or null if nothing
  /// searchable remains. Every ASCII character that is not a letter or digit
  /// (quotes, `*`, `-`, `:`, `^`, parentheses, ...) becomes a separator,
  /// exactly how the default `simple` tokenizer splits the indexed text
  /// (non-ASCII characters are token characters there). Operator words
  /// (AND/OR/NOT/NEAR) are lowercased so they are plain terms; other tokens
  /// are left as-is because `simple` only folds ASCII case. Each token gets
  /// `*` for prefix matching; tokens are joined with spaces (implicit AND).
  static String? buildFtsMatchQuery(String query) {
    const operators = {'AND', 'OR', 'NOT', 'NEAR'};
    final cleaned = query.replaceAll(
      RegExp(r'[\x00-\x2F\x3A-\x40\x5B-\x60\x7B-\x7F]+'),
      ' ',
    );
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map((t) => operators.contains(t) ? t.toLowerCase() : t)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '$t*').join(' ');
  }

  @override
  Future<Track?> deleteTrack(int id) async {
    final removed = await _database.transaction<Track?>((txn) async {
      final rows = await txn.rawQuery(
        'SELECT * FROM tracks WHERE id = ? LIMIT 1',
        [id],
      );
      if (rows.isEmpty) return null;
      final track = _trackFromRow(rows.first);

      final playlistRows = await txn.rawQuery(
        'SELECT DISTINCT playlist_id FROM playlist_entries WHERE track_id = ?',
        [id],
      );
      // Playlist entries are removed by ON DELETE CASCADE.
      await txn.rawDelete('DELETE FROM tracks WHERE id = ?', [id]);
      for (final r in playlistRows) {
        final playlistId = _asInt(r['playlist_id']);
        if (playlistId != null) {
          await _renumberPlaylist(txn, playlistId);
        }
      }
      return track;
    });
    if (removed != null) _notify();
    return removed;
  }

  @override
  Future<int> trackCount() => _countTracks(_database);

  static Future<int> _countTracks(DatabaseExecutor exec) async {
    final rows = await exec.rawQuery('SELECT COUNT(*) FROM tracks');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  @override
  Future<List<Playlist>> playlists() async {
    final rows = await _database.rawQuery(
      'SELECT p.id AS id, p.name AS name, COUNT(e.id) AS track_count '
      'FROM playlists p '
      'LEFT JOIN playlist_entries e ON e.playlist_id = p.id '
      'GROUP BY p.id, p.name '
      'ORDER BY p.name COLLATE NOCASE, p.id',
    );
    return rows
        .map(
          (r) => Playlist(
            id: _asInt(r['id']) ?? 0,
            name: (r['name'] as String?) ?? '',
            trackCount: _asInt(r['track_count']) ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<int> createPlaylist(String name) async {
    final id = await _database.rawInsert(
      'INSERT INTO playlists (name, created_at) VALUES (?, ?)',
      [name.trim(), DateTime.now().millisecondsSinceEpoch],
    );
    _notify();
    return id;
  }

  @override
  Future<void> renamePlaylist(int playlistId, String name) async {
    await _database.rawUpdate(
      'UPDATE playlists SET name = ? WHERE id = ?',
      [name.trim(), playlistId],
    );
    _notify();
  }

  @override
  Future<void> deletePlaylist(int playlistId) async {
    // Entries are removed by ON DELETE CASCADE.
    await _database.rawDelete('DELETE FROM playlists WHERE id = ?', [
      playlistId,
    ]);
    _notify();
  }

  @override
  Future<void> addToPlaylist(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    final added = await _database.transaction<int>((txn) async {
      final exists = await txn.rawQuery(
        'SELECT 1 FROM playlists WHERE id = ? LIMIT 1',
        [playlistId],
      );
      if (exists.isEmpty) return 0;

      // Only append ids that still exist, so positions stay contiguous.
      final unique = trackIds.toSet().toList();
      final existing = <int>{};
      for (var start = 0; start < unique.length; start += _maxVariables) {
        final end = (start + _maxVariables < unique.length)
            ? start + _maxVariables
            : unique.length;
        final chunk = unique.sublist(start, end);
        final rows = await txn.rawQuery(
          'SELECT id FROM tracks WHERE id IN (${_placeholders(chunk.length)})',
          chunk,
        );
        for (final r in rows) {
          final id = _asInt(r['id']);
          if (id != null) existing.add(id);
        }
      }

      final maxRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) FROM playlist_entries '
        'WHERE playlist_id = ?',
        [playlistId],
      );
      var position = (Sqflite.firstIntValue(maxRows) ?? -1) + 1;

      final batch = txn.batch();
      var count = 0;
      for (final trackId in trackIds) {
        if (!existing.contains(trackId)) continue;
        batch.rawInsert(
          'INSERT INTO playlist_entries (playlist_id, position, track_id) '
          'VALUES (?, ?, ?)',
          [playlistId, position, trackId],
        );
        position++;
        count++;
      }
      if (count > 0) {
        await batch.commit(noResult: true);
      }
      return count;
    });
    if (added > 0) _notify();
  }

  @override
  Future<void> removeFromPlaylist(int playlistId, int position) async {
    await _database.transaction<void>((txn) async {
      await txn.rawDelete(
        'DELETE FROM playlist_entries WHERE playlist_id = ? AND position = ?',
        [playlistId, position],
      );
      await _renumberPlaylist(txn, playlistId);
    });
    _notify();
  }

  /// Rewrites positions of [playlistId] to 0..n-1, keeping their order.
  static Future<void> _renumberPlaylist(Transaction txn, int playlistId) async {
    final rows = await txn.rawQuery(
      'SELECT id, position FROM playlist_entries WHERE playlist_id = ? '
      'ORDER BY position, id',
      [playlistId],
    );
    final batch = txn.batch();
    var changed = false;
    for (var i = 0; i < rows.length; i++) {
      final entryId = _asInt(rows[i]['id']);
      final current = _asInt(rows[i]['position']);
      if (entryId == null || current == i) continue;
      batch.rawUpdate(
        'UPDATE playlist_entries SET position = ? WHERE id = ?',
        [i, entryId],
      );
      changed = true;
    }
    if (changed) {
      await batch.commit(noResult: true);
    }
  }

  @override
  Future<List<Track>> tracksForPlaylist(int playlistId) async {
    final rows = await _database.rawQuery(
      'SELECT t.* FROM playlist_entries e '
      'JOIN tracks t ON t.id = e.track_id '
      'WHERE e.playlist_id = ? '
      'ORDER BY e.position, e.id',
      [playlistId],
    );
    return rows.map(_trackFromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // Playback state (single row, id = 0). These writes do not emit [changes].
  // ---------------------------------------------------------------------------

  @override
  Future<void> savePlaybackSnapshot(PlaybackSnapshot snapshot) async {
    await _database.rawInsert(
      'INSERT OR REPLACE INTO playback_state '
      '(id, queue_ids, current_index, position_ms, shuffle, repeat) '
      'VALUES (0, ?, ?, ?, ?, ?)',
      [
        snapshot.queueTrackIds.join(','),
        snapshot.currentIndex,
        snapshot.positionMs,
        snapshot.shuffle ? 1 : 0,
        snapshot.repeat.name,
      ],
    );
  }

  @override
  Future<void> savePlaybackPosition(int positionMs) async {
    await _database.rawUpdate(
      'UPDATE playback_state SET position_ms = ? WHERE id = 0',
      [positionMs],
    );
  }

  @override
  Future<PlaybackSnapshot?> loadPlaybackSnapshot() async {
    final rows = await _database.rawQuery(
      'SELECT * FROM playback_state WHERE id = 0 LIMIT 1',
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final rawQueue = (r['queue_ids'] as String?) ?? '';
    final queue = <int>[];
    for (final part in rawQueue.split(',')) {
      final id = int.tryParse(part.trim());
      if (id != null) queue.add(id);
    }
    final repeatName = r['repeat'] as String?;
    var repeat = RepeatMode.off;
    for (final m in RepeatMode.values) {
      if (m.name == repeatName) {
        repeat = m;
        break;
      }
    }
    return PlaybackSnapshot(
      queueTrackIds: queue,
      currentIndex: _asInt(r['current_index']) ?? 0,
      positionMs: _asInt(r['position_ms']) ?? 0,
      shuffle: (_asInt(r['shuffle']) ?? 0) != 0,
      repeat: repeat,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Track _trackFromRow(Map<String, Object?> r) {
    return Track(
      id: _asInt(r['id']) ?? 0,
      title: _orDefault(r['title'] as String?, _unknownTitle),
      artist: _orDefault(r['artist'] as String?, _unknownArtist),
      album: _orDefault(r['album'] as String?, _unknownAlbum),
      albumArtist: _nullIfBlank(r['album_artist'] as String?),
      trackNumber: _asInt(r['track_number']),
      discNumber: _asInt(r['disc_number']),
      year: _asInt(r['year']),
      genre: _nullIfBlank(r['genre'] as String?),
      durationMs: _asInt(r['duration_ms']) ?? 0,
      filePath: (r['file_path'] as String?) ?? '',
      contentHash: (r['content_hash'] as String?) ?? '',
      artworkPath: r['artwork_path'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(r['added_at']) ?? 0,
      ),
    );
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String _orDefault(String? v, String fallback) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? fallback : t;
  }

  static String? _nullIfBlank(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String _placeholders(int n) => List.filled(n, '?').join(', ');
}
