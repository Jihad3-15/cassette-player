import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_repository.dart';

typedef LibraryLoad<T> = Future<T> Function(LibraryRepository repo);
typedef LibraryWidgetBuilder<T> = Widget Function(BuildContext context, T data);

/// Loads data from the [LibraryRepository] and reloads it every time
/// [LibraryRepository.changes] emits. Keeps showing the previous data while a
/// reload is in flight, so lists don't flicker during imports.
class LibraryBuilder<T> extends StatefulWidget {
  const LibraryBuilder({
    super.key,
    required this.load,
    required this.builder,
    this.reloadKey,
    this.pageScaffold = false,
  });

  final LibraryLoad<T> load;
  final LibraryWidgetBuilder<T> builder;

  /// When this value changes between builds, the data is reloaded
  /// (for example a sort order).
  final Object? reloadKey;

  /// Wraps the loading / error states in a Scaffold with an AppBar, for use
  /// as the root of a pushed page.
  final bool pageScaffold;

  @override
  State<LibraryBuilder<T>> createState() => _LibraryBuilderState<T>();
}

class _LibraryBuilderState<T> extends State<LibraryBuilder<T>> {
  late final LibraryRepository _repo;
  StreamSubscription<void>? _sub;

  T? _data;
  bool _hasData = false;
  Object? _error;

  bool _inFlight = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _repo = context.read<LibraryRepository>();
    _sub = _repo.changes.listen((_) => _reload());
    _reload();
  }

  @override
  void didUpdateWidget(LibraryBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _reload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  /// Coalesces bursts of change events: at most one load runs at a time and
  /// one more is queued if anything changed meanwhile.
  Future<void> _reload() async {
    if (_inFlight) {
      _dirty = true;
      return;
    }
    _inFlight = true;
    try {
      do {
        _dirty = false;
        try {
          final data = await widget.load(_repo);
          if (!mounted) return;
          setState(() {
            _data = data;
            _hasData = true;
            _error = null;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() => _error = e);
        }
      } while (_dirty && mounted);
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasData) return widget.builder(context, _data as T);
    final body = _buildPlaceholder();
    if (!widget.pageScaffold) return body;
    return Scaffold(appBar: AppBar(), body: body);
  }

  Widget _buildPlaceholder() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                "Couldn't load your library.\n$error",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
