import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class UserMenuMessage extends StatelessWidget {
  const UserMenuMessage({
    super.key,
    required this.text,
    this.onRetry,
    this.height = 140,
  });

  final String? text;
  final VoidCallback? onRetry;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = text;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Center(
        child: message == null
            ? const SizedBox(width: 22, height: 22, child: DSpinner())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRetry != null)
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (onRetry case final retry?)
                      DButton(
                        label: const Text('Retry'),
                        onPressed: retry,
                        variant: DButtonVariant.link,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class UserMenuLoading extends StatelessWidget {
  const UserMenuLoading({
    super.key,
    this.semanticsLabel = 'Loading notifications',
  });

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: semanticsLabel,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final width in const [0.65, 0.85, 0.5, 0.75, 0.6, 0.8])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DSkeleton(width: 16, height: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DSkeleton(height: 14),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: width,
                        child: const DSkeleton(height: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
