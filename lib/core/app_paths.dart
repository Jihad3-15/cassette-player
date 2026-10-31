import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// All on-device locations the app uses. Nothing is ever sent to a server.
///
/// Everything lives in app-private storage (Application Support), which other
/// apps can't read. Android cloud backup is disabled in the manifest.
class AppPaths {
  final Directory root;
  AppPaths._(this.root);

  static AppPaths? _instance;
  static AppPaths get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppPaths.init() must be awaited before use');
    }
    return i;
  }

  static Future<AppPaths> init() async {
    final support = await getApplicationSupportDirectory();
    final paths = AppPaths._(support);
    await paths.musicDir.create(recursive: true);
    await paths.artworkDir.create(recursive: true);
    _instance = paths;
    return paths;
  }

  /// Imported audio files, stored as `<sha256>.<ext>`.
  Directory get musicDir => Directory(p.join(root.path, 'music'));

  /// Cover art thumbnails, stored as `<sha256>.jpg` (or .png).
  Directory get artworkDir => Directory(p.join(root.path, 'artwork'));

  /// SQLite library database.
  String get databasePath => p.join(root.path, 'library.db');
}
