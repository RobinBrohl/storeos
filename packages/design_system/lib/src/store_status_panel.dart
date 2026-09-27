import 'package:flutter/material.dart';

import 'store_spacing.dart';

enum StoreStatusTone { neutral, positive, warning, critical }

class StoreStatusPanel extends StatelessWidget {
  const StoreStatusPanel({
    required this.title,
    required this.message,
    required this.tone,
    super.key,
  });

  final String title;
  final String message;
  final StoreStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (tone) {
      StoreStatusTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
        Icons.info_outline,
      ),
      StoreStatusTone.positive => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      StoreStatusTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      StoreStatusTone.critical => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(StoreSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: foreground)),
              const SizedBox(width: StoreSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: StoreSpacing.xs),
                    Text(message, style: TextStyle(color: foreground)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
