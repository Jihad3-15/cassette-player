import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/library_repository.dart';
import 'track_actions.dart';
import 'widgets/mini_player.dart';
import 'widgets/track_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _debounce = Duration(milliseconds: 250);

  final TextEditingController _controller = TextEditingController();
  late final LibraryRepository _repo;
  StreamSubscription<void>? _changesSub;
  Timer? _timer;

  String _query = '';
  List<Track> _results = const [];
  bool _searching = false;
  Object? _error;

  /// Incremented per search so stale results are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repo = context.read<LibraryRepository>();
    // Re-run the current query if the library changes (e.g. a delete).
    _changesSub = _repo.changes.listen((_) => _run(_query));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _changesSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _run(text.trim()));
    setState(() {}); // update the clear button
  }

  Future<void> _run(String query) async {
    if (!mounted) return;
    final gen = ++_generation;
    _query = query;
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _repo.search(query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = results;
        _searching = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _searching = false;
        _error = e;
      });
    }
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    _run('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget body;
    if (_error != null) {
      body = _Message(icon: Icons.error_outline, text: 'Search failed: $_error');
    } else if (_query.isEmpty) {
      body = const _Message(
        icon: Icons.search,
        text: 'Search songs, artists, albums and genres.',
      );
    } else if (_results.isEmpty && !_searching) {
      body = _Message(icon: Icons.search_off, text: 'No matches for "$_query"');
    } else {
      final results = _results;
      body = ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) => TrackTile(
          track: results[i],
          onTap: () {
            FocusScope.of(context).unfocus();
            playList(context, results, i);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (text) {
            _timer?.cancel();
            _run(text.trim());
          },
          decoration: InputDecoration(
            hintText: 'Search your library',
            border: InputBorder.none,
            hintStyle: TextStyle(color: scheme.onSurfaceVariant),
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: _clear,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: SizedBox(
            height: 2,
            child: _searching ? const LinearProgressIndicator(minHeight: 2) : null,
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
