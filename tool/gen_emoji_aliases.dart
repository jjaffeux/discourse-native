/// Generates the native shortcode-alias index from Discourse's emoji data.
///
/// Discourse's `/emojis.json` endpoint returns canonical picker entries, but
/// cooked prose and plain topic titles may retain aliases such as `:mega:`.
/// Core resolves those through `discourse-emojis/dist/aliases.json`; keeping a
/// compile-time reverse index here gives native text the same answer without
/// adding a request to every connected site.
library;

import 'dart:convert';
import 'dart:io';

const String _revision = '29ebe49dee08fcb921e2530ed7718e3236f802a7';
const String _output = 'lib/src/models/discourse_emoji_aliases.dart';

Future<void> main() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'https://raw.githubusercontent.com/discourse/discourse-emojis/'
        '$_revision/dist/aliases.json',
      ),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      stderr.writeln('Alias download failed: HTTP ${response.statusCode}');
      exitCode = 1;
      return;
    }

    final decoded = jsonDecode(await utf8.decodeStream(response));
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('Alias payload is not a JSON object.');
      exitCode = 1;
      return;
    }

    final aliases = <String, String>{};
    for (final MapEntry(key: canonical, value: rawAliases) in decoded.entries) {
      if (rawAliases is! List<dynamic>) continue;
      for (final alias in rawAliases.whereType<String>()) {
        // Mirrors Emoji.reverse_aliases: a duplicate alias belongs to the
        // last canonical entry in the upstream object's iteration order.
        aliases[alias] = canonical;
      }
    }

    final ordered = aliases.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    await File(_output).writeAsString(_render(ordered));
    stdout.writeln('Wrote $_output — ${ordered.length} aliases');
  } finally {
    client.close(force: true);
  }
}

String _render(List<MapEntry<String, String>> aliases) {
  final output = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('// Run `dart run tool/gen_emoji_aliases.dart` to refresh it.')
    ..writeln()
    ..writeln(
      "/// Discourse's built-in shortcode aliases, keyed by alias and valued by the",
    )
    ..writeln('/// canonical emoji name returned from `/emojis.json`.')
    ..writeln('///')
    ..writeln('/// Generated from `discourse/discourse-emojis` revision')
    ..writeln('/// `$_revision`, `dist/aliases.json`.')
    ..writeln('const Map<String, String> discourseEmojiAliases = {');
  for (final MapEntry(key: alias, value: canonical) in aliases) {
    output.writeln("  '${_escape(alias)}': '${_escape(canonical)}',");
  }
  return (output..writeln('};')).toString();
}

String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
