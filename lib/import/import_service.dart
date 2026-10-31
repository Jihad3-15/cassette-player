import '../core/models.dart';

/// Turns user-picked audio files into library entries, entirely on-device.
/// Implemented by LocalImportService in local_import_service.dart.
abstract class ImportService {
  /// Opens the system file picker for audio files (multi-select).
  /// Returns local file paths, or an empty list if the user cancelled.
  Future<List<String>> pickAudioFiles();

  /// Copies each file into app storage, parses tags, hashes, de-duplicates,
  /// and inserts into the library in batches. Cover art is extracted in a
  /// second pass. Emits progress; the last event has finished == true.
  /// Never throws for a single bad file; counts it as failed instead.
  Stream<ImportProgress> importFiles(List<String> sourcePaths);

  /// Deletes a track from the library and removes its audio + artwork files.
  Future<void> deleteTrack(int trackId);
}
