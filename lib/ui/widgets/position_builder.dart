import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../playback/playback_controller.dart';

/// Rebuilds [builder] with the current playback position.
///
/// The position stream is fetched once in initState so rebuilds of the
/// parent don't resubscribe to it.
class PositionBuilder extends StatefulWidget {
  const PositionBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Duration position) builder;

  @override
  State<PositionBuilder> createState() => _PositionBuilderState();
}

class _PositionBuilderState extends State<PositionBuilder> {
  late final Stream<Duration> _stream;
  late final Duration _initial;

  @override
  void initState() {
    super.initState();
    final playback = context.read<PlaybackController>();
    _stream = playback.positionStream;
    _initial = playback.position;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: _stream,
      initialData: _initial,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data ?? Duration.zero),
    );
  }
}
