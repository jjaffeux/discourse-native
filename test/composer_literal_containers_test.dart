import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/shell/composer/components/details.dart';
import 'package:discourse_native/src/shell/composer/components/image.dart';
import 'package:discourse_native/src/shell/composer/components/table.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/shell/composer/components/code_source.dart';
import 'package:discourse_native/src/shell/composer/components/details_source.dart';
import 'package:discourse_native/src/shell/composer/components/gallery_source.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/components/link.dart';
import 'package:discourse_native/src/shell/composer/components/table_source.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
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
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SizedBox(width: 760, height: 600,
      child: ComposerEditor(composer: composer, hintText: 'Reply',
        textStyle: const TextStyle(fontSize: 16, height: 1.5), hintStyle: null),
    )),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final (index, type) in [
    (0, ComposerTableEditor),
    (1, ComposerDetailsEditor),
    (2, ComposerImagePreview),
  ]) {
    testWidgets('literal container audit witness $index stays editable source', (tester) async {
      await _pump(tester, _witnesses[index]);
      expect(find.byType(type), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  const image = '![photo](https://example.test/a.png)';
  const video = '![clip|video](upload://a.mp4)';
  const table = '| A | B |\n| --- | --- |\n| x | y |';
  const details = '[details=summary]\nbody\n[/details]';
  const gallery = '[grid]\n$image\n[/grid]';
  const link = '[label](https://example.test/path)';
  const code = '```dart\nprint(1);\n```';
  final hidden = [image, video, table, details, gallery, link, 'https://example.test/bare', code].join('\n\n');
  for (final newline in ['\n', '\r\n']) {
    for (final wrapper in ['<!--\n$hidden\n-->', '[CODE=python]\n$hidden\n[/CODE]']) {
      test('core parsers exclude literal source and keep active offsets $newline $wrapper', () {
        final source = '$wrapper\n\n$image\n\n$video\n\n$table\n\n$details\n\n$gallery\n\n$link\n\n$code'.replaceAll('\n', newline);
        final activeStart = wrapper.replaceAll('\n', newline).length;
        final rawCode = markdownCodeRanges(source);
        final images = parseComposerImages(source, codeRanges: rawCode);
        expect(images, hasLength(2));
        expect(parseComposerVideos(source, codeRanges: rawCode), hasLength(1));
        final tables = parseComposerTables(source);
        expect(tables, hasLength(1));
        expect(tables.single.cell(1, 0), 'x');
        expect(parseComposerDetails(source), hasLength(1));
        expect(parseComposerImageGalleries(source, codeRanges: rawCode), hasLength(1));
        expect(parseComposerLinks(source, codeRanges: rawCode), hasLength(1));
        expect(parseComposerCodeBlocks(source), hasLength(1));
        for (final block in <dynamic>[
          ...images, ...parseComposerVideos(source), ...tables,
          ...parseComposerDetails(source), ...parseComposerImageGalleries(source),
          ...parseComposerLinks(source), ...parseComposerCodeBlocks(source),
        ]) {
          expect(block.start as int, greaterThan(activeStart));
          expect(source.substring(block.start as int, block.end as int), block.source);
        }
      });
    }
  }

  for (final prefix in [
    '<!--\n```\n--> ',
    '[code]\n<!-- unclosed\n[/code]',
    '<!--\n[code]\n-->',
    '`<!--`',
    '```\n<!--\n```',
    '    <!--',
    '- ```\n  <!--\n  ```',
  ]) {
    test('literal delimiters preserve following active image: $prefix', () {
      final source = '$prefix\n\n$image';
      final block = parseComposerImages(source, codeRanges: markdownCodeRanges(source)).single;
      expect(block.start, source.lastIndexOf(image));
      expect(block.source, image);
    });
  }

  test('inline BBCode uses its first closer and unclosed code stays ordinary', () {
    final source = 'prose [code]$image[/code] $image\n\n[code]\n$image';
    expect(parseComposerImages(source).map((block) => block.start), [source.indexOf(image, source.indexOf('[/code]')), source.lastIndexOf(image)]);
  });

  test('table edits preserve original inline comment and inline code cells', () {
    const source = '| `code` <!-- | hidden --> | B |\r\n| --- | --- |\r\n| x | y |';
    final block = parseComposerTables(source).single;
    expect(block.columnCount, 2);
    expect(block.cell(0, 0), '`code` <!-- | hidden -->');
    expect(block.editCell(1, 0, 'changed'), source.replaceFirst('| x |', '| changed |'));
  });

  test('hidden fences tables and details remain partially editable', () {
    for (final (source, formatter) in [
      ('<!--\n$table\n-->', const ComposerTableInputFormatter()),
      ('<!--\n$details\n-->', const ComposerDetailsInputFormatter()),
      ('[code]\n$code\n[/code]', const ComposerCodeInputFormatter()),
    ]) {
      final at = source.indexOf('\n') + 2;
      final old = TextEditingValue(text: source, selection: TextSelection.collapsed(offset: at));
      final next = TextEditingValue(text: source.replaceRange(at, at, 'edit'), selection: TextSelection.collapsed(offset: at + 4));
      expect(formatter.formatEditUpdate(old, next), next);
    }
  });

  test('actual cooker hides comments and renders BBCode code literally', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    for (final (index, source) in _witnesses.indexed) {
      final result = await service.cook(CookingRequest(
        raw: source,
        snapshot: CookingSnapshot(siteId: 'test-site', accountId: 'test-account'),
      ));
      expect(result.failure, isNull);
      if (index < 2) {
        expect(result.html.trim(), isEmpty);
      } else {
        expect(result.html, contains('<pre><code'));
        expect(result.html, contains('![hidden](upload://a.png)'));
        expect(result.html, isNot(contains('<img')));
      }
    }
  });
}
