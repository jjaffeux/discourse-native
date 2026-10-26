library;

import 'package:flutter/painting.dart';
import 'package:html/dom.dart' as dom;

import '../../models/json.dart';

/// The templates write a category color verbatim after `#`, and core stores
/// one as six or three hex digits.
Color? hexColorIn(String? style) {
  if (style == null) return null;
  final match = _hexPattern.firstMatch(style);
  if (match == null) return null;
  final value = categoryColorValueOrNull(match.group(1)!);
  return value == null ? null : Color(value);
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

// CSS's four- and eight-digit forms carry alpha, which no category color has.
final RegExp _hexPattern = RegExp(
  r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9a-fA-F])',
);
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _nonDigitPattern = RegExp(r'[^\d]');
