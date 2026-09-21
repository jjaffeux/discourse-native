import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

CodeColors codeEditorColors(ThemeData theme) =>
    theme.extension<CodeColors>() ??
    (theme.brightness == Brightness.dark ? CodeColors.dark : CodeColors.light);

Map<String, TextStyle> codeEditorStyles(ThemeData theme) {
  final colors = codeEditorColors(theme);
  TextStyle color(Color color) => TextStyle(color: color);

  return {
    'root': TextStyle(
      color: theme.colorScheme.onSurface,
      backgroundColor: colors.blockBackground,
    ),
    for (final scope in const [
      'keyword',
      'built_in',
      'builtin-name',
      'type',
      'literal',
      'operator',
      'selector-tag',
      'tag',
    ])
      scope: color(colors.keyword),
    for (final scope in const [
      'string',
      'regexp',
      'symbol',
      'char',
      'quote',
      'addition',
      'selector-attr',
    ])
      scope: color(colors.string),
    for (final scope in const ['comment', 'doctag'])
      scope: color(colors.comment),
    for (final scope in const ['number', 'deletion'])
      scope: color(colors.number),
    for (final scope in const [
      'title',
      'class',
      'function',
      'name',
      'section',
      'attr',
      'attribute',
      'variable',
      'template-variable',
      'selector-id',
      'selector-class',
      'bullet',
    ])
      scope: color(colors.name),
    for (final scope in const [
      'meta',
      'meta-keyword',
      'meta-string',
      'subst',
      'link',
      'formula',
    ])
      scope: color(colors.meta),
  };
}
