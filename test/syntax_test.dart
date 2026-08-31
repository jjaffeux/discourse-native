import 'package:discourse_native/src/shell/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> scopesOf(List<CodeToken> line) => [
  for (final token in line.where((t) => t.scope != null)) token.scope!,
];

String textOf(List<CodeToken> line) => line.map((token) => token.text).join();

void main() {
  group('highlightLines', () {
    setUp(clearSyntaxHighlightCacheForTesting);

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
          lines,
          hasLength(source.split('\n').length),
          reason: 'line boundaries survived $language',
        );
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

    test('reuses parsed tokens without sharing mutable list containers', () {
      final first = highlightLines('def cached = "value"', 'ruby');
      final parsedToken = first.first.first;

      first.first.clear();
      first.clear();
      final second = highlightLines('def cached = "value"', 'ruby');

      expect(second.map(textOf).join('\n'), 'def cached = "value"');
      expect(identical(second.first.first, parsedToken), isTrue);
    });

    test('needs a parse only where one would actually run', () {
      // The deferral path in `markdown_highlight.dart` asks this before taking
      // a fence off the frame, so it must agree exactly with what
      // `highlightLines` would do — plain path and cache key normalization
      // included.
      expect(highlightNeedsParse('def hello', 'ruby'), isTrue);

      highlightLines('def hello', 'RUBY');
      expect(highlightNeedsParse('def hello', 'ruby'), isFalse);

      expect(highlightNeedsParse('def hello', null), isFalse);
      expect(highlightNeedsParse('def hello', ''), isFalse);
      expect(highlightNeedsParse('def hello', 'plaintext'), isFalse);
      expect(highlightNeedsParse('def hello', 'nohighlight'), isFalse);

      final huge = List.filled(4000, 'def hello').join('\n');
      expect(huge.length, greaterThan(maxHighlightedChars));
      expect(highlightNeedsParse(huge, 'ruby'), isFalse);
    });

    test('evicts the least-recently used highlighted block', () {
      const retainedSource = 'def retained = 1';
      const evictedSource = 'def evicted = 2';
      final retainedToken = highlightLines(retainedSource, 'ruby').first.first;
      final evictedToken = highlightLines(evictedSource, 'ruby').first.first;

      for (var index = 0; index < syntaxHighlightCacheCapacity - 2; index++) {
        highlightLines('def filler_$index = $index', 'ruby');
      }

      // A hit promotes this entry, so the older `evictedSource` should leave.
      expect(
        identical(
          highlightLines(retainedSource, 'ruby').first.first,
          retainedToken,
        ),
        isTrue,
      );
      highlightLines('def overflow = 33', 'ruby');

      expect(
        identical(
          highlightLines(evictedSource, 'ruby').first.first,
          evictedToken,
        ),
        isFalse,
      );
      expect(
        identical(
          highlightLines(retainedSource, 'ruby').first.first,
          retainedToken,
        ),
        isTrue,
      );
    });
  });
}
