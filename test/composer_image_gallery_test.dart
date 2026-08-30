import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_image_gallery.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _source =
    '[grid]\n'
    '![First image|400x300](upload://first)\n'
    '![Second image|300x400](upload://second)\n'
    '![Third image](upload://third)\n'
    '[/grid]\n'
    'After';

void main() {
  testWidgets('draws one full-width gallery with options below square tiles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gallery = parseComposerImageGalleries(_source).single;
    final keys = [for (var i = 0; i < 3; i++) GlobalKey()];
    var edits = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ComposerImageGalleryPreview(
            gallery: gallery,
            onEdit: () => edits++,
            items: [
              for (final (index, image) in gallery.images.indexed)
                ComposerImageGalleryItem(
                  image: image,
                  url: null,
                  imageKey: keys[index],
                  highlighted: index == 1,
                ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
    expect(find.byType(ComposerImageGalleryTile), findsNWidgets(3));
    expect(find.byType(ComposerImageGalleryControl), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComposerImageGalleryPreview),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.foregroundPainter != null,
        ),
      ),
      findsOneWidget,
    );

    for (final tile in find.byType(ComposerImageGalleryTile).evaluate()) {
      expect(tester.getSize(find.byWidget(tile.widget)).aspectRatio, 1);
    }

    final galleryRect = tester.getRect(
      find.byType(ComposerImageGalleryPreview),
    );
    expect(galleryRect.width, tester.getSize(find.byType(Scaffold)).width);
    final controlRect = tester.getRect(
      find.byType(ComposerImageGalleryControl),
    );
    expect(controlRect.height, ComposerImageGalleryControl.extent);
    expect(galleryRect.contains(controlRect.center), isTrue);
    for (final key in keys) {
      final tileRect = tester.getRect(find.byKey(key));
      expect(galleryRect.contains(tileRect.topLeft), isTrue);
      expect(galleryRect.contains(tileRect.bottomRight), isTrue);
      expect(tileRect.overlaps(controlRect), isFalse);
      expect(controlRect.top, greaterThan(tileRect.bottom));
    }

    expect(find.bySemanticsLabel('Image gallery, 3 images'), findsOneWidget);
    expect(find.bySemanticsLabel('First image'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Second image')),
      isSemantics(
        label: 'Second image',
        isImage: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Gallery options')),
      isSemantics(
        label: 'Gallery options',
        hint: '3 images. Add or remove images.',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Gallery options')),
      isSemantics(isFocusable: true, isFocused: true),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(edits, 2);
    semantics.dispose();
  });

  testWidgets('gallery artwork uses cover-sized image tiles', (tester) async {
    final gallery = parseComposerImageGalleries(_source).single;
    final image = gallery.images.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComposerImageGalleryPreview(
            gallery: gallery,
            items: [
              ComposerImageGalleryItem(
                image: image,
                url: 'https://example.com/first.png',
                imageKey: GlobalKey(),
                highlighted: false,
              ),
            ],
          ),
        ),
      ),
    );

    final artwork = tester.widget<SiteImage>(find.byType(SiteImage));
    expect(artwork.fit, BoxFit.cover);
    expect(artwork.width, ComposerImageGalleryPreview.tileExtent);
    expect(artwork.height, ComposerImageGalleryPreview.tileExtent);
  });

  testWidgets('fills a narrow composer with options below the tiles', (
    tester,
  ) async {
    final gallery = parseComposerImageGalleries(_source).single;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: ComposerImageGalleryPreview(
                gallery: gallery,
                items: [
                  for (final image in gallery.images)
                    ComposerImageGalleryItem(
                      image: image,
                      url: null,
                      imageKey: GlobalKey(),
                      highlighted: false,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ComposerImageGalleryPreview)).width, 280);
    expect(find.byType(ComposerImageGalleryTile), findsNWidgets(3));
    expect(find.text('Gallery options'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ComposerImageGalleryControl)).height,
      ComposerImageGalleryControl.extent,
    );
  });

  testWidgets(
    'projects a gallery without changing raw offsets or scroll height',
    (tester) async {
      final controller = MarkdownEditingController(text: _source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: TextField(controller: controller, maxLines: null),
            ),
          ),
        ),
      );

      final gallery = controller.galleryBlocks.single;
      final images = gallery.images;
      expect(controller.galleryAtOffset(images[1].start), same(gallery));
      expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
      expect(find.byType(ComposerImagePreview), findsNothing);
      expect(controller.text, _source);

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(editable.renderEditable.plainText.length, _source.length);
      expect(
        tester.getSize(find.byType(EditableText)).height,
        greaterThanOrEqualTo(
          tester.getSize(find.byType(ComposerImageGalleryPreview)).height,
        ),
      );

      final galleryRect = controller.collapsedGalleryGlobalRect(gallery)!;
      expect(
        controller.collapsedGalleryAtGlobalPosition(galleryRect.center),
        same(gallery),
      );
      final controlRect = tester.getRect(
        find.byType(ComposerImageGalleryControl),
      );
      expect(
        controller.collapsedImageAtGlobalPosition(controlRect.center),
        isNull,
      );
      expect(
        controller.collapsedGalleryAtGlobalPosition(controlRect.center),
        same(gallery),
      );
      for (final image in images) {
        expect(controller.isImageCollapsed(image), isTrue);
        final imageRect = controller.collapsedImageGlobalRect(image)!;
        expect(imageRect.size.aspectRatio, 1);
        expect(galleryRect.contains(imageRect.center), isTrue);
        expect(
          controller.collapsedImageAtGlobalPosition(imageRect.center),
          same(image),
        );
      }
    },
  );

  testWidgets('a selected child stays projected and is highlighted', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: _source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );

    final gallery = controller.galleryBlocks.single;
    final selected = gallery.images[1];
    controller.selection = TextSelection.collapsed(offset: selected.end);
    controller.selectPillForKeyboard(selected);
    await tester.pump();

    expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
    final preview = tester.widget<ComposerImageGalleryPreview>(
      find.byType(ComposerImageGalleryPreview),
    );
    expect(preview.items.map((item) => item.highlighted), [false, true, false]);
    expect(controller.keyboardSelectedImage, same(selected));
    expect(controller.isImageCollapsed(selected), isTrue);
  });

  testWidgets(
    'typing after a gallery retains its compound and child elements',
    (tester) async {
      final controller = MarkdownEditingController(text: _source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      final preview = find.byType(ComposerImageGalleryPreview);
      final tiles = find.byType(ComposerImageGalleryTile);
      final previewElement = tester.element(preview);
      final tileElements = tiles.evaluate().toList();

      const edited = '$_source!';
      controller.value = const TextEditingValue(
        text: edited,
        selection: TextSelection.collapsed(offset: edited.length),
      );
      await tester.pump();

      expect(tester.element(preview), same(previewElement));
      final nextTileElements = tiles.evaluate().toList();
      expect(nextTileElements, hasLength(tileElements.length));
      for (var index = 0; index < tileElements.length; index++) {
        expect(nextTileElements[index], same(tileElements[index]));
      }
      for (final image in controller.galleryBlocks.single.images) {
        expect(controller.collapsedImageGlobalRect(image), isNotNull);
      }
    },
  );

  testWidgets('caret editing reveals the whole raw gallery', (tester) async {
    final controller = MarkdownEditingController(text: _source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );

    final gallery = controller.galleryBlocks.single;
    controller.selection = TextSelection.collapsed(
      offset: gallery.contentStart,
    );
    await tester.pump();

    expect(find.byType(ComposerImageGalleryPreview), findsNothing);
    expect(find.byType(ComposerImagePreview), findsNothing);
    expect(controller.isGalleryCollapsed(gallery), isFalse);

    controller.selection = TextSelection.collapsed(offset: gallery.end);
    await tester.pump();
    expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
  });

  testWidgets('pointer editing can hold the compound projection in place', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: _source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );

    final gallery = controller.galleryBlocks.single;
    controller.keepGalleryCollapsedForPointerEdit(gallery);
    controller.selection = TextSelection.collapsed(
      offset: gallery.contentStart,
    );
    await tester.pump();
    expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);

    controller.releaseGalleryPointerEdit(gallery);
    await tester.pump();
    expect(find.byType(ComposerImageGalleryPreview), findsNothing);
  });

  testWidgets('projects an empty gallery as an editable add target', (
    tester,
  ) async {
    const source = '[grid]\n[/grid]';
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );

    expect(controller.galleryBlocks.single.images, isEmpty);
    expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
    expect(find.byType(ComposerImageGalleryTile), findsNothing);
    expect(find.byType(ComposerImageGalleryControl), findsOneWidget);
    expect(find.text('Gallery options'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ComposerImageGalleryControl)).height,
      ComposerImageGalleryControl.extent,
    );
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.renderEditable.plainText.length, source.length);
  });

  testWidgets('the visible control selects the gallery in the composer', (
    tester,
  ) async {
    final composer = ComposerController(
      _target,
      resolveUploadUrls: (_) async => const {},
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await shell.load();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    final source = _source.substring(0, _source.length - '\nAfter'.length);
    composer.text.value = TextEditingValue(
      text: source,
      selection: const TextSelection.collapsed(offset: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final controlCenter = tester.getCenter(
      find.byType(ComposerImageGalleryControl),
    );
    expect(
      tester.getRect(find.byType(EditableText)).contains(controlCenter),
      isTrue,
      reason: 'the gallery control must be inside the editor viewport',
    );
    final gallery = composer.text.galleryBlocks.single;
    expect(composer.text.collapsedImageAtGlobalPosition(controlCenter), isNull);
    expect(
      composer.text.collapsedGalleryAtGlobalPosition(controlCenter),
      same(gallery),
    );

    await tester.tapAt(controlCenter);
    await tester.pump();
    await tester.pump();

    expect(composer.text.selection.extentOffset, gallery.end);
    expect(
      find.byKey(const ValueKey('composer-gallery-toolbar')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ComposerImageGalleryPreview>(
            find.byType(ComposerImageGalleryPreview),
          )
          .highlighted,
      isTrue,
    );
  });

  testWidgets('dragging a tile onto another requests a reorder', (
    tester,
  ) async {
    final gallery = parseComposerImageGalleries(_source).single;
    ComposerImageBlock? moved;
    int? destination;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ComposerImageGalleryPreview(
            gallery: gallery,
            items: [
              for (final image in gallery.images)
                ComposerImageGalleryItem(
                  image: image,
                  url: null,
                  imageKey: GlobalKey(),
                  highlighted: false,
                ),
            ],
            onReorder: (image, newIndex) {
              moved = image;
              destination = newIndex;
            },
          ),
        ),
      ),
    );

    final tiles = find.byType(ComposerImageGalleryTile);
    final first = tester.getCenter(tiles.at(0));
    final last = tester.getCenter(tiles.at(2));
    await tester.dragFrom(first, last - first);
    await tester.pumpAndSettle();

    expect(moved, same(gallery.images.first));
    expect(destination, 2);
  });
}

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'gallery-topic',
  topicTitle: 'Gallery topic',
);
