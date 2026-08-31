import 'package:flutter/material.dart';

import '../theme/d_button.dart';

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

    return SizedBox(
      height: height,
      child: Center(
        child: message == null
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              )
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
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
