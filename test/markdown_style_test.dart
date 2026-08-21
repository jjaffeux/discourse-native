import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:discourse_native/src/shell/markdown_style.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = AppTheme.light;
  const base = TextStyle(
    color: Color(0xFF123456),
    fontSize: DiscourseTypography.base,
  );

  test('uses the exact cooked heading scale', () {
    final expected = [
      DiscourseTypography.fontUp3,
      DiscourseTypography.fontUp2,
      DiscourseTypography.fontUp1,
      DiscourseTypography.base,
      DiscourseTypography.fontDown1,
      DiscourseTypography.fontDown2,
    ];

    for (var level = 1; level <= 6; level++) {
      final style = markdownStyle(Md.heading, '$level', base, theme);
      expect(style.fontSize, expected[level - 1]);
      expect(style.height, DiscourseTypography.lineHeightMedium);
      expect(style.fontWeight, FontWeight.w700);
    }
  });

  test('keeps quoted prose in the normal cooked foreground', () {
    final style = markdownStyle(Md.quote, null, base, theme);

    expect(style.color, base.color);
    expect(style.fontSize, base.fontSize);
  });

  test('matches cooked big, small, and code sizes', () {
    expect(
      markdownStyle(Md.htmlTag, 'big', base, theme).fontSize,
      DiscourseTypography.base * 1.5,
    );
    expect(
      markdownStyle(Md.htmlTag, 'small', base, theme).fontSize,
      DiscourseTypography.base * 0.75,
    );
    expect(markdownStyle(Md.codeBlock, null, base, theme).fontSize, 14);
  });
}
