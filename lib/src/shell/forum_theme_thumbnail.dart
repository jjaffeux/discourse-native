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
      width: 34,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.shell.content,
          border: Border.all(color: DTokens.of(context).border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              _line(20, 3, theme.colorScheme.primary),
              _line(10, 2, theme.colorScheme.onSurface.withValues(alpha: .45)),
              _line(16, 2, theme.colorScheme.onSurface.withValues(alpha: .45)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _line(double width, double height, Color color) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
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
