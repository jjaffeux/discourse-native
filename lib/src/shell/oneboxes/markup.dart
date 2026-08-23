/// What every onebox engine has to read out of cooked markup, in one place.
///
/// These run inside a `customWidgetBuilder`, on the frame that draws the post,
/// and a post rebuilds every time it scrolls back into view — the same reason
/// `cooked_dom.dart` walks a DOM once rather than per child. Each of these was
/// written out in two or three engines with a pattern literal in it, which
/// compiles a regular expression per onebox per frame.
library;

import 'package:flutter/painting.dart';
import 'package:html/dom.dart' as dom;

/// The colour Discourse wrote into a `style` attribute.
///
/// A category's colour reaches a onebox only as a style attribute, because
/// there is no stylesheet here to give a class meaning: a subcategory dot
/// carries `background-color: #hex` and a category card carries
/// `box-shadow: -5px 0px #hex`. Both are read the same way — the first
/// six-digit hex in the string — and both are opaque.
Color? hexColorIn(String? style) {
  if (style == null) return null;
  final match = _hexPattern.firstMatch(style);
  if (match == null) return null;
  final value = int.tryParse(match.group(1)!, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// [hexColorIn] for an element's own `style` attribute.
Color? hexColorOf(dom.Element? element) =>
    hexColorIn(element?.attributes['style']);

/// An element's text as one line: every run of whitespace collapsed to a
/// single space, trimmed, and null rather than empty.
///
/// The templates indent their markup, so the text of anything spanning more
/// than one line arrives with the indentation in it.
String? oneLineText(dom.Element? element) {
  if (element == null) return null;
  return element.text.replaceAll(_whitespacePattern, ' ').trim().nullIfEmpty;
}

/// The digits in an element's text, as a number.
///
/// GitHub's templates write counts with their label around them — "4 files
/// changed", "+12" — and only the digits are the count.
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
