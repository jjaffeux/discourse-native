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
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ContentAlignmentSetting(
                            alignment: appSettings.contentAlignment,
                            onChanged: (alignment) => unawaited(
                              appSettings.setContentAlignment(alignment),
                            ),
                          ),
                          const SizedBox(height: 36),
                          _TextSizeSetting(
                            scale: appSettings.textScale,
                            onDecrease: appSettings.textScale.index == 0
                                ? null
                                : () => unawaited(
                                    appSettings.decreaseTextScale(),
                                  ),
                            onIncrease:
                                appSettings.textScale.index ==
                                    AppTextScale.values.length - 1
                                ? null
                                : () => unawaited(
                                    appSettings.increaseTextScale(),
                                  ),
                            onReset:
                                appSettings.textScale == AppTextScale.percent100
                                ? null
                                : () => unawaited(appSettings.resetTextScale()),
                          ),
                          const SizedBox(height: 36),
                          SwitchListTile.adaptive(
                            key: const ValueKey(
                              'disable-gif-animations-switch',
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Disable GIF animations'),
                            subtitle: const Text(
                              'Pause GIFs by default in posts and chat messages.',
                            ),
                            value: appSettings.disableGifAnimations,
                            onChanged: (disabled) => unawaited(
                              appSettings.setDisableGifAnimations(disabled),
                            ),
                          ),
                        ],
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

class _TextSizeSetting extends StatelessWidget {
  const _TextSizeSetting({
    required this.scale,
    required this.onDecrease,
    required this.onIncrease,
    required this.onReset,
  });

  final AppTextScale scale;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (scale.factor * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Text size',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Applies across every forum. On desktop, use Command or Control '
          'with + or −; use the same modifier with 0 to reset.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton.iconOnly(
              key: const ValueKey('text-size-decrease'),
              onPressed: onDecrease,
              icon: const DIcon(DIcons.minus, size: 16),
              tooltip: 'Decrease text size',
              semanticLabel: 'Decrease text size',
              size: DButtonSize.small,
            ),
            Semantics(
              key: const ValueKey('text-size-value'),
              container: true,
              excludeSemantics: true,
              label: 'Current text size',
              value: '$percentage percent',
              liveRegion: true,
              child: SizedBox(
                width: 64,
                child: Center(
                  child: Text(
                    '$percentage%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            DButton.iconOnly(
              key: const ValueKey('text-size-increase'),
              onPressed: onIncrease,
              icon: const DIcon(DIcons.plus, size: 16),
              tooltip: 'Increase text size',
              semanticLabel: 'Increase text size',
              size: DButtonSize.small,
            ),
            DButton(
              key: const ValueKey('text-size-reset'),
              label: const Text('Reset'),
              onPressed: onReset,
              size: DButtonSize.small,
            ),
          ],
        ),
      ],
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
