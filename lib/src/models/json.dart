// The small acts of reading a Discourse payload, written once.
//
// The wire is forgiving in the ways it writes: numbers arrive as strings,
// keys are dropped rather than nulled, and a title comes in a plain and an
// HTML flavour. Every parser answers that with a default rather than a
// throw — a field the site did not send is a field left at its default —
// and these are the shapes that answer.

import 'package:html/parser.dart' as html;

/// Largest legal `fancy_title` source Discourse can serialize.
///
/// Core limits a topic title to 255 characters. Its fancy-title fallback is
/// the HTML-escaped raw title, whose longest entity (`&quot;`) is six UTF-16
/// code units, so even that worst case fits in 255 * 6. Bounding the fallback
/// before DOM parsing keeps a malformed response from allocating an arbitrary
/// HTML tree without changing any conforming title.
const int maximumFancyTitleSourceCodeUnits = 1530;

/// Largest textual integer representation a Discourse payload can require.
///
/// Server IDs and counts are signed 64-bit values: 19 digits, plus an optional
/// minus sign. Reject longer strings before `int.tryParse`; a malformed JSON
/// response is otherwise able to spend CPU and temporary memory parsing a
/// multi-megabyte decimal field at every model boundary that uses these
/// helpers.
const int maximumJsonIntegerCodeUnits = 20;

/// Generous ceiling for an ISO-8601 timestamp emitted by Discourse.
///
/// Normal wire values are around 24–35 code units. Sixty-four leaves room for
/// fractional precision and a numeric timezone while refusing corrupted
/// multi-megabyte strings before `DateTime.tryParse` scans them.
const int maximumJsonDateCodeUnits = 64;

/// Reads [value] as an int: a number, or a string that parses as one.
/// Anything else is zero.
int jsonInt(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s when s.length <= maximumJsonIntegerCodeUnits =>
    int.tryParse(s) ?? 0,
  _ => 0,
};

/// Reads [value] as an int, or null when there is none.
int? jsonIntOrNull(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s when s.length <= maximumJsonIntegerCodeUnits => int.tryParse(
    s,
  ),
  _ => null,
};

/// Reads [value] as a string without changing its contents.
String jsonString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

/// Reads [value] as a JSON object, or an empty object for any other shape.
Map<String, dynamic> jsonObject(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// Reads [value] as a JSON array, or an empty array for any other shape.
List<dynamic> jsonArray(Object? value) =>
    value is List<dynamic> ? value : const [];

/// The object entries of a JSON array, with malformed entries skipped.
Iterable<Map<String, dynamic>> jsonObjects(Object? value) sync* {
  for (final entry in jsonArray(value)) {
    if (entry is Map<String, dynamic>) yield entry;
  }
}

/// Reads [value] as a trimmed string, or null when it is absent, not a
/// string, or blank.
String? jsonText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Reads an HTML-escaped text field as the plain text a native widget expects.
String? jsonHtmlText(Object? value) {
  final source = jsonText(value);
  if (source == null) return null;
  return jsonText(html.parseFragment(source).text);
}

/// Reads [value] as an ISO 8601 date, or null when it is absent or the site
/// sent something unparseable.
DateTime? jsonDate(Object? value) => switch (value) {
  final String s when s.length <= maximumJsonDateCodeUnits => DateTime.tryParse(
    s,
  ),
  _ => null,
};

/// A title out of the two flavours Discourse writes.
///
/// [plain] is preferred: it is the same text as unicode, which is what a
/// native Text widget wants. [fancy] is HTML — smart quotes as entities,
/// ampersands escaped — and only means anything once unescaped, which is why
/// it is the fallback and never the first choice.
String jsonTitle(Object? plain, Object? fancy) {
  if (plain case final String title when title.isNotEmpty) return title;
  if (fancy case final String fancy when fancy.isNotEmpty) {
    final source = _boundedFancyTitleSource(fancy);
    return html.parseFragment(source).text ?? source;
  }
  return '';
}

String _boundedFancyTitleSource(String source) {
  if (source.length <= maximumFancyTitleSourceCodeUnits) return source;

  var end = maximumFancyTitleSourceCodeUnits;
  final before = source.codeUnitAt(end - 1);
  final after = source.codeUnitAt(end);
  if (_isHighSurrogate(before) && _isLowSurrogate(after)) end--;
  return source.substring(0, end);
}

bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

/// Resolves a Discourse category color field into an opaque ARGB value.
///
/// Category colors are hex digits normally sent without a leading `#`, but
/// sites also produce `#`-prefixed and CSS three-digit shorthand forms. Every
/// serializer that carries a category color must resolve it through this one
/// helper; anything unrecognized becomes Discourse's default category gray.
int categoryColorValue(String color) {
  var hex = color.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = [for (final digit in hex.split('')) '$digit$digit'].join();
  }
  if (hex.length != 6) return 0xFF888888;
  return int.tryParse('FF$hex', radix: 16) ?? 0xFF888888;
}

/// Resolves a Discourse avatar template into an image URL for this site.
///
/// Templates are normally site-relative and carry a `{size}` placeholder,
/// while CDN-backed sites may answer with a protocol-relative or absolute URL.
String? resolveAvatarUrl(String? template, String siteUrl, {int size = 90}) {
  if (template == null || template.isEmpty) return null;
  final sized = template.replaceAll('{size}', '$size');
  if (sized.startsWith('//')) return 'https:$sized';
  if (sized.startsWith('http')) return sized;
  return '$siteUrl${sized.startsWith('/') ? '' : '/'}$sized';
}
