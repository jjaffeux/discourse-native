import 'dart:async';

import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'before\n![A photo|640x480, 75%](upload://abc)\nafter';

ComposerImageBlock _image({
  required int width,
  required int height,
  int? scale,
}) => ComposerImageBlock(
  start: 0,
  end: 1,
  source: 'x',
  alt: 'image',
  url: 'https://images.test/image.png',
  width: width,
  height: height,
  scale: scale,
);

void main() {
  group('preview sizing', () {
    test('fits declared dimensions within the preview bounds', () {
      expect(
        ComposerImagePreview.displaySize(_image(width: 320, height: 180)),
        const Size(320, 180),
      );
      expect(
        ComposerImagePreview.displaySize(_image(width: 920, height: 380)),
        const Size(460, 190),
      );
      expect(
        ComposerImagePreview.displaySize(_image(width: 1, height: 9999)),
        const Size(1, 4),
      );
      final wide = ComposerImagePreview.displaySize(
        _image(width: 9999, height: 1),
      );
      expect(wide.width, 460);
      expect(wide.height, closeTo(115, 0.000000001));
    });

    test('applies a valid percentage after fitting the image', () {
      expect(
        ComposerImagePreview.displaySize(
          _image(width: 640, height: 480, scale: 75),
        ),
        const Size(190, 142.5),
      );
    });

    test('ignores percentages outside the supported range', () {
      for (final scale in [0, 101, 999]) {
        expect(
          ComposerImagePreview.displaySize(
            _image(width: 320, height: 180, scale: scale),
          ),
          const Size(320, 180),
          reason: 'scale $scale should not affect layout',
        );
      }
    });

    test('uses safe fallback geometry for invalid dimensions', () {
      final fallback = ComposerImagePreview.displaySize(
        _image(width: 0, height: 0),
      );

      expect(fallback.width, closeTo(337.77777777777777, 0.000000001));
      expect(fallback.height, 190);
      expect(
        ComposerImagePreview.displaySize(_image(width: 1 << 2000, height: 1)),
        fallback,
      );
    });
  });

  group('preview decode policy', () {
    testWidgets('bounds raster decoding when dimensions are declared', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final image = parseComposerImages(
        '![known|640x480](https://images.test/known.png)',
      ).single;
      late ImageProvider<Object> provider;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              provider = composerPreviewImageProvider(
                context,
                url: image.url,
                logicalSize: ComposerImagePreview.displaySize(image),
                measureNaturalSize: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      final resized = provider as ResizeImage;
      final network = resized.imageProvider as NetworkImage;
      expect(network.url, 'https://images.test/known.png');
      expect(network.scale, 1);
      expect(resized.width, 507);
      expect(resized.height, 380);
      expect(resized.policy, ResizeImagePolicy.fit);
      expect(resized.allowUpscaling, isFalse);
    });

    testWidgets('preserves intrinsic measurement when dimensions are absent', (
      tester,
    ) async {
      final image = parseComposerImages(
        '![unknown](https://images.test/unknown.png)',
      ).single;
      late ImageProvider<Object> provider;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              provider = composerPreviewImageProvider(
                context,
                url: image.url,
                logicalSize: ComposerImagePreview.displaySize(image),
                measureNaturalSize: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      final network = provider as NetworkImage;
      expect(network.url, 'https://images.test/unknown.png');
      expect(network.scale, 1);
    });
  });

  group('editor image projection', () {
    testWidgets('renders an unresolved upload as an exact bounded fallback', (
      tester,
    ) async {
      final resolution = Completer<Map<String, String>>();
      final requests = <Set<String>>[];
      final controller = MarkdownEditingController(
        text: _source,
        resolveUploadUrls: (urls) {
          requests.add(Set.unmodifiable(urls));
          return resolution.future;
        },
      );
      addTearDown(() {
        if (!resolution.isCompleted) resolution.complete(const {});
        controller.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      expect(requests, [
        const {'upload://abc'},
      ]);
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      expect(find.text('A photo'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ComposerImagePreview)),
        const Size(190, 150.5),
      );

      resolution.complete(const {});
      await tester.pump();
      expect(requests, [
        const {'upload://abc'},
      ]);
    });

    testWidgets('preserves raw offsets while the image is collapsed', (
      tester,
    ) async {
      final controller = MarkdownEditingController(text: _source);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(controller.text, _source);
      expect(editable.renderEditable.plainText.length, _source.length);

      final projected = controller.imageBlocks.single;
      expect(controller.isImageCollapsed(projected), isTrue);
      expect(
        controller.collapsedImageAtOffset(projected.start + 1),
        same(projected),
      );
      expect(
        controller.collapsedImageAtOffset(projected.end - 1),
        same(projected),
      );
      expect(controller.collapsedImageAtOffset(projected.start), isNull);
      expect(controller.collapsedImageAtOffset(projected.end), isNull);
    });

    testWidgets('passes the target site to the preview and image loader', (
      tester,
    ) async {
      const siteUrl = 'https://meta.discourse.org';
      const imageUrl = '$siteUrl/secure-uploads/image.png';
      final controller = MarkdownEditingController(
        text: '![secure|640x480]($imageUrl)',
        imageSiteUrl: siteUrl,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );

      final preview = tester.widget<ComposerImagePreview>(
        find.byType(ComposerImagePreview),
      );
      expect(preview.url, imageUrl);
      expect(preview.siteUrl, siteUrl);

      final artwork = tester.widget<SiteImage>(find.byType(SiteImage));
      expect(artwork.url, imageUrl);
      expect(artwork.siteUrl, siteUrl);
      expect(artwork.excludeFromSemantics, isTrue);
    });

    testWidgets('reveals raw source only while the caret is inside the image', (
      tester,
    ) async {
      final controller = MarkdownEditingController(text: _source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TextField(controller: controller, maxLines: null),
          ),
        ),
      );
      final image = controller.imageBlocks.single;
      expect(find.byType(ComposerImagePreview), findsOneWidget);

      controller.selection = TextSelection.collapsed(offset: image.start + 4);
      await tester.pump();

      expect(find.byType(ComposerImagePreview), findsNothing);
      expect(controller.isImageCollapsed(image), isFalse);
      expect(controller.text, _source);

      controller.selection = TextSelection.collapsed(offset: image.start);
      await tester.pump();
      expect(find.byType(ComposerImagePreview), findsOneWidget);

      controller.selection = TextSelection.collapsed(offset: image.end);
      await tester.pump();
      expect(find.byType(ComposerImagePreview), findsOneWidget);
    });
  });

  group('short URL resolution', () {
    testWidgets('does not duplicate pending or failed lookups across frames', (
      tester,
    ) async {
      final failure = Completer<Map<String, String>>();
      final requests = <Set<String>>[];
      final controller = MarkdownEditingController(
        text: _source,
        resolveUploadUrls: (urls) {
          requests.add(Set.unmodifiable(urls));
          return failure.future;
        },
      );
      addTearDown(() {
        if (!failure.isCompleted) failure.complete(const {});
        controller.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );

      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
      }
      expect(requests, [
        const {'upload://abc'},
      ]);

      failure.completeError(StateError('offline'));
      await tester.pump();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
      }
      expect(requests, [
        const {'upload://abc'},
      ]);
    });

    testWidgets('retries a transport failure and caches the later success', (
      tester,
    ) async {
      final completions = <Completer<Map<String, String>>>[];
      final requests = <Set<String>>[];
      final controller = MarkdownEditingController(
        text: _source,
        resolveUploadUrls: (urls) {
          requests.add(Set.unmodifiable(urls));
          final completion = Completer<Map<String, String>>();
          completions.add(completion);
          return completion.future;
        },
      );
      addTearDown(() {
        for (final completion in completions) {
          if (!completion.isCompleted) completion.complete(const {});
        }
        controller.dispose();
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(SizedBox));
      const style = TextStyle(fontSize: 15);

      controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: false,
      );
      expect(requests, [
        const {'upload://abc'},
      ]);

      completions.single.completeError(StateError('offline'));
      await tester.pump();
      controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: false,
      );
      expect(requests, [
        const {'upload://abc'},
        const {'upload://abc'},
      ]);

      completions.last.complete(const {
        'upload://abc': 'https://cdn.example/abc.png',
      });
      await tester.pump();

      final image = controller.imageBlocks.single;
      expect(controller.resolvedImageUrl(image), 'https://cdn.example/abc.png');
      controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: false,
      );
      expect(requests, [
        const {'upload://abc'},
        const {'upload://abc'},
      ]);
    });
  });

  group('preview semantics and selection', () {
    testWidgets('exposes one selected image named by its alt text', (
      tester,
    ) async {
      final image = parseComposerImages(
        '![A diagram](upload://pending)',
      ).single;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ComposerImagePreview(
                image: image,
                url: null,
                highlighted: true,
                onNaturalSize: (_) {},
              ),
            ),
          ),
        );

        expect(find.text('A diagram'), findsOneWidget);
        final target = find.bySemanticsLabel('A diagram');
        expect(target, findsOneWidget);
        expect(
          tester.getSemantics(target),
          isSemantics(
            label: 'A diagram',
            isImage: true,
            hasSelectedState: true,
            isSelected: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('paints the selected border above the preview surface', (
      tester,
    ) async {
      final image = parseComposerImages(
        '![A diagram](upload://pending)',
      ).single;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ComposerImagePreview(
              image: image,
              url: null,
              highlighted: true,
              onNaturalSize: (_) {},
            ),
          ),
        ),
      );

      final previewContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(ComposerImagePreview),
          matching: find.byType(Container),
        ),
      );
      final background = previewContainer.decoration! as BoxDecoration;
      final foreground =
          previewContainer.foregroundDecoration! as BoxDecoration;
      final border = foreground.border! as Border;

      expect(previewContainer.clipBehavior, Clip.antiAlias);
      expect(previewContainer.padding, const EdgeInsets.all(2));
      expect(background.border, isNull);
      expect(foreground.borderRadius, background.borderRadius);
      expect(previewContainer.padding, border.dimensions);
      for (final side in [
        border.top,
        border.right,
        border.bottom,
        border.left,
      ]) {
        expect(side.color, AppTheme.light.colorScheme.primary);
        expect(side.width, 2);
        expect(side.strokeAlign, BorderSide.strokeAlignInside);
      }
    });

    testWidgets('keeps preview geometry stable when selection changes', (
      tester,
    ) async {
      final image = parseComposerImages(
        '![A diagram](upload://pending)',
      ).single;
      var highlighted = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ComposerImagePreview(
                  image: image,
                  url: null,
                  highlighted: highlighted,
                  onNaturalSize: (_) {},
                );
              },
            ),
          ),
        ),
      );

      final preview = find.byType(ComposerImagePreview);
      final container = find.descendant(
        of: preview,
        matching: find.byType(Container),
      );
      Container previewContainer() => tester.widget<Container>(container);
      Border previewBorder() =>
          (previewContainer().foregroundDecoration! as BoxDecoration).border!
              as Border;

      final idleSize = tester.getSize(container);
      final idlePadding = previewContainer().padding;
      final idleFallbackRect = tester.getRect(find.text('A diagram'));
      expect(idlePadding, const EdgeInsets.all(2));
      expect(previewBorder().top.width, 1);

      update(() => highlighted = true);
      await tester.pump();

      expect(tester.getSize(container), idleSize);
      expect(previewContainer().padding, idlePadding);
      expect(tester.getRect(find.text('A diagram')), idleFallbackRect);
      expect(previewBorder().top.width, 2);
    });
  });
}
