import 'package:flutter/material.dart';

/// The tertiary color of Discourse's default light scheme.
const Color discourseBlue = Color(0xFF0088CC);

/// What Discourse paints a like — `$love` in its stylesheets.
///
/// One value for both brightnesses, unlike everything in [ShellColors]: a
/// heart that changed color with the theme would stop reading as the same
/// thing, and it is drawn on a floating surface either way.
const Color discourseLove = Color(0xFFFA6C8D);

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
    required this.hover,
    required this.placeholder,
    required this.marker,
    required this.mention,
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

  /// Wash laid over [content] for the row the pointer is on. Opaque rather than
  /// a translucent tint so a hovered row does not go see-through over whatever
  /// happens to be painted behind the column.
  final Color hover;

  /// Text for anything the UI shows but cannot do yet: fake rows, stand-in
  /// counts, destinations with nothing behind them. Nothing that actually works
  /// is ever drawn in it, so anything orange on screen is a to-do list item.
  final Color placeholder;

  /// The markdown syntax itself in the composer — the `**`, the `#`, the
  /// backticks.
  ///
  /// Its own colour rather than [CodeColors.comment], which reads as "de-
  /// emphasised" but only reaches 4.3:1 against [content] in the dark scheme.
  /// These characters are not decoration: someone who cannot read the `**`
  /// cannot tell bold from italic, and the two post differently. Both values
  /// clear 4.5:1 against the surface the composer is drawn on.
  final Color marker;

  /// Behind a mention or hashtag pill, mirroring Discourse's
  /// `--mention-background-color`.
  ///
  /// Not [rail], which is the nearest existing neutral and the wrong one: in
  /// the dark scheme it is *darker* than every surface a pill is drawn on —
  /// [content], [sidebar] where chat renders, [floating] in a user card —
  /// while Discourse's is a step lighter than its surface. It is also what
  /// inline code fills with, and a mention is not a code span.
  final Color mention;

  static const ShellColors dark = ShellColors(
    rail: Color(0xFF131417),
    sidebar: Color(0xFF1A1C20),
    content: Color(0xFF212429),
    panel: Color(0xFF1A1C20),
    divider: Color(0xFF2B2E35),
    floating: Color(0xFF272B32),
    hover: Color(0xFF262A30),
    placeholder: Color(0xFFFF9E4D),
    marker: Color(0xFF8B939F),
    mention: Color(0xFF3A3F48),
  );

  static const ShellColors light = ShellColors(
    rail: Color(0xFFE3E6EA),
    sidebar: Color(0xFFF1F3F5),
    content: Color(0xFFFFFFFF),
    panel: Color(0xFFF1F3F5),
    divider: Color(0xFFDBDFE4),
    floating: Color(0xFFFFFFFF),
    hover: Color(0xFFF6F8F9),
    placeholder: Color(0xFFC25400),
    marker: Color(0xFF6B7280),
    mention: Color(0xFFDFE4E9),
  );

  @override
  ShellColors copyWith({
    Color? rail,
    Color? sidebar,
    Color? content,
    Color? panel,
    Color? divider,
    Color? floating,
    Color? hover,
    Color? placeholder,
    Color? marker,
    Color? mention,
  }) {
    return ShellColors(
      rail: rail ?? this.rail,
      sidebar: sidebar ?? this.sidebar,
      content: content ?? this.content,
      panel: panel ?? this.panel,
      divider: divider ?? this.divider,
      floating: floating ?? this.floating,
      hover: hover ?? this.hover,
      placeholder: placeholder ?? this.placeholder,
      marker: marker ?? this.marker,
      mention: mention ?? this.mention,
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
      hover: Color.lerp(hover, other.hover, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      marker: Color.lerp(marker, other.marker, t)!,
      mention: Color.lerp(mention, other.mention, t)!,
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
