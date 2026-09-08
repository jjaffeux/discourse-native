import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

void main() {
  group('quote metadata scanning', () {
    for (final (name, unit, tail) in [
      ('straight quotes', '[quote="unfinished ', ''),
      ('curly quotes', '[quote=“unfinished ', ''),
      ('unquoted values', '[quote=x ', ''),
      ('shared invalid tail', '[quote=“unfinished ', '”'),
    ]) {
      test('$name scale with the draft', () {
        String draft(int count) =>
            '[quote]\n${unit * count}'
            '${tail.isEmpty ? '' : '$tail${' ' * count}invalid]'}\n'
            '[/quote]';
        final smallSource = draft(128);
        final largeSource = draft(1024);
        final smallCode = CodeRanges.of(scanMarkdown(smallSource));
        final largeCode = CodeRanges.of(scanMarkdown(largeSource));
        for (final (source, code) in [
          (smallSource, smallCode),
          (largeSource, largeCode),
        ]) {
          final quotes = parseComposerQuotes(source, knownCodeRanges: code);
          expect(quotes, hasLength(1), reason: '${source.length} characters');
          final quote = quotes.single;
          expect(quote.source, source);
          expect(quote.start, 0);
          expect(quote.end, source.length);
          expect(quote.contents, source.substring(8, source.length - 9).trim());
          expect(quote.username, isNull);
        }

        final (:small, :large) = measureScaling(
          () => parseComposerQuotes(
            smallSource,
            knownCodeRanges: smallCode,
          ).single.end,
          () => parseComposerQuotes(
            largeSource,
            knownCodeRanges: largeCode,
          ).single.end,
        );
        expect(
          large,
          lessThan(small * 25),
          reason: '8x malformed $name: ${large / small}x',
        );
      });
    }

    test(
      'retains every quotation mark, metadata field and source boundary',
      () {
        const pairs = [
          ('"', '"'),
          ("'", "'"),
          ('“', '”'),
          ('„', '”'),
          ('”', '”'),
          ('‘', '’'),
          ('‚', '’'),
          ('«', '»'),
          ('‹', '›'),
          ('', ''),
        ];
        for (final (open, close) in pairs) {
          final blockSource =
              '[QuOtE=${open}Last, First, post: 5, topic: 650, '
              'full: TRUE, username: sam$close \t]\r\n'
              '  Quoted 😀 words.  \r\n'
              '[/QuOtE] \t\r\n\r\n';
          final source = 'Before\n  $blockSource\nAfter';
          final quotes = parseComposerQuotes(source);
          expect(quotes, hasLength(1), reason: 'quotation marks: $open$close');
          final quote = quotes.single;

          expect(quote.start, 'Before\n  '.length);
          expect(quote.end, 'Before\n  $blockSource'.length);
          expect(quote.length, blockSource.length);
          expect(quote.source, blockSource);
          expect(quote.contents, 'Quoted 😀 words.');
          expect(
            (
              username: quote.username,
              displayName: quote.displayName,
              title: quote.title,
              postNumber: quote.postNumber,
              topicId: quote.topicId,
              full: quote.full,
            ),
            (
              username: 'sam',
              displayName: 'Last, First',
              title: 'Last, First',
              postNumber: 5,
              topicId: 650,
              full: true,
            ),
            reason: 'quotation marks: $open$close',
          );
        }
      },
    );

    test('retains Unicode trim whitespace after a closing quotation mark', () {
      const whitespace =
          ' \t\v\f\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004'
          '\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f'
          '\u205f\u3000\ufeff';
      const source = '[quote="sam"$whitespace]\nBody\n[/quote]';
      final quote = parseComposerQuotes(source).single;
      expect(quote.username, 'sam');
      expect(quote.source, source);
      expect(quote.contents, 'Body');
    });

    test(
      'rejects line breaks and non-whitespace after the first close mark',
      () {
        for (final opener in [
          '[quote="sam"x]',
          '[quote="sam" x "]',
          '[quote="sam"\r]',
          '[quote="sam"\n]',
          '[quote="sa\rm"]',
          '[quote="sa\nm"]',
          '[quote=sa\rm]',
          '[quote=sa\nm]',
          '[quote=“sam"]',
          '[quote="sam"',
          '[quote=sam',
        ]) {
          expect(
            parseComposerQuotes('$opener\nBody\n[/quote]'),
            isEmpty,
            reason: opener,
          );
        }
      },
    );

    test('inline metadata consumes apparent closing tags without nesting', () {
      for (final inline in [
        '[quote="literal [/quote] metadata"]',
        '[quote=“literal [/quote] metadata”]',
        '[quote=literal [/quote] metadata]',
        '[quote="literal [quote] metadata"]',
        '[quote]',
      ]) {
        final source = '[quote]\nBefore $inline after\nBody\n[/quote]';
        expect(
          parseComposerQuotes(
            source,
          ).map((quote) => (quote.source, quote.contents)),
          [(source, 'Before $inline after\nBody')],
          reason: inline,
        );
      }
    });

    test('invalid inline metadata leaves apparent closing tags visible', () {
      const source =
          '[quote]\nBefore [quote="literal [/quote] metadata"invalid]\n'
          'Body\n[/quote]';
      final quote = parseComposerQuotes(source).single;
      expect(quote.contents, 'Before [quote="literal');
      expect(quote.source, '[quote]\nBefore [quote="literal [/quote]');
      expect(quote.end, source.indexOf('] metadata') + 1);
    });

    test('preserves nested ambiguity and block indentation boundaries', () {
      for (final indent in ['', ' ', '  ', '\t', '\r', '\u00a0']) {
        final source = '[quote]\n$indent[quote="inner"]\nBody\n[/quote]';
        expect(parseComposerQuotes(source), isEmpty, reason: source);
        expect(
          parseComposerQuotes('$source\n[/quote]').map((quote) => quote.source),
          ['$source\n[/quote]'],
          reason: source,
        );
      }
      const source = '[quote]\n   [quote="inline"]\nBody\n[/quote]';
      expect(parseComposerQuotes(source).single.source, source);
    });

    test('honors scanned and supplied code ranges and escaped text', () {
      const source =
          '```\n[quote]\nignored\n[/quote]\n```\n'
          '\\[quote="escaped"]\n'
          '[quote="sam"]\n'
          '`[/quote]` and \\[quote="inline"]\n'
          '```\n[/quote]\n[quote]\n```\n'
          'Body\n[/quote]';
      final code = CodeRanges.of(scanMarkdown(source));
      for (final ranges in [null, code]) {
        final quotes = parseComposerQuotes(source, knownCodeRanges: ranges);
        expect(
          quotes,
          hasLength(1),
          reason: 'precomputed ranges: ${ranges != null}',
        );
        final quote = quotes.single;
        expect(quote.start, source.indexOf('[quote="sam"]'));
        expect(quote.end, source.length);
        expect(quote.username, 'sam');
        expect(quote.contents, contains('`[/quote]`'));
      }
      const hiddenSource = '[quote]\nBody\n[/quote]';
      final hiddenClose = hiddenSource.indexOf('[/quote]');
      final supplied = CodeRanges.of([
        MarkdownRun(hiddenClose, hiddenSource.length, Md.code),
      ]);
      expect(
        parseComposerQuotes(hiddenSource, knownCodeRanges: supplied),
        isEmpty,
      );
    });
  });

  test('input formatting keeps malformed quote bodies atomic', () {
    final body = '${'[quote=“unfinished ' * 128}\nBody';
    final source = '[quote="sam"]\n$body\n[/quote]\n\nafter';
    final quote = parseComposerQuotes(source).single;
    const formatter = ComposerQuoteInputFormatter();
    final old = TextEditingValue(text: source);
    final bodyEdit = TextEditingValue(
      text: source.replaceFirst('Body', 'Edit'),
    );
    expect(formatter.formatEditUpdate(old, bodyEdit), old);

    final removed = TextEditingValue(text: source.substring(quote.end));
    expect(formatter.formatEditUpdate(old, removed), removed);
    final appended = TextEditingValue(text: '${source}word');
    expect(formatter.formatEditUpdate(old, appended), appended);
  });
}
