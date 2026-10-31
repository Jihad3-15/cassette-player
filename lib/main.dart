import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'core/app_paths.dart';
import 'data/library_repository.dart';
import 'data/sqlite_library_repository.dart';
import 'import/import_service.dart';
import 'import/local_import_service.dart';
import 'playback/audio_init.dart';
import 'playback/just_audio_playback_controller.dart';
import 'playback/playback_controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAudioBackground();
  final paths = await AppPaths.init();

  final repo = SqliteLibraryRepository(paths.databasePath);
  await repo.open();

  final importer = LocalImportService(repo, paths);
  final player = JustAudioPlaybackController(repo);
  await player.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<LibraryRepository>.value(value: repo),
        Provider<ImportService>.value(value: importer),
        ChangeNotifierProvider<PlaybackController>.value(value: player),
      ],
      child: const CassetteApp(),
    ),
  );
}
