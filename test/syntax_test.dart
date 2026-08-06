import 'package:discourse_native/src/shell/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scopes on a line, in order, ignoring unscoped source.
List<String> scopesOf(List<CodeToken> line) => [
  for (final token in line.where((t) => t.scope != null)) token.scope!,
];

String textOf(List<CodeToken> line) => line.map((token) => token.text).join();

void main() {
  group('highlightLines', () {
    test('scopes a language it knows', () {
      final lines = highlightLines('def hello\n  "hi"\nend', 'ruby');

      expect(lines.length, 3);
      expect(scopesOf(lines.first), contains('keyword'));
      expect(scopesOf(lines[1]), contains('string'));
    });

    test('resolves the aliases highlight.js registers', () {
      // Discourse writes Ruby as `lang-rb`.
      expect(scopesOf(highlightLines('def hello', 'rb').first), isNotEmpty);
    });

    test('resolves the aliases it does not', () {
      // `lang-es6` is a Discourse-ism; highlight.js has never heard of it.
      expect(
        scopesOf(highlightLines('const x = 1;', 'es6').first),
        contains('keyword'),
      );
    });

    test('leaves plaintext alone', () {
      final lines = highlightLines('def hello', 'plaintext');

      expect(scopesOf(lines.first), isEmpty);
      expect(textOf(lines.first), 'def hello');
    });

    test('leaves a language nobody has heard of alone', () {
      final lines = highlightLines('def hello', 'sumerian');

      expect(lines.length, 1);
      expect(textOf(lines.first), 'def hello');
    });

    test('cuts a token that spans lines back onto its lines', () {
      // A block comment is one token to the highlighter and three lines here.
      final lines = highlightLines('/*\n a\n*/\nx', 'javascript');

      expect(lines.length, 4);
      expect(scopesOf(lines[0]), contains('comment'));
      expect(scopesOf(lines[1]), contains('comment'));
      expect(textOf(lines[1]), ' a');
    });

    test('never changes the text or the number of lines', () {
      const source = 'class A\n\n  # comment\n  def b = "c"\nend\n';

      for (final language in ['ruby', 'plaintext', 'nonsense', 'auto', null]) {
        final lines = highlightLines(source, language);

        expect(
          lines.map(textOf).join('\n'),
          source,
          reason: 'text survived $language',
        );
      }
    });

    test('detects a language when the markup says auto', () {
      // The pastebin onebox is the one place Discourse emits `lang-auto`.
      final lines = highlightLines('def hello\n  puts "hi"\nend', 'auto');

      expect(scopesOf(lines.first), isNotEmpty);
    });

    test('gives up on a block too big to highlight without jank', () {
      final huge = List.filled(4000, 'def hello').join('\n');
      expect(huge.length, greaterThan(maxHighlightedChars));

      final lines = highlightLines(huge, 'ruby');

      expect(lines.length, 4000);
      expect(scopesOf(lines.first), isEmpty);
    });

    test('an empty line is an empty list of tokens, not a missing line', () {
      final lines = highlightLines('a\n\nb', 'ruby');

      expect(lines.length, 3);
      expect(lines[1], isEmpty);
    });
  });
}
