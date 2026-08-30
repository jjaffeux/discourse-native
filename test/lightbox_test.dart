import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/image_download.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:photo_view/photo_view.dart';

import 'cooked_html_test.dart' show pumpCooked, renderedText;
import 'support/finders.dart';

/// Real `add_lightbox!` output: the wrapper, the anchor carrying the full-size
/// URL, a resized `img`, and the `.meta` overlay Discourse writes the intrinsic
/// size into.
const String singleImage = '''
<p>Before.</p>
<div class="lightbox-wrapper">
  <a class="lightbox" href="https://meta.discourse.org/uploads/original/4X/a/b/c/full.png" data-download-href="https://meta.discourse.org/uploads/short-url/xyz.png?dl=1" title="screenshot.png">
    <img src="https://meta.discourse.org/uploads/optimized/4X/a/b/c/thumb.png" alt="screenshot" width="690" height="388" data-dominant-color="2A2A2A">
    <div class="meta">
      <svg class="fa d-icon d-icon-far-image svg-icon" aria-hidden="true"><use href="#far-image"></use></svg>
      <span class="filename">screenshot.png</span>
      <span class="informations">1920×1080 234 KB</span>
      <svg class="fa d-icon d-icon-discourse-expand svg-icon" aria-hidden="true"><use href="#discourse-expand"></use></svg>
    </div>
  </a>
</div>
<p>After.</p>
''';

/// A lightboxed image whose `img` carries no `width`/`height` — which chat's
/// markup does, and which leaves the tile with no declared aspect ratio.
const String sizelessImage = '''
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/full.png" title="no-size.png"><img src="https://example.com/thumb.png"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
''';

/// Three images in one post, the middle one inside a spoiler.
const String threeImages = '''
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/one.png" title="one.png"><img src="https://example.com/one-t.png" width="100" height="100"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
<div class="spoiler">
  <div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/two.png" title="two.png"><img src="https://example.com/two-t.png" width="100" height="100"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
</div>
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/three.png" title="three.png"><img src="https://example.com/three-t.png" width="100" height="100"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
''';

dom.Element anchorIn(String source, {int index = 0}) =>
    html.parse(source).querySelectorAll('a.lightbox')[index];

LightboxImage parse(String source, {int index = 0}) =>
    LightboxImage.from(anchorIn(source, index: index))!;

/// [pumpCooked], but on a stated platform — which is what decides between the
/// arrows a pointer gets and the swipe a finger gets.
Future<void> pumpCookedOn(
  WidgetTester tester,
  String html,
  TargetPlatform platform,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      home: Scaffold(
        body: SingleChildScrollView(child: CookedHtml(html: html)),
      ),
    ),
  );
  await tester.pump();
}

/// The tappable image itself. [LightboxThumbnail] fills the column so the post
/// keeps its rhythm, but the image inside it sits left at its own width, so the
/// centre of the widget is usually empty space.
Finder thumbnail([int index = 0]) => find.descendant(
  of: find.byType(LightboxThumbnail).at(index),
  matching: find.byType(InkWell),
);

Future<void> pumpGallery(
  WidgetTester tester, {
  List<LightboxImage>? images,
  int initialIndex = 0,
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      home: LightboxGallery(
        images: images ?? [parse(singleImage)],
        initialIndex: initialIndex,
      ),
    ),
  );
  await tester.pump();
}

Finder photoViewAt(int index) => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return widget is PhotoView && key is ObjectKey && key.value == index;
});

PhotoViewControllerBase<PhotoViewControllerValue> photoControllerAt(
  WidgetTester tester,
  int index,
) => tester.widget<PhotoView>(photoViewAt(index)).controller!;

Finder fullImageAt(int index) =>
    find.descendant(of: photoViewAt(index), matching: find.byType(SiteImage));

Finder galleryButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

