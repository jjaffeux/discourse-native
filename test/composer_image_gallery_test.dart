import 'dart:ui' as ui;

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
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  group('gallery preview layout', () {
    testWidgets('uses large square tiles beside options', (tester) async {
      final gallery = parseComposerImageGalleries(_source).single;
      final keys = [for (var i = 0; i < 3; i++) GlobalKey()];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ComposerImageGalleryPreview(
              gallery: gallery,
              items: [
                for (final (index, image) in gallery.images.indexed)
                  ComposerImageGalleryItem(
                    image: image,
                    url: null,
                    imageKey: keys[index],
                    highlighted: false,
                  ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(ComposerImageGalleryTile), findsNWidgets(3));
      expect(find.byType(ComposerImageGalleryControl), findsOneWidget);
      expect(find.byType(DButton), findsOneWidget);

      for (final tile in find.byType(ComposerImageGalleryTile).evaluate()) {
        final size = tester.getSize(find.byWidget(tile.widget));
        expect(size.aspectRatio, 1);
        expect(size.shortestSide, greaterThanOrEqualTo(80));
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
        expect(tileRect.center.dy, controlRect.center.dy);
      }
    });

    testWidgets('matches the rendered grid column rules', (tester) async {
      for (final (imageCount, expectedColumns, expectedRows) in [
        (4, 2, 2),
        (7, 3, 3),
      ]) {
        final gallery = parseComposerImageGalleries(
          _gallerySource(imageCount),
        ).single;
        final keys = [for (var i = 0; i < imageCount; i++) GlobalKey()];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ComposerImageGalleryPreview(
                gallery: gallery,
                items: [
                  for (final (index, image) in gallery.images.indexed)
                    ComposerImageGalleryItem(
                      image: image,
                      url: null,
                      imageKey: keys[index],
                      highlighted: false,
                    ),
                ],
              ),
            ),
          ),
        );

        final rects = [for (final key in keys) tester.getRect(find.byKey(key))];
        expect(
          rects.map((rect) => rect.left).toSet(),
          hasLength(expectedColumns),
        );
        expect(rects.map((rect) => rect.top).toSet(), hasLength(expectedRows));
        expect(
          tester.getSize(find.byType(ComposerImageGalleryPreview)).height,
          ComposerImageGalleryPreview.displayHeight(imageCount),
        );
      }
    });

    testWidgets('keeps carousel images on one scrollable row', (tester) async {
      final gallery = parseComposerImageGalleries(
        _gallerySource(7, mode: ComposerGalleryMode.carousel),
      ).single;
      final keys = [for (var i = 0; i < 7; i++) GlobalKey()];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ComposerImageGalleryPreview(
                gallery: gallery,
                items: [
                  for (final (index, image) in gallery.images.indexed)
                    ComposerImageGalleryItem(
                      image: image,
                      url: null,
                      imageKey: keys[index],
                      highlighted: false,
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final rects = [for (final key in keys) tester.getRect(find.byKey(key))];
      expect(rects.map((rect) => rect.top).toSet(), hasLength(1));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(
        tester.getSize(find.byType(ComposerImageGalleryPreview)).height,
        ComposerImageGalleryPreview.displayHeight(
          7,
          mode: ComposerGalleryMode.carousel,
        ),
      );
    });

    testWidgets('keeps the selected border inside its paint bounds', (
      tester,
    ) async {
      final gallery = parseComposerImageGalleries(_source).single;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ComposerImageGalleryPreview(
              gallery: gallery,
              highlighted: true,
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
      );

      final preview = find.byType(ComposerImageGalleryPreview);
      final size = tester.getSize(preview);
      final middle = size.height / 2;
      expect(
        preview,
        paints
          ..path(color: const Color(0x00000000))
          ..path(
            includes: [Offset(2, middle), Offset(size.width - 2, middle)],
            excludes: [Offset(0.5, middle), Offset(size.width - 0.5, middle)],
            color: Theme.of(tester.element(preview)).colorScheme.primary,
            strokeWidth: 2.5,
            style: PaintingStyle.stroke,
          ),
      );
    });

    testWidgets('uses cover-sized artwork', (tester) async {
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

    testWidgets('fits a 280-pixel composer without overflow', (tester) async {
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
      expect(
        tester.getSize(find.byType(ComposerImageGalleryPreview)).width,
        280,
      );
      expect(find.byType(ComposerImageGalleryTile), findsNWidgets(3));
      expect(find.byType(DButton), findsOneWidget);
      expect(
        tester.getSize(find.byType(ComposerImageGalleryControl)).height,
        ComposerImageGalleryControl.extent,
      );
      final tiles = find.byType(ComposerImageGalleryTile);
      expect(
        tester.getTopLeft(tiles.at(0)).dy,
        tester.getTopLeft(tiles.at(1)).dy,
      );
      expect(
        tester.getTopLeft(tiles.at(2)).dy,
        greaterThan(tester.getTopLeft(tiles.at(0)).dy),
      );
    });
  });

  group('gallery accessibility', () {
    testWidgets('describes the gallery, selected image, and options control', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final gallery = parseComposerImageGalleries(_source).single;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ComposerImageGalleryPreview(
                gallery: gallery,
                onEdit: () {},
                items: [
                  for (final (index, image) in gallery.images.indexed)
                    ComposerImageGalleryItem(
                      image: image,
                      url: null,
                      imageKey: GlobalKey(),
                      highlighted: index == 1,
                    ),
                ],
              ),
            ),
          ),
        );

        expect(
          tester.getSemantics(find.bySemanticsLabel('Image gallery, 3 images')),
          isSemantics(
            label: 'Image gallery, 3 images',
            hasSelectedState: true,
            isSelected: false,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('First image')),
          isSemantics(
            label: 'First image',
            isImage: true,
            hasSelectedState: true,
            isSelected: false,
          ),
        );
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
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('activates gallery options with Enter and Space', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final gallery = parseComposerImageGalleries(_source).single;
        var edits = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ComposerImageGalleryPreview(
                gallery: gallery,
                onEdit: () => edits++,
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
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Gallery options')),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(edits, 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(edits, 2);
      } finally {
        semantics.dispose();
      }
    });
  });

  group('gallery editor projection', () {
    testWidgets('preserves raw source offsets and editable scroll height', (
      tester,
    ) async {
      final controller = MarkdownEditingController(text: _source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              final style = Theme.of(context).textTheme.bodyMedium!;
              return Scaffold(
                body: SizedBox(
                  width: 600,
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    style: style,
                    strutStyle: StrutStyle.fromTextStyle(
                      style,
                      forceStrutHeight: false,
                    ),
                  ),
                ),
              );
            },
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
    });

    testWidgets('keeps the trailing caret next to a scaled long gallery', (
      tester,
    ) async {
      final source = [
        '[grid]',
        for (var index = 0; index < 10; index++)
          '![Image $index](upload://image$index)',
        '[/grid]',
      ].join('\n');
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      composer.text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
      addTearDown(composer.dispose);
      final editorLayout = ValueNotifier((width: 280.0, scale: 1.0));
      addTearDown(editorLayout.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<({double scale, double width})>(
                valueListenable: editorLayout,
                builder: (context, layout, _) => SizedBox(
                  width: layout.width,
                  height: 600,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: ComposerEditor(
                      composer: composer,
                      hintText: '',
                      textStyle: Theme.of(context).textTheme.bodyMedium,
                      hintStyle: Theme.of(context).textTheme.bodyMedium,
                      enableDropTarget: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      editorLayout.value = (width: 600, scale: 1.5);
      await tester.pumpAndSettle();

      final gallery = composer.text.galleryBlocks.single;
      final galleryRect = tester.getRect(
        find.byType(ComposerImageGalleryPreview),
      );
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: gallery.end),
      );
      final globalCaret = caret.shift(render.localToGlobal(Offset.zero));

      expect(globalCaret.top - galleryRect.bottom, inInclusiveRange(-8, 32));
      expect(
        render.getPositionForPoint(render.localToGlobal(caret.center)).offset,
        gallery.end,
      );
      expect(render.plainText.length, source.length);

      final editableRect = tester.getRect(find.byType(EditableText));
      final belowGallery = Offset(
        galleryRect.left + 24,
        editableRect.bottom - 24,
      );
      expect(
        tester.getRect(find.byType(EditableText)).contains(belowGallery),
        isTrue,
      );
      expect(
        composer.text.collapsedGalleryAtGlobalPosition(belowGallery),
        isNull,
      );

      await tester.tapAt(belowGallery);
      await tester.pump();
      await tester.pump();

      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: gallery.end),
      );
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(_composerEditable(tester).showCursor, isTrue);
    });

    testWidgets('refreshes a cached gallery projection after reassemble', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1450, 1110);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final source = _gallerySource(10);
      composer.text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
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

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: ComposerPanel(composer: composer, height: 555),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gallery = composer.text.galleryBlocks.single;
      final galleryRect = tester.getRect(
        find.byType(ComposerImageGalleryPreview),
      );
      final editable = find.byType(EditableText);
      final render = tester.state<EditableTextState>(editable).renderEditable;
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: gallery.end),
      );
      final globalCaret = caret.shift(render.localToGlobal(Offset.zero));
      expect(globalCaret.top - galleryRect.bottom, inInclusiveRange(-8, 32));

      final context = tester.element(editable);
      final style = tester.widget<EditableText>(editable).style;
      final before = composer.text.buildTextSpan(
        context: context,
        style: style,
        withComposing: true,
      );

      final reassemble = tester.binding.reassembleApplication();
      await tester.pump();
      await reassemble;

      final after = composer.text.buildTextSpan(
        context: tester.element(editable),
        style: tester.widget<EditableText>(editable).style,
        withComposing: true,
      );
      expect(after, isNot(same(before)));

      final belowGallery = Offset(
        galleryRect.left + 24,
        tester.getRect(editable).bottom - 24,
      );
      await tester.tapAt(belowGallery);
      await tester.pump();
      await tester.pump();

      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: gallery.end),
      );
      final caretAfterTap = render.getLocalRectForCaret(
        TextPosition(offset: gallery.end),
      );
      final globalCaretAfterTap = caretAfterTap.shift(
        render.localToGlobal(Offset.zero),
      );
      expect(
        globalCaretAfterTap.top - galleryRect.bottom,
        inInclusiveRange(-8, 32),
      );
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
    });

    testWidgets('keeps wrapped rows scrollable in a narrow editor', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      composer.text.text = _gallerySource(7);
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                height: 180,
                child: ComposerEditor(
                  composer: composer,
                  hintText: '',
                  textStyle: const TextStyle(fontSize: 14),
                  hintStyle: const TextStyle(fontSize: 14),
                  autofocus: false,
                  enableDropTarget: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = find.byType(ComposerImageGalleryPreview);
      expect(
        tester.getSize(preview).height,
        ComposerImageGalleryPreview.displayHeight(7, gridColumns: 2),
      );
      final scrollable = find.descendant(
        of: find.byType(EditableText),
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollable);
      expect(
        scrollState.position.maxScrollExtent,
        greaterThanOrEqualTo(tester.getSize(preview).height - 180),
      );
      scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
      await tester.pump();

      final gallery = composer.text.galleryBlocks.single;
      final galleryRect = composer.text.collapsedGalleryGlobalRect(gallery)!;
      final lastImageRect = composer.text.collapsedImageGlobalRect(
        gallery.images.last,
      )!;
      expect(galleryRect.contains(lastImageRect.center), isTrue);
      expect(
        tester
            .getRect(find.byType(EditableText))
            .contains(lastImageRect.center),
        isTrue,
      );
      expect(
        composer.text.collapsedImageAtGlobalPosition(lastImageRect.center),
        same(gallery.images.last),
      );
    });

    testWidgets('paints a gallery at the same scroll rate as text', (
      tester,
    ) async {
      const galleryColor = Color(0xFFFF00FF);
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      composer.text.text = [
        for (var index = 0; index < 8; index++) 'Before $index',
        _gallerySource(3),
        for (var index = 0; index < 20; index++) 'After $index',
      ].join('\n');
      addTearDown(composer.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 180);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            colorScheme: ThemeData.dark().colorScheme.copyWith(
              surfaceContainerLow: galleryColor,
            ),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('composer-paint-boundary'),
              child: ComposerEditor(
                composer: composer,
                hintText: '',
                textStyle: const TextStyle(fontSize: 14, height: 1),
                hintStyle: const TextStyle(fontSize: 14, height: 1),
                autofocus: false,
                enableDropTarget: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byType(EditableText),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(0);
      await tester.pump();

      final gallery = composer.text.galleryBlocks.single;
      final geometryBeforeScroll = composer.text.collapsedGalleryGlobalRect(
        gallery,
      )!;
      final paintedBeforeScroll = await _paintedColorBounds(
        tester,
        galleryColor,
      );
      const scrollDelta = 40.0;
      position.jumpTo(scrollDelta);
      await tester.pump();
      final paintedAfterScroll = await _paintedColorBounds(
        tester,
        galleryColor,
      );
      final geometryAfterScroll = composer.text.collapsedGalleryGlobalRect(
        gallery,
      )!;

      expect(position.pixels, scrollDelta);
      expect(
        paintedAfterScroll.top,
        closeTo(paintedBeforeScroll.top - scrollDelta, 1),
      );
      expect(
        geometryAfterScroll.top,
        closeTo(geometryBeforeScroll.top - scrollDelta, 0.01),
      );
    });

    testWidgets('maps gallery, image, and control positions to source blocks', (
      tester,
    ) async {
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
    });

    testWidgets(
      'highlights a keyboard-selected child without revealing source',
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

        final gallery = controller.galleryBlocks.single;
        final selected = gallery.images[1];
        controller.selection = TextSelection.collapsed(offset: selected.end);
        controller.selectPillForKeyboard(selected);
        await tester.pump();

        expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
        final preview = tester.widget<ComposerImageGalleryPreview>(
          find.byType(ComposerImageGalleryPreview),
        );
        expect(preview.items.map((item) => item.highlighted), [
          false,
          true,
          false,
        ]);
        expect(controller.keyboardSelectedImage, same(selected));
        expect(controller.isImageCollapsed(selected), isTrue);
      },
    );

    testWidgets(
      'retains gallery and tile elements when text changes after it',
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

    testWidgets('never reveals source for selections crossing the gallery', (
      tester,
    ) async {
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

      final gallery = controller.galleryBlocks.single;
      for (final selection in [
        TextSelection.collapsed(offset: gallery.contentStart),
        TextSelection(baseOffset: 0, extentOffset: gallery.contentStart),
        TextSelection(baseOffset: 0, extentOffset: gallery.end + 1),
        TextSelection(
          baseOffset: gallery.end + 1,
          extentOffset: gallery.contentStart,
        ),
      ]) {
        controller.selection = selection;
        await tester.pump();

        expect(
          find.byType(ComposerImageGalleryPreview),
          findsOneWidget,
          reason: 'selection $selection exposed the gallery Markdown',
        );
        expect(find.byType(ComposerImagePreview), findsNothing);
        expect(controller.isGalleryCollapsed(gallery), isTrue);
      }
    });

    testWidgets('a pointer edit cannot reveal gallery source', (tester) async {
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

      final gallery = controller.galleryBlocks.single;
      controller.keepGalleryCollapsedForPointerEdit(gallery);
      controller.selection = TextSelection.collapsed(
        offset: gallery.contentStart,
      );
      await tester.pump();
      expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);

      controller.releaseGalleryPointerEdit(gallery);
      await tester.pump();
      expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
    });

    testWidgets('keeps an empty gallery as an editable options target', (
      tester,
    ) async {
      const source = '[grid]\n[/grid]';
      final controller = MarkdownEditingController(text: source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      expect(controller.galleryBlocks.single.images, isEmpty);
      expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
      expect(find.byType(ComposerImageGalleryTile), findsNothing);
      expect(find.byType(ComposerImageGalleryControl), findsOneWidget);
      expect(find.byType(DButton), findsOneWidget);
      expect(
        tester.getSize(find.byType(ComposerImageGalleryControl)).height,
        ComposerImageGalleryControl.extent,
      );
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(editable.renderEditable.plainText.length, source.length);
    });

    testWidgets('gallery options toggle while keeping the caret outside', (
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
      expect(
        composer.text.collapsedImageAtGlobalPosition(controlCenter),
        isNull,
      );
      expect(
        composer.text.collapsedGalleryAtGlobalPosition(controlCenter),
        same(gallery),
      );

      await tester.tapAt(controlCenter);
      await tester.pump();
      await tester.pump();

      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: gallery.end),
      );
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
      expect(_composerEditable(tester).showCursor, isFalse);

      await tester.tapAt(controlCenter);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(
        tester
            .widget<ComposerImageGalleryPreview>(
              find.byType(ComposerImageGalleryPreview),
            )
            .highlighted,
        isFalse,
      );
      expect(_composerEditable(tester).showCursor, isTrue);

      await tester.tapAt(controlCenter);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(_composerEditable(tester).showCursor, isFalse);

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(composer.text.selection.extentOffset, gallery.start);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(_composerEditable(tester).showCursor, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.selection.extentOffset, gallery.end);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(_composerEditable(tester).showCursor, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.selection.extentOffset, gallery.end);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(_composerEditable(tester).showCursor, isTrue);
    });

    testWidgets('vertical arrows leave a selected gallery', (tester) async {
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
      composer.text.text = _source;

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

      final gallery = composer.text.galleryBlocks.single;
      final controlCenter = _paintedGalleryControlCenter(tester, composer);
      for (final (key, expectedOffset) in [
        (LogicalKeyboardKey.arrowUp, gallery.start),
        (LogicalKeyboardKey.arrowDown, gallery.end),
      ]) {
        await tester.tapAt(controlCenter);
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('composer-gallery-toolbar')),
          findsOneWidget,
        );

        composer.focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pump();

        expect(
          composer.text.selection,
          TextSelection.collapsed(offset: expectedOffset),
        );
        expect(
          find.byKey(const ValueKey('composer-gallery-toolbar')),
          findsNothing,
        );
        expect(_composerEditable(tester).showCursor, isTrue);
      }
    });

    testWidgets('Backspace deletes a selected gallery', (tester) async {
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
      const source = 'Before\n$_source';
      composer.text.text = source;

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

      final gallery = composer.text.galleryBlocks.single;
      await tester.tapAt(_paintedGalleryControlCenter(tester, composer));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(
        composer.text.text,
        source.replaceRange(gallery.start, gallery.end, ''),
      );
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: gallery.start),
      );
      expect(composer.text.galleryBlocks, isEmpty);
      expect(composer.text.imageBlocks, isEmpty);
      expect(find.byType(ComposerImageGalleryPreview), findsNothing);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(_composerEditable(tester).showCursor, isTrue);
    });

    testWidgets('selects a gallery when a vertical arrow enters it', (
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
      const source = 'Before\n$_source';
      composer.text.text = source;

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

      final gallery = composer.text.galleryBlocks.single;
      composer.focus.requestFocus();
      for (final (caret, key) in [
        (gallery.start, LogicalKeyboardKey.arrowDown),
        (gallery.end, LogicalKeyboardKey.arrowUp),
      ]) {
        composer.text.selection = TextSelection.collapsed(offset: caret);
        await tester.pump();

        await tester.sendKeyEvent(key);
        await tester.pump();

        expect(composer.text.text, source);
        expect(
          composer.text.selection,
          TextSelection.collapsed(offset: gallery.end),
        );
        expect(composer.text.isGalleryCollapsed(gallery), isTrue);
        expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
        expect(
          find.byKey(const ValueKey('composer-gallery-toolbar')),
          findsOneWidget,
        );
        expect(_composerEditable(tester).showCursor, isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
      }
    });
  });

  group('gallery reordering', () {
    testWidgets('requests the dragged image and destination index', (
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
  });
}

Future<Rect> _paintedColorBounds(WidgetTester tester, Color color) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('composer-paint-boundary')),
  );
  final capture = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final result = (
      width: image.width,
      height: image.height,
      bytes: await image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    image.dispose();
    return result;
  });
  final (:width, :height, :bytes) = capture!;
  if (bytes == null) fail('Could not read the rendered composer pixels.');
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xFF;
  final green = (argb >> 8) & 0xFF;
  final blue = argb & 0xFF;
  final alpha = (argb >> 24) & 0xFF;

  var left = width;
  var top = height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (bytes.getUint8(offset) != red ||
          bytes.getUint8(offset + 1) != green ||
          bytes.getUint8(offset + 2) != blue ||
          bytes.getUint8(offset + 3) != alpha) {
        continue;
      }
      left = x < left ? x : left;
      top = y < top ? y : top;
      right = x > right ? x : right;
      bottom = y > bottom ? y : bottom;
    }
  }
  if (right < 0) fail('The gallery paint color was not rendered.');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (right + 1).toDouble(),
    (bottom + 1).toDouble(),
  );
}

Offset _paintedGalleryControlCenter(
  WidgetTester tester,
  ComposerController composer,
) {
  final gallery = composer.text.galleryBlocks.single;
  final paintedGallery = composer.text.collapsedGalleryGlobalRect(gallery)!;
  final laidOutGallery = tester.getRect(
    find.byType(ComposerImageGalleryPreview),
  );
  return tester.getCenter(find.byType(ComposerImageGalleryControl)) +
      paintedGallery.topLeft -
      laidOutGallery.topLeft;
}

EditableText _composerEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller is MarkdownEditingController,
        ),
      ),
    );

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'gallery-topic',
  topicTitle: 'Gallery topic',
);

String _gallerySource(
  int imageCount, {
  ComposerGalleryMode mode = ComposerGalleryMode.grid,
}) {
  final opening = switch (mode) {
    ComposerGalleryMode.grid => '[grid]',
    ComposerGalleryMode.carousel => '[grid mode=carousel]',
  };
  final images = [
    for (var index = 0; index < imageCount; index++)
      '![Image ${index + 1}](upload://image-${index + 1})',
  ].join('\n');
  return '$opening\n$images\n[/grid]';
}
