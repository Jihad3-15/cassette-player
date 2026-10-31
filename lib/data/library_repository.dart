import '../core/models.dart';

/// The library database. Implemented by SqliteLibraryRepository in
/// sqlite_library_repository.dart. Other parts of the app depend only on this
/// interface.
abstract class LibraryRepository {
  /// Opens (and creates/migrates) the database. Call once at startup.
  Future<void> open();

  /// Emits after any write (tracks, playlists) so the UI can refresh.
  /// Not emitted for playback-state writes.
  Stream<void> get changes;

  // ---- Import support ----
  Future<bool> hasHash(String contentHash);

  /// Inserts drafts in a single transaction. Skips drafts whose contentHash
  /// already exists. Returns the number actually inserted.
  Future<int> insertTracks(List<TrackDraft> drafts);

  /// Sets cover art for every track with this content hash.
  Future<void> setArtworkForHash(String contentHash, String artworkPath);

  // ---- Browsing ----
  Future<List<Track>> allTracks({TrackSort sort = TrackSort.title});
  Future<Track?> trackById(int id);

  /// Returns tracks in the same order as [ids]; missing ids are skipped.
  Future<List<Track>> tracksByIds(List<int> ids);

  Future<List<AlbumSummary>> albums();
  Future<List<Track>> tracksForAlbum(String album, String artist);
  Future<List<ArtistSummary>> artists();
  Future<List<Track>> tracksForArtist(String artist);

  /// Full-text search over title, artist, album, album artist and genre.
  /// Prefix matching ("beat" finds "Beatles"). Empty query returns [].
  Future<List<Track>> search(String query, {int limit = 50});

  /// Removes the track row (and playlist entries). Does NOT delete files;
  /// returns the removed track so the caller can delete its file/artwork.
  Future<Track?> deleteTrack(int id);

  Future<int> trackCount();

  // ---- Playlists ----
  Future<List<Playlist>> playlists();
  Future<int> createPlaylist(String name);
  Future<void> renamePlaylist(int playlistId, String name);
  Future<void> deletePlaylist(int playlistId);
  Future<void> addToPlaylist(int playlistId, List<int> trackIds);
  Future<void> removeFromPlaylist(int playlistId, int position);
  Future<List<Track>> tracksForPlaylist(int playlistId);

  // ---- Playback state (single row) ----
  Future<void> savePlaybackSnapshot(PlaybackSnapshot snapshot);

  /// Cheap update of only the position; called every few seconds.
  Future<void> savePlaybackPosition(int positionMs);
  Future<PlaybackSnapshot?> loadPlaybackSnapshot();

  Future<void> close();
}
