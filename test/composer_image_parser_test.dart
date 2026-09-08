import 'dart:math';

import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

void main() {
  group('composer image parser behavior', () {
    test('preserves accepted URLs, titles, dimensions, and UTF-16 offsets', () {
      const source =
          '😀 before ![café \\[🐱\\]|0640x0480, 75%|extra](UPLOAD://abc "a title") '
          'then ![](HTTP://example.test/a("b)) '
          '![remote](hTtPs://example.test/路径\u2003"title\nwith a newline") '
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
          ('', 'HTTP://example.test/a("b', null, null, null),
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
      _expectLegacyImages(source);
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
        r'\![escaped opener](upload://ok)',
      ];
      for (final source in sources) {
        expect(parseComposerImages(source), isNotEmpty, reason: source);
        _expectLegacyImages(source);
      }
    });

    test('rejects malformed syntax without adding URL or title syntax', () {
      for (final source in const [
        '![x](https://)',
        '![x](upload://)',
        '![x](ftp://example.test/a)',
        '![x] (https://example.test/a)',
        '![x]( https://example.test/a)',
        '![x](https://example.test/a )',
        "![x](https://example.test/a 'title')",
        '![x](https://example.test/a "title" )',
        r'![x\](upload://a)',
        '![x\n](upload://a)',
        '![x\ralt](upload://a)',
        '![x\u2028alt](upload://a)',
        '![x\u2029alt](upload://a)',
      ]) {
        expect(parseComposerImages(source), isEmpty, reason: source);
        _expectLegacyImages(source);
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
      _expectLegacyImages(source);
    });

    test('agrees with the previous parser on generated mixed input', () {
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
      for (var sample = 0; sample < 6000; sample += 1) {
        final source = List.generate(
          1 + random.nextInt(20),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();
        if (_expectLegacyImages(source) > 0) {
          withImages += 1;
        } else {
          withoutImages += 1;
        }
      }
      expect(withImages, greaterThan(1000));
      expect(withoutImages, greaterThan(1000));
    });
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

int _expectLegacyImages(String source) {
  final code = CodeRanges.of(scanMarkdown(source));
  final expected = _legacyImages(source, code);
  expect(
    parseComposerImages(source).map(_value),
    expected,
    reason: 'source: ${source.codeUnits}',
  );
  for (final ranges in [code, CodeRanges.none]) {
    expect(
      parseComposerImages(source, codeRanges: ranges).map(_value),
      _legacyImages(source, ranges),
      reason: 'source: ${source.codeUnits}; code: ${ranges.ranges.toList()}',
    );
  }
  return expected.length;
}

// Keep the previous syntax as an independent oracle. Generated inputs stay
// short; malformed long-input behavior belongs in the scaling tests above.
final _legacyImagePattern = RegExp(
  r'!\[((?:\\.|[^\\\]\n])*)\]\(((?:upload://|https?://)[^)\s]+)(?:\s+"[^"]*")?\)',
  caseSensitive: false,
);
final _legacyLabelPattern = RegExp(
  r'^(.*?)(?:\|(\d{1,4})x(\d{1,4})(?:,\s*(\d{1,3})%)?)?(?:\|.*)?$',
);

List<_ImageValue> _legacyImages(String source, CodeRanges code) {
  final images = <_ImageValue>[];
  for (final match in _legacyImagePattern.allMatches(source)) {
    if (code.overlaps(match.start, match.end)) continue;
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
