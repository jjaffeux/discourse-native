import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_images.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = 'before\n![A photo|640x480, 75%](upload://abc)\nafter';

  test('keeps supplied preview geometry finite, positive, and bounded', () {
    ComposerImageBlock image({
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

    final unscaled = image(width: 640, height: 480);
    expect(
      ComposerImagePreview.displaySize(
        image(width: 640, height: 480, scale: 999),
      ),
      ComposerImagePreview.displaySize(unscaled),
    );
    expect(
      ComposerImagePreview.displaySize(
        image(width: 640, height: 480, scale: 75),
      ),
      const Size(190, 142.5),
    );
    expect(
      ComposerImagePreview.displaySize(image(width: 1, height: 9999)),
      const Size(1, 4),
    );

    final hostile = [
      image(width: 0, height: 0, scale: 0),
      image(width: 1 << 2000, height: 1, scale: 101),
      image(width: 9999, height: 1),
    ];
    for (final value in hostile) {
      final size = ComposerImagePreview.displaySize(value);
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size.width, inInclusiveRange(0.000001, 460));
      expect(size.height, inInclusiveRange(0.000001, 190));
    }
  });

  testWidgets(
    'bounds known image decodes but preserves intrinsic measurement',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final known = parseComposerImages(
        '![known|640x480](https://images.test/known.png)',
      ).single;
      final unknown = parseComposerImages(
        '![unknown](https://images.test/unknown.png)',
      ).single;
      final knownSize = ComposerImagePreview.displaySize(known);
      final unknownSize = ComposerImagePreview.displaySize(unknown);
      late ImageProvider<Object> knownProvider;
      late ImageProvider<Object> unknownProvider;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              knownProvider = composerPreviewImageProvider(
                context,
                url: known.url,
                logicalSize: knownSize,
                measureNaturalSize: !known.hasDimensions,
              );
              unknownProvider = composerPreviewImageProvider(
                context,
                url: unknown.url,
                logicalSize: unknownSize,
                measureNaturalSize: !unknown.hasDimensions,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      final resized = knownProvider as ResizeImage;
      expect(resized.imageProvider, isA<NetworkImage>());
      expect(resized.width, (knownSize.width * 2).ceil());
      expect(resized.height, (knownSize.height * 2).ceil());
      expect(resized.policy, ResizeImagePolicy.fit);
      expect(resized.allowUpscaling, isFalse);
      expect(unknownProvider, isA<NetworkImage>());
    },
  );

  testWidgets('projects a bounded fallback without changing raw offsets', (
    tester,
  ) async {
    final requested = <String>[];
    final controller = MarkdownEditingController(
      text: source,
      resolveUploadUrls: (urls) async {
        requested.addAll(urls);
        return const {};
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );
    await tester.pump();

    expect(find.byType(ComposerImagePreview), findsOneWidget);
    expect(find.text('A photo'), findsOneWidget);
    expect(requested, ['upload://abc']);
    expect(controller.text, source);
    expect(
      controller
          .buildTextSpan(
            context: tester.element(find.byType(TextField)),
            style: const TextStyle(fontSize: 15),
            withComposing: true,
          )
          .toPlainText(includeSemanticsLabels: false)
          .length,
      source.length,
    );
    final size = tester.getSize(find.byType(ComposerImagePreview));
    expect(size.width, lessThanOrEqualTo(460));
    expect(size.height, lessThanOrEqualTo(200));

    final projected = controller.imageBlocks.single;
    expect(
      controller.collapsedImageAtOffset(projected.end - 1),
      same(projected),
    );
    expect(controller.collapsedImageAtOffset(projected.start), isNull);
    expect(controller.collapsedImageAtOffset(projected.end), isNull);
  });

  testWidgets('carries the target site into a resolved image preview', (
    tester,
  ) async {
    const siteUrl = 'https://meta.discourse.org';
    final controller = MarkdownEditingController(
      text: '![secure|640x480]($siteUrl/secure-uploads/image.png)',
      imageSiteUrl: siteUrl,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
          .siteUrl,
      siteUrl,
    );
    expect(tester.widget<SiteImage>(find.byType(SiteImage)).siteUrl, siteUrl);
  });

  testWidgets('a failing short-url lookup does not retry every frame', (
    tester,
  ) async {
    var attempts = 0;
    final controller = MarkdownEditingController(
      text: source,
      resolveUploadUrls: (urls) {
        attempts++;
        return Future<Map<String, String>>.error(StateError('offline'));
      },
    );
    addTearDown(controller.dispose);

    // A live field, because the loop needs a listener: announcing artwork from
    // the failure handler drops the span cache, the rebuild asks again, and an
    // unreachable site pays a request and a relayout per frame.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump();
    }

    expect(attempts, 1);

    // A real edit is still allowed to ask again.
    await tester.enterText(find.byType(TextField), '$source ');
    await tester.pump();
    expect(attempts, greaterThan(1));
  });

  testWidgets('a thrown short-url lookup is retried on a later repaint', (
    tester,
  ) async {
    var attempts = 0;
    final controller = MarkdownEditingController(
      text: source,
      resolveUploadUrls: (urls) {
        attempts++;
        if (attempts == 1) return Future.error(StateError('offline'));
        return Future.value(const {
          'upload://abc': 'https://cdn.example/abc.png',
        });
      },
    );
    addTearDown(controller.dispose);

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
    await tester.pump();
    expect(attempts, 1);

    controller.buildTextSpan(
      context: context,
      style: style,
      withComposing: false,
    );
    await tester.pump();

    final image = controller.imageBlocks.single;
    expect(attempts, 2);
    expect(controller.resolvedImageUrl(image), 'https://cdn.example/abc.png');
  });

  testWidgets('pending preview is one selected image with its alt text', (
    tester,
  ) async {
    final image = parseComposerImages('![A diagram](upload://pending)').single;
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

      // The fallback remains visible, but its repeated text is presentation;
      // the preview's single outer node owns the image name and state.
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

  testWidgets('reveals ordinary markdown when the caret enters the image', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );
    final image = controller.imageBlocks.single;
    expect(find.byType(ComposerImagePreview), findsOneWidget);

    controller.selection = TextSelection.collapsed(offset: image.start + 4);
    await tester.pump();

    expect(find.byType(ComposerImagePreview), findsNothing);
    expect(controller.text, source);

    controller.selection = TextSelection.collapsed(offset: image.end);
    await tester.pump();

    expect(find.byType(ComposerImagePreview), findsOneWidget);
  });
}
