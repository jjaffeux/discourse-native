import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Decorative miniature, not an interactive replacement for a Native control.
class ThemeThumbnail extends StatelessWidget {
  const ThemeThumbnail({super.key, required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 44,
      height: 36,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DTokens.of(context).radius),
        child: ColoredBox(
          color: theme.shell.content,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 9,
                  child: ColoredBox(
                    color:
                        (theme.extension<ForumThemeEffects>()?.sidebarTheme ??
                                theme)
                            .shell
                            .sidebar,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 3,
                    children: [
                      for (var i = 0; i < 4; i++)
                        FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: i.isEven ? 1 : .6,
                          child: SizedBox(
                            height: 3,
                            child: ColoredBox(
                              color: i == 0
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: .24,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ThemePaletteStrip extends StatelessWidget {
  const ThemePaletteStrip({super.key, required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.extension<DTokens>() ?? DTokens.fromTheme(theme);
    final discourse = theme.extension<DiscourseColors>()!;
    return Wrap(
      spacing: DSpacing.sm,
      runSpacing: DSpacing.sm,
      children: [
        for (final color in [
          tokens.background,
          tokens.foreground,
          theme.colorScheme.primary,
          theme.colorScheme.secondary,
          discourse.success,
          theme.colorScheme.error,
          discourse.love,
        ])
          Semantics(
            label:
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            child: SizedBox(
              width: 24,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: DTokens.of(context).border),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
