import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _owner = 'lib/src/models/topic_link.dart';

/// Files whose `/t/` pattern is not a topic path, and why.
const _exceptions = {
  'lib/src/plugins/chat/chat_route.dart':
      'a chat thread route: /c/slug/id/t/id',
};

/// A regular expression over a topic path, or a test of a path's first segment
/// against the topic route.
final _handParser = RegExp(
  r"""RegExp\(\s*r?['"][^'"\n]*\\*/t\\*/|"""
  r"""\b\w+(?:\.first|\[0\])\s*[!=]=\s*'t'""",
);

String _withoutComments(String source) =>
    source.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  final sources = {
    for (final file in Directory('lib/src').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        file.path.replaceAll(r'\', '/'): _withoutComments(
          file.readAsStringSync(),
        ),
  };

  test('only TopicLink reads a topic link', () {
    final parsers = [
      for (final entry in sources.entries)
        if (entry.key != _owner && !_exceptions.containsKey(entry.key))
          for (final match in _handParser.allMatches(entry.value))
            '${entry.key}: ${match[0]}',
    ];
    // ignore: avoid_print
    print('PERF_PROOF topic-link-owner hand_parsers=${parsers.length}');
    expect(
      parsers,
      isEmpty,
      reason:
          'Use TopicLink.parse. /t/id/post and /t/slug/id have the same '
          'length, and a hand parser cannot tell them apart.',
    );
  });

  test('the scan still recognises what it rejects', () {
    for (final copy in [
      r"RegExp(r'/t/(?:[^/]+/)?([0-9]+)')",
      "RegExp(\n  r'^/t/([1-9]\\d*)')",
      r"RegExp('\\/t\\/')",
      "parts.first == 't'",
      "segments[0] != 't'",
    ]) {
      expect(_handParser.hasMatch(copy), isTrue, reason: copy);
    }
    expect(_handParser.hasMatch("query['t'] = '1s'"), isFalse);
    expect(_handParser.hasMatch("parts.first == 'p'"), isFalse);
  });
}
