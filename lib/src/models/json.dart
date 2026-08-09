// The small acts of reading a Discourse payload, written once.
//
// The wire is forgiving in the ways it writes: numbers arrive as strings,
// keys are dropped rather than nulled, and a title comes in a plain and an
// HTML flavour. Every parser answers that with a default rather than a
// throw — a field the site did not send is a field left at its default —
// and these are the shapes that answer.

import 'package:html/parser.dart' as html;

/// Reads [value] as an int: a number, or a string that parses as one.
/// Anything else is zero.
int jsonInt(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

/// Reads [value] as an int, or null when there is none.
int? jsonIntOrNull(Object? value) => switch (value) {
  final num n when n.isFinite => n.toInt(),
  final String s => int.tryParse(s),
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

/// Reads [value] as an ISO 8601 date, or null when it is absent or the site
/// sent something unparseable.
DateTime? jsonDate(Object? value) => switch (value) {
  final String s => DateTime.tryParse(s),
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
    return html.parseFragment(fancy).text ?? fancy;
  }
  return '';
}

/// Resolves a Discourse avatar template into an image URL for this site.
///
/// Templates are normally site-relative and carry a `{size}` placeholder,
/// while CDN-backed sites may answer with a protocol-relative or absolute URL.
String? resolveAvatarUrl(String? template, String siteUrl) {
  if (template == null || template.isEmpty) return null;
  final sized = template.replaceAll('{size}', '90');
  if (sized.startsWith('//')) return 'https:$sized';
  if (sized.startsWith('http')) return sized;
  return '$siteUrl${sized.startsWith('/') ? '' : '/'}$sized';
}
