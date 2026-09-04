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
      height: DiscourseTypography.lineHeightMedium,
    );
  }

  if (mask & Md.code != 0) {
    scale *= 0.875;
    style = style
        .merge(monospaceTextStyle)
        .copyWith(backgroundColor: theme.code.inlineBackground);
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
      'sup' => (
        style.copyWith(fontFeatures: const [FontFeature.superscripts()]),
        1.0,
      ),
      'sub' => (
        style.copyWith(fontFeatures: const [FontFeature.subscripts()]),
        1.0,
      ),
      'small' => (style, 0.75),
      'big' => (style, 1.5),
      'ins' => (style.copyWith(decoration: TextDecoration.underline), 1.0),
      'del' => (style.copyWith(decoration: TextDecoration.lineThrough), 1.0),
      _ => (style, 1.0),
    };

double _headingScale(int level) =>
    DiscourseTypography.headingSize(level) / DiscourseTypography.base;
