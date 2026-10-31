import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../playback/playback_controller.dart';
import '../format.dart';
import '../track_actions.dart';
import 'artwork.dart';

/// A song row: artwork, title, artist/album, duration and an actions menu.
/// Highlights itself when it is the track currently playing.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.leadingNumber,
    this.showArtwork = true,
    this.subtitle,
    this.onRemoveFromPlaylist,
  });

  final Track track;
  final VoidCallback onTap;

  /// Shows a track number instead of artwork (album pages).
  final int? leadingNumber;
  final bool showArtwork;
  final String? subtitle;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = context.select<PlaybackController, bool>(
        (p) => p.current?.id == track.id);

    final Widget? leading;
    if (leadingNumber != null) {
      leading = SizedBox(
        width: 32,
        child: Center(
          child: isCurrent
              ? Icon(Icons.graphic_eq, color: theme.colorScheme.primary)
              : Text('$leadingNumber',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    } else if (showArtwork) {
      leading = Stack(
        children: [
          Artwork(path: track.artworkPath, size: 48, borderRadius: 6),
          if (isCurrent)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.graphic_eq, color: Colors.white),
              ),
            ),
        ],
      );
    } else {
      leading = null;
    }

    final sub = subtitle ?? '${track.artist} · ${track.album}';

    return ListTile(
      leading: leading,
      selected: isCurrent,
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatDuration(track.duration),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onPressed: () => showTrackActions(context, track,
                onRemoveFromPlaylist: onRemoveFromPlaylist),
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: () => showTrackActions(context, track,
          onRemoveFromPlaylist: onRemoveFromPlaylist),
    );
  }
}
