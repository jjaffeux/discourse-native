import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/forum_font.dart';
import 'forum_settings_controller.dart';

/// Two independent assignments, with each bundled face shown in its own font.
class ForumFontChooser extends StatelessWidget {
  const ForumFontChooser({
    super.key,
    required this.settings,
    this.keyPrefix = 'display',
  });

  final ForumSettingsController settings;
  final String keyPrefix;

  Future<void> _choose(
    BuildContext context,
    ForumFont font, {
    required bool reading,
  }) async {
    try {
      await settings.setShared(
        settings.shared.copyWith(
          font: reading ? font : null,
          interfaceFont: reading ? null : font,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        DToast.show(
          context,
          context.l10n.couldNotSaveTheFont,
          type: DToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final theme = Theme.of(context);
      final systemFamily = ThemeData(
        platform: theme.platform,
      ).textTheme.bodyLarge!.fontFamily;
      return LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          return DItemGroup(
            spacing: DSpacing.sm,
            children: [
              for (final font in ForumFont.values)
                DItem(
                  key: ValueKey('$keyPrefix-font-${font.name}'),
                  variant: DItemVariant.outline,
                  children: [
                    DItemContent(
                      children: [
                        Text(font.label, style: theme.textTheme.bodySmall),
                        Text(
                          context.l10n.theQuickBrownFoxJumpsOverTheLazyDog,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            fontFamily: font.family ?? systemFamily,
                            fontFamilyFallback:
                                forumFontFamilyFallback(font.family) ??
                                const [],
                          ),
                        ),
                        if (stacked) _assignments(context, font),
                      ],
                    ),
                    if (!stacked)
                      DItemActions(children: [_assignments(context, font)]),
                  ],
                ),
            ],
          );
        },
      );
    },
  );

  Widget _assignments(BuildContext context, ForumFont font) => Wrap(
    spacing: DSpacing.sm,
    runSpacing: DSpacing.sm,
    children: [
      DToggle(
        key: ValueKey('$keyPrefix-font-${font.name}-interface'),
        pressed: settings.shared.interfaceFont == font,
        onPressedChanged: (_) =>
            unawaited(_choose(context, font, reading: false)),
        variant: DToggleVariant.outline,
        size: DToggleSize.small,
        semanticLabel: context.l10n.fontForInterface(font.label),
        child: Text(context.l10n.interfaceFontUse),
      ),
      DToggle(
        key: ValueKey('$keyPrefix-font-${font.name}-reading'),
        pressed: settings.shared.readingFont == font,
        onPressedChanged: (_) =>
            unawaited(_choose(context, font, reading: true)),
        variant: DToggleVariant.outline,
        size: DToggleSize.small,
        semanticLabel: context.l10n.fontForReading(font.label),
        child: Text(context.l10n.readingFontUse),
      ),
    ],
  );
}
