import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/library_repository.dart';
import '../import/import_service.dart';
import '../playback/playback_controller.dart';
import 'feedback.dart';
import 'format.dart';
import 'widgets/dialogs.dart';

enum TrackAction { playNext, addToQueue, addToPlaylist, removeFromPlaylist, delete }

/// Plays [tracks] starting at [index], reporting errors in a SnackBar.
void playList(BuildContext context, List<Track> tracks, int index,
    {bool shuffle = false}) {
  if (tracks.isEmpty) return;
  final playback = context.read<PlaybackController>();
  runGuarded(
    context,
    () => playback.playTracks(tracks, startIndex: index, shuffle: shuffle),
    errorMessage: "Couldn't play",
  );
}

/// Bottom sheet listing the actions for [track].
/// [onRemoveFromPlaylist] adds a "Remove from playlist" entry when given.
Future<void> showTrackActions(
  BuildContext context,
  Track track, {
  VoidCallback? onRemoveFromPlaylist,
}) async {
  final action = await showModalBottomSheet<TrackAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      void pick(TrackAction a) => Navigator.of(sheetContext).pop(a);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${track.artist} · ${formatDuration(track.duration)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.queue_play_next),
              title: const Text('Play next'),
              onTap: () => pick(TrackAction.playNext),
            ),
            ListTile(
              leading: const Icon(Icons.add_to_queue),
              title: const Text('Add to queue'),
              onTap: () => pick(TrackAction.addToQueue),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () => pick(TrackAction.addToPlaylist),
            ),
            if (onRemoveFromPlaylist != null)
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: const Text('Remove from this playlist'),
                onTap: () => pick(TrackAction.removeFromPlaylist),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error),
              title: Text('Delete from library',
                  style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error)),
              onTap: () => pick(TrackAction.delete),
            ),
          ],
        ),
      );
    },
  );
  if (!context.mounted) return;
  if (action == null) return;
  await handleTrackAction(context, track, action,
      onRemoveFromPlaylist: onRemoveFromPlaylist);
}

Future<void> handleTrackAction(
  BuildContext context,
  Track track,
  TrackAction action, {
  VoidCallback? onRemoveFromPlaylist,
}) async {
  final playback = context.read<PlaybackController>();
  switch (action) {
    case TrackAction.playNext:
      await runGuarded(context, () => playback.playNext(track),
          errorMessage: "Couldn't add", successMessage: 'Playing next');
    case TrackAction.addToQueue:
      await runGuarded(context, () => playback.addToQueue(track),
          errorMessage: "Couldn't add", successMessage: 'Added to queue');
    case TrackAction.addToPlaylist:
      await showAddToPlaylist(context, [track]);
    case TrackAction.removeFromPlaylist:
      onRemoveFromPlaylist?.call();
    case TrackAction.delete:
      await confirmAndDeleteTrack(context, track);
  }
}

Future<void> confirmAndDeleteTrack(BuildContext context, Track track) async {
  final importer = context.read<ImportService>();
  final playback = context.read<PlaybackController>();
  final ok = await showConfirmDialog(
    context,
    title: 'Delete song?',
    message: '"${track.title}" will be removed from your library and its '
        'file deleted from this phone. This cannot be undone.',
  );
  if (!context.mounted) return;
  if (!ok) return;
  await runGuarded(
    context,
    () async {
      await importer.deleteTrack(track.id);
      await playback.removeTrackEverywhere(track.id);
    },
    errorMessage: "Couldn't delete",
    successMessage: 'Deleted "${track.title}"',
  );
}

/// Picks a playlist (or creates a new one) and adds [tracks] to it.
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return;
  final repo = context.read<LibraryRepository>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  List<Playlist> lists;
  try {
    lists = await repo.playlists();
  } catch (e) {
    showSnack(messenger, "Couldn't load playlists: $e");
    return;
  }
  if (!context.mounted) return;

  // -1 means "new playlist".
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Add to playlist',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.add)),
            title: const Text('New playlist'),
            onTap: () => Navigator.of(sheetContext).pop(-1),
          ),
          for (final p in lists)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.queue_music)),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(songCount(p.trackCount)),
              onTap: () => Navigator.of(sheetContext).pop(p.id),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (picked == null) return;

  var playlistId = picked;
  String? playlistName;
  for (final p in lists) {
    if (p.id == picked) playlistName = p.name;
  }
  if (picked == -1) {
    final name = await showNameDialog(context,
        title: 'New playlist', confirmLabel: 'Create');
    if (!context.mounted) return;
    if (name == null) return;
    try {
      playlistId = await repo.createPlaylist(name);
      playlistName = name;
    } catch (e) {
      showSnack(messenger, "Couldn't create playlist: $e");
      return;
    }
  }

  try {
    await repo.addToPlaylist(playlistId, tracks.map((t) => t.id).toList());
    final what = tracks.length == 1 ? '"${tracks.first.title}"' : songCount(tracks.length);
    showSnack(messenger, 'Added $what to ${playlistName ?? 'playlist'}');
  } catch (e) {
    showSnack(messenger, "Couldn't add to playlist: $e");
  }
}
