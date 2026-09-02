import 'package:html/parser.dart' as html;

/// Core limits a topic title to 255 characters. Its fancy-title fallback is
/// the HTML-escaped raw title, whose longest entity (`&quot;`) is six UTF-16
/// code units, so even that worst case fits in 255 * 6. Bounding the fallback
/// before DOM parsing keeps a malformed response from allocating an arbitrary
/// HTML tree without changing any conforming title.
const int maximumFancyTitleSourceCodeUnits = 1530;

/// Server IDs and counts are signed 64-bit values: 19 digits, plus an optional
/// minus sign. Reject longer strings before `int.tryParse`; a malformed JSON
/// response is otherwise able to spend CPU and temporary memory parsing a
/// multi-megabyte decimal field at every model boundary that uses these
/// helpers.
const int maximumJsonIntegerCodeUnits = 20;

/// Normal wire values are around 24–35 code units. Sixty-four leaves room for
/// fractional precision and a numeric timezone while refusing corrupted
/// multi-megabyte strings before `DateTime.tryParse` scans them.
const int maximumJsonDateCodeUnits = 64;

int jsonInt(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s when s.length <= maximumJsonIntegerCodeUnits =>
    int.tryParse(s) ?? 0,
  _ => 0,
};

int? jsonIntOrNull(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s when s.length <= maximumJsonIntegerCodeUnits => int.tryParse(
    s,
  ),
  _ => null,
};

String jsonString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

Map<String, dynamic> jsonObject(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// Plugin codecs read values back from this app's own storage, where a map
/// may have been decoded with untyped keys. A codec answers null for a value
/// that is not an object or carries a non-string key, because a value it
/// cannot read is one it must not claim to hold; [jsonObject]'s empty
/// fallback would turn that into a default record.
Map<String, Object?>? jsonObjectFields(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<dynamic> jsonArray(Object? value) =>
    value is List<dynamic> ? value : const [];

Iterable<Map<String, dynamic>> jsonObjects(Object? value) sync* {
  for (final entry in jsonArray(value)) {
    if (entry is Map<String, dynamic>) yield entry;
  }
}

String? jsonText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? jsonHtmlText(Object? value) {
  final source = jsonText(value);
  if (source == null) return null;
  return jsonText(html.parseFragment(source).text);
}

DateTime? jsonDate(Object? value) => switch (value) {
  final String s when s.length <= maximumJsonDateCodeUnits => DateTime.tryParse(
    s,
  ),
  _ => null,
};

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

/// Templates are normally site-relative and carry a `{size}` placeholder,
/// while CDN-backed sites may answer with a protocol-relative or absolute URL.
String? resolveAvatarUrl(String? template, String siteUrl, {int size = 90}) {
  if (template == null || template.isEmpty) return null;
  final sized = template.replaceAll('{size}', '$size');
  if (sized.startsWith('//')) return 'https:$sized';
  if (sized.startsWith('http')) return sized;
  return '$siteUrl${sized.startsWith('/') ? '' : '/'}$sized';
}
