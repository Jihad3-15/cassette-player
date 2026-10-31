# Cassette Player V1 - build contract

Local-only music library app in Flutter (Android first, iPhone via sideloading).
Music never leaves the device: no network calls anywhere in the app.

## Hard rules for every part
- No Flutter/Dart SDK is available in this workspace. Code cannot be compiled
  here; GitHub Actions compiles it. So write conservative, idiomatic Dart 3 /
  Flutter 3.x code and only use package APIs you have verified.
- Verify package APIs by reading the package source on GitHub via
  https://raw.githubusercontent.com/<owner>/<repo>/<branch-or-tag>/<path>
  (curl in Bash works; pub.dev is blocked). Prefer the git tag matching the
  version range in pubspec.yaml.
- Do NOT edit files owned by another part. Shared files (pubspec.yaml,
  lib/main.dart, lib/core/*, the three interface files) are owned by the
  coordinator; if you truly need a change there, say so in your final report
  instead of editing.
- Do not run git commands.
- Imports between parts go only through the interfaces:
  lib/data/library_repository.dart, lib/import/import_service.dart,
  lib/playback/playback_controller.dart, plus lib/core/models.dart and
  lib/core/app_paths.dart.
- Every file must analyze cleanly (no unused imports, no missing awaits that
  matter, null-safe).

## Fixed composition (see lib/main.dart)
- `SqliteLibraryRepository(String databasePath)` implements LibraryRepository
  -> lib/data/sqlite_library_repository.dart
- `LocalImportService(LibraryRepository repo, AppPaths paths)` implements
  ImportService -> lib/import/local_import_service.dart
- `Future<void> initAudioBackground()` -> lib/playback/audio_init.dart
- `JustAudioPlaybackController(LibraryRepository repo)` implements
  PlaybackController -> lib/playback/just_audio_playback_controller.dart
- `CassetteApp` (const constructor) -> lib/ui/app.dart; reads services with
  `context.read<LibraryRepository>()`, `context.read<ImportService>()`,
  `context.watch<PlaybackController>()` (package:provider).

## Package versions (pubspec.yaml)
just_audio ^0.10.0, just_audio_background 0.0.1-beta.17, audio_session ^0.2.0,
sqflite ^2.4.0, file_picker >=8.0.0 <11.0.0 (use the v8-v10 API:
`FilePicker.platform.pickFiles(...)` returning `FilePickerResult?`),
audio_metadata_reader ^1.4.0, crypto ^3.0.6, path_provider ^2.1.4,
path ^1.9.0, provider ^6.1.2.
