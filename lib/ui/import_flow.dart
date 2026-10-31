import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../import/import_service.dart';
import 'feedback.dart';

/// Opens the file picker, then shows import progress in a bottom sheet that
/// can only be dismissed once the import has finished.
Future<void> startImport(BuildContext context) async {
  final importer = context.read<ImportService>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  List<String> paths;
  try {
    paths = await importer.pickAudioFiles();
  } catch (e) {
    showSnack(messenger, "Couldn't open the file picker: $e");
    return;
  }
  if (!context.mounted) return;
  if (paths.isEmpty) return;

  // Created once here: the sheet builder may run more than once.
  final progress = importer.importFiles(paths);
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => ImportProgressSheet(
      stream: progress,
      total: paths.length,
    ),
  );
}

class ImportProgressSheet extends StatefulWidget {
  const ImportProgressSheet({
    super.key,
    required this.stream,
    required this.total,
  });

  final Stream<ImportProgress> stream;
  final int total;

  @override
  State<ImportProgressSheet> createState() => _ImportProgressSheetState();
}

class _ImportProgressSheetState extends State<ImportProgressSheet> {
  StreamSubscription<ImportProgress>? _sub;
  late ImportProgress _progress = ImportProgress(
    total: widget.total,
    processed: 0,
    added: 0,
    duplicates: 0,
    failed: 0,
  );
  Object? _error;

  /// True once the stream has finished, errored, or sent finished == true.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          if (p.finished) _done = true;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _done = true;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _done = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = _progress;
    final total = p.total > 0 ? p.total : widget.total;
    final fraction = total == 0 ? null : (p.processed / total).clamp(0.0, 1.0).toDouble();

    return PopScope(
      canPop: _done,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _done
                        ? (_error == null
                            ? Icons.check_circle_outline
                            : Icons.error_outline)
                        : Icons.downloading,
                    color: _error == null ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _done
                          ? (_error == null ? 'Import finished' : 'Import stopped')
                          : 'Importing music…',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _done ? 1 : fraction,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text('${p.processed} of $total files',
                  style: theme.textTheme.bodyMedium),
              if (!_done) ...[
                const SizedBox(height: 4),
                Text(
                  p.currentFile ?? 'Preparing…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _Stat(label: 'Added', value: p.added, color: scheme.primary),
                  _Stat(
                      label: 'Duplicates',
                      value: p.duplicates,
                      color: scheme.tertiary),
                  _Stat(label: 'Failed', value: p.failed, color: scheme.error),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text('$_error',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.error)),
              ],
              const SizedBox(height: 12),
              Text(
                'Files are copied into the app and stay on this phone.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _done ? () => Navigator.of(context).pop() : null,
                child: Text(_done ? 'Done' : 'Please wait…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text('$value',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
