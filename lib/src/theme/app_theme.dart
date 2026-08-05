import 'package:flutter/material.dart';

/// The tertiary color of Discourse's default light scheme.
const Color discourseBlue = Color(0xFF0088CC);

/// The stacked neutral surfaces the shell is built from.
///
/// These live outside [ColorScheme] because the shell needs several distinct
/// neutrals sitting directly next to each other, which Material's surface roles
/// do not map onto cleanly. Per-instance color schemes will override these once
/// we can read them from each site.
@immutable
class ShellColors extends ThemeExtension<ShellColors> {
  const ShellColors({
    required this.rail,
    required this.sidebar,
    required this.content,
    required this.panel,
    required this.divider,
    required this.floating,
  });

  final Color rail;
  final Color sidebar;
  final Color content;
  final Color panel;
  final Color divider;

  /// Surface for elements that float *over* the columns, such as the user bar.
  /// Deliberately lighter than every column so the edge reads wherever it
  /// happens to sit.
  final Color floating;

  static const ShellColors dark = ShellColors(
    rail: Color(0xFF131417),
    sidebar: Color(0xFF1A1C20),
    content: Color(0xFF212429),
    panel: Color(0xFF1A1C20),
    divider: Color(0xFF2B2E35),
    floating: Color(0xFF272B32),
  );

  static const ShellColors light = ShellColors(
    rail: Color(0xFFE3E6EA),
    sidebar: Color(0xFFF1F3F5),
    content: Color(0xFFFFFFFF),
    panel: Color(0xFFF1F3F5),
    divider: Color(0xFFDBDFE4),
    floating: Color(0xFFFFFFFF),
  );

  @override
  ShellColors copyWith({
    Color? rail,
    Color? sidebar,
    Color? content,
    Color? panel,
    Color? divider,
    Color? floating,
  }) {
    return ShellColors(
      rail: rail ?? this.rail,
      sidebar: sidebar ?? this.sidebar,
      content: content ?? this.content,
      panel: panel ?? this.panel,
      divider: divider ?? this.divider,
      floating: floating ?? this.floating,
    );
  }

  @override
  ShellColors lerp(ThemeExtension<ShellColors>? other, double t) {
    if (other is! ShellColors) return this;
    return ShellColors(
      rail: Color.lerp(rail, other.rail, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      content: Color.lerp(content, other.content, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      floating: Color.lerp(floating, other.floating, t)!,
    );
  }
}

extension ShellColorsAccess on ThemeData {
  /// Shorthand for `Theme.of(context).extension<ShellColors>()!`.
  ShellColors get shell => extension<ShellColors>()!;
}

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, ShellColors.light);
  static ThemeData get dark => _build(Brightness.dark, ShellColors.dark);

  static ThemeData _build(Brightness brightness, ShellColors shell) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: discourseBlue,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      // The backdrop the panels sit on, visible above them and behind the rail.
      scaffoldBackgroundColor: shell.rail,
      extensions: [shell],
      dividerTheme: DividerThemeData(
        color: shell.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
