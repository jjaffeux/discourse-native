import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/shell/composer/components/code_source.dart';
import 'package:discourse_native/src/shell/composer/components/details.dart';
import 'package:discourse_native/src/shell/composer/components/details_source.dart';
import 'package:discourse_native/src/shell/composer/components/gallery_source.dart';
import 'package:discourse_native/src/shell/composer/components/image.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/components/link.dart';
import 'package:discourse_native/src/shell/composer/components/table.dart';
import 'package:discourse_native/src/shell/composer/components/table_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/html_comments.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _witnesses = [
  '<!--\n| A | B |\n| --- | --- |\n| x | y |\n-->',
  '<!--\n[details=secret]\nbody\n[/details]\n-->',
  '[code]\n![hidden](upload://a.png)\n[/code]',
];

Future<void> _pump(WidgetTester tester, String source) async {
  final composer = ComposerController(
    const ReplyComposerTarget(
      privateMessageTopic: false,
      siteUrl: 'https://example.test',
      topicId: 1,
      slug: 'topic',
      topicTitle: 'Topic',
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    composer.dispose();
  });
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          width: 760,
          height: 600,
          child: ComposerEditor(
            composer: composer,
            hintText: 'Reply',
            textStyle: const TextStyle(fontSize: 16, height: 1.5),
            hintStyle: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final (index, type) in [
    (0, ComposerTableEditor),
    (1, ComposerDetailsEditor),
    (2, ComposerImagePreview),
  ]) {
    testWidgets(
      'literal container audit witness $index stays editable source',
      (tester) async {
        await _pump(tester, _witnesses[index]);
        expect(find.byType(type), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  const image = '![photo](https://example.test/a.png)';
  const video = '![clip|video](upload://a.mp4)';
  const table = '| A | B |\n| --- | --- |\n| x | y |';
  const details = '[details=summary]\nbody\n[/details]';
  const gallery = '[grid]\n$image\n[/grid]';
  const link = '[label](https://example.test/path)';
  const code = '```dart\nprint(1);\n```';
  final hidden = [
    image,
    video,
    table,
    details,
    gallery,
    link,
    'https://example.test/bare',
    code,
  ].join('\n\n');
  for (final newline in ['\n', '\r\n']) {
    for (final wrapper in [
      '<!--\n$hidden\n-->',
      '[CODE=python]\n$hidden\n[/CODE]',
    ]) {
      test(
        'core parsers exclude literal source and keep active offsets $newline $wrapper',
        () {
          final source =
              '$wrapper\n\n$image\n\n$video\n\n$table\n\n$details\n\n$gallery\n\n$link\n\n$code'
                  .replaceAll('\n', newline);
          final activeStart = wrapper.replaceAll('\n', newline).length;
          final rawCode = markdownCodeRanges(source);
          final images = parseComposerImages(source, codeRanges: rawCode);
          expect(images, hasLength(2));
          expect(
            parseComposerVideos(source, codeRanges: rawCode),
            hasLength(1),
          );
          final tables = parseComposerTables(source);
          expect(tables, hasLength(1));
          expect(tables.single.cell(1, 0), 'x');
          expect(parseComposerDetails(source), hasLength(1));
          expect(
            parseComposerImageGalleries(source, codeRanges: rawCode),
            hasLength(1),
          );
          expect(parseComposerLinks(source, codeRanges: rawCode), hasLength(1));
          expect(parseComposerCodeBlocks(source), hasLength(1));
          final ranges = [
            ...images.map((block) => (block.start, block.end, block.source)),
            ...parseComposerVideos(
              source,
            ).map((block) => (block.start, block.end, block.source)),
            ...tables.map((block) => (block.start, block.end, block.source)),
            ...parseComposerDetails(
              source,
            ).map((block) => (block.start, block.end, block.source)),
            ...parseComposerImageGalleries(
              source,
            ).map((block) => (block.start, block.end, block.source)),
            ...parseComposerLinks(
              source,
            ).map((block) => (block.start, block.end, block.source)),
            ...parseComposerCodeBlocks(
              source,
            ).map((block) => (block.start, block.end, block.source)),
          ];
          for (final (start, end, raw) in ranges) {
            expect(start, greaterThan(activeStart));
            expect(source.substring(start, end), raw);
          }
        },
      );
    }
  }

  for (final prefix in [
    '<!--\n```\n--> ',
    '[code]\n<!-- unclosed\n[/code]',
    '<!--\n[code]\n-->',
    '`<!--`',
    r' \``',
    '```\n<!--\n```',
    '    <!--',
    '- ```\n  <!--\n  ```',
  ]) {
    test('literal delimiters preserve following active image: $prefix', () {
      final source = '$prefix\n\n$image';
      final block = parseComposerImages(
        source,
        codeRanges: markdownCodeRanges(source),
      ).single;
      expect(block.start, source.lastIndexOf(image));
      expect(block.source, image);
    });
  }

  test(
    'inline BBCode uses its first closer and unclosed code stays ordinary',
    () {
      const source = 'prose [code]$image[/code] $image\n\n[code]\n$image';
      expect(parseComposerImages(source).map((block) => block.start), [
        source.indexOf(image, source.indexOf('[/code]')),
        source.lastIndexOf(image),
      ]);
    },
  );

  for (final (context, prefix, continuation, suffix) in [
    ('plain', 'prose\n    ', '', '\n'),
    ('list', '- prose\n      ', '  ', '\n\n'),
    ('quote', '> prose\n>     ', '> ', '\n\n'),
  ]) {
    for (final (name, literal) in [
      ('multiline comment', '<!--\n![hidden](https://example.test/a.png)\n-->'),
      ('same-line comment', '<!-- ![hidden](https://example.test/a.png) -->'),
      ('inline BBCode', '[code]![hidden](https://example.test/a.png)[/code]'),
      (
        'multiline BBCode',
        '[code]\n![hidden](https://example.test/a.png)\n[/code]',
      ),
    ]) {
      test(
        'four-space paragraph continuation in $context owns $name inline',
        () async {
          const active = '![active](https://example.test/b.png)';
          final source =
              '$prefix${literal.replaceAll('\n', '\n$continuation')}$suffix$active';
          final service = OfflineCookingService();
          addTearDown(service.dispose);
          final result = await service.cook(
            CookingRequest(
              raw: source,
              snapshot: CookingSnapshot(
                siteId: 'test-site',
                accountId: 'test-account',
              ),
            ),
          );
          expect(result.failure, isNull);
          expect(result.html, isNot(contains('alt="hidden"')));
          expect(result.html, contains('alt="active"'));
          final images = parseComposerImages(source);
          expect(images.map((block) => block.alt), ['active']);
          expect(images.single.start, source.indexOf(active));
          expect(images.single.source, active);
          final containers = ComposerLiteralContainers(source);
          expect(containers.contains(prefix.length), isTrue);
          expect(containers.containsBlock(prefix.length), isFalse);
        },
      );
    }
  }

  for (final (name, literal) in [
    ('unclosed comment', '<!--'),
    ('paragraph-limited BBCode', '[code]\n'),
  ]) {
    test('four-space paragraph continuation keeps $name literal', () async {
      const active = '![active](https://example.test/b.png)';
      final source =
          'prose\n    $literal\n\n$active${name == 'paragraph-limited BBCode' ? '\n[/code]' : ''}';
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final result = await service.cook(
        CookingRequest(
          raw: source,
          snapshot: CookingSnapshot(
            siteId: 'test-site',
            accountId: 'test-account',
          ),
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('alt="active"'));
      final block = parseComposerImages(source).single;
      expect(block.start, source.indexOf(active));
      expect(block.source, active);
      expect(
        ComposerLiteralContainers(source).contains(source.indexOf(literal)),
        isFalse,
      );
    });
  }

  test(
    'four-space paragraph continuation BBCode takes its first closer',
    () async {
      const active = '![active](https://example.test/b.png)';
      const source =
          'prose\n    [code]![hidden](https://example.test/a.png)[/code] $active[/code]';
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final result = await service.cook(
        CookingRequest(
          raw: source,
          snapshot: CookingSnapshot(
            siteId: 'test-site',
            accountId: 'test-account',
          ),
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, isNot(contains('alt="hidden"')));
      expect(result.html, contains('alt="active"'));
      final images = parseComposerImages(source);
      expect(images.map((block) => block.alt), ['active']);
      final block = images.single;
      expect(block.start, source.indexOf(active));
      expect(block.source, active);
    },
  );

  for (final (name, prefix, indentation, tail) in [
    ('document start', '', '    ', '\n'),
    ('blank line', 'prose\n\n', '    ', '\n'),
    ('new list', 'prose\n', '-     ', '\n\n'),
    ('new quote', 'prose\n', '>     ', '\n\n'),
    ('quote separator', '> prose\n>\n', '>     ', '\n\n'),
    ('heading', '# Heading\n', '    ', '\n'),
    ('thematic break', '---\n', '    ', '\n'),
    ('spaced star break', '* * *\n', '    ', '\n'),
    ('spaced dash break', '- - -\n', '    ', '\n'),
    ('closed fence', '```\ncode\n```\n', '    ', '\n'),
    ('closed comment', '<!-- closed -->\n', '    ', '\n'),
    ('closed BBCode', '[code]code[/code]\n', '    ', '\n'),
  ]) {
    test(
      'four-space paragraph continuation preserves code after $name',
      () async {
        const active = '![active](https://example.test/b.png)';
        final source = '$prefix$indentation<!--$tail$active\n-->';
        final service = OfflineCookingService();
        addTearDown(service.dispose);
        final result = await service.cook(
          CookingRequest(
            raw: source,
            snapshot: CookingSnapshot(
              siteId: 'test-site',
              accountId: 'test-account',
            ),
          ),
        );
        expect(result.failure, isNull);
        expect(result.html, contains('<pre><code>&lt;!--'));
        expect(result.html, contains('alt="active"'));
        final images = parseComposerImages(source);
        expect(images.map((block) => block.alt), ['active']);
        expect(images.single.start, source.indexOf(active));
        expect(images.single.source, active);
      },
    );
  }

  test('rejected inline comments preserve the later paragraph image', () {
    const active = '![active](https://example.test/b.png)';
    final source = '${'text <!--\n' * 2000}\n-->\n\n$active';
    final block = parseComposerImages(source).single;
    expect(block.start, source.indexOf(active));
    expect(block.source, active);
  });

  test('table edits preserve original inline comment and inline code cells', () {
    const source =
        '| `code` <!-- | hidden --> | B |\r\n| --- | --- | --- |\r\n| x | y |';
    final block = parseComposerTables(source).single;
    expect(block.columnCount, 3);
    expect(block.cell(0, 0), '`code` <!--');
    expect(
      block.editCell(1, 0, 'changed'),
      source.replaceFirst('| x |', '| changed |'),
    );
  });

  test('hidden fences tables and details remain partially editable', () {
    for (final (source, formatter) in [
      ('<!--\n$table\n-->', const ComposerTableInputFormatter()),
      ('<!--\n$details\n-->', const ComposerDetailsInputFormatter()),
      ('[code]\n$code\n[/code]', const ComposerCodeInputFormatter()),
    ]) {
      final at = source.indexOf('\n') + 2;
      final old = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: at),
      );
      final next = TextEditingValue(
        text: source.replaceRange(at, at, 'edit'),
        selection: TextSelection.collapsed(offset: at + 4),
      );
      expect(formatter.formatEditUpdate(old, next), next);
    }
  });

  test('mask preserves UTF16 length CRLF and original offsets', () {
    const source = '😀<!--\r\nsecret\r\n-->\r\n[code]<!--[/code] tail';
    final ranges = ComposerLiteralContainers(source);
    final masked = ranges.mask(source);
    expect(masked.length, source.length);
    expect(masked.split('\r\n').length, source.split('\r\n').length);
    expect(masked.substring(0, 2), '😀');
    expect(masked.endsWith(' tail'), isTrue);
    expect(ranges.contains(source.indexOf('secret')), isTrue);
    expect(ranges.contains(source.length - 1), isFalse);
    expect(
      ComposerHtmlComments(source).mask(source),
      contains('[code]<!--[/code]'),
    );
  });

  for (final header in ['| A | B <!--', '| A | B [code]']) {
    test('inline containers cannot claim active table rows $header', () {
      final source = '$header\n| --- | --- |\n| x | y |\n--> | z |';
      final block = parseComposerTables(source).single;
      expect(block.columnCount, 2);
      expect(block.rowCount, 2);
      expect(block.source, source);
      expect(
        block.editCell(1, 0, 'edited'),
        source.replaceFirst('| x |', '| edited |'),
      );
    });
  }

  for (final codeSource in [
    '    $image',
    '\t$image',
    '- Parent\n\n      $image',
  ]) {
    test('indented code excludes projected images: $codeSource', () {
      expect(
        parseComposerImages(
          '$codeSource\n\n$image',
        ).map((block) => block.start),
        [codeSource.length + 2],
      );
    });
  }

  for (final prefix in [
    '> [code]\n> $image\n> [/code]',
    '> <!--\n> $image\n> -->',
    '> ```\n> <!--\n> ```',
    '- [code]\n  $image\n  [/code]',
    '- <!--\n  $image\n  -->',
    'prose [code]\n$image\n[/code]',
    '[CODE]\n[code]\n$image\n[/code]\n$image\n[/CODE]',
  ]) {
    test('nested literal contexts preserve active image $prefix', () {
      final source = '$prefix\n\n$image';
      expect(parseComposerImages(source).map((block) => block.start), [
        source.lastIndexOf(image),
      ]);
    });
  }

  test(
    'cooker grammar agrees for complete inline nested and unclosed code',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      for (final (source, projected, marker) in [
        ('prose [code]$image[/code]  ', 0, '<code>![photo]'),
        ('[code=python]\n$image\n[/code]', 0, '<pre><code'),
        ('[CODE]\n[code]\n$image\n[/code]\n$image\n[/CODE]', 0, '<pre><code'),
        ('[code]\n$image', 1, '<img '),
        ('[code]\n$image\n[code]\n$image\n[/code]', 1, '<img '),
        ('prose [code]\n\n$image\n[/code]', 1, '<img '),
        ('> [code]\n> $image\n> [/code]', 0, '<pre><code'),
        ('- [code]\n  $image\n  [/code]', 0, '<pre><code'),
      ]) {
        final result = await service.cook(
          CookingRequest(
            raw: source,
            snapshot: CookingSnapshot(
              siteId: 'test-site',
              accountId: 'test-account',
            ),
          ),
        );
        expect(result.failure, isNull);
        expect(result.html, contains(marker), reason: source);
        expect(
          parseComposerImages(source),
          hasLength(projected),
          reason: source,
        );
      }
    },
  );

  test(
    'incomplete outer code preserves active prose and complete inner code',
    () {
      const source = '[code]\n$image\n[code]\n$image\n[/code]';
      expect(parseComposerImages(source).map((block) => block.start), [
        source.indexOf(image),
      ]);
      final repeated = '${'[code]\n' * 2000}$image\n[/code]\n\n$image';
      expect(parseComposerImages(repeated).map((block) => block.start), [
        repeated.lastIndexOf(image),
      ]);
    },
  );

  test(
    'active outer image and link tokens retain original inner syntax',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      for (final source in [
        'x <!-- ![broken -->$image',
        'x [code]![broken[/code]$image',
        '![caption <!-- hidden -->](https://example.test/a.png)',
        '![caption](https://example.test/a[code]b[/code].png)',
        '![caption](https://example.test/a<!--b-->.png)',
        '[label <!-- hidden -->](https://example.test/path)',
        'x <!-- [broken -->$link',
        'x [code][broken[/code]$link',
      ]) {
        final result = await service.cook(
          CookingRequest(
            raw: source,
            snapshot: CookingSnapshot(
              siteId: 'test-site',
              accountId: 'test-account',
            ),
          ),
        );
        expect(result.failure, isNull);
        final isImage = source.contains('![');
        expect(
          result.html,
          contains(isImage ? '<img ' : '<a '),
          reason: source,
        );
        if (isImage) {
          final images = parseComposerImages(source);
          expect(images, hasLength(1), reason: source);
          final block = images.single;
          expect(source.substring(block.start, block.end), block.source);
          expect(block.start, source.lastIndexOf('!['));
        } else {
          final links = parseComposerLinks(source);
          expect(links, hasLength(1), reason: source);
          final block = links.single;
          expect(source.substring(block.start, block.end), block.source);
        }
      }
    },
  );

  for (final (name, outer, closer, outerImages, outerLinks) in [
    (
      'image destination comment',
      '![caption](https://example.test/a<!--.png)',
      '-->',
      1,
      0,
    ),
    (
      'link destination comment',
      '[caption](https://example.test/a<!--)',
      '-->',
      0,
      1,
    ),
    (
      'image destination BBCode',
      '![caption](https://example.test/a[code].png)',
      '[/code]',
      1,
      0,
    ),
    (
      'link destination BBCode',
      '[caption](https://example.test/a[code])',
      '[/code]',
      0,
      1,
    ),
    (
      'image label BBCode',
      '![caption [code]](https://example.test/a.png)',
      '[/code]',
      0,
      0,
    ),
    (
      'link label BBCode',
      '[caption [code]](https://example.test/a)',
      '[/code]',
      0,
      1,
    ),
  ]) {
    test('token boundary preserves later active image: $name', () {
      const active = '![active](https://example.test/b.png)';
      final source = '$outer\n$active\n$closer';
      final images = parseComposerImages(source);
      expect(images.map((block) => block.start), [
        if (outerImages > 0) 0,
        source.indexOf(active),
      ]);
      expect(images.last.source, active);
      expect(
        parseComposerLinks(source, enableLinkify: false),
        hasLength(outerLinks),
      );
    });
  }

  for (final outer in [
    '[caption <!-- [ -->](https://example.test/a<!--)',
    '[caption <!-- ](fake) -->](https://example.test/a<!--)',
    '![caption <!-- [ -->](https://example.test/a[code].png)',
    '![caption <!-- ](fake) -->](https://example.test/a[code].png)',
  ]) {
    test('closed label comment cannot poison token boundary: $outer', () {
      const active = '![active](https://example.test/b.png)';
      final source = '$outer\n$active\n[/code] -->';
      final block = parseComposerImages(source).last;
      expect(block.start, source.indexOf(active));
      expect(block.source, active);
    });
  }

  test(
    'indented fence-like source preserves a following active image',
    () async {
      const source = '\t```\n$image';
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final result = await service.cook(
        CookingRequest(
          raw: source,
          snapshot: CookingSnapshot(
            siteId: 'test-site',
            accountId: 'test-account',
          ),
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('<pre><code>```'));
      expect(result.html, contains('<img '));
      final block = parseComposerImages(
        source,
        codeRanges: markdownCodeRanges(source),
      ).single;
      expect(block.start, source.indexOf(image));
      expect(block.source, image);
    },
  );

  test('fenced fake labels cannot poison later raw token boundaries', () {
    const active = '![active](https://example.test/b.png)';
    const source =
        '```text\n[bogus <!-- ](https://example.test/fake)\n```\n'
        '![caption](https://example.test/a[code].png)\n$active\n[/code]';
    final block = parseComposerImages(source).last;
    expect(block.start, source.indexOf(active));
    expect(block.source, active);
  });

  for (final outer in [
    '![caption <!--](https://example.test/a.png)',
    '[caption <!--](https://example.test/a)',
  ]) {
    test('cross-label HTML comment retains later image ownership: $outer', () {
      const active = '![active](https://example.test/b.png)';
      final source = '$outer\n$active\n-->';
      expect(
        parseComposerImages(source).map((block) => block.start),
        isNot(contains(source.indexOf(active))),
      );
      expect(parseComposerLinks(source, enableLinkify: false), isEmpty);
    });
  }

  test(
    'actual cooker hides comments and renders BBCode code literally',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      for (final (index, source) in _witnesses.indexed) {
        final result = await service.cook(
          CookingRequest(
            raw: source,
            snapshot: CookingSnapshot(
              siteId: 'test-site',
              accountId: 'test-account',
            ),
          ),
        );
        expect(result.failure, isNull);
        if (index < 2) {
          expect(result.html.trim(), isEmpty);
        } else {
          expect(result.html, contains('<pre><code'));
          expect(result.html, contains('![hidden](upload://a.png)'));
          expect(result.html, isNot(contains('<img')));
        }
      }
    },
  );
}
