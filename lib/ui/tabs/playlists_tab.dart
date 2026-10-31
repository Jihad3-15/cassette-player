import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../data/library_repository.dart';
import '../feedback.dart';
import '../format.dart';
import '../track_actions.dart';
import '../widgets/dialogs.dart';
import '../widgets/library_builder.dart';
import '../widgets/track_list_page.dart';
import '../widgets/track_tile.dart';

Future<void> createPlaylistFlow(BuildContext context) async {
  final repo = context.read<LibraryRepository>();
  final name =
      await showNameDialog(context, title: 'New playlist', confirmLabel: 'Create');
  if (!context.mounted) return;
  if (name == null) return;
  await runGuarded(context, () => repo.createPlaylist(name),
      errorMessage: "Couldn't create playlist");
}

Future<void> renamePlaylistFlow(BuildContext context, Playlist playlist) async {
  final repo = context.read<LibraryRepository>();
  final name = await showNameDialog(context,
      title: 'Rename playlist', initial: playlist.name, confirmLabel: 'Rename');
  if (!context.mounted) return;
  if (name == null || name == playlist.name) return;
  await runGuarded(context, () => repo.renamePlaylist(playlist.id, name),
      errorMessage: "Couldn't rename playlist");
}

/// Returns true if the playlist was deleted.
Future<bool> deletePlaylistFlow(BuildContext context, Playlist playlist) async {
  final repo = context.read<LibraryRepository>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await showConfirmDialog(
    context,
    title: 'Delete playlist?',
    message: '"${playlist.name}" will be deleted. The songs stay in your library.',
  );
  if (!ok) return false;
  try {
    await repo.deletePlaylist(playlist.id);
    showSnack(messenger, 'Deleted "${playlist.name}"');
    return true;
  } catch (e) {
    showSnack(messenger, "Couldn't delete playlist: $e");
    return false;
  }
}

enum _PlaylistMenu { rename, delete }

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return LibraryBuilder<List<Playlist>>(
      load: (repo) => repo.playlists(),
      builder: (context, lists) {
        final scheme = Theme.of(context).colorScheme;
        return ListView(
          key: const PageStorageKey('playlists'),
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.add),
              ),
              title: const Text('New playlist'),
              onTap: () => createPlaylistFlow(context),
            ),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No playlists yet. Make a mixtape: create a playlist, then '
                  'add songs from any song menu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            for (final p in lists)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                  child: const Icon(Icons.queue_music_rounded),
                ),
                title:
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(songCount(p.trackCount)),
                trailing: PopupMenuButton<_PlaylistMenu>(
                  tooltip: 'More',
                  onSelected: (m) {
                    switch (m) {
                      case _PlaylistMenu.rename:
                        renamePlaylistFlow(context, p);
                      case _PlaylistMenu.delete:
                        deletePlaylistFlow(context, p);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: _PlaylistMenu.rename, child: Text('Rename')),
                    PopupMenuItem(
                        value: _PlaylistMenu.delete, child: Text('Delete')),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PlaylistDetailPage(playlist: p),
                )),
              ),
          ],
        );
      },
    );
  }
}

/// The playlist's current name/count come from the repository (so renames
/// show up); its tracks are loaded separately.
class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return LibraryBuilder<_PlaylistData>(
      pageScaffold: true,
      load: (repo) async {
        final lists = await repo.playlists();
        Playlist? current;
        for (final p in lists) {
          if (p.id == playlist.id) current = p;
        }
        final tracks = current == null
            ? const <Track>[]
            : await repo.tracksForPlaylist(playlist.id);
        return _PlaylistData(current, tracks);
      },
      builder: (context, data) {
        final p = data.playlist;
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This playlist was deleted.')),
          );
        }
        final tracks = data.tracks;
        return TrackListPage(
          title: p.name,
          subtitle: 'Playlist',
          headerIcon: Icons.queue_music_rounded,
          tracks: tracks,
          emptyMessage:
              'This playlist is empty. Add songs with "Add to playlist" '
              'from any song menu.',
          actions: [
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => renamePlaylistFlow(context, p),
            ),
            IconButton(
              tooltip: 'Delete playlist',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final deleted = await deletePlaylistFlow(context, p);
                if (deleted && navigator.mounted) navigator.pop();
              },
            ),
          ],
          tileBuilder: (context, i) => TrackTile(
            // Position-based key: the same song can appear twice.
            key: ValueKey('pl-${p.id}-$i-${tracks[i].id}'),
            track: tracks[i],
            onTap: () => playList(context, tracks, i),
            onRemoveFromPlaylist: () => _removeAt(context, p, i),
          ),
        );
      },
    );
  }

  void _removeAt(BuildContext context, Playlist p, int position) {
    final repo = context.read<LibraryRepository>();
    runGuarded(
      context,
      () => repo.removeFromPlaylist(p.id, position),
      errorMessage: "Couldn't remove",
      successMessage: 'Removed from ${p.name}',
    );
  }
}

class _PlaylistData {
  const _PlaylistData(this.playlist, this.tracks);
  final Playlist? playlist;
  final List<Track> tracks;
}
