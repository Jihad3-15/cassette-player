import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../playback/playback_controller.dart';
import 'feedback.dart';
import 'format.dart';
import 'widgets/artwork.dart';
import 'widgets/position_builder.dart';

const String kNowPlayingHeroTag = 'now-playing-art';

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const NowPlayingPage(),
    ),
  );
}

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  // Turns the reels on the cassette placeholder while playing.
  late final AnimationController _reels = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void dispose() {
    _reels.dispose();
    super.dispose();
  }

  /// Starts/stops the reel animation after the frame, so the controller is
  /// never driven from inside build.
  void _syncReels(bool playing) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (playing && !_reels.isAnimating) {
        _reels.repeat();
      } else if (!playing && _reels.isAnimating) {
        _reels.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final track = playback.current;
    _syncReels(playback.playing && track != null);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('NOW PLAYING',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: track == null
          ? const Center(child: Text('Nothing is playing'))
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > constraints.maxHeight &&
                    constraints.maxWidth > 700;
                final player = _PlayerPanel(track: track, reels: _reels);
                final queue = _UpNext(playback: playback);
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: SingleChildScrollView(child: player)),
                      const VerticalDivider(width: 1),
                      Expanded(child: queue),
                    ],
                  );
                }
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: player),
                    ...queue.slivers(context),
                  ],
                );
              },
            ),
    );
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({required this.track, required this.reels});

  final Track track;
  final Animation<double> reels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final playback = context.watch<PlaybackController>();
    final size = MediaQuery.sizeOf(context);
    final artSize = (size.width - 64).clamp(160.0, 380.0).toDouble();
    final art = track.artworkPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          Center(
            child: Hero(
              tag: kNowPlayingHeroTag,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: SizedBox.square(
                  dimension: artSize,
                  child: art == null || art.isEmpty
                      ? CassettePlaceholder(spin: reels)
                      : Artwork(
                          path: art,
                          size: artSize,
                          borderRadius: 0,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(track.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(track.artist,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: scheme.primary)),
          Text(track.album,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          _SeekBar(total: playback.duration ?? track.duration),
          const SizedBox(height: 8),
          _Transport(playback: playback),
        ],
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.total});

  final Duration total;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  /// Position (ms) while the user is dragging; null when not dragging.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalMs = widget.total.inMilliseconds.toDouble();
    final tabular = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return PositionBuilder(
      builder: (context, position) {
        final max = totalMs > 0 ? totalMs : 1.0;
        final current =
            (_dragMs ?? position.inMilliseconds.toDouble())
            .clamp(0.0, max)
            .toDouble();
        return Column(
          children: [
            Slider(
              value: current,
              max: max,
              onChanged: totalMs <= 0
                  ? null
                  : (v) => setState(() => _dragMs = v),
              onChangeEnd: (v) {
                final playback = context.read<PlaybackController>();
                setState(() => _dragMs = null);
                runGuarded(
                  context,
                  () => playback.seek(Duration(milliseconds: v.round())),
                  errorMessage: "Couldn't seek",
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(Duration(milliseconds: current.round())),
                      style: tabular),
                  Text(formatDuration(widget.total), style: tabular),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repeat = playback.repeat;
    final repeatLabel = switch (repeat) {
      RepeatMode.off => 'Repeat off',
      RepeatMode.all => 'Repeat all',
      RepeatMode.one => 'Repeat one',
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: playback.shuffle ? 'Shuffle on' : 'Shuffle off',
          isSelected: playback.shuffle,
          color: scheme.onSurfaceVariant,
          selectedIcon: Icon(Icons.shuffle_rounded, color: scheme.primary),
          icon: const Icon(Icons.shuffle_rounded),
          onPressed: () => runGuarded(
              context, () => playback.setShuffle(!playback.shuffle),
              errorMessage: "Couldn't change shuffle"),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: () => runGuarded(context, playback.previous,
              errorMessage: "Couldn't go back"),
        ),
        IconButton.filled(
          tooltip: playback.playing ? 'Pause' : 'Play',
          iconSize: 44,
          padding: const EdgeInsets.all(14),
          icon: Icon(
              playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: () => runGuarded(context, playback.togglePlay,
              errorMessage: "Couldn't play"),
        ),
        IconButton(
          tooltip: 'Next',
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: () =>
              runGuarded(context, playback.next, errorMessage: "Couldn't skip"),
        ),
        IconButton(
          tooltip: repeatLabel,
          isSelected: repeat != RepeatMode.off,
          color: scheme.onSurfaceVariant,
          selectedIcon: Icon(
            repeat == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: scheme.primary,
          ),
          icon: const Icon(Icons.repeat_rounded),
          onPressed: () => runGuarded(context, playback.cycleRepeat,
              errorMessage: "Couldn't change repeat"),
        ),
      ],
    );
  }
}

/// The queue. Rendered as slivers under the player on phones, or as its own
/// scrolling list beside the player on wide screens.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.playback});

  final PlaybackController playback;

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = playback.queue.length -
        (playback.currentIndex < 0 ? 0 : playback.currentIndex + 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text('UP NEXT',
              style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary)),
          const Spacer(),
          Text(remaining > 0 ? songCount(remaining) : 'End of queue',
              style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    final theme = Theme.of(context);
    final queue = playback.queue;
    final t = queue[index];
    final isCurrent = index == playback.currentIndex;
    final isPast = playback.currentIndex >= 0 && index < playback.currentIndex;
    return Opacity(
      opacity: isPast ? 0.55 : 1,
      child: ListTile(
        dense: true,
        selected: isCurrent,
        leading: SizedBox(
          width: 28,
          child: Center(
            child: isCurrent
                ? Icon(Icons.graphic_eq, color: theme.colorScheme.primary)
                : Text('${index + 1}', style: theme.textTheme.labelMedium),
          ),
        ),
        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(formatDuration(t.duration),
            style: theme.textTheme.bodySmall),
        onTap: () => runGuarded(
            context, () => playback.skipToQueueIndex(index),
            errorMessage: "Couldn't skip"),
      ),
    );
  }

  List<Widget> slivers(BuildContext context) => [
        SliverToBoxAdapter(child: _header(context)),
        SliverList.builder(
          itemCount: playback.queue.length,
          itemBuilder: _row,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(context),
        Expanded(
          child: ListView.builder(
            itemCount: playback.queue.length,
            itemBuilder: _row,
          ),
        ),
      ],
    );
  }
}
