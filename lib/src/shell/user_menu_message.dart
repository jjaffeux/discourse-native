import 'package:flutter/material.dart';

/// The waiting, empty and failed states a fetching surface shows in place of
/// its rows, given enough height that it does not collapse to nothing while it
/// has none.
///
/// A null [text] is the wait. Every tab and card that fetches its own content
/// wants the same three, so they are drawn in one place rather than once per
/// surface.
class UserMenuMessage extends StatelessWidget {
  const UserMenuMessage({
    super.key,
    required this.text,
    this.onRetry,
    this.height = 140,
  });

  final String? text;
  final VoidCallback? onRetry;

  /// The footprint held while waiting, so the surface does not jump around
  /// once its content arrives.
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = text;

    return SizedBox(
      height: height,
      child: Center(
        child: message == null
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (onRetry case final retry?)
                      TextButton(onPressed: retry, child: const Text('Retry')),
                  ],
                ),
              ),
      ),
    );
  }
}
