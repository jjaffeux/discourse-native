import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';

Future<void> showForumSettingsDialog(
  BuildContext context, {
  required String siteUrl,
  required String name,
}) => showDDialog<void>(
  context: context,
  builder: (_, _) => ForumSettingsDialog(siteUrl: siteUrl, name: name),
);

class ForumSettingsDialog extends StatelessWidget {
  const ForumSettingsDialog({
    super.key,
    required this.siteUrl,
    required this.name,
  });

  final String siteUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final settings = ShellScope.identityOf(context).forumSettings;
    return DDialogContent(
      key: const ValueKey('forum-settings-dialog'),
      maxWidth: 600,
      semanticLabel: 'Settings',
      spacing: DSpacing.xl,
      closeButton: DDialogClose<void>(
        builder: (_, close) => DButton.iconOnly(
          key: const ValueKey('forum-settings-close'),
          onPressed: close,
          icon: const DIcon(DIcons.xmark),
          tooltip: 'Close',
          semanticLabel: 'Close settings',
          size: DButtonSize.small,
          variant: DButtonVariant.ghost,
        ),
      ),
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(
              child: Semantics(headingLevel: 1, child: const Text('Settings')),
            ),
            DDialogDescription(child: Text('Preferences for $name.')),
          ],
        ),
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => DFieldGroup(
            children: [
              DField(
                orientation: MediaQuery.textScalerOf(context).scale(14) > 21
                    ? DFieldOrientation.vertical
                    : DFieldOrientation.responsive,
                responsiveBreakpoint: 520,
                children: [
                  const DFieldContent(
                    children: [
                      DFieldTitle(child: Text('Appearance')),
                      DFieldDescription(
                        child: Text(
                          'Choose a theme or follow your system settings.',
                        ),
                      ),
                    ],
                  ),
                  DSelect<AppThemeMode>.controlled(
                    key: const ValueKey('appearance-theme-select'),
                    semanticLabel: 'Appearance',
                    value: settings.themeModeFor(siteUrl),
                    entries: const [
                      DSelectOption(
                        value: AppThemeMode.system,
                        label: 'System',
                        child: Text('System'),
                      ),
                      DSelectOption(
                        value: AppThemeMode.light,
                        label: 'Light',
                        child: Text('Light'),
                      ),
                      DSelectOption(
                        value: AppThemeMode.dark,
                        label: 'Dark',
                        child: Text('Dark'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) {
                        unawaited(settings.setThemeMode(siteUrl, mode));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
