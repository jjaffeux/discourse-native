import 'package:flutter/material.dart';

@immutable
class CodeColors extends ThemeExtension<CodeColors> {
  const CodeColors({
    required this.blockBackground,
    required this.inlineBackground,
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.name,
    required this.meta,
  });

  final Color blockBackground;
  final Color inlineBackground;

  final Color keyword;

  final Color string;

  final Color comment;

  final Color number;

  final Color name;

  final Color meta;

  static const CodeColors dark = CodeColors(
    blockBackground: Color(0xFF131417),
    inlineBackground: Color(0xFF131417),
    keyword: Color(0xFFC792EA),
    string: Color(0xFF9CCC7C),
    comment: Color(0xFF7E8794),
    number: Color(0xFFF78C6C),
    name: Color(0xFF82AAFF),
    meta: Color(0xFF89DDFF),
  );

  static const CodeColors light = CodeColors(
    blockBackground: Color(0xFFE3E6EA),
    inlineBackground: Color(0xFFE3E6EA),
    keyword: Color(0xFF8B2FA0),
    string: Color(0xFF2E7D32),
    comment: Color(0xFF6B7280),
    number: Color(0xFFB35309),
    name: Color(0xFF1A56B0),
    meta: Color(0xFF00707A),
  );

  @override
  CodeColors copyWith({
    Color? blockBackground,
    Color? inlineBackground,
    Color? keyword,
    Color? string,
    Color? comment,
    Color? number,
    Color? name,
    Color? meta,
  }) {
    return CodeColors(
      blockBackground: blockBackground ?? this.blockBackground,
      inlineBackground: inlineBackground ?? this.inlineBackground,
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
      blockBackground: Color.lerp(blockBackground, other.blockBackground, t)!,
      inlineBackground: Color.lerp(
        inlineBackground,
        other.inlineBackground,
        t,
      )!,
      keyword: Color.lerp(keyword, other.keyword, t)!,
      string: Color.lerp(string, other.string, t)!,
      comment: Color.lerp(comment, other.comment, t)!,
      number: Color.lerp(number, other.number, t)!,
      name: Color.lerp(name, other.name, t)!,
      meta: Color.lerp(meta, other.meta, t)!,
    );
  }
}

Color? scopeColor(String? scope, CodeColors colors) => switch (scope) {
  'keyword' ||
  'built_in' ||
  'builtin-name' ||
  'type' ||
  'literal' ||
  'operator' ||
  'selector-tag' ||
  'tag' => colors.keyword,

  'string' ||
  'regexp' ||
  'symbol' ||
  'char' ||
  'quote' ||
  'addition' ||
  'selector-attr' => colors.string,

  'comment' || 'doctag' => colors.comment,

  'number' || 'deletion' => colors.number,

  'title' ||
  'class' ||
  'function' ||
  'name' ||
  'section' ||
  'attr' ||
  'attribute' ||
  'variable' ||
  'template-variable' ||
  'selector-id' ||
  'selector-class' ||
  'bullet' => colors.name,

  'meta' ||
  'meta-keyword' ||
  'meta-string' ||
  'subst' ||
  'link' ||
  'formula' => colors.meta,

  _ => null,
};
