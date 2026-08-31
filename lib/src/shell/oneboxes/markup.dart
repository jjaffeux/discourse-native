library;

import 'package:flutter/painting.dart';
import 'package:html/dom.dart' as dom;

Color? hexColorIn(String? style) {
  if (style == null) return null;
  final match = _hexPattern.firstMatch(style);
  if (match == null) return null;
  final value = int.tryParse(match.group(1)!, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

Color? hexColorOf(dom.Element? element) =>
    hexColorIn(element?.attributes['style']);

String? oneLineText(dom.Element? element) {
  if (element == null) return null;
  return element.text.replaceAll(_whitespacePattern, ' ').trim().nullIfEmpty;
}

int? digitsIn(dom.Element? element) {
  if (element == null) return null;
  return int.tryParse(element.text.replaceAll(_nonDigitPattern, ''));
}

extension NullIfEmptyString on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

final RegExp _hexPattern = RegExp(r'#([0-9a-fA-F]{6})');
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _nonDigitPattern = RegExp(r'[^\d]');
