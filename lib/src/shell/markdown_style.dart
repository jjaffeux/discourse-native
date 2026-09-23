import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'code_block.dart';
import 'markdown_highlight.dart';

TextStyle markdownStyle(
  int mask,
  String? detail,
  TextStyle base,
  ThemeData theme,
) {
  var style = base;
  var scale = 1.0;

  if (mask & Md.codeBlock != 0) {
    scale *= 0.875;
    style = style
        .merge(monospaceTextStyle)
        .copyWith(
          color: scopeColor(detail, theme.code) ?? theme.colorScheme.onSurface,
        );
  }

  if (mask & Md.heading != 0) {
    // The detail slot is shared: an inline HTML tag inside a heading appends
    // its name after a comma, so the level is the first component.
    final level = int.tryParse((detail ?? '1').split(',').first) ?? 1;
    scale *= _headingScale(level);
    style = style.copyWith(
      fontWeight: FontWeight.w700,
      height: DiscourseTypography.headingLineHeight(level),
    );
  }

  if (mask & Md.code != 0) {
    scale *= 0.875;
    style = style
        .merge(monospaceTextStyle)
        .copyWith(
          backgroundColor:
              (theme.extension<DTokens>() ?? DTokens.fromTheme(theme))
                  .inlineCodeBackground,
        );
  }

  if (mask & Md.bold != 0) style = style.copyWith(fontWeight: FontWeight.w700);
  if (mask & Md.italic != 0) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (mask & Md.strikethrough != 0) {
    style = style.copyWith(decoration: TextDecoration.lineThrough);
  }

  if (mask & Md.htmlTag != 0) {
    for (final tag in (detail ?? '').split(',')) {
      if (tag.startsWith('color=') || tag.startsWith('bgcolor=')) {
        final color = _inlineColor(tag.split('=').last);
        if (color != null) {
          style = tag.startsWith('bgcolor=')
              ? style.copyWith(backgroundColor: color)
              : style.copyWith(color: color);
        }
        continue;
      }
      final (tagStyle, tagScale) = _tagStyle(tag, style, theme);
      style = tagStyle;
      scale *= tagScale;
    }
  }

  if (mask & (Md.linkText | Md.linkUrl | Md.mention | Md.emoji | Md.hashtag) !=
      0) {
    style = style.copyWith(color: theme.colorScheme.primary);
  }
  if (mask & (Md.mention | Md.hashtag) != 0) {
    style = style.copyWith(fontWeight: FontWeight.w600);
  }

  if (mask & Md.marker != 0) {
    style = style.copyWith(color: theme.shell.marker);
  }

  return scale == 1.0
      ? style
      : style.copyWith(
          fontSize: (base.fontSize ?? DiscourseTypography.base) * scale,
        );
}

Color? _inlineColor(String value) {
  if (value.startsWith('#')) {
    var hex = value.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    final rgb = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return rgb == null ? null : Color(0xff000000 | rgb);
  }
  return const {
    'red': Color(0xffff0000),
    'green': Color(0xff008000),
    'blue': Color(0xff0000ff),
    'black': Color(0xff000000),
    'white': Color(0xffffffff),
    'yellow': Color(0xffffff00),
    'orange': Color(0xffffa500),
    'purple': Color(0xff800080),
    'gray': Color(0xff808080),
    'grey': Color(0xff808080),
    'pink': Color(0xffffc0cb),
    'brown': Color(0xffa52a2a),
  }[value];
}

(TextStyle, double) _tagStyle(String tag, TextStyle style, ThemeData theme) =>
    switch (tag) {
      'kbd' => (
        style
            .merge(monospaceTextStyle)
            .copyWith(backgroundColor: theme.code.inlineBackground),
        0.9,
      ),
      'mark' => (
        style.copyWith(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        1.0,
      ),
      'sup' || 'sub' => (style, 0.75),
      'small' => (style, 0.75),
      'big' => (style, 1.5),
      'ins' => (_withDecoration(style, TextDecoration.underline), 1.0),
      'del' => (_withDecoration(style, TextDecoration.lineThrough), 1.0),
      _ => (style, 1.0),
    };

TextStyle _withDecoration(TextStyle style, TextDecoration decoration) =>
    style.copyWith(
      decoration: TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        decoration,
      ]),
    );

double _headingScale(int level) =>
    DiscourseTypography.headingSize(level) / DiscourseTypography.base;
