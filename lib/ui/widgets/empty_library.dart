import 'package:flutter/material.dart';

import '../import_flow.dart';
import 'artwork.dart';

/// Shown when the library has no tracks yet.
class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CassettePlaceholder(),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('Your tape deck is empty',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                'Import songs from your phone to start listening. Files are '
                'copied into Cassette and stay on this phone. Nothing is '
                'uploaded anywhere.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(220, 56),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: () => startImport(context),
                icon: const Icon(Icons.library_add),
                label: const Text('Import music'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Private and offline',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
