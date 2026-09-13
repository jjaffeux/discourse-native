import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'app_home_theme.dart';
import 'shell_scope.dart';

Future<void> showAppSettingsModal(BuildContext context) async {
  final shell = ShellScope.read(context);
  if (!shell.openAppSettingsModal()) return;

  try {
    await showDDialog<void>(
      context: context,
      builder: (_, _) => const AppSettingsModal(),
    );
  } finally {
    shell.closeAppSettingsModal();
  }
}

class AppSettingsModal extends StatelessWidget {
  const AppSettingsModal({super.key});

  @override
  Widget build(BuildContext context) {
    final appSettings = ShellScope.identityOf(context).appSettings;
    return AppHomeTheme(
      child: DDialogContent(
        key: const ValueKey('app-settings-modal'),
        maxWidth: 600,
        semanticLabel: 'Settings',
        spacing: DSpacing.xl,
        closeButton: DDialogClose<void>(
          builder: (_, close) => DButton.iconOnly(
            key: const ValueKey('app-settings-close'),
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
            key: const ValueKey('app-settings-header'),
            children: [
              DDialogTitle(
                child: Semantics(
                  headingLevel: 1,
                  child: const Text('Settings'),
                ),
              ),
              const DDialogDescription(
                child: Text('Preferences for all your forums.'),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: appSettings,
            builder: (context, _) => DFieldGroup(
              key: const ValueKey('app-settings-form'),
              children: [
                _ContentAlignmentSetting(
                  alignment: appSettings.contentAlignment,
                  onChanged: (alignment) =>
                      unawaited(appSettings.setContentAlignment(alignment)),
                ),
                const DFieldSeparator(),
                _TextSizeSetting(
                  scale: appSettings.textScale,
                  onDecrease: appSettings.textScale.index == 0
                      ? null
                      : () => unawaited(appSettings.decreaseTextScale()),
                  onIncrease:
                      appSettings.textScale.index ==
                          AppTextScale.values.length - 1
                      ? null
                      : () => unawaited(appSettings.increaseTextScale()),
                  onReset: appSettings.textScale == AppTextScale.percent100
                      ? null
                      : () => unawaited(appSettings.resetTextScale()),
                ),
                const DFieldSeparator(),
                DSwitchTile(
                  key: const ValueKey('disable-gif-animations-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const DLabel(child: Text('Disable GIF animations')),
                  subtitle: const DFieldDescription(
                    child: Text(
                      'Pause GIFs by default in posts and chat messages.',
                    ),
                  ),
                  value: appSettings.disableGifAnimations,
                  onChanged: (disabled) =>
                      unawaited(appSettings.setDisableGifAnimations(disabled)),
                ),
              ],
            ),
          ),
          const DFieldDescription(child: Text('Changes apply immediately.')),
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) => DField(
    orientation: MediaQuery.textScalerOf(context).scale(14) > 21
        ? DFieldOrientation.vertical
        : DFieldOrientation.responsive,
    responsiveBreakpoint: 520,
    children: [
      DFieldContent(
        children: [
          DFieldTitle(child: Semantics(headingLevel: 2, child: Text(title))),
          DFieldDescription(child: Text(description)),
        ],
      ),
      control,
    ],
  );
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
    final percentage = (scale.factor * 100).round();
    final platform = Theme.of(context).platform;
    final desktop = switch (platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final modifier = platform == TargetPlatform.macOS ? '⌘' : 'Ctrl';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsField(
          title: 'Text size',
          description: 'Choose a comfortable reading size.',
          control: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: DSpacing.sm,
            runSpacing: DSpacing.sm,
            children: [
              DButtonGroup(
                semanticLabel: 'Text size controls',
                children: [
                  DButton.iconOnly(
                    key: const ValueKey('text-size-decrease'),
                    onPressed: onDecrease,
                    icon: const DIcon(DIcons.minus),
                    tooltip: 'Decrease text size',
                    semanticLabel: 'Decrease text size',
                    variant: DButtonVariant.outline,
                  ),
                  DButtonGroupText(
                    child: Semantics(
                      key: const ValueKey('text-size-value'),
                      container: true,
                      excludeSemantics: true,
                      label: 'Current text size',
                      value: '$percentage percent',
                      liveRegion: true,
                      child: Text(
                        '$percentage%',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  DButton.iconOnly(
                    key: const ValueKey('text-size-increase'),
                    onPressed: onIncrease,
                    icon: const DIcon(DIcons.plus),
                    tooltip: 'Increase text size',
                    semanticLabel: 'Increase text size',
                    variant: DButtonVariant.outline,
                  ),
                ],
              ),
              DButton(
                key: const ValueKey('text-size-reset'),
                label: const Text('Reset'),
                onPressed: onReset,
                variant: DButtonVariant.ghost,
              ),
            ],
          ),
        ),
        if (desktop) ...[
          const SizedBox(height: DSpacing.md),
          DFieldDescription(
            child: Wrap(
              spacing: DSpacing.xs,
              runSpacing: DSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Shortcuts:'),
                DKbd('$modifier +'),
                const Text('or'),
                DKbd('$modifier −'),
                const Text('to resize ·'),
                DKbd('$modifier 0'),
                const Text('to reset'),
              ],
            ),
          ),
        ],
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
  Widget build(BuildContext context) => _SettingsField(
    title: 'Content alignment',
    description: 'Position forum content in your window.',
    control: DToggleGroup<ContentAlignment>(
      key: const ValueKey('content-alignment-segmented-button'),
      semanticLabel: 'Content alignment options',
      items: const [
        DToggleGroupItem(value: ContentAlignment.left, child: Text('Left')),
        DToggleGroupItem(value: ContentAlignment.center, child: Text('Center')),
        DToggleGroupItem(value: ContentAlignment.right, child: Text('Right')),
      ],
      values: [alignment],
      allowEmptySelection: false,
      variant: DToggleVariant.outline,
      spacing: 0,
      onChanged: (selection) => onChanged(selection.single),
    ),
  );
}
