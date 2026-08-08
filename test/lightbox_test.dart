import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:photo_view/photo_view_gallery.dart';

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

    testWidgets('lays out an image whose markup declared no size', (
      tester,
    ) async {
      // No `width`/`height` means no [AspectRatio] to bound the tile, and a
      // post scrolls, so a tile that asks to fill its box asks for an infinite
      // height and takes the viewport's layout down with it.
      await pumpCooked(tester, sizelessImage);

      expect(tester.takeException(), isNull);
      expect(find.byType(LightboxThumbnail), findsOneWidget);
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

      expect(find.byType(PhotoViewGallery), findsOneWidget);
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

    testWidgets('offers a download for an upload', (tester) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.download), findsOneWidget);
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

      expect(find.byType(PhotoViewGallery), findsNothing);
    });

    testWidgets('closes on Escape, which is what the web client binds', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(PhotoViewGallery), findsNothing);
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
