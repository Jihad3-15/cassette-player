import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../youtube/youtube_import_service.dart';

/// Opens the "Add from YouTube" sheet. Only reachable in builds made with
/// kYouTubeImport on.
Future<void> showYouTubeImport(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: true,
    builder: (_) => const YouTubeImportSheet(),
  );
}

class YouTubeImportSheet extends StatefulWidget {
  const YouTubeImportSheet({super.key});

  @override
  State<YouTubeImportSheet> createState() => _YouTubeImportSheetState();
}

class _YouTubeImportSheetState extends State<YouTubeImportSheet> {
  final _link = TextEditingController();
  bool _confirmed = false;
  bool _asMp3 = true;
  bool _running = false;
  YouTubeProgress? _progress;
  StreamSubscription<YouTubeProgress>? _sub;

  bool get _validLink => YouTubeImportService.videoIdFrom(_link.text) != null;

  @override
  void initState() {
    super.initState();
    _link.addListener(() => setState(() {}));
    _prefillFromClipboard();
  }

  Future<void> _prefillFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (!mounted || text == null || _link.text.isNotEmpty) return;
      if (YouTubeImportService.videoIdFrom(text) != null) _link.text = text;
    } catch (_) {
      // Clipboard access is optional.
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null) return;
    _link.text = text;
  }

  void _start() {
    final service = context.read<YouTubeImportService>();
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _progress = null;
    });
    _sub = service.importLink(_link.text, asMp3: _asMp3).listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          if (p.finished) _running = false;
        });
      },
      onDone: () {
        if (mounted) setState(() => _running = false);
      },
    );
  }

  void _cancel() => context.read<YouTubeImportService>().cancel();

  void _reset() {
    setState(() {
      _progress = null;
      _link.clear();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;
    final finished = progress?.finished ?? false;
    final failed = progress?.phase == YouTubePhase.failed;

    return PopScope(
      canPop: !_running,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add from YouTube', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Saves the video\'s audio on this phone. Nothing is uploaded.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              enabled: !_running,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'YouTube link',
                hintText: 'https://youtu.be/…',
                border: const OutlineInputBorder(),
                errorText: _link.text.isNotEmpty && !_validLink
                    ? "That isn't a YouTube video link"
                    : null,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _running ? null : _paste,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _asMp3,
              onChanged: _running ? null : (v) => setState(() => _asMp3 = v),
              title: const Text('Save as MP3'),
              subtitle: Text(_asMp3
                  ? 'Converted on the phone. Plays anywhere; slightly lower quality.'
                  : 'Keeps YouTube\'s original audio (.m4a). Best quality.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _confirmed,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _confirmed = v ?? false),
              title: const Text('I have the right to save this'),
              subtitle: const Text(
                  'My own uploads, Creative Commons, or audio the creator lets people download.'),
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              if (progress.title != null)
                Text(progress.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: finished
                    ? 1
                    : progress.phase == YouTubePhase.downloading
                        ? progress.fraction
                        : null,
                color: failed ? theme.colorScheme.error : null,
              ),
              const SizedBox(height: 8),
              Text(
                progress.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: failed ? theme.colorScheme.error : null),
              ),
            ],
            const SizedBox(height: 16),
            if (_running)
              OutlinedButton(onPressed: _cancel, child: const Text('Cancel'))
            else if (finished)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: _reset, child: const Text('Add another')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done')),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _validLink && _confirmed ? _start : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Save audio'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
