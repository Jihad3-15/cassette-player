import 'package:flutter/material.dart';

import 'home_page.dart';
import 'theme.dart';

/// Root widget. Services are provided above this by lib/main.dart:
/// LibraryRepository, ImportService (Provider) and PlaybackController
/// (ChangeNotifierProvider).
class CassetteApp extends StatelessWidget {
  const CassetteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cassette',
      debugShowCheckedModeBanner: false,
      theme: buildCassetteTheme(Brightness.light),
      darkTheme: buildCassetteTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
