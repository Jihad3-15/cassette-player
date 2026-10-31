import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../format.dart';
import '../track_actions.dart';
import '../widgets/library_builder.dart';
import '../widgets/track_tile.dart';

class SongsTab extends StatefulWidget {
  const SongsTab({super.key});

  @override
  State<SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<SongsTab> {
  TrackSort _sort = TrackSort.title;

  static const _labels = {
    TrackSort.title: 'Title',
    TrackSort.artist: 'Artist',
    TrackSort.album: 'Album',
    TrackSort.recentlyAdded: 'Recently added',
  };

  @override
  Widget build(BuildContext context) {
    final sort = _sort;
    return LibraryBuilder<List<Track>>(
      reloadKey: sort,
      load: (repo) => repo.allTracks(sort: sort),
      builder: (context, tracks) {
        final theme = Theme.of(context);
        return CustomScrollView(
          key: const PageStorageKey('songs'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => playList(context, tracks, 0, shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle all'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(songCount(tracks.length),
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    PopupMenuButton<TrackSort>(
                      tooltip: 'Sort',
                      initialValue: _sort,
                      onSelected: (s) => setState(() => _sort = s),
                      itemBuilder: (context) => [
                        for (final s in TrackSort.values)
                          CheckedPopupMenuItem<TrackSort>(
                            value: s,
                            checked: s == _sort,
                            child: Text(_labels[s]!),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, size: 20),
                            const SizedBox(width: 6),
                            Text(_labels[_sort]!,
                                style: theme.textTheme.labelLarge),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackTile(
                track: tracks[i],
                onTap: () => playList(context, tracks, i),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        );
      },
    );
  }
}
