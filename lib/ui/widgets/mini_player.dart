import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../playback/playback_controller.dart';
import '../feedback.dart';
import '../now_playing_page.dart';
import 'artwork.dart';
import 'position_builder.dart';

/// Compact player shown above the NavigationBar (and at the bottom of detail
/// pages) while something is loaded. Collapses to nothing otherwise.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.hero = false});

  /// Enables the shared-element artwork flight into Now Playing. Only one
  /// route in the stack should enable it (the home page).
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final track = playback.current;
    if (track == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = playback.duration ?? track.duration;
    final thumb = Artwork(path: track.artworkPath, size: 44, borderRadius: 6);

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => openNowPlaying(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 2,
              child: PositionBuilder(
                builder: (context, position) {
                  final ms = total.inMilliseconds;
                  final value = ms <= 0
                      ? 0.0
                      : (position.inMilliseconds / ms).clamp(0.0, 1.0).toDouble();
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    backgroundColor: scheme.surfaceContainerHighest,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  if (hero)
                    Hero(tag: kNowPlayingHeroTag, child: thumb)
                  else
                    thumb,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall),
                        Text(track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: playback.playing ? 'Pause' : 'Play',
                    iconSize: 32,
                    icon: Icon(playback.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    onPressed: () => runGuarded(context, playback.togglePlay,
                        errorMessage: "Couldn't play"),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: () => runGuarded(context, playback.next,
                        errorMessage: "Couldn't skip"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
