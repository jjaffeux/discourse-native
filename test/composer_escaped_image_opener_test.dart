import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/shell/composer/components/image.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = ReplyComposerTarget(
  privateMessageTopic: false,
  siteUrl: 'https://example.test',
  topicId: 1,
  slug: 'topic',
  topicTitle: 'Topic',
);

void main() {
  test('opener escape parity preserves UTF-16 ranges and later images', () {
    const image = '![photo|40x20, 50%](upload://photo.png)';
    const later = '![later](https://example.test/later.png)';
    for (var slashes = 0; slashes <= 4; slashes++) {
      final source = '😀 ${'\\' * slashes}$image then $later';
      final code = CodeRanges.of(scanMarkdown(source));
      for (final ranges in <CodeRanges?>[null, code, CodeRanges.none]) {
        final images = parseComposerImages(source, codeRanges: ranges);
        expect(images.map((image) => image.url), [
          if (slashes.isEven) 'upload://photo.png',
          'https://example.test/later.png',
        ], reason: '$slashes backslashes');
        expect(images.last.start, source.indexOf(later));
        for (final image in images) {
          expect(source.substring(image.start, image.end), image.source);
        }
        if (slashes.isEven) {
          expect(images.first.start, 3 + slashes);
          expect(images.first.source, image);
          expect(
            (images.first.width, images.first.height, images.first.scale),
            (40, 20, 50),
          );
        }
      }
    }
  });

  test('escaped image text cannot become a gallery member', () {
    final controller = MarkdownEditingController(
      text:
          '[grid]\n'
          r'\![literal](upload://literal.png)'
          '\n![real](upload://real.png)\n[/grid]',
    );
    addTearDown(controller.dispose);
    expect(controller.imageBlocks.map((image) => image.url), [
      'upload://real.png',
    ]);
    expect(controller.galleryBlocks, isEmpty);
    controller.text = '[grid]\n![real](upload://real.png)\n[/grid]';
    expect(
      controller.galleryBlocks.single.images.single.url,
      'upload://real.png',
    );
  });

  test('real cooker renders escaped opener as bang and text link', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    const source = r'\![literal](https://example.test/a.png)';
    final cooked = await service.cook(
      CookingRequest(
        raw: source,
        snapshot: CookingSnapshot(siteId: 'test', accountId: 'test'),
      ),
    );
    expect(cooked.failure, isNull);
    expect(
      cooked.html,
      '<p>!<a href="https://example.test/a.png">literal</a></p>',
    );
    expect(parseComposerImages(source), isEmpty);
  });

  for (final slashes in [0, 1, 2, 3, 4]) {
    testWidgets('editor projects image only with even slash count $slashes', (
      tester,
    ) async {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      final source = '${'\\' * slashes}![photo](upload://photo.png)';
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
      expect(
        find.byType(ComposerImagePreview),
        slashes.isEven ? findsOneWidget : findsNothing,
      );
      expect(composer.text.text, source);
    });
  }
}
