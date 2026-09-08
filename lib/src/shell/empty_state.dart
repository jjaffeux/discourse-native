import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'add_instance_sheet.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.shell.content,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DIcon(
                    DIcons.comments,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const DText(
                    'No sites yet',
                    textAlign: TextAlign.center,
                    variant: DTextVariant.h3,
                    headingLevel: 1,
                  ),
                  const SizedBox(height: 8),
                  const DText(
                    'Connect a Discourse forum to get started.',
                    textAlign: TextAlign.center,
                    variant: DTextVariant.muted,
                  ),
                  const SizedBox(height: 24),
                  DButton(
                    label: const Text('Add a site'),
                    onPressed: () => showAddInstanceSheet(context),
                    icon: const DIcon(DIcons.plus, size: 18),
                    variant: DButtonVariant.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
