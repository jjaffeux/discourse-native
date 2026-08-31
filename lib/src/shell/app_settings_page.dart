import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appSettings = ShellScope.identityOf(context).appSettings;

    return Material(
      color: theme.shell.content,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            const _SettingsHeader(),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('app-settings-scroll-view'),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    key: const ValueKey('app-settings-form'),
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListenableBuilder(
                      listenable: appSettings,
                      builder: (context, _) => _ContentAlignmentSetting(
                        alignment: appSettings.contentAlignment,
                        onChanged: (alignment) => unawaited(
                          appSettings.setContentAlignment(alignment),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('app-settings-header'),
      height: shellHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        children: [
          DButton.iconOnly(
            key: const ValueKey('app-settings-back'),
            onPressed: () =>
                ShellScope.read(context).handleBack(canReturnToSidebar: false),
            icon: const DIcon(DIcons.arrowLeft, size: 20),
            tooltip: 'Back',
            semanticLabel: 'Back',
            variant: DButtonVariant.flat,
          ),
          const SizedBox(width: 4),
          Semantics(
            header: true,
            child: Text(
              'Settings',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentAlignmentSetting extends StatelessWidget {
  const _ContentAlignmentSetting({
    required this.alignment,
    required this.onChanged,
  });

  final ContentAlignment alignment;
  final ValueChanged<ContentAlignment> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Content alignment',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose where topic rows, posts, and chat messages appear in the '
          'available desktop space. Their reading lane is limited to 825 px; '
          'headers, toolbars, tabs, composers, and auxiliary panes continue '
          'to use the available width.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          key: const ValueKey('content-alignment-control'),
          container: true,
          explicitChildNodes: true,
          label: 'Content alignment options',
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ContentAlignment>(
              key: const ValueKey('content-alignment-segmented-button'),
              segments: const [
                ButtonSegment(
                  value: ContentAlignment.left,
                  label: Text('Left'),
                ),
                ButtonSegment(
                  value: ContentAlignment.center,
                  label: Text('Center'),
                ),
                ButtonSegment(
                  value: ContentAlignment.right,
                  label: Text('Right'),
                ),
              ],
              selected: {alignment},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => onChanged(selection.single),
            ),
          ),
        ),
      ],
    );
  }
}
