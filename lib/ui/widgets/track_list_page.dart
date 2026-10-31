import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../format.dart';
import '../track_actions.dart';
import 'artwork.dart';
import 'mini_player.dart';

/// Shared layout for album / artist / playlist detail pages: a header with
/// artwork, title, counts, Play + Shuffle buttons, then the track list.
class TrackListPage extends StatelessWidget {
  const TrackListPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.tileBuilder,
    this.artworkPath,
    this.headerIcon,
    this.actions = const [],
    this.emptyMessage = 'No songs here yet.',
  });

  final String title;
  final String subtitle;
  final List<Track> tracks;
  final Widget Function(BuildContext context, int index) tileBuilder;
  final String? artworkPath;

  /// Shown instead of artwork (artists, playlists).
  final IconData? headerIcon;
  final List<Widget> actions;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = tracks.fold<Duration>(Duration.zero, (a, t) => a + t.duration);

    final Widget art = headerIcon != null
        ? Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(headerIcon, size: 56, color: scheme.onPrimaryContainer),
          )
        : Artwork(path: artworkPath, size: 120, borderRadius: 16);

    return Scaffold(
      appBar: AppBar(actions: actions),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  art,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (subtitle.isNotEmpty)
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(color: scheme.primary)),
                        const SizedBox(height: 4),
                        Text(
                          tracks.isEmpty
                              ? songCount(0)
                              : '${songCount(tracks.length)} · ${formatTotal(total)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => playList(context, tracks, 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () => playList(context, tracks, 0, shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(emptyMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: tileBuilder,
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}
