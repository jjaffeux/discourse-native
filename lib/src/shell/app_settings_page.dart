import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/forum_background.dart';
import '../models/forum_font.dart';
import '../theme/d_icons.dart';
import 'app_home_theme.dart';
import 'forum_appearance_effects.dart';
import 'forum_settings_controller.dart';
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
    final identity = ShellScope.identityOf(context);
    final appSettings = identity.appSettings;
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
                DSwitchTile(
                  key: const ValueKey('limit-content-size-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const DLabel(child: Text('Limit content size')),
                  subtitle: const DFieldDescription(
                    child: Text(
                      'Center content in each panel with a maximum width of 825 px.',
                    ),
                  ),
                  value: appSettings.limitContentSize,
                  onChanged: (value) =>
                      unawaited(appSettings.setLimitContentSize(value)),
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
                _FontSetting(settings: identity.forumSettings),
                const DFieldSeparator(),
                _EffectsSetting(settings: identity.forumSettings),
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
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({required this.title, required this.control});

  final String title;
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
        ],
      ),
      control,
    ],
  );
}

/// The reading font, which every forum and Aggregate share. Each choice is
/// drawn in its own face so it can be compared before it is chosen.
class _FontSetting extends StatelessWidget {
  const _FontSetting({required this.settings});

  final ForumSettingsController settings;

  Future<void> _choose(BuildContext context, ForumFont font) async {
    try {
      // Read when the choice lands: the effects may have changed since the
      // modal last drew.
      await settings.setShared(settings.shared.copyWith(font: font));
    } catch (_) {
      if (context.mounted) {
        DToast.show(
          context,
          'Could not save the font.',
          type: DToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final systemFamily = ThemeData(
      platform: theme.platform,
    ).textTheme.bodyLarge!.fontFamily;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final chosen = settings.shared.font;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DSpacing.md,
          children: [
            DFieldContent(
              children: [
                DFieldTitle(
                  child: Semantics(headingLevel: 2, child: const Text('Font')),
                ),
                const DFieldDescription(
                  child: Text('Used for reading and writing in every forum.'),
                ),
              ],
            ),
            DCard(
              spacing: 16,
              backgroundColor: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              children: [
                DCardContent(
                  child: DItemGroup(
                    key: const ValueKey('app-settings-font'),
                    spacing: 0,
                    children: [
                      for (final font in ForumFont.values) ...[
                        if (font != ForumFont.values.first)
                          const DItemSeparator(),
                        DItem(
                          key: ValueKey('appearance-font-${font.name}'),
                          selected: chosen == font,
                          shape: DItemShape.fullWidth,
                          selectionStyle: DItemSelectionStyle.leadingAccent,
                          onPressed: () => unawaited(_choose(context, font)),
                          children: [
                            DItemContent(
                              children: [
                                Text(
                                  font.label,
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  'The quick brown fox jumps over the lazy dog.',
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    fontFamily: font.family ?? systemFamily,
                                    fontFamilyFallback:
                                        forumFontFamilyFallback(font.family) ??
                                        const [],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The window effects, which every forum draws over its own colours. The
/// workspace behind the modal shows each one as it is chosen.
class _EffectsSetting extends StatelessWidget {
  const _EffectsSetting({required this.settings});

  final ForumSettingsController settings;

  Future<void> _change(
    BuildContext context,
    ForumBackground Function(ForumBackground) change,
  ) async {
    try {
      // Applied to the effects as they are when the choice lands, so two
      // choices made before the modal redraws are both kept.
      final shared = settings.shared;
      await settings.setShared(
        shared.copyWith(effects: change(shared.effects)),
      );
    } catch (_) {
      if (context.mounted) {
        DToast.show(
          context,
          'Could not save the effects.',
          type: DToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.md,
    children: [
      DFieldContent(
        children: [
          DFieldTitle(
            child: Semantics(headingLevel: 2, child: const Text('Effects')),
          ),
          const DFieldDescription(
            child: Text('Drawn over the colours of every forum.'),
          ),
        ],
      ),
      DCard(
        spacing: 16,
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        children: [
          DCardContent(
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => ForumAppearanceEffects(
                key: const ValueKey('appearance-effects'),
                effects: settings.shared.effects,
                onChanged: (change) => unawaited(_change(context, change)),
              ),
            ),
          ),
        ],
      ),
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
