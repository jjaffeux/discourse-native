import 'dart:math';

import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

typedef _ExpectedLink = ({
  String source,
  String anchor,
  String url,
  ComposerLinkKind kind,
});

void main() {
  group('pasted links', () {
    TextEditingValue selected(String text) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );

    test('escapes label brackets and URL delimiters', () {
      final next = composerPastedLinkValue(
        selected('the [guide]'),
        ' https://example.com/a(b) ',
      );
      expect(next!.text, r'[the \[guide\]](https://example.com/a%28b%29)');
      final link = parseComposerLinks(next.text).single;
      expect(link.kind, ComposerLinkKind.markdown);
      expect(link.source, next.text);
      expect(link.anchor, r'the \[guide\]');
    });

    for (final clipboard in [
      'ordinary text',
      'https://example.com and more',
      'https://one.com\nhttps://two.com',
      'https://',
      'javascript:alert(1)',
    ]) {
      test('keeps ordinary paste for $clipboard', () {
        expect(composerPastedLinkValue(selected('label'), clipboard), isNull);
      });
    }

    for (final text in [
      '`code`',
      '[existing](https://example.com)',
      'https://example.com',
      'two\nlines',
      '   ',
    ]) {
      test('does not wrap $text', () {
        expect(
          composerPastedLinkValue(selected(text), 'https://discourse.org'),
          isNull,
        );
      });
    }

    test('leaves URL paste at a collapsed caret alone', () {
      expect(
        composerPastedLinkValue(
          const TextEditingValue(
            text: 'text',
            selection: TextSelection.collapsed(offset: 2),
          ),
          'https://discourse.org',
        ),
        isNull,
      );
    });
  });

  group('composer link parser behavior', () {
    test('keeps escaped label brackets inside the full source range', () {
      for (final anchor in const [r'A\]B', r'the \[guide\]', r'path\\name']) {
        final markdown = '[$anchor](https://example.test)';
        _expectLinks(markdown, [
          _markdown(markdown, anchor, 'https://example.test'),
        ]);
      }
    });

    test('preserves ordering, UTF-16 offsets, and normalized destinations', () {
      const source =
          '😀 See https://example.test/路径 and [café 🐱](../relative) '
          'then team+news@discourse.org, //example.test/path, '
          'FTP://files.test/a and EXAMPLE.COM:8080/path?q=é.';

      _expectLinks(source, [
        _linkify('https://example.test/路径'),
        _markdown('[café 🐱](../relative)', 'café 🐱', '../relative'),
        _linkify('team+news@discourse.org', 'mailto:team+news@discourse.org'),
        _linkify('//example.test/path'),
        _linkify('FTP://files.test/a'),
        _linkify(
          'EXAMPLE.COM:8080/path?q=é',
          'http://EXAMPLE.COM:8080/path?q=é',
        ),
      ]);
    });

    test('keeps balanced destination parentheses inside the source range', () {
      for (final url in const [
        'https://en.wikipedia.org/wiki/Dart_(programming_language)',
        'https://example.test/one(two(three)four)(five)?q=(six)',
        '../relative(one(two)three)/🐱',
      ]) {
        final markdown = '[café 🐱]($url)';
        _expectLinks('😀 Read $markdown) then [next](../next).', [
          _markdown(markdown, 'café 🐱', url),
          _markdown('[next](../next)', 'next', '../next'),
        ]);
      }
    });

    test('keeps escaped delimiters literal and preserves editable escapes', () {
      for (final url in const [
        r'https://example.test/one\(two\)three',
        r'https://example.test/one\)two',
        r'https://example.test/one\(two',
        r'https://example.test/one(two\)three)',
        r'https://example.test/one\\(two)',
        r'https://example.test/one\\\)two',
        r'https://example.test/one\\',
      ]) {
        final markdown = '[link]($url)';
        _expectLinks('😀 $markdown after', [_markdown(markdown, 'link', url)]);
      }
    });

    test(
      'falls back from unfinished or whitespace-containing destinations',
      () {
        for (final source in const [
          '[link](../one(two)',
          '[link](../one(two',
          r'[link](../one\)',
          r'[link](../one\\(two)',
          '[link](../one(two three))',
          r'[link](../one\ space)',
          '[link](../one(two\nthree))',
          '[link](../one\\\nthree)',
        ]) {
          _expectLinks(source, []);
        }

        _expectLinks('[broken](https://example.test/one(two) [kept](../ok)', [
          _linkify('https://example.test/one(two)'),
          _markdown('[kept](../ok)', 'kept', '../ok'),
        ]);
      },
    );

    test('recovers later links inside unfinished destinations', () {
      for (final source in const [
        '[outer](../unfinished([kept](../ok)',
        '[[[outer](../unfinished [kept](../ok)',
      ]) {
        _expectLinks(source, [_markdown('[kept](../ok)', 'kept', '../ok')]);
      }
    });

    test('uses the markdown-it limit for destination nesting', () {
      for (final depth in [32, 33]) {
        final url = '../${'(' * depth}part${')' * depth}';
        final markdown = '[link]($url)';
        _expectLinks(markdown, [
          if (depth == 32) _markdown(markdown, 'link', url),
        ]);
      }
    });

    test('excludes images and code with nested destinations', () {
      const source =
          '![image](https://image.test/one(two(three)).png) '
          '`[inline](https://inline.test/one(two))`\n'
          '```\n[fenced](https://fenced.test/one(two))\n```\n'
          '[visible](https://visible.test/one(two))';
      _expectLinks(source, [
        _markdown(
          '[visible](https://visible.test/one(two))',
          'visible',
          'https://visible.test/one(two)',
        ),
      ]);
    });

    test('honors configured TLDs and disabling linkification', () {
      const source =
          'example.com example.IT team@EXAMPLE.IT example.invalid '
          'https://a ftp://example.unknown //example.unknown '
          '[kept](custom:destination)';
      const tlds = [' .IT ', '', '  ', 'it'];
      final explicit = _markdown(
        '[kept](custom:destination)',
        'kept',
        'custom:destination',
      );

      _expectLinks(source, [
        _linkify('example.IT', 'http://example.IT'),
        _linkify('team@EXAMPLE.IT', 'mailto:team@EXAMPLE.IT'),
        _linkify('https://a'),
        _linkify('ftp://example.unknown'),
        _linkify('//example.unknown'),
        explicit,
      ], linkifyTlds: tlds);
      _expectLinks(source, [
        _linkify('https://a'),
        _linkify('ftp://example.unknown'),
        _linkify('//example.unknown'),
        explicit,
      ], linkifyTlds: const []);
      _expectLinks(source, [explicit], enableLinkify: false);
    });

    test(
      'excludes markdown, images, code, reference destinations, and HTML',
      () {
        const source =
            '`https://inline.test` [label.com](https://markdown.test) '
            '![image.com](https://image.test/logo.png)\n'
            '[ref]: https://reference.test\n'
            '```\nhttps://fenced.test\n```\n'
            '<a href="https://attribute.test">https://adjacent.test </a> '
            '<span> https://visible.test </span> '
            '<https://autolink.test> https://after.test';

        _expectLinks(source, [
          _markdown(
            '[label.com](https://markdown.test)',
            'label.com',
            'https://markdown.test',
          ),
          _linkify('https://visible.test'),
          _linkify('https://after.test'),
        ]);
      },
    );

    test('retains malformed and escaped delimiter fallback', () {
      const source =
          r'\[escaped](https://escaped.test) '
          r'\\[valid](https://valid.test) '
          r'[escaped\](https://closing.test) '
          '[broken](https://space.test title) '
          '[missing](https://missing.test '
          '<unfinished\nhttps://hidden.test > https://outside.test '
          r'\<https://escaped-angle.test > https://last.test';

      _expectLinks(source, [
        _linkify('https://escaped.test'),
        _markdown('[valid](https://valid.test)', 'valid', 'https://valid.test'),
        _linkify('https://closing.test'),
        _linkify('https://space.test'),
        _linkify('https://missing.test'),
        _linkify('https://outside.test'),
        _linkify('https://last.test'),
      ]);
    });

    test('reference prefixes use full whitespace semantics on each line', () {
      const source =
          '\u00a0\t[ref]:\u2003https://hidden.test https://second.test\n'
          '[label https://label.test ]: https://destination.test\r\n'
          'prose [ref]: https://prose.test\n'
          '[]: https://empty-label.test\n'
          '[ref]:\nhttps://next-line.test\n'
          '[broken\n]: https://broken.test\n'
          ' \t\r\n\u2028[ref]:\ufeffhttps://unicode-hidden.test\n'
          'https://final.test';

      _expectLinks(source, [
        _linkify('https://second.test'),
        _linkify('https://label.test'),
        _linkify('https://prose.test'),
        _linkify('https://empty-label.test'),
        _linkify('https://next-line.test'),
        _linkify('https://broken.test'),
        _linkify('https://final.test'),
      ]);
    });

    test(
      'keeps boundary rules and advances context through excluded matches',
      () {
        const source =
            '_https://boundary.test @example.com xhttps://prefixed.test '
            'éhttps://unicode.test [x](https://markdown.test/<) '
            'https://hidden.test > https://shown.test '
            '`https://code.test/<` https://also-hidden.test '
            '> https://after-code.test';

        _expectLinks(source, [
          _linkify('https://unicode.test'),
          _markdown(
            '[x](https://markdown.test/<)',
            'x',
            'https://markdown.test/<',
          ),
          _linkify('https://shown.test'),
          _linkify('https://after-code.test'),
        ]);
      },
    );

    test('preserves balanced punctuation and the order of trimming passes', () {
      const suffixes = {
        '(film).': '(film)',
        '(film))))': '(film)',
        '[part]]],': '[part]',
        '{part}}}?!': '{part}',
        '((part)))))': '((part))',
        'part?))))': 'part?',
        'part)]}': 'part)]',
        'part}])': 'part',
        r'part\)))': r'part\',
        ')part(': ')part(',
        'part...': 'part',
      };
      for (final entry in suffixes.entries) {
        final source = 'See https://example.test/${entry.key} end';
        _expectLinks(source, [_linkify('https://example.test/${entry.value}')]);
      }
    });

    test('finds links where long runs without spaces end', () {
      final letters = 'a' * 4096;
      final base64 = 'Ab3+/' * 820;
      final labels = 'a.' * 2048;

      // Every character of the run before an @ is its local part.
      for (final run in [letters, base64, labels]) {
        _expectLinks('${run}x@example.com.', [
          _linkify('${run}x@example.com', 'mailto:${run}x@example.com'),
        ]);
      }
      // A URL needs a boundary before it, which a slash or a space gives.
      _expectLinks('${letters}https://example.com/a', []);
      _expectLinks('${base64}https://example.com/a', [
        _linkify('https://example.com/a'),
      ]);
      _expectLinks('$letters https://example.com/a).', [
        _linkify('https://example.com/a'),
      ]);
      // Labels before a host are its subdomains, however many there are.
      _expectLinks('${labels}example.com', [
        _linkify('${labels}example.com', 'http://${labels}example.com'),
      ]);
      _expectLinks('$labels www.example.com.', [
        _linkify('www.example.com', 'http://www.example.com'),
      ]);
      _expectLinks('${letters}www.example.com', []);
      _expectLinks('${'ab-' * 1365} see www.example.com/a_(b)).', [
        _linkify('www.example.com/a_(b)', 'http://www.example.com/a_(b)'),
      ]);
    });

    test('keeps the 63-character label limit', () {
      final longest = '${'a' * 63}.com';
      _expectLinks('$longest ${'b' * 64}.com x@${'c' * 64}.com', [
        _linkify(longest, 'http://$longest'),
      ]);
    });
  });

  group('linkify candidates', () {
    // The pattern the candidate scan replaced, one alternative per constant.
    const urlPattern = r'(?:(?:https?|ftp)://|//)[^\s<]+';
    const emailPattern =
        r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
        r'(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+'
        r'[A-Za-z]{2,63}';
    const hostPattern =
        r'(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+'
        r'[A-Za-z]{2,63}(?::[0-9]{1,5})?(?:[/?#][^\s<]*)?';
    RegExp compile(String pattern) =>
        RegExp(pattern, caseSensitive: false, unicode: true);
    final pattern = compile('$urlPattern|$emailPattern|$hostPattern');
    List<(int, int)> matches(String source) => [
      for (final match in pattern.allMatches(source)) (match.start, match.end),
    ];

    test('agree with the pattern they replaced', () {
      const alphabet = [
        'a',
        'Z',
        '7',
        '-',
        '.',
        '@',
        '_',
        '+',
        '/',
        ':',
        '?',
        '#',
        '<',
        ' ',
        '\n',
        'ab',
        'com',
        '.io',
        'x.y',
        'www.',
        'x@',
        '@ab.cd',
        'http',
        'HTTPS',
        'ftp',
        '://',
        '//',
        ':80',
        '123456',
        '(',
        ')',
        ',',
        "'",
        // Whitespace outside ASCII, the two code points that case-fold onto
        // ASCII letters, a letter that does not, and surrogates.
        '\u00a0',
        '\u2028',
        '\u3000',
        '\ufeff',
        '\u017f',
        '\u212a',
        'é',
        '😀',
        '\ud800',
        // Two of these make a label longer than 63 characters.
        'bcdefghijklmnopqrstuvwxyzabcdef',
      ];
      final alternatives = {
        'url': compile(urlPattern),
        'email': compile(emailPattern),
        'host': compile(hostPattern),
      };
      final reached = {for (final kind in alternatives.keys) kind: 0};
      var sourcesWithoutCandidates = 0;
      final random = Random(20260927);

      for (var attempt = 0; attempt < 20000; attempt += 1) {
        final buffer = StringBuffer();
        for (var i = random.nextInt(24); i > 0; i -= 1) {
          buffer.write(alphabet[random.nextInt(alphabet.length)]);
        }
        final source = buffer.toString();
        final expected = matches(source);

        expect(
          composerLinkifyCandidates(source),
          expected,
          reason: 'differed on ${source.codeUnits}',
        );
        if (expected.isEmpty) sourcesWithoutCandidates += 1;
        for (final (start, _) in expected) {
          final kind = alternatives.entries
              .firstWhere(
                (entry) => entry.value.matchAsPrefix(source, start) != null,
              )
              .key;
          reached[kind] = reached[kind]! + 1;
        }
      }

      expect(sourcesWithoutCandidates, greaterThan(1000));
      for (final entry in reached.entries) {
        expect(entry.value, greaterThan(1000), reason: entry.key);
      }
    });

    test('agree with the pattern at its length limits', () {
      for (final source in [
        '${'a' * 63}.com',
        '${'a' * 64}.com',
        '${'a' * 70}.${'b' * 63}.${'c' * 64}.com',
        '-${'a' * 62}-.com',
        'a.${'b' * 70}',
        'x@${'b' * 63}.com',
        'x@${'b' * 64}.com',
        'x@a.${'b' * 64}.c',
        'host.com:123456/path',
        'host.com:/path',
        'host.com:8a',
        'https:// x',
        'http\u017f://x',
        '//<x',
        '\u017f.com',
        'a.\u212aa',
      ]) {
        expect(
          composerLinkifyCandidates(source),
          matches(source),
          reason: source,
        );
      }
    });
  });

  group('composer link parser scaling', () {
    final destinationShapes = <String, String Function(int)>{
      'unfinished labels': (count) =>
          '${'[' * count}link](../${'part' * count}',
      'unfinished nested destinations': (count) => '[link](../part' * count,
      'balanced destination parentheses': (count) =>
          '[link](../${'(part)' * count})',
    };
    for (final shape in destinationShapes.entries) {
      test('${shape.key} scale with their length', () {
        final smallSource = shape.value(1024);
        final largeSource = shape.value(8192);
        int scan(String source) => parseComposerLinks(
          source,
          codeRanges: CodeRanges.none,
          enableLinkify: false,
        ).length;

        final expectedCount = shape.key.startsWith('unfinished') ? 0 : 1;
        expect(scan(smallSource), expectedCount);
        expect(scan(largeSource), expectedCount);

        final (:small, :large) = measureScaling(
          () => scan(smallSource),
          () => scan(largeSource),
        );
        expect(large, lessThan(small * 25));
      });
    }

    // An 8x input separates linear growth from the former ~64x cost, with room
    // for VM and scheduling noise. Keep markdown scanning outside timed work.
    for (final referenceLabel in [false, true]) {
      test(
        'URL lists scale with their length (reference label: $referenceLabel)',
        () {
          String urls(int count) {
            final list = 'See https://example.test/some-page ' * count;
            return referenceLabel ? '[$list]: https://reference.test' : list;
          }

          final smallSource = urls(128);
          final largeSource = urls(1024);
          final smallCode = CodeRanges.of(scanMarkdown(smallSource));
          final largeCode = CodeRanges.of(scanMarkdown(largeSource));
          final smallLinks = parseComposerLinks(
            smallSource,
            codeRanges: smallCode,
          );
          final largeLinks = parseComposerLinks(
            largeSource,
            codeRanges: largeCode,
          );
          expect(smallLinks, hasLength(128));
          expect(largeLinks, hasLength(1024));
          expect(
            largeLinks.last.end,
            largeSource.lastIndexOf('https://example.test/some-page') +
                'https://example.test/some-page'.length,
          );

          final (:small, :large) = measureScaling(
            () =>
                parseComposerLinks(smallSource, codeRanges: smallCode).last.end,
            () =>
                parseComposerLinks(largeSource, codeRanges: largeCode).last.end,
          );
          expect(large, lessThan(small * 25));
        },
      );
    }

    // A paste with no space in it, such as a base64 blob or a minified token,
    // is one run that every later start position shares. A failed candidate
    // must not reread the rest of it; the former pattern grew ~60x here.
    const spacelessRuns = {
      'letters': 'a',
      'base64': 'Ab3+/',
      'hyphenated words': 'ab-',
      'one-letter labels': 'a.',
      'email local parts with no @': 'first.last+tag_',
    };
    for (final run in spacelessRuns.entries) {
      test('a run of ${run.key} scales with its length', () {
        final count = (1024 / run.value.length).ceil();
        final smallSource = run.value * count;
        final largeSource = run.value * (count * 8);
        int scan(String source) =>
            parseComposerLinks(source, codeRanges: CodeRanges.none).length;
        expect(scan(smallSource), 0);
        expect(scan(largeSource), 0);

        final (:small, :large) = measureScaling(
          () => scan(smallSource),
          () => scan(largeSource),
        );
        expect(
          large,
          lessThan(small * 25),
          reason: 'eight times "${run.value}" took ${large / small} times',
        );
      });
    }

    for (final closer in [')', ']', '}']) {
      test('unmatched $closer suffixes scale with their length', () {
        const url = 'https://example.test/part';
        final smallSource = '$url${closer * 1024}';
        final largeSource = '$url${closer * 8192}';
        _expectLinks(smallSource, [_linkify(url)]);
        _expectLinks(largeSource, [_linkify(url)]);

        final (:small, :large) = measureScaling(
          () => parseComposerLinks(
            smallSource,
            codeRanges: CodeRanges.none,
          ).single.end,
          () => parseComposerLinks(
            largeSource,
            codeRanges: CodeRanges.none,
          ).single.end,
        );
        expect(large, lessThan(small * 25));
      });
    }
  });
}

