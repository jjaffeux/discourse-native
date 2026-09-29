import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/forum_background.dart';
import '../theme/d_icons.dart';
import 'app_home_theme.dart';
import 'forum_appearance_effects.dart';
import 'forum_display_settings.dart';
import 'forum_font_chooser.dart';
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
        semanticLabel: context.l10n.settings,
        spacing: DSpacing.xl,
        closeButton: DDialogClose<void>(
          builder: (_, close) => DButton.iconOnly(
            key: const ValueKey('app-settings-close'),
            onPressed: close,
            icon: const DIcon(DIcons.xmark),
            tooltip: context.l10n.close,
            semanticLabel: context.l10n.closeSettings,
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
                  child: Text(context.l10n.settings),
                ),
              ),
              DDialogDescription(
                child: Text(context.l10n.preferencesForAllYourForums),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: appSettings,
            builder: (context, _) => DFieldGroup(
              key: const ValueKey('app-settings-form'),
              children: [
                if (MediaQuery.sizeOf(context).width >=
                    ForumDisplaySettings.wideLayoutMinWidth) ...[
                  DSwitchTile(
                    key: const ValueKey('limit-content-size-switch'),
                    hoverHighlight: true,
                    title: DLabel(child: Text(context.l10n.limitContentSize)),
                    subtitle: DFieldDescription(
                      child: Text(
                        context
                            .l10n
                            .centerContentInEachPanelWithAMaximumWidthOf825,
                      ),
                    ),
                    value: appSettings.limitContentSize,
                    onChanged: (value) =>
                        unawaited(appSettings.setLimitContentSize(value)),
                  ),
                  const DFieldSeparator(),
                ],
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
                  hoverHighlight: true,
                  title: DLabel(child: Text(context.l10n.disableGIFAnimations)),
                  subtitle: DFieldDescription(
                    child: Text(
                      context.l10n.pauseGIFsByDefaultInPostsAndChatMessages,
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

class _FontSetting extends StatelessWidget {
  const _FontSetting({required this.settings});
  final ForumSettingsController settings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.md,
    children: [
      DFieldContent(
        children: [
          DFieldTitle(
            child: Semantics(headingLevel: 2, child: Text(context.l10n.font)),
          ),
          DFieldDescription(
            child: Text(context.l10n.fontAssignmentsDescription),
          ),
        ],
      ),
      ForumFontChooser(
        key: const ValueKey('app-settings-font'),
        settings: settings,
        keyPrefix: 'appearance',
      ),
    ],
  );
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
          appL10n.couldNotSaveTheEffects,
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
            child: Semantics(
              headingLevel: 2,
              child: Text(context.l10n.effects),
            ),
          ),
          DFieldDescription(
            child: Text(context.l10n.drawnOverTheColoursOfEveryForum),
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
    final modifier = platform == TargetPlatform.macOS ? '⌘' : context.l10n.ctrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsField(
          title: context.l10n.textSize,
          control: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: DSpacing.sm,
            runSpacing: DSpacing.sm,
            children: [
              DButtonGroup(
                semanticLabel: context.l10n.textSizeControls,
                children: [
                  DButton.iconOnly(
                    key: const ValueKey('text-size-decrease'),
                    onPressed: onDecrease,
                    icon: const DIcon(DIcons.minus),
                    tooltip: context.l10n.decreaseTextSize,
                    semanticLabel: context.l10n.decreaseTextSize,
                    variant: DButtonVariant.outline,
                  ),
                  DButtonGroupText(
                    child: Semantics(
                      key: const ValueKey('text-size-value'),
                      container: true,
                      excludeSemantics: true,
                      label: context.l10n.currentTextSize,
                      value: context.l10n.percentAppsettingspage(
                        (percentage).toString(),
                      ),
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
                    tooltip: context.l10n.increaseTextSize,
                    semanticLabel: context.l10n.increaseTextSize,
                    variant: DButtonVariant.outline,
                  ),
                ],
              ),
              DButton(
                key: const ValueKey('text-size-reset'),
                label: Text(context.l10n.reset),
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
                Text(context.l10n.shortcuts),
                DKbd('$modifier +'),
                Text(context.l10n.orAppsettingspage),
                DKbd('$modifier −'),
                Text(context.l10n.toResize),
                DKbd('$modifier 0'),
                Text(context.l10n.toReset),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
