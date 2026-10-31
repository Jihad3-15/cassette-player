import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../format.dart';
import '../track_actions.dart';
import '../widgets/library_builder.dart';
import '../widgets/track_list_page.dart';
import '../widgets/track_tile.dart';

class ArtistsTab extends StatelessWidget {
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return LibraryBuilder<List<ArtistSummary>>(
      load: (repo) => repo.artists(),
      builder: (context, artists) {
        if (artists.isEmpty) {
          return const Center(child: Text('No artists yet'));
        }
        final scheme = Theme.of(context).colorScheme;
        return ListView.builder(
          key: const PageStorageKey('artists'),
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final a = artists[i];
            final initial =
                a.name.trim().isEmpty ? '?' : a.name.trim().characters.first;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.secondaryContainer,
                foregroundColor: scheme.onSecondaryContainer,
                child: Text(initial.toUpperCase()),
              ),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(songCount(a.trackCount)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ArtistDetailPage(artist: a.name),
              )),
            );
          },
        );
      },
    );
  }
}

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({super.key, required this.artist});

  final String artist;

  @override
  Widget build(BuildContext context) {
    return LibraryBuilder<List<Track>>(
      pageScaffold: true,
      load: (repo) => repo.tracksForArtist(artist),
      builder: (context, tracks) => TrackListPage(
        title: artist,
        subtitle: 'Artist',
        headerIcon: Icons.person_rounded,
        tracks: tracks,
        tileBuilder: (context, i) => TrackTile(
          track: tracks[i],
          subtitle: tracks[i].album,
          onTap: () => playList(context, tracks, i),
        ),
      ),
    );
  }
}