_ExpectedLink _linkify(String source, [String? url]) => (
  source: source,
  anchor: source,
  url: url ?? source,
  kind: ComposerLinkKind.linkify,
);

_ExpectedLink _markdown(String source, String anchor, String url) =>
    (source: source, anchor: anchor, url: url, kind: ComposerLinkKind.markdown);

void _expectLinks(
  String source,
  List<_ExpectedLink> expected, {
  bool enableLinkify = true,
  List<String> linkifyTlds = const ['com', 'org'],
}) {
  var offset = 0;
  final blocks = <(int, int, _ExpectedLink)>[];
  for (final link in expected) {
    final start = source.indexOf(link.source, offset);
    expect(start, greaterThanOrEqualTo(offset));
    offset = start + link.source.length;
    blocks.add((start, offset, link));
  }
  for (final code in [null, CodeRanges.of(scanMarkdown(source))]) {
    final actual = parseComposerLinks(
      source,
      codeRanges: code,
      enableLinkify: enableLinkify,
      linkifyTlds: linkifyTlds,
    );
    expect(
      [
        for (final link in actual)
          (
            link.start,
            link.end,
            (
              source: link.source,
              anchor: link.anchor,
              url: link.url,
              kind: link.kind,
            ),
          ),
      ],
      blocks,
      reason: source,
    );
    for (final link in actual) {
      expect(source.substring(link.start, link.end), link.source);
    }
  }
}
