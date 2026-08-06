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

/// Colors for the token kinds a syntax highlighter reports.
///
/// Like [ShellColors] these sit outside [ColorScheme], which has no roles for
/// "string" or "comment". The two sets are tuned per brightness rather than
/// derived from the seed: syntax colors have to stay distinguishable from each
/// other, which a generated scheme does not guarantee.
@immutable
class CodeColors extends ThemeExtension<CodeColors> {
  const CodeColors({
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.name,
    required this.meta,
  });

  /// Keywords, literals and operators.
  final Color keyword;

  /// String and regexp literals.
  final Color string;

  /// Comments and quoted documentation.
  final Color comment;

  /// Numbers and other scalar literals.
  final Color number;

  /// Declared names: functions, classes, sections, tags.
  final Color name;

  /// Annotations, preprocessor lines, attributes.
  final Color meta;

  static const CodeColors dark = CodeColors(
    keyword: Color(0xFFC792EA),
    string: Color(0xFF9CCC7C),
    comment: Color(0xFF7E8794),
    number: Color(0xFFF78C6C),
    name: Color(0xFF82AAFF),
    meta: Color(0xFF89DDFF),
  );

  static const CodeColors light = CodeColors(
    keyword: Color(0xFF8B2FA0),
    string: Color(0xFF2E7D32),
    comment: Color(0xFF6B7280),
    number: Color(0xFFB35309),
    name: Color(0xFF1A56B0),
    meta: Color(0xFF00707A),
  );

  @override
  CodeColors copyWith({
    Color? keyword,
    Color? string,
    Color? comment,
    Color? number,
    Color? name,
    Color? meta,
  }) {
    return CodeColors(
      keyword: keyword ?? this.keyword,
      string: string ?? this.string,
      comment: comment ?? this.comment,
      number: number ?? this.number,
      name: name ?? this.name,
      meta: meta ?? this.meta,
    );
  }

  @override
  CodeColors lerp(ThemeExtension<CodeColors>? other, double t) {
    if (other is! CodeColors) return this;
    return CodeColors(
      keyword: Color.lerp(keyword, other.keyword, t)!,
      string: Color.lerp(string, other.string, t)!,
      comment: Color.lerp(comment, other.comment, t)!,
      number: Color.lerp(number, other.number, t)!,
      name: Color.lerp(name, other.name, t)!,
      meta: Color.lerp(meta, other.meta, t)!,
    );
  }
}

extension ShellColorsAccess on ThemeData {
  /// Shorthand for `Theme.of(context).extension<ShellColors>()!`.
  ShellColors get shell => extension<ShellColors>()!;

  /// Shorthand for `Theme.of(context).extension<CodeColors>()!`.
  CodeColors get code => extension<CodeColors>()!;
}

abstract final class AppTheme {
  static ThemeData get light =>
      _build(Brightness.light, ShellColors.light, CodeColors.light);
  static ThemeData get dark =>
      _build(Brightness.dark, ShellColors.dark, CodeColors.dark);

  static ThemeData _build(
    Brightness brightness,
    ShellColors shell,
    CodeColors code,
  ) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: discourseBlue,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      // The backdrop the panels sit on, visible above them and behind the rail.
      scaffoldBackgroundColor: shell.rail,
      extensions: [shell, code],
      dividerTheme: DividerThemeData(
        color: shell.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
