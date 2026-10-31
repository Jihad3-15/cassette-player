import 'package:flutter/material.dart';

import '../core/features.dart';
import 'import_flow.dart';
import 'search_page.dart';
import 'tabs/albums_tab.dart';
import 'tabs/artists_tab.dart';
import 'tabs/playlists_tab.dart';
import 'tabs/songs_tab.dart';
import 'widgets/empty_library.dart';
import 'widgets/library_builder.dart';
import 'widgets/mini_player.dart';
import 'youtube_import_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.music_note_outlined),
      selectedIcon: Icon(Icons.music_note),
      label: 'Songs',
    ),
    NavigationDestination(
      icon: Icon(Icons.album_outlined),
      selectedIcon: Icon(Icons.album),
      label: 'Albums',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Artists',
    ),
    NavigationDestination(
      icon: Icon(Icons.queue_music_outlined),
      selectedIcon: Icon(Icons.queue_music),
      label: 'Playlists',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'CASSETTE',
              style: theme.textTheme.titleLarge?.copyWith(
                letterSpacing: 3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchPage()),
            ),
          ),
          IconButton(
            tooltip: 'Import music',
            icon: const Icon(Icons.add),
            onPressed: () => startImport(context),
          ),
          if (kYouTubeImport)
            IconButton(
              tooltip: 'Add from YouTube link',
              icon: const Icon(Icons.link),
              onPressed: () => showYouTubeImport(context),
            ),
        ],
      ),
      body: LibraryBuilder<int>(
        load: (repo) => repo.trackCount(),
        builder: (context, count) {
          // Playlists are still reachable when the library is empty.
          if (count == 0 && _tab != 3) return const EmptyLibrary();
          return IndexedStack(
            index: _tab,
            children: const [
              SongsTab(),
              AlbumsTab(),
              ArtistsTab(),
              PlaylistsTab(),
            ],
          );
        },
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(hero: true),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: _destinations,
          ),
        ],
      ),
    );
  }
}
