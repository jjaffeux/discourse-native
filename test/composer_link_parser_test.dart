import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

typedef _ExpectedLink = ({
  String source,
  String anchor,
  String url,
  ComposerLinkKind kind,
});

void main() {
  group('composer link parser behavior', () {
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
  });

  group('composer link parser scaling', () {
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
