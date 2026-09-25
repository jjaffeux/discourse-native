import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/forum_font.dart';
import '../theme/d_icons.dart';
import 'app_settings_controller.dart';
import 'forum_settings_controller.dart';

/// Shared reading and icon preferences, followed by the content width choice.
class ForumDisplaySettings extends StatelessWidget {
  const ForumDisplaySettings({
    super.key,
    required this.appSettings,
    required this.forumSettings,
  });

  final AppSettingsController appSettings;
  final ForumSettingsController forumSettings;

  Future<void> _setFont(BuildContext context, ForumFont font) async {
    try {
      await forumSettings.setShared(forumSettings.shared.copyWith(font: font));
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

  Future<void> _setIconSet(BuildContext context, DIconSet set) async {
    try {
      await forumSettings.setShared(
        forumSettings.shared.copyWith(iconSet: set),
      );
    } catch (_) {
      if (context.mounted) {
        DToast.show(
          context,
          'Could not save the icon set.',
          type: DToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([appSettings, forumSettings]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final tokens = DTokens.of(context);
      final systemFamily = ThemeData(
        platform: theme.platform,
      ).textTheme.bodyLarge!.fontFamily;
      final scale = appSettings.textScale;
      final percentage = (scale.factor * 100).round();
      return SingleChildScrollView(
        child: DPageReadingLaneBox(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          widthLimit: DPageReadingLane.maxWidth - 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: DSpacing.md,
                runSpacing: DSpacing.sm,
                children: [
                  const Text('Font'),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: DSpacing.controlGap,
                    children: [
                      DButtonGroup(
                        semanticLabel: 'Text size controls',
                        children: [
                          DButton.iconOnly(
                            key: const ValueKey('text-size-decrease'),
                            onPressed: scale.index == 0
                                ? null
                                : () => unawaited(
                                    appSettings.decreaseTextScale(),
                                  ),
                            icon: const DIcon(DIcons.minus),
                            tooltip: 'Decrease text size',
                            semanticLabel: 'Decrease text size',
                            variant: DButtonVariant.outline,
                            size: DButtonSize.segment,
                          ),
                          DButtonGroupText(
                            child: Semantics(
                              key: const ValueKey('text-size-value'),
                              container: true,
                              excludeSemantics: true,
                              label: 'Current text size',
                              value: '$percentage percent',
                              liveRegion: true,
                              child: Text('$percentage%'),
                            ),
                          ),
                          DButton.iconOnly(
                            key: const ValueKey('text-size-increase'),
                            onPressed:
                                scale.index == AppTextScale.values.length - 1
                                ? null
                                : () => unawaited(
                                    appSettings.increaseTextScale(),
                                  ),
                            icon: const DIcon(DIcons.plus),
                            tooltip: 'Increase text size',
                            semanticLabel: 'Increase text size',
                            variant: DButtonVariant.outline,
                            size: DButtonSize.segment,
                          ),
                        ],
                      ),
                      DButton(
                        key: const ValueKey('text-size-reset'),
                        label: const Text('Reset'),
                        onPressed: scale == AppTextScale.percent100
                            ? null
                            : () => unawaited(appSettings.resetTextScale()),
                        variant: DButtonVariant.ghost,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: DSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final font in ForumFont.values) ...[
                    DItem(
                      key: ValueKey('display-font-${font.name}'),
                      selected: forumSettings.shared.font == font,
                      selectionStyle: DItemSelectionStyle.tinted,
                      showSelectionIndicator: false,
                      variant: DItemVariant.outline,
                      onPressed: () => unawaited(_setFont(context, font)),
                      children: [
                        DItemContent(
                          children: [
                            Text(
                              font.label,
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: forumSettings.shared.font == font
                                    ? tokens.foreground
                                    : tokens.mutedForeground,
                              ),
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
                    const SizedBox(height: DSpacing.sm),
                  ],
                ],
              ),
              const SizedBox(height: DSpacing.lg),
              const Text('Icons'),
              const SizedBox(height: DSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - (columns - 1) * DSpacing.sm) /
                      columns;
                  return Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: DSpacing.sm,
                    children: [
                      for (final set in DIconSet.values)
                        SizedBox(
                          width: width,
                          child: DIconSetScope(
                            iconSet: set,
                            child: DItem(
                              key: ValueKey('display-icon-set-${set.name}'),
                              selected: forumSettings.shared.iconSet == set,
                              selectionStyle: DItemSelectionStyle.tinted,
                              showSelectionIndicator: false,
                              variant: DItemVariant.outline,
                              onPressed: () =>
                                  unawaited(_setIconSet(context, set)),
                              children: [
                                DItemContent(
                                  children: [
                                    Center(
                                      child: Text(
                                        set.label,
                                        style: TextStyle(
                                          color:
                                              forumSettings.shared.iconSet ==
                                                  set
                                              ? tokens.foreground
                                              : tokens.mutedForeground,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: DSpacing.sm),
                                    const _IconSetPreview(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: DSpacing.lg),
              const Text('Content width'),
              const SizedBox(height: DSpacing.sm),
              DToggleGroup<bool>(
                key: const ValueKey('settings-content-width'),
                values: [appSettings.limitContentSize],
                expanded: true,
                inset: true,
                allowEmptySelection: false,
                onChanged: (values) {
                  if (values.isNotEmpty) {
                    unawaited(appSettings.setLimitContentSize(values.first));
                  }
                },
                items: const [
                  DToggleGroupItem(value: true, child: Text('Normal')),
                  DToggleGroupItem(value: false, child: Text('Wide')),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _IconSetPreview extends StatelessWidget {
  const _IconSetPreview();

  @override
  Widget build(BuildContext context) => const Column(
    spacing: DSpacing.sm,
    children: [
      Row(
        children: [
          Expanded(child: Center(child: DIcon(DIcons.layerGroup))),
          Expanded(child: Center(child: DIcon(DIcons.bell))),
          Expanded(child: Center(child: DIcon(DIcons.bookmark))),
          Expanded(child: Center(child: DIcon(DIcons.magnifyingGlass))),
        ],
      ),
      Row(
        children: [
          Expanded(child: Center(child: DIcon(DIcons.users))),
          Expanded(child: Center(child: DIcon(DIcons.tag))),
          Expanded(child: Center(child: DIcon(DIcons.reply))),
          Expanded(child: Center(child: DIcon(DIcons.gear))),
        ],
      ),
    ],
  );
}
