import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../format.dart';
import '../track_actions.dart';
import '../widgets/artwork.dart';
import '../widgets/library_builder.dart';
import '../widgets/track_list_page.dart';
import '../widgets/track_tile.dart';

class AlbumsTab extends StatelessWidget {
  const AlbumsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return LibraryBuilder<List<AlbumSummary>>(
      load: (repo) => repo.albums(),
      builder: (context, albums) {
        if (albums.isEmpty) {
          return const Center(child: Text('No albums yet'));
        }
        return GridView.builder(
          key: const PageStorageKey('albums'),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) => _AlbumCard(album: albums[i]),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AlbumDetailPage(album: album),
      )),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Artwork(
                    path: album.artworkPath, borderRadius: 10, cacheSize: 200),
              ),
            ),
            const SizedBox(height: 6),
            Text(album.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            Text(album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({super.key, required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context) {
    return LibraryBuilder<List<Track>>(
      pageScaffold: true,
      load: (repo) => repo.tracksForAlbum(album.album, album.artist),
      builder: (context, tracks) {
        String? art = album.artworkPath;
        if (art == null) {
          for (final t in tracks) {
            if (t.artworkPath != null) {
              art = t.artworkPath;
              break;
            }
          }
        }
        return TrackListPage(
          title: album.album,
          subtitle: album.artist,
          artworkPath: art,
          tracks: tracks,
          tileBuilder: (context, i) {
            final t = tracks[i];
            return TrackTile(
              track: t,
              leadingNumber: t.trackNumber ?? (i + 1),
              subtitle: t.artist == album.artist
                  ? formatDuration(t.duration)
                  : t.artist,
              onTap: () => playList(context, tracks, i),
            );
          },
        );
      },
    );
  }
}
