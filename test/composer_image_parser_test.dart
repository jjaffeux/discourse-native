import 'dart:math';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import 'support/scaling_benchmark.dart';

void main() {
  group('composer image parser behavior', () {
    test('keeps a balanced destination and its exact token range', () {
      const token = '![photo|640x480, 75%](https://example.test/photo_(1).png)';
      const source = '😀 before $token).png) after';
      final image = parseComposerImages(source).single;
      expect(image.url, 'https://example.test/photo_(1).png');
      expect(image.source, token);
      expect(image.start, source.indexOf('!['));
      expect(image.end, source.indexOf('![') + token.length);
      expect((image.width, image.height, image.scale), (640, 480, 75));
    });

    test(
      'matches actual cooker destination grammar and decoded URLs',
      () async {
        final cooker = OfflineCookingService();
        addTearDown(cooker.dispose);
        const cases = <(String, String)>[
          (
            r'![x](https://example.test/photo_(1).png)',
            'https://example.test/photo_(1).png',
          ),
          (
            r'![x](https://example.test/photo_\(1\).png)',
            'https://example.test/photo_(1).png',
          ),
          (
            r'![x](https://example.test/photo_(1).png "title")',
            'https://example.test/photo_(1).png',
          ),
          (
            "![x](https://example.test/photo_(1).png 'title')",
            'https://example.test/photo_(1).png',
          ),
          (
            r'![x](https://example.test/photo_(1).png (title))',
            'https://example.test/photo_(1).png',
          ),
          (r'![x](https://example.test/a )', 'https://example.test/a'),
          (r'![x](https://example.test/a "title" )', 'https://example.test/a'),
          ('![x]( \t\nhttps://example.test/a)', 'https://example.test/a'),
          (
            r'![x](<https://example.test/photo_(1).png>)',
            'https://example.test/photo_(1).png',
          ),
          (r'![x](https://example.test/a\))', 'https://example.test/a)'),
          (r'![x](https://example.test/a "ti\"tle")', 'https://example.test/a'),
          (r'![x](https://example.test/a "ti)tle")', 'https://example.test/a'),
          (
            r'![x](https://example.test/a?a=1&amp;b=2)',
            'https://example.test/a?a=1&b=2',
          ),
          (
            r'![x](https://example.test/a\&amp;b)',
            'https://example.test/a&amp;b',
          ),
        ];
        for (final (raw, url) in cases) {
          final cooked = await cooker.cook(
            CookingRequest(
              raw: raw,
              snapshot: CookingSnapshot(
                siteId: 'destination',
                accountId: 'destination',
              ),
            ),
          );
          expect(cooked.failure, isNull, reason: raw);
          final cookedImage = html
              .parseFragment(cooked.html)
              .querySelector('img');
          expect(cookedImage?.attributes['src'], url, reason: raw);
          final image = parseComposerImages('😀 $raw tail').single;
          expect(image.url, url, reason: raw);
          expect(image.source, raw, reason: raw);
          expect((image.start, image.end), (3, 3 + raw.length), reason: raw);
        }
      },
    );

    test('uses cooker numeric entity validation and HTML fallback', () async {
      final cooker = OfflineCookingService();
      addTearDown(cooker.dispose);
      for (final (entity, decoded) in const [
        ('&#128;', '&#128;'),
        ('&#000000128;', '€'),
        ('&#x00000080;', '&#x00000080;'),
        ('&#x000000080;', '€'),
        ('&#000000000;', '\ufffd'),
        ('&#x110000;', '&#x110000;'),
        ('&#128x;', '&#128x;'),
        ('&#x20acx;', '&#x20acx;'),
        ('&#9999999999999999999999999999999;', '\ufffd'),
        ('&#xfffffffffffffffffffffffffff;', '\ufffd'),
      ]) {
        final raw = '![x](https://example.test/a$entity.png)';
        final expected = 'https://example.test/a$decoded.png';
        final cooked = await cooker.cook(
          CookingRequest(
            raw: raw,
            snapshot: CookingSnapshot(
              siteId: 'destination',
              accountId: 'destination',
            ),
          ),
        );
        expect(cooked.failure, isNull, reason: raw);
        final cookedUrl = html
            .parseFragment(cooked.html)
            .querySelector('img')!
            .attributes['src']!;
        expect(Uri.decodeFull(cookedUrl), expected, reason: raw);
        expect(parseComposerImages(raw).single.url, expected, reason: raw);
      }
    });

    test('requires a real outer terminator and recovers later images', () {
      for (final malformed in const [
        '![x](https://example.test/a(b)',
        '![x](https://example.test/a(b',
        '![x](https://example.test/a "title"',
        '![x](https://example.test/a "unfinished',
        '![x](https://example.test/a (nested(title)))',
        '![x](https://example.test/a "title" trailing)',
        '![x](<https://example.test/a)',
        '![x](<https://example.test/a>trailing)',
        '![x](<https://example.test/a\nb>)',
      ]) {
        expect(parseComposerImages(malformed), isEmpty, reason: malformed);
        final images = parseComposerImages('$malformed\n![later](upload://ok)');
        expect(images.map((image) => image.url), [
          'upload://ok',
        ], reason: malformed);
      }
    });

    test(
      'blank lines terminate destinations while later images recover',
      () async {
        final cooker = OfflineCookingService();
        addTearDown(cooker.dispose);
        const later = '![later](https://example.test/later.png)';
        for (final newline in ['\n', '\r\n', '\r']) {
          final blank = '$newline \t$newline';
          for (final raw in [
            '![x](${blank}https://example.test/a)',
            '![x](https://example.test/a$blank)',
            '![x](https://example.test/a "title${blank}continues")',
          ]) {
            for (final source in [raw, '$raw$blank$later']) {
              final expected = source.endsWith(later)
                  ? ['https://example.test/later.png']
                  : <String>[];
              final cooked = await cooker.cook(
                CookingRequest(
                  raw: source,
                  snapshot: CookingSnapshot(
                    siteId: 'destination',
                    accountId: 'destination',
                  ),
                ),
              );
              expect(cooked.failure, isNull, reason: source);
              expect(
                html
                    .parseFragment(cooked.html)
                    .querySelectorAll('img')
                    .map((image) => image.attributes['src']),
                expected,
                reason: source,
              );
              final images = parseComposerImages(source);
              expect(
                images.map((image) => image.url),
                expected,
                reason: source,
              );
              if (images.isNotEmpty) expect(images.single.source, later);
            }
          }
        }
      },
    );

    test('uses the cooker nesting limit without truncating deeper input', () {
      for (final depth in [32, 33]) {
        final raw = '![x](https://example.test/${'(' * depth}a${')' * depth})';
        final images = parseComposerImages(raw);
        expect(images.length, depth == 32 ? 1 : 0);
        if (images.isNotEmpty) expect(images.single.source, raw);
      }
    });

    test('edited images retain escaped destination punctuation', () {
      for (final raw in const [
        r'![x](https://example.test/a\).png)',
        r'![x](https://example.test/a\(b.png)',
        r'![x](https://example.test/a\\b.png)',
        r'![x](https://example.test/photo_(1).png "title")',
        r'![x](https://example.test/a?a=1&amp;b=2)',
        r'![x](https://example.test/a\&amp;b)',
        r'![x](<https://example.test/a b.png>)',
        '![x]( \n<https://example.test/a_(b).png> "Title" \n)',
      ]) {
        final image = parseComposerImages(raw).single;
        final edited = parseComposerImages(
          image.toMarkdown(alt: 'edited', width: 20, height: 10),
        ).single;
        expect(edited.url, image.url, reason: raw);
        expect((edited.alt, edited.width, edited.height), ('edited', 20, 10));
        expect(
          edited.source.substring(edited.source.indexOf('](') + 2),
          raw.substring(raw.indexOf('](') + 2),
        );
      }
    });

    test('preserves accepted URLs, titles, dimensions, and UTF-16 offsets', () {
      const source =
          '😀 before ![café \\[🐱\\]|0640x0480, 75%|extra](UPLOAD://abc "a title") '
          'then ![](HTTP://example.test/a("b)) '
          '![remote](hTtPs://example.test/路径 "title\nwith a newline") '
          '![zero|0x20, 0%](upload://zero) '
          '![large|9999x9999, 100%](upload://large) '
          '![bad scale|1x2, 101%](upload://scale) after';
      final images = parseComposerImages(source);
      expect(
        [
          for (final image in images)
            (image.alt, image.url, image.width, image.height, image.scale),
        ],
        [
          ('café [🐱]', 'UPLOAD://abc', 640, 480, 75),
          ('', 'HTTP://example.test/a("b)', null, null, null),
          ('remote', 'hTtPs://example.test/路径', null, null, null),
          ('zero', 'upload://zero', null, null, null),
          ('large', 'upload://large', 9999, 9999, 100),
          ('bad scale', 'upload://scale', 1, 2, null),
        ],
      );
      expect(images.first.start, source.indexOf('!['));
      for (final image in images) {
        expect(source.substring(image.start, image.end), image.source);
      }
    });

    test('recovers images after invalid labels, destinations, and titles', () {
      const sources = [
        '![missing ![same closer](bogus) ![after](upload://ok)',
        r'![missing ![escaped\](bogus) ![same alt](upload://ok)',
        '![broken](bogus![inside](upload://ok))',
        '![broken](https://a "unfinished ![inside](upload://ok)',
        '![broken](https://a![inside](upload://ok))',
        '![empty](https://) ![after](upload://ok)',
        '![broken\\\n![after](upload://ok)',
        '![broken\\\r![after](upload://ok)',
        '![broken\\\u2028![after](upload://ok)',
        '![broken\\\u2029![after](upload://ok)',
        '![bad\n![after](upload://ok)',
        r'![outer \![inner](upload://ok)',
        r'![even\\](upload://ok) ![odd\] alt](upload://two)',
      ];
      for (final source in sources) {
        expect(parseComposerImages(source), isNotEmpty, reason: source);
      }
    });

    test('rejects unsupported schemes and malformed image syntax', () {
      for (final source in const [
        '![x](https://)',
        '![x](upload://)',
        '![x](ftp://example.test/a)',
        '![x] (https://example.test/a)',
        r'![x\](upload://a)',
        '![x\n](upload://a)',
        '![x\ralt](upload://a)',
        '![x\u2028alt](upload://a)',
        '![x\u2029alt](upload://a)',
      ]) {
        expect(parseComposerImages(source), isEmpty, reason: source);
      }
    });

    test('excludes whole matches overlapping code before continuing', () {
      const source =
          '`![inline](upload://one)`\n\n'
          '```\n![fenced](upload://two)\n```\n\n'
          '![alt `code` ![nested](upload://four) '
          '![title](upload://five "with `code`") '
          r'![escaped \`code\`](upload://six) '
          '![visible](upload://seven)';
      expect(parseComposerImages(source).map((image) => image.url), [
        'upload://six',
        'upload://seven',
      ]);
    });

    test('retains exact disjoint ranges on generated mixed input', () {
      const pieces = [
        '![',
        '![a',
        '![outer ![inner',
        r'\',
        r'\\',
        r'\]',
        r'\![',
        r'\`',
        '\n',
        '\r',
        '\r\n',
        '\u2028',
        '\u2029',
        '\u00a0',
        '\u2003',
        '\ufeff',
        '\t',
        '\v',
        '\u0085',
        '\u180e',
        ' ',
        '|640x480, 50%',
        '|0x0001, 0%',
        '|99999x2, 999%',
        '|extra',
        '](upload://a)',
        '](https://a "title")',
        '](HTTP://a)',
        '](bogus)',
        '](https://',
        '](UPLOAD://',
        '](https://a "',
        '](https://a ',
        ']',
        ')',
        '"',
        '`',
        '```\n',
        'a😀',
        '![ok](upload://x)',
        '![x](https://a "title\nacross lines")',
        r'![a \[b\] \\ c|1x2, 100%](HTTPS://a)',
      ];
      final random = Random(4815);
      var withImages = 0;
      var withoutImages = 0;
      var withoutOpeners = 0;
      for (var sample = 0; sample < 6000; sample += 1) {
        final source = List.generate(
          1 + random.nextInt(20),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();
        if (_expectImageInvariants(source) > 0) {
          withImages += 1;
        } else {
          withoutImages += 1;
        }
        if (!source.contains('![')) withoutOpeners += 1;
      }
      expect(withImages, greaterThan(1000));
      expect(withoutImages, greaterThan(1000));
      // Sources with no opener skip the scan, and must still agree.
      expect(withoutOpeners, greaterThan(500));
    });
  });

  test('agrees with the legacy oracle for unchanged simple destinations', () {
    const pieces = [
      'plain text ',
      '😀 before ',
      '![one](upload://one)',
      '![two|640x480, 75%](https://example.test/two.png)',
      '![three](HTTP://example.test/three "Title")',
      '`![code](upload://code)`',
      '\n\n```\n![fenced](upload://fenced)\n```\n\n',
    ];
    final random = Random(616);
    for (var sample = 0; sample < 1000; sample++) {
      final source = List.generate(
        1 + random.nextInt(10),
        (_) => pieces[random.nextInt(pieces.length)],
      ).join(' ');
      _expectLegacyUnescapedImages(source);
    }
  });

  group('composer image parser scaling', () {
    for (final suffix in const [
      '](bogus)',
      '](https://example.test/missing-close',
      r'\](bogus)',
    ]) {
      for (final precomputedCode in [false, true]) {
        test(
          'shared failed suffix $suffix (precomputed code: $precomputedCode)',
          () {
            final smallSource = '${'![missing ' * 128}$suffix';
            final largeSource = '${'![missing ' * 1024}$suffix';
            final smallCode = precomputedCode
                ? CodeRanges.of(scanMarkdown(smallSource))
                : null;
            final largeCode = precomputedCode
                ? CodeRanges.of(scanMarkdown(largeSource))
                : null;
            expect(
              parseComposerImages(smallSource, codeRanges: smallCode),
              isEmpty,
            );
            expect(
              parseComposerImages(largeSource, codeRanges: largeCode),
              isEmpty,
            );

            final (:small, :large) = measureScaling(
              () => parseComposerImages(
                smallSource,
                codeRanges: smallCode,
              ).length,
              () => parseComposerImages(
                largeSource,
                codeRanges: largeCode,
              ).length,
            );
            expect(
              large,
              lessThan(small * 25),
              reason:
                  'eight times the input took ${large / small} times as long',
            );
          },
        );
      }
    }

    for (final suffix in [
      ' "${'x' * 20000}',
      " '${'x' * 20000}",
      ' (${'x' * 20000}',
    ]) {
      test(
        'nested destinations share a long failed title tail ${suffix[1]}',
        () {
          final smallSource = '${'![a](https://example.test/' * 128}$suffix';
          final largeSource = '${'![a](https://example.test/' * 1024}$suffix';
          expect(
            parseComposerImages(smallSource, codeRanges: CodeRanges.none),
            isEmpty,
          );
          expect(
            parseComposerImages(largeSource, codeRanges: CodeRanges.none),
            isEmpty,
          );
          final (:small, :large) = measureScaling(
            () => parseComposerImages(
              smallSource,
              codeRanges: CodeRanges.none,
            ).length,
            () => parseComposerImages(
              largeSource,
              codeRanges: CodeRanges.none,
            ).length,
          );
          expect(large, lessThan(small * 25));
        },
      );
    }

    for (final suffix in const ['', ' "unfinished', ' "closed" trailing']) {
      test('nested destinations share their failed boundary: $suffix', () {
        final smallSource = '${'![a](https://example.test/' * 128}$suffix';
        final largeSource = '${'![a](https://example.test/' * 1024}$suffix';
        expect(
          parseComposerImages(smallSource, codeRanges: CodeRanges.none),
          isEmpty,
        );
        expect(
          parseComposerImages(largeSource, codeRanges: CodeRanges.none),
          isEmpty,
        );
        final (:small, :large) = measureScaling(
          () => parseComposerImages(
            smallSource,
            codeRanges: CodeRanges.none,
          ).length,
          () => parseComposerImages(
            largeSource,
            codeRanges: CodeRanges.none,
          ).length,
        );
        expect(large, lessThan(small * 25));
      });
    }
  });
}

typedef _ImageValue = ({
  int start,
  int end,
  String source,
  String alt,
  String url,
  int? width,
  int? height,
  int? scale,
});

_ImageValue _value(ComposerImageBlock image) => (
  start: image.start,
  end: image.end,
  source: image.source,
  alt: image.alt,
  url: image.url,
  width: image.width,
  height: image.height,
  scale: image.scale,
);

int _expectImageInvariants(String source) {
  final images = parseComposerImages(source);
  var previousEnd = 0;
  final code = markdownCodeRanges(source);
  for (final image in images) {
    expect(image.start, greaterThanOrEqualTo(previousEnd));
    expect(image.end, greaterThan(image.start));
    expect(image.end, lessThanOrEqualTo(source.length));
    expect(source.substring(image.start, image.end), image.source);
    expect(code.overlaps(image.start, image.end), isFalse);
    previousEnd = image.end;
  }
  expect(
    parseComposerImages(source, codeRanges: code).map(_value),
    images.map(_value),
  );
  return images.length;
}

int _expectLegacyUnescapedImages(String source) {
  final code = CodeRanges.of(scanMarkdown(source));
  final expected = _legacyUnescapedImages(source, code);
  expect(
    parseComposerImages(source).map(_value),
    expected,
    reason: 'source: ${source.codeUnits}',
  );
  for (final ranges in [code, CodeRanges.none]) {
    expect(
      parseComposerImages(source, codeRanges: ranges).map(_value),
      _legacyUnescapedImages(source, ranges),
      reason: 'source: ${source.codeUnits}; code: ${ranges.ranges.toList()}',
    );
  }
  return expected.length;
}

final _legacyImagePattern = RegExp(
  r'!\[((?:\\.|[^\\\]\n])*)\]\(((?:upload://|https?://)[^)\s]+)(?:\s+"[^"]*")?\)',
  caseSensitive: false,
);
final _legacyLabelPattern = RegExp(
  r'^(.*?)(?:\|(\d{1,4})x(\d{1,4})(?:,\s*(\d{1,3})%)?)?(?:\|.*)?$',
);

List<_ImageValue> _legacyUnescapedImages(String source, CodeRanges code) {
  final images = <_ImageValue>[];
  for (final match in _legacyImagePattern.allMatches(source)) {
    var slashes = 0;
    for (
      var at = match.start - 1;
      at >= 0 && source.codeUnitAt(at) == 0x5c;
      at--
    ) {
      slashes++;
    }
    if (slashes.isOdd || code.overlaps(match.start, match.end)) continue;
    final label = _legacyLabelPattern.firstMatch(match.group(1)!);
    if (label == null) continue;
    final width = int.tryParse(label.group(2) ?? '');
    final height = int.tryParse(label.group(3) ?? '');
    final validDimensions =
        width != null && width > 0 && height != null && height > 0;
    final scale = int.tryParse(label.group(4) ?? '');
    images.add((
      start: match.start,
      end: match.end,
      source: match.group(0)!,
      alt: label
          .group(1)!
          .replaceAllMapped(RegExp(r'\\([\\\[\]`])'), (match) => match[1]!),
      url: match.group(2)!,
      width: validDimensions ? width : null,
      height: validDimensions ? height : null,
      scale: scale != null && scale >= 1 && scale <= 100 ? scale : null,
    ));
  }
  return images;
}
