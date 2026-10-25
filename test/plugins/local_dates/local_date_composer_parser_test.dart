import 'package:discourse_native/src/plugins/local_dates/local_date_composer_parser.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scaling_benchmark.dart';

const _date = '[date=2026-09-08 timezone=UTC]';
const _range = '[date-range from=2026-09-08T09:00 to=2026-09-09T10:00]';
const _quotes = [('"', '"'), ("'", "'"), ('“', '”'), ('‘', '’')];

void main() {
  final environment = LocalDateEnvironment.instance;

  setUpAll(environment.ensureDatabase);

  group('local-date composer closing brackets', () {
    for (final (open, close) in _quotes) {
      test('preserves $open$close quoting, source, and UTF-16 offsets', () {
        const prefix = '😀 before ';
        final tag =
            '[DaTe= \t${open}2026-09-08$close '
            'future = ${open}a ] [date=2025-01-01] b$close\t ]';
        final source = '$prefix$tag after';
        final block = parseLocalDateComposerBlocks(
          source,
          environment: environment,
        ).single;

        expect(
          (block.start, block.end),
          (prefix.length, prefix.length + tag.length),
        );
        expect(block.source, tag);
        expect(block.tagName, 'DaTe');
        expect(block.trailingWhitespace, '\t ');
        expect(block.attributes.map((attribute) => attribute.value), [
          '2026-09-08',
          'a ] [date=2025-01-01] b',
        ]);
        final attribute = block.attributes.last;
        expect((attribute.openingQuote, attribute.closingQuote), (open, close));
        expect(attribute.raw, ' future = ${open}a ] [date=2025-01-01] b$close');
        expect(attribute.leadingWhitespace, ' ');
        expect(attribute.whitespaceBeforeEquals, ' ');
        expect(attribute.whitespaceAfterEquals, ' ');
      });

      test(
        'restarts quote state for tags inside unfinished $open attributes',
        () {
          for (final ending in ['', close]) {
            final prefix = '😀 [date future=$open unfinished ';
            final source = '$prefix$_date$ending\n$_range';
            _expectBlocks(source, [
              (prefix.length, _date),
              (source.length - _range.length, _range),
            ], environment);
          }
        },
      );

      test('keeps nested tags raw inside a closed $open$close attribute', () {
        final prefix = '[date future=$open $_date $close] ';
        _expectBlocks('$prefix$_date', [(prefix.length, _date)], environment);
      });
    }

    test('ignores other quote types and brackets inside a quoted value', () {
      for (final (open, close) in _quotes) {
        for (final (innerOpen, innerClose) in _quotes) {
          if (innerOpen == open) continue;
          final tag =
              '[date=${open}2026-09-08$close '
              'future=$open$innerOpen]$_date$innerClose$close]';
          _expectBlocks('$tag $_range', [
            (0, tag),
            (tag.length + 1, _range),
          ], environment);
        }
      }
    });

    test('retains line boundaries and malformed or unsupported fallback', () {
      for (final malformed in [
        '[date date=“ unfinished',
        '[date date="unfinished]',
        '[date=2023-02-29]',
        '[date=2026-09-08 DATE=2026-09-09]',
        '[date=2026-09-08 timezone=Future/Mars]',
        '[date=2026-09-08 recurring=0.days]',
        '[date=2026-09-08 calendar=maybe]',
        '[date-range from=2026-09-08T24:00 to=2026-09-09]',
      ]) {
        for (final newline in ['\n', '\r\n']) {
          final source = '$malformed$newline$_date$newline$_range';
          _expectBlocks(source, [
            (malformed.length + newline.length, _date),
            (source.length - _range.length, _range),
          ], environment);
        }
      }
      // A carriage return alone is still part of a quoted value.
      const source = '[date=2026-09-08 future="a\rb"]';
      _expectBlocks(source, [(0, source)], environment);
    });

    test('resumes after code-contained and code-overlapping openers', () {
      for (final excluded in [
        '`$_date`',
        '```\n$_date\n```',
        '[date future=“ `code` $_date',
        '[date=2026-09-08 future="`code`"]',
      ]) {
        final source = '$excluded\n$_range';
        final expected = [
          if (excluded.endsWith(_date)) (excluded.length - _date.length, _date),
          (excluded.length + 1, _range),
        ];
        _expectBlocks(source, expected, environment);
      }
      const prefix = '[date=2026-09-08 future="`code`"] ';
      _expectBlocks('$prefix$_date', [(prefix.length, _date)], environment);
    });
  });

  group('local-date composer admission', () {
    List<String> projected(String source) => [
      for (final block in parseLocalDateComposerBlocks(
        source,
        environment: environment,
      ))
        block.source,
    ];

    test('accepts the last valid clock values and five preview zones', () {
      const zones =
          'UTC|Europe/Paris|Asia/Tokyo|America/New_York|Europe/London';
      for (final source in [
        '[date-range from=2026-09-08T23:59:59 to=2026-09-09T23:00]',
        '[date=2026-12-31 timezones="$zones"]',
      ]) {
        expect(projected(source), [source], reason: source);
      }
      expect(
        projected('[date=2026-12-31 timezones="$zones|Australia/Sydney"]'),
        isEmpty,
      );
    });

    test('keeps a date holding range attributes and a range holding date '
        'options raw', () {
      for (final source in [
        '[date=2026-09-08 from=2026-09-08T09:00]',
        '[date=2026-09-08 to=2026-09-09T09:00]',
        '[date-range from=2026-09-08T09:00 to=2026-09-09 recurring=1.weeks]',
        '[date-range from=2026-09-08T09:00 to=2026-09-09 countdown=true]',
        '[date-range from=2026-09-08T09:00 to=2026-09-09 date=2026-09-08]',
      ]) {
        expect(projected(source), isEmpty, reason: source);
      }
    });

    test('admits only the calendar values and range ends upstream reads', () {
      for (final source in [
        '[date=2026-09-08 calendar=on]',
        '[date=2026-09-08 calendar=off]',
        '[date-range from=2026-09-08 to=2026-09-09]',
      ]) {
        expect(projected(source), [source], reason: source);
      }
      for (final source in [
        '[date-range from=2026-09-08T09:00 to=2026-02-30]',
        '[date-range from=2026-09-08T09:00T10 to=2026-09-09]',
        '[date=2026-09-08 future= ]',
      ]) {
        expect(projected(source), isEmpty, reason: source);
      }
    });

    test('keeps a bracket inside an unquoted value raw', () {
      // The closing scan reads the quote as opening a value, so the bracket
      // lands inside the tag; the attribute parser must still refuse it.
      expect(projected('[date=2026-09-08 future=a"]"]'), isEmpty);
    });

    test('a tag name cut off by the end of the draft is not a tag', () {
      expect(projected('see [date'), isEmpty);
      expect(projected('see [date-range'), isEmpty);
    });

    test('a block contains its source range end-exclusively', () {
      final block = parseLocalDateComposerBlocks(
        'x $_date y',
        environment: environment,
      ).single;

      expect(block.containsOffset(block.start), isTrue);
      expect(block.containsOffset(block.end - 1), isTrue);
      expect(block.containsOffset(block.start - 1), isFalse);
      expect(block.containsOffset(block.end), isFalse);
    });
  });

  group('local-date markup values', () {
    test('quotes values the unquoted grammar would misread', () {
      expect(renderLocalDateMarkupValue('UTC'), 'UTC');
      expect(renderLocalDateMarkupValue(''), '""');
      for (final (open, _) in _quotes) {
        expect(
          renderLocalDateMarkupValue('${open}x'),
          isNot(startsWith(open)),
          reason: open,
        );
      }
    });

    test('an implicit date edits without gaining a name', () {
      final block = parseLocalDateComposerBlocks(
        '[date= 2026-09-08 timezone=UTC]',
        environment: environment,
      ).single;

      expect(block.attributes.first.withValue('2026-10-01'), '= 2026-10-01');
      expect(
        block.attributes.last.withValue('Asia/Tokyo'),
        ' timezone=Asia/Tokyo',
      );
    });
  });

  group('local-date composer scaling', () {
    test('a draft whose brackets open no date is not scanned for code', () {
      // Every composer parses every edit, whether or not the site has dates.
      final source = [
        for (var link = 0; link < 40; link += 1)
          'Date-free [link $link](https://example.com/$link) and `[x]`.',
      ].join('\n\n');
      final scans = markdownScanCount;

      expect(
        parseLocalDateComposerBlocks(source, environment: environment),
        isEmpty,
      );
      expect(markdownScanCount, scans);
    });

    for (final quote in ['', ..._quotes.map((pair) => pair.$1)]) {
      test('unfinished $quote attributes scale with the draft', () {
        final unit = '[date date=$quote ';
        final smallSource = '${unit * 256}\n$_date';
        final largeSource = '${unit * 2048}\n$_date';
        List<LocalDateComposerBlock> parse(String source) =>
            parseLocalDateComposerBlocks(
              source,
              environment: environment,
              knownCodeRanges: CodeRanges.none,
            );

        expect(
          parse(smallSource).single.start,
          smallSource.length - _date.length,
        );
        expect(
          parse(largeSource).single.start,
          largeSource.length - _date.length,
        );

        // Keep Markdown setup outside the timed work. An 8x input distinguishes
        // linear growth from repeated suffix scans (~64x), allowing VM noise.
        final (:small, :large) = measureScaling(
          () => parse(smallSource).single.end,
          () => parse(largeSource).single.end,
        );
        expect(
          large,
          lessThan(small * 25),
          reason: '8x input: ${large / small}x',
        );
      });
    }
  });
}

void _expectBlocks(
  String source,
  List<(int, String)> expected,
  LocalDateEnvironment environment,
) {
  for (final codeRanges in [null, CodeRanges.of(scanMarkdown(source))]) {
    final blocks = parseLocalDateComposerBlocks(
      source,
      environment: environment,
      knownCodeRanges: codeRanges,
    );
    expect(
      [for (final block in blocks) (block.start, block.end, block.source)],
      [for (final (start, raw) in expected) (start, start + raw.length, raw)],
      reason: source,
    );
  }
}
