import 'package:html/parser.dart' as html;

/// The small acts of reading a Discourse payload, written once.
///
/// The wire is forgiving in the ways it writes: numbers arrive as strings,
/// keys are dropped rather than nulled, and a title comes in a plain and an
/// HTML flavour. Every parser answers that with a default rather than a
/// throw — a field the site did not send is a field left at its default —
/// and these are the shapes that answer.

/// Reads [value] as an int: a number, or a string that parses as one.
/// Anything else is zero.
int jsonInt(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

/// Reads [value] as an int, or null when there is none.
int? jsonIntOrNull(Object? value) => switch (value) {
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

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