IconButton galleryButtonWidget(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(galleryButton(tooltip));

double containedScale(Size viewport, Size image) {
  final widthScale = viewport.width / image.width;
  final heightScale = viewport.height / image.height;
  return widthScale < heightScale ? widthScale : heightScale;
}

void main() {
  group('LightboxImage.from', () {
    test('reads the full-size image off the anchor, not the thumbnail', () {
      final image = parse(singleImage);

      expect(
        image.fullSrc,
        'https://meta.discourse.org/uploads/original/4X/a/b/c/full.png',
      );
      expect(
        image.thumbnailSrc,
        'https://meta.discourse.org/uploads/optimized/4X/a/b/c/thumb.png',
      );
    });

    test('reads the caption and the download link', () {
      final image = parse(singleImage);

      expect(image.title, 'screenshot.png');
      expect(image.description, 'screenshot');
      expect(image.details, '1920×1080 234 KB');
      expect(
        image.downloadHref,
        'https://meta.discourse.org/uploads/short-url/xyz.png?dl=1',
      );
    });

    test('sizes the slot from the resized dimensions the markup declares', () {
      final image = parse(singleImage);

      expect(image.width, 690);
      expect(image.height, 388);
      expect(image.aspectRatio, closeTo(690 / 388, 0.0001));
    });

    test('keeps the full image size separate from its thumbnail slot', () {
      final image = parse(singleImage);

      expect(image.fullSize, const Size(1920, 1080));
      expect(image.width, 690);
      expect(image.height, 388);
    });

    test('prefers target dimensions for the full image size', () {
      final image = parse('''
        <a class="lightbox" href="full.png" data-target-width="2560" data-target-height="1440">
          <img src="thumb.png" width="690" height="388">
          <span class="informations">1920×1080 1 MB</span>
        </a>
      ''');

      expect(image.fullSize, const Size(2560, 1440));
      expect(image.width, 690);
      expect(image.height, 388);
    });

    test('falls back through intrinsic and thumbnail dimensions safely', () {
      final intrinsic = parse('''
        <a class="lightbox" href="full.png" data-target-width="bad" data-target-height="1440">
          <img src="thumb.png" width="640" height="480">
          <span class="informations">1600x1200 1 MB</span>
        </a>
      ''');
      final thumbnail = parse(
        '<a class="lightbox" href="full.png">'
        '<img src="thumb.png" width="640" height="480"></a>',
      );

      expect(intrinsic.fullSize, const Size(1600, 1200));
      expect(thumbnail.fullSize, const Size(640, 480));
    });

    test(
      'falls back to intrinsic information when img dimensions are absent',
      () {
        final image = parse(sizelessImage);

        expect(image.width, 1000);
        expect(image.height, 1000);
        expect(image.aspectRatio, 1);
      },
    );

    test('bounds hostile dimensions before they reach layout constraints', () {
      LightboxImage dimensions(String width, String height) => parse(
        '<a class="lightbox" href="full.png">'
        '<img src="thumb.png" width="$width" height="$height"></a>',
      );

      for (final pair in const [
        ('0', '1'),
        ('-1', '1'),
        ('1', '0'),
        ('1', '-1'),
        ('NaN', '1'),
        ('1', 'NaN'),
        ('Infinity', '1'),
        ('1', 'Infinity'),
      ]) {
        final image = dimensions(pair.$1, pair.$2);
        expect(image.width, isNull, reason: '${pair.$1}x${pair.$2}');
        expect(image.height, isNull, reason: '${pair.$1}x${pair.$2}');
        expect(image.aspectRatio, isNull, reason: '${pair.$1}x${pair.$2}');
      }

      final tooWide = dimensions('1e308', '1');
      expect(tooWide.width, 10000);
      expect(tooWide.aspectRatio, 4);
      final tooTall = dimensions('1', '1e308');
      expect(tooTall.width, 1);
      expect(tooTall.aspectRatio, 0.25);
    });

    test('prefers data-large-src over href, the way lib/lightbox.js does', () {
      final image = parse('''
        <a class="lightbox" href="https://example.com/href.png" data-large-src="https://example.com/large.png"><img src="https://example.com/t.png"></a>
      ''');

      expect(image.fullSrc, 'https://example.com/large.png');
    });

    test('falls back from the anchor title to alt to the image title', () {
      expect(
        parse(
          '<a class="lightbox" href="a.png"><img src="t.png" alt="alt text" title="img title"></a>',
        ).title,
        'alt text',
      );
      expect(
        parse(
          '<a class="lightbox" href="a.png"><img src="t.png" title="img title"></a>',
        ).title,
        'img title',
      );
      expect(
        parse('<a class="lightbox" href="a.png"><img src="t.png"></a>').title,
        isNull,
      );
    });

    test('treats an empty attribute as an absent one', () {
      final image = parse(
        '<a class="lightbox" href="a.png" title="" data-download-href=""><img src="t.png"></a>',
      );

      expect(image.title, isNull);
      expect(image.downloadHref, isNull);
    });

    test('is null when there is no image to point at', () {
      final anchor = html
          .parse('<a class="lightbox"><img src="t.png"></a>')
          .querySelector('a.lightbox')!;

      expect(LightboxImage.from(anchor), isNull);
    });
  });

  group('LightboxImage.galleryFor', () {
    test('collects every image in the post, in the order they are written', () {
      final gallery = LightboxImage.galleryFor(anchorIn(threeImages));

      expect(gallery.map((i) => i.title), ['one.png', 'two.png', 'three.png']);
    });

    test('includes spoilered images, matching the web client', () {
      // `*:not(.spoiler):not(.spoiled) .lightbox` reads as an exclusion but
      // does not act as one: div.lightbox-wrapper is itself an ancestor that
      // is neither, so the descendant combinator is satisfied.
      final gallery = LightboxImage.galleryFor(anchorIn(threeImages));

      expect(gallery.map((i) => i.title), contains('two.png'));
    });

    test('is the same gallery whichever image it is asked about', () {
      final first = LightboxImage.galleryFor(anchorIn(threeImages));
      final last = LightboxImage.galleryFor(anchorIn(threeImages, index: 2));

      expect(first.map((i) => i.fullSrc), last.map((i) => i.fullSrc));
    });

    test('gives each image a hero tag of its own', () {
      final gallery = LightboxImage.galleryFor(anchorIn(threeImages));
      final tags = gallery.map((i) => i.heroTag).toSet();

      expect(tags, hasLength(3));
    });

    test('a repeated image still gets two tags, one per place it appears', () {
      // Two live [Hero]s under one tag is an error, so the tag has to come from
      // the element rather than the URL.
      const twice = '''
        <div class="lightbox-wrapper"><a class="lightbox" href="same.png"><img src="t.png"></a></div>
        <div class="lightbox-wrapper"><a class="lightbox" href="same.png"><img src="t.png"></a></div>
      ''';
      final gallery = LightboxImage.galleryFor(anchorIn(twice));

      expect(gallery, hasLength(2));
      expect(gallery[0].heroTag, isNot(same(gallery[1].heroTag)));
    });

    test('a hero tag is stable across reparses of the same element', () {
      final anchor = anchorIn(singleImage);

      expect(
        LightboxImage.from(anchor)!.heroTag,
        same(LightboxImage.from(anchor)!.heroTag),
      );
    });
  });

  group('in a post', () {
    testWidgets('draws the thumbnail natively instead of as a bare img', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);

      expect(find.byType(LightboxThumbnail), findsOneWidget);
      expect(renderedText('Before.'), findsOneWidget);
      expect(renderedText('After.'), findsOneWidget);
    });

    testWidgets('names the thumbnail as an image-opening action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCooked(tester, singleImage);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Open image: screenshot'),
      );
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('bounds thumbnail decoding to its physical layout width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await pumpCooked(tester, singleImage);

      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(LightboxThumbnail),
          matching: find.byType(Image),
        ),
      );
      final provider = image.image as ResizeImage;
      expect(provider.width, 1380);
      expect(provider.allowUpscaling, isFalse);
    });

    testWidgets('lays out an image whose markup declared no size', (
      tester,
    ) async {
      // Chat can omit `width`/`height`, but its information line still gives
      // us enough to reserve the slot before the image loads.
      await pumpCooked(tester, sizelessImage);

      expect(tester.takeException(), isNull);
      expect(find.byType(LightboxThumbnail), findsOneWidget);
    });

    testWidgets('standalone thumbnails contain unusually tall images', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<a class="lightbox" href="full.png"><img src="thumb.png" '
        'width="100" height="1000"></a>',
      );

      expect(
        tester.widget<LightboxTile>(find.byType(LightboxTile)).fit,
        BoxFit.contain,
      );
    });

    testWidgets('does not print the .meta overlay as stray text', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);

      // Left to [HtmlWidget] the filename and the dimensions land in the post
      // as two loose lines under the image.
      expect(renderedText('screenshot.png'), findsNothing);
      expect(renderedText('1920×1080 234 KB'), findsNothing);
    });

    testWidgets('opens the gallery on the image that was tapped', (
      tester,
    ) async {
      await pumpCooked(tester, threeImages);
      await tester.tap(thumbnail(2));
      await tester.pumpAndSettle();

      expect(photoViewAt(2), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('three.png'), findsOneWidget);
    });

    testWidgets('shows the caption Discourse wrote into the markup', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.text('screenshot.png'), findsOneWidget);
      expect(find.text('1920×1080 234 KB'), findsOneWidget);
    });

    testWidgets('keeps extreme full-image geometry for PhotoView transforms', (
      tester,
    ) async {
      final image = parse('''
        <a class="lightbox" href="full.png" data-target-width="2000" data-target-height="100">
          <img src="thumb.png" width="2000" height="100">
        </a>
      ''');

      // Post layout remains defensive, but full-screen transform math must not
      // reshape a legitimate panorama to that 4:1 layout bound.
      expect(image.aspectRatio, 4);
      await pumpGallery(tester, images: [image]);

      final childSize = tester.widget<PhotoView>(photoViewAt(0)).childSize!;
      expect(childSize, const Size(2000, 100));
      expect(childSize.width / childSize.height, 20);
    });

    testWidgets(
      'defers a late natural size and resets the zoom to its bounds',
      (tester) async {
        final image = parse('''
        <a class="lightbox" href="full.png" data-target-width="1000" data-target-height="1000">
          <img src="thumb.png" width="1000" height="1000">
        </a>
      ''');
        await pumpGallery(tester, images: [image]);
        final controller = photoControllerAt(tester, 0);
        final pointer =
            tester.getCenter(photoViewAt(0)) + const Offset(120, 80);

        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: pointer,
            scrollDelta: const Offset(0, -100),
          ),
        );
        await tester.pump();
        final zoomedScale = controller.scale!;
        expect(controller.position.distance, greaterThan(0));

        const naturalSize = Size(2000, 1000);
        tester.widget<SiteImage>(fullImageAt(0)).onNaturalSize!(naturalSize);

        expect(
          tester.widget<PhotoView>(photoViewAt(0)).childSize,
          const Size(1000, 1000),
        );
        expect(controller.scale, zoomedScale);

        await tester.pump();
        await tester.pump();

        expect(tester.widget<PhotoView>(photoViewAt(0)).childSize, naturalSize);
        expect(
          controller.scale,
          closeTo(
            containedScale(tester.getSize(photoViewAt(0)), naturalSize),
            0.001,
          ),
        );
        expect(controller.position, Offset.zero);
      },
    );

    testWidgets('resizing the viewport resets the current zoom and position', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final image = parse('''
        <a class="lightbox" href="full.png" data-target-width="1000" data-target-height="1000">
          <img src="thumb.png" width="1000" height="1000">
        </a>
      ''');
      await pumpGallery(tester, images: [image]);
      final controller = photoControllerAt(tester, 0);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(photoViewAt(0)) + const Offset(120, 80),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(controller.position.distance, greaterThan(0));

      tester.view.physicalSize = const Size(400, 600);
      await tester.pump();
      await tester.pump();

      expect(
        controller.scale,
        closeTo(
          containedScale(
            tester.getSize(photoViewAt(0)),
            const Size(1000, 1000),
          ),
          0.001,
        ),
      );
      expect(controller.position, Offset.zero);
    });

    testWidgets('labels the full image and exposes accessible zoom controls', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpGallery(tester);

      final image = tester.getSemantics(find.bySemanticsLabel('screenshot'));
      expect(image.getSemanticsData().flagsCollection.isImage, isTrue);

      for (final label in const ['Zoom out', 'Reset zoom', 'Zoom in']) {
        final target = find.bySemanticsLabel(label);
        final button = galleryButton(label);
        expect(find.byTooltip(label), findsOneWidget);
        expect(target, findsOneWidget);
        expect(button, findsOneWidget);
        expect(
          tester
              .getSemantics(button)
              .getSemanticsData()
              .flagsCollection
              .isButton,
          isTrue,
        );
        expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      }

      expect(
        tester
            .getSemantics(galleryButton('Zoom in'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
    });

    testWidgets('zooms with the visible controls and resets', (tester) async {
      await pumpGallery(tester);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(controller.scale, greaterThan(initialScale));

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(controller.scale, closeTo(initialScale, 0.001));

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pumpAndSettle();
      expect(controller.scale, closeTo(initialScale, 0.001));
    });

    testWidgets('disables zoom controls at their scale bounds', (tester) async {
      await pumpGallery(tester);

      expect(galleryButtonWidget(tester, 'Zoom out').onPressed, isNull);
      expect(galleryButtonWidget(tester, 'Reset zoom').onPressed, isNull);
      expect(galleryButtonWidget(tester, 'Zoom in').onPressed, isNotNull);

      await tester.tap(galleryButton('Zoom in'));
      await tester.pump();
      expect(galleryButtonWidget(tester, 'Zoom out').onPressed, isNotNull);
      expect(galleryButtonWidget(tester, 'Reset zoom').onPressed, isNotNull);

      var zoomIns = 1;
      while (galleryButtonWidget(tester, 'Zoom in').onPressed != null &&
          zoomIns < 20) {
        await tester.tap(galleryButton('Zoom in'));
        await tester.pump();
        zoomIns++;
      }

      expect(zoomIns, lessThan(20));
      expect(galleryButtonWidget(tester, 'Zoom in').onPressed, isNull);
      expect(galleryButtonWidget(tester, 'Zoom out').onPressed, isNotNull);
      expect(galleryButtonWidget(tester, 'Reset zoom').onPressed, isNotNull);
    });

    testWidgets('styles disabled zoom controls with inherited muted color', (
      tester,
    ) async {
      await pumpGallery(tester);
      final button = galleryButtonWidget(tester, 'Zoom out');
      final icon = tester.widget<DIcon>(
        find.descendant(
          of: galleryButton('Zoom out'),
          matching: find.byType(DIcon),
        ),
      );

      expect(button.onPressed, isNull);
      expect(
        button.style?.foregroundColor?.resolve({WidgetState.disabled}),
        Colors.white38,
      );
      expect(icon.color, isNull);
    });

    testWidgets('zooms with keyboard shortcuts', (tester) async {
      await pumpGallery(tester);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      expect(controller.scale, greaterThan(initialScale));

      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pumpAndSettle();
      expect(controller.scale, closeTo(initialScale, 0.001));

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(controller.scale, closeTo(initialScale, 0.001));
    });

    testWidgets('zooms around an off-center pointer with the mouse wheel', (
      tester,
    ) async {
      await pumpGallery(tester);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;
      final pointer = tester.getCenter(photoViewAt(0)) + const Offset(120, 80);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.scale, greaterThan(initialScale));
      expect(controller.position.dx, lessThan(0));
      expect(controller.position.dy, lessThan(0));

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.scale, closeTo(initialScale, 0.001));
      expect(controller.position, Offset.zero);
    });

    testWidgets('diagonal mouse-wheel zoom does not change the gallery page', (
      tester,
    ) async {
      await pumpGallery(
        tester,
        images: LightboxImage.galleryFor(anchorIn(threeImages)),
      );
      final first = photoControllerAt(tester, 0);

      await tester.tap(galleryButton('Zoom in'));
      await tester.pump();
      final zoomedScale = first.scale!;

      // Downward wheel input would advance a scrollable from its first page if
      // the gallery did not claim it for image zooming.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(photoViewAt(0)),
          scrollDelta: const Offset(30, 100),
        ),
      );
      await tester.pumpAndSettle();

      expect(first.scale, lessThan(zoomedScale));
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('2 / 3'), findsNothing);
    });

    testWidgets('mouse-wheel zoom works over a toolbar button', (tester) async {
      await pumpGallery(tester);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(galleryButton('Zoom in')),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();

      expect(controller.scale, greaterThan(initialScale));
    });

    testWidgets('ignores a modified mouse wheel', (tester) async {
      await pumpGallery(tester);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;
      final pointer = tester.getCenter(photoViewAt(0)) + const Offset(120, 80);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      try {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: pointer,
            scrollDelta: const Offset(0, -100),
          ),
        );
        await tester.pump();
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }

      expect(controller.scale, closeTo(initialScale, 0.001));
      expect(controller.position, Offset.zero);
    });

    testWidgets('resets the zoom when changing pages', (tester) async {
      await pumpGallery(
        tester,
        images: LightboxImage.galleryFor(anchorIn(threeImages)),
      );
      final first = photoControllerAt(tester, 0);
      final initialScale = first.scale!;

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(first.scale, greaterThan(initialScale));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(first.scale, closeTo(initialScale, 0.001));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      expect(first.scale, closeTo(initialScale, 0.001));
    });

    testWidgets('double tap still zooms after returning to minimum scale', (
      tester,
    ) async {
      await pumpGallery(tester);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;

      await tester.tap(galleryButton('Zoom in'));
      await tester.pump();
      await tester.tap(galleryButton('Zoom out'));
      await tester.pumpAndSettle();
      expect(controller.scale, closeTo(initialScale, 0.001));

      final target = tester.getCenter(photoViewAt(0));

      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(target);
      await tester.pumpAndSettle();

      expect(controller.scale, greaterThan(initialScale));
    });

    testWidgets('pinches the image to zoom in with two touch pointers', (
      tester,
    ) async {
      await pumpGallery(tester, platform: TargetPlatform.iOS);
      final controller = photoControllerAt(tester, 0);
      final initialScale = controller.scale!;
      final center = tester.getCenter(photoViewAt(0));
      final first = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );

      await first.moveTo(center - const Offset(120, 0));
      await second.moveTo(center + const Offset(120, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(controller.scale, greaterThan(initialScale));
    });

    testWidgets('offers a download for an upload', (tester) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.download), findsOneWidget);
    });

    testWidgets('downloads the upload instead of opening its URL', (
      tester,
    ) async {
      final downloader = _FakeImageDownloader();
      await tester.pumpWidget(
        MaterialApp(
          home: LightboxGallery(
            images: [parse(singleImage)],
            initialIndex: 0,
            siteUrl: 'https://meta.discourse.org',
            imageDownloader: downloader,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.dIcon(DIcons.download));
      await tester.pump();

      expect(
        downloader.url,
        'https://meta.discourse.org/uploads/short-url/xyz.png?dl=1',
      );
      expect(downloader.title, 'screenshot.png');
      expect(downloader.siteUrl, 'https://meta.discourse.org');
      expect(downloader.calls, 1);
      expect(find.text('Saved screenshot.png.'), findsOneWidget);
    });

    testWidgets('puts top controls on dark surfaces', (tester) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      IconButton button(DIconData icon) => tester.widget<IconButton>(
        find.ancestor(of: find.dIcon(icon), matching: find.byType(IconButton)),
      );

      for (final icon in [DIcons.download, DIcons.xmark]) {
        expect(
          button(icon).style?.backgroundColor?.resolve({}),
          const Color(0xBB000000),
        );
      }
    });

    testWidgets('fits gallery controls at 320px with 2x text scaling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mediaQuery = MediaQueryData.fromView(
        tester.view,
      ).copyWith(textScaler: const TextScaler.linear(2));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: mediaQuery,
            child: LightboxGallery(
              images: [
                parse(singleImage),
                ...LightboxImage.galleryFor(anchorIn(threeImages)),
              ],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('1 / 4'), findsOneWidget);
      expect(galleryButton('Zoom in'), findsOneWidget);
      expect(find.dIcon(DIcons.download), findsOneWidget);
      expect(find.dIcon(DIcons.xmark), findsOneWidget);
    });

    testWidgets('offers no download for an image that carries no link', (
      tester,
    ) async {
      // `data-download-href` is only written for uploads.
      await pumpCooked(tester, threeImages);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.download), findsNothing);
    });

    testWidgets('hides the counter for a post with one image', (tester) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('closes on the close button', (tester) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.xmark));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoView), findsNothing);
    });

    testWidgets('reveals hidden controls when the pointer moves', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: LightboxGallery(images: [parse(singleImage)], initialIndex: 0),
        ),
      );
      await tester.pump();

      final chrome = find.ancestor(
        of: find.dIcon(DIcons.xmark),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);

      final photoView = find.byType(PhotoView);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final center = tester.getCenter(photoView);
      await mouse.moveTo(center);
      await tester.pump();

      tester.widget<PhotoView>(photoView).onTapUp!(
        tester.element(photoView),
        TapUpDetails(kind: PointerDeviceKind.mouse),
        const PhotoViewControllerValue(
          position: Offset.zero,
          scale: 1,
          rotation: 0,
          rotationFocusPoint: null,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);

      await mouse.moveTo(center + const Offset(10, 0));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);
    });

    testWidgets('closes on Escape, which is what the web client binds', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoView), findsNothing);
    });

    testWidgets('steps between images with the arrow keys', (tester) async {
      await pumpCooked(tester, threeImages);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('offers arrows to a pointer', (tester) async {
      await pumpCookedOn(tester, threeImages, TargetPlatform.macOS);
      await tester.tap(thumbnail(1));
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.chevronLeft), findsOneWidget);
      expect(find.dIcon(DIcons.chevronRight), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.chevronRight));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('offers no arrows to a finger, which swipes instead', (
      tester,
    ) async {
      await pumpCookedOn(tester, threeImages, TargetPlatform.iOS);
      await tester.tap(thumbnail(1));
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.chevronLeft), findsNothing);
      expect(find.dIcon(DIcons.chevronRight), findsNothing);
    });

    testWidgets('leaves images Discourse did not lightbox alone', (
      tester,
    ) async {
      // No wrapper: a onebox image, a small one, an animated GIF.
      await pumpCooked(
        tester,
        '<p><img src="https://example.com/small.png" width="50" height="50"></p>',
      );

      expect(find.byType(LightboxThumbnail), findsNothing);
    });
  });
}

final class _FakeImageDownloader implements LightboxImageDownloader {
  int calls = 0;
  String? url;
  String? title;
  String? siteUrl;

  @override
  Future<ImageDownloadOutcome> download({
    required String url,
    required String? title,
    required String? siteUrl,
    required SiteImageRepository? repository,
    Rect? sharePositionOrigin,
  }) async {
    calls++;
    this.url = url;
    this.title = title;
    this.siteUrl = siteUrl;
    return ImageDownloadOutcome.saved;
  }
}
