import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/foundation/media_download_environment.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_plugin.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/image_decode.dart';
import 'package:discourse_native/src/shell/image_download.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/media_download_result.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_view/photo_view.dart';

import 'cooked_html_test.dart' show pumpCooked, renderedText;
import 'support/blank_png.dart';
import 'support/fakes.dart';
import 'support/finders.dart';
import 'support/pending_thumbnails.dart';

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

const String sizelessImage = '''
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/full.png" title="no-size.png"><img src="https://example.com/thumb.png"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
''';

const String threeImages = '''
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/one.png" title="one.png"><img src="https://example.com/one-t.png" width="100" height="100"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/two.png" title="two.png"><img src="https://example.com/two-t.png" width="100" height="100"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/three.png" title="three.png"><img src="https://example.com/three-t.png" width="100" height="100"><div class="meta"><span class="informations">1000×1000 1 MB</span></div></a></div>
''';

String galleryImage(String name) =>
    '<a class="lightbox" href="https://example.com/$name.png" '
    'title="$name"><img src="https://example.com/$name-t.png" '
    'width="80" height="80"></a>';

dom.Element anchorIn(String source, {int index = 0}) =>
    html.parse(source).querySelectorAll('a.lightbox')[index];

LightboxImage parse(String source, {int index = 0}) =>
    LightboxImage.from(anchorIn(source, index: index))!;

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

Finder barText(String text) => find.descendant(
  of: find.byType(LightboxGallery),
  matching: find.textContaining(text, findRichText: true),
);

Finder galleryButton(String tooltip) =>
    find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(DButton));

DButton galleryButtonWidget(WidgetTester tester, String tooltip) =>
    tester.widget<DButton>(galleryButton(tooltip));

double containedScale(Size viewport, Size image) {
  final widthScale = viewport.width / image.width;
  final heightScale = viewport.height / image.height;
  return widthScale < heightScale ? widthScale : heightScale;
}

void main() {
  testWidgets('loading skeleton fills the image slot and follows its scale', (
    tester,
  ) async {
    await pumpGallery(
      tester,
      images: [parse(singleImage.replaceAll('full.png', 'pending.png'))],
    );
    final skeleton = find.byType(DSkeleton);
    expect(skeleton, findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    expect(tester.getSize(skeleton), tester.getSize(fullImageAt(0)));
    final size = tester.getSize(skeleton);
    expect(size.width / size.height, closeTo(1920 / 1080, 0.01));

    photoControllerAt(tester, 0).scale = 2;
    await tester.pump();
    final box = tester.renderObject<RenderBox>(skeleton);
    final origin = box.localToGlobal(Offset.zero);
    final corner = box.localToGlobal(box.size.bottomRight(Offset.zero));
    expect((corner - origin).dx, closeTo(size.width * 2, 0.01));
    expect((corner - origin).dy, closeTo(size.height * 2, 0.01));
    await tester.pumpWidget(const SizedBox.shrink());
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('retiring a gallery leaves a newer unrelated route in place', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final retire = Completer<void>();
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold();
          },
        ),
      ),
    );
    unawaited(
      showLightboxGallery(
        host,
        images: [parse(singleImage)],
        initialIndex: 0,
        dismissWhen: retire.future,
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Newer route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    retire.complete();
    await tester.pumpAndSettle();
    expect(find.text('Newer route'), findsOneWidget);
    expect(find.byType(LightboxGallery, skipOffstage: false), findsNothing);
  });

  group('LightboxImage.from', () {
    test('reads upload URLs, caption and thumbnail/full-image dimensions', () {
      final image = parse(singleImage);

      expect(
        (image.source as RemoteLightboxImage).url,
        'https://meta.discourse.org/uploads/original/4X/a/b/c/full.png',
      );
      expect(
        image.thumbnailSrc,
        'https://meta.discourse.org/uploads/optimized/4X/a/b/c/thumb.png',
      );
      expect(image.title, 'screenshot.png');
      expect(image.description, 'screenshot');
      expect(image.details, '1920×1080 234 KB');
      expect(
        image.downloadHref,
        'https://meta.discourse.org/uploads/short-url/xyz.png?dl=1',
      );
      expect(image.width, 690);
      expect(image.height, 388);
      expect(image.aspectRatio, closeTo(690 / 388, 0.0001));
      expect(image.fullSize, const Size(1920, 1080));
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

      expect(
        (image.source as RemoteLightboxImage).url,
        'https://example.com/large.png',
      );
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
    test('collects ordinary images in written order', () {
      final gallery = LightboxImage.galleryFor(anchorIn(threeImages));

      expect(gallery.map((i) => i.title), ['one.png', 'two.png', 'three.png']);
    });

    for (final boundary in const [
      ('div', 'class="spoiler"'),
      ('span', 'class="spoiler"'),
      ('div', 'class="hidden"'),
      ('span', 'class="hidden"'),
      ('details', ''),
      ('details', 'open'),
    ]) {
      test('excludes ${boundary.$1} ${boundary.$2} descendants', () {
        final document = html.parseFragment(
          '${galleryImage('before')}'
          '<${boundary.$1} ${boundary.$2}>'
          '${galleryImage('concealed')}'
          '</${boundary.$1}>'
          '${galleryImage('after')}',
        );
        final anchors = document.querySelectorAll('a.lightbox');

        expect(
          LightboxImage.galleryFor(anchors.first).map((image) => image.title),
          ['before', 'after'],
        );
        expect(LightboxImage.galleryFor(anchors[1]), isEmpty);
        expect(
          LightboxImage.galleryFor(anchors.last).map((image) => image.title),
          ['before', 'after'],
        );
      });
    }

    test('keeps an ordinary detached anchor as its own gallery', () {
      final anchor = anchorIn(singleImage).clone(true);

      expect(LightboxImage.galleryFor(anchor).single.title, 'screenshot.png');
    });

    test('is the same gallery whichever image it is asked about', () {
      final first = LightboxImage.galleryFor(anchorIn(threeImages));
      final last = LightboxImage.galleryFor(anchorIn(threeImages, index: 2));

      expect(
        first.map((i) => (i.source as RemoteLightboxImage).url),
        last.map((i) => (i.source as RemoteLightboxImage).url),
      );
    });

    test('gives each image a hero tag of its own', () {
      final gallery = LightboxImage.galleryFor(anchorIn(threeImages));
      final tags = gallery.map((i) => i.heroTag).toSet();

      expect(tags, hasLength(3));
    });

    test('a repeated image still gets two tags, one per place it appears', () {
      // Flutter rejects simultaneous heroes that share a tag.
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
    testWidgets('keeps excerpt lightboxes as inline text links', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final launched = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      // Core's ExcerptParser strips carousel markup and replaces images with
      // bracketed labels, but preserves their enclosing a.lightbox links.
      await pumpCooked(
        tester,
        '<aside class="quote" data-topic="123" data-post="1">'
        '<div class="title"><a href="/t/blog/123">Discourse Blog</a></div>'
        '<blockquote>I deployed the blog. '
        '<a class="lightbox" href="https://example.com/one.png">[image]</a> '
        '<a class="lightbox" href="https://example.com/two.png">[second image]</a> '
        'More quoted text...</blockquote></aside>'
        '<p>After the quote.</p>',
      );

      expect(find.byType(LightboxThumbnail), findsNothing);
      expect(find.byType(SiteImage), findsNothing);
      expect(renderedText('[image]'), findsOneWidget);
      expect(renderedText('[second image]'), findsOneWidget);
      expect(
        tester.getBottomLeft(renderedText('After the quote.')).dy,
        lessThan(200),
      );
      await tester.tapOnText(find.textRange.ofSubstring('[second image]'));
      await tester.pumpAndSettle();
      expect(launched, ['https://example.com/two.png']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps wrapped text lightboxes as links too', (tester) async {
      await pumpCooked(
        tester,
        '<div class="lightbox-wrapper">'
        '<a class="lightbox" href="https://example.com/full.png">'
        '[screenshot]</a></div>',
      );

      expect(find.byType(LightboxThumbnail), findsNothing);
      expect(find.byType(SiteImage), findsNothing);
      expect(renderedText('[screenshot]'), findsOneWidget);
    });

    testWidgets('still renders actual images inside quotes', (tester) async {
      await pumpCooked(
        tester,
        '<aside class="quote"><blockquote>$singleImage</blockquote></aside>',
      );

      expect(find.byType(LightboxThumbnail), findsOneWidget);
      expect(find.byType(DImagePreview), findsOneWidget);
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
      // 690 logical pixels at 2x, rounded up so a resize can reuse it.
      expect(provider.width, coarseDecodePixels(1380));
      expect(provider.allowUpscaling, isFalse);
    });

    testWidgets(
      'draws the thumbnail from its srcset and opens the full image',
      (tester) async {
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        const optimized =
            'https://meta.discourse.org/uploads/optimized/4X/a/b/c';
        await pumpCooked(
          tester,
          singleImage.replaceFirst(
            'data-dominant-color',
            'srcset="$optimized/thumb.png, $optimized/thumb_1035.png 1.5x, '
                '$optimized/thumb_1380.png 2x" data-dominant-color',
          ),
        );

        expect(
          tester
              .widget<SiteImage>(
                find.descendant(
                  of: find.byType(LightboxTile),
                  matching: find.byType(SiteImage),
                ),
              )
              .url,
          '$optimized/thumb_1380.png',
        );

        await tester.tap(thumbnail());
        await tester.pumpAndSettle();

        expect(
          tester.widget<SiteImage>(fullImageAt(0)).url,
          'https://meta.discourse.org/uploads/original/4X/a/b/c/full.png',
        );
      },
    );

    testWidgets('lays out an image whose markup declared no size', (
      tester,
    ) async {
      // Chat supplies the usable dimensions only in the information line.
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

    testWidgets('reveals post metadata inside the image on hover', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);

      expect(find.byType(LightboxThumbnail), findsOneWidget);
      expect(renderedText('Before.'), findsOneWidget);
      expect(renderedText('After.'), findsOneWidget);
      expect(renderedText('screenshot.png'), findsNothing);
      expect(renderedText('1920×1080 234 KB'), findsNothing);
      final preview = find.byType(DImagePreview);
      final bounds = tester.getRect(preview);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: bounds.center);
      await tester.pumpAndSettle();
      final opacity = find.descendant(
        of: preview,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, .9);
      expect(find.text('screenshot.png'), findsOneWidget);
      expect(find.text('1920×1080 234 KB'), findsOneWidget);
      expect(tester.getRect(preview), bounds);
      await mouse.removePointer();
    });

    testWidgets('opens the gallery on the image that was tapped', (
      tester,
    ) async {
      await pumpCooked(tester, threeImages);
      await tester.tap(thumbnail(2));
      await tester.pumpAndSettle();

      expect(photoViewAt(2), findsOneWidget);
      expect(barText('3 of 3'), findsOneWidget);
      expect(barText('three.png'), findsOneWidget);
    });

    testWidgets('galleries respect closed and revealed spoiler boundaries', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '${galleryImage('before')}'
        '<div class="spoiler">'
        '${galleryImage('revealed-one')}${galleryImage('revealed-two')}'
        '<span class="spoiler">${galleryImage('nested-secret')}</span>'
        '<span class="hidden">${galleryImage('event-secret')}</span>'
        '</div>'
        '<div class="hidden">${galleryImage('hidden-secret')}</div>'
        '${galleryImage('after')}',
        registry: const PluginRegistry([DiscourseEventsPlugin()]),
      );
      expect(find.byType(LightboxThumbnail), findsNWidgets(2));

      await tester.tap(thumbnail());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LightboxGallery>(find.byType(LightboxGallery))
            .images
            .map((image) => image.title),
        ['before', 'after'],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(barText('after'), findsOneWidget);
      await tester.tap(find.dIcon(DIcons.xmark));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DSpoiler));
      await tester.pumpAndSettle();
      expect(find.byType(LightboxThumbnail), findsNWidgets(4));
      final revealed = find.byWidgetPredicate(
        (widget) =>
            widget is LightboxThumbnail && widget.image.title == 'revealed-one',
      );
      await tester.tap(
        find.descendant(of: revealed, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LightboxGallery>(find.byType(LightboxGallery))
            .images
            .map((image) => image.title),
        ['revealed-one', 'revealed-two'],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(barText('revealed-two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('details images open only within their revealed fragment', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '${galleryImage('outside')}'
        '<details><summary>More images</summary>'
        '${galleryImage('inside')}</details>',
      );
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LightboxGallery>(find.byType(LightboxGallery))
            .images
            .single
            .title,
        'outside',
      );
      await tester.tap(find.dIcon(DIcons.xmark));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More images'));
      await tester.pumpAndSettle();
      await tester.tap(thumbnail(1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LightboxGallery>(find.byType(LightboxGallery))
            .images
            .single
            .title,
        'inside',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a readable caption and download action for an upload', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.download), findsOneWidget);
      expect(barText('1 of 1'), findsNothing);
      expect(barText('screenshot.png'), findsOneWidget);
      expect(find.text('1920×1080 234 KB'), findsOneWidget);

      final captionSurfaces = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.text('1920×1080 234 KB'),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>();

      expect(
        captionSurfaces,
        contains(
          isA<BoxDecoration>().having(
            (decoration) => decoration.color,
            'background color',
            const Color(0xCC000000),
          ),
        ),
      );
    });

    testWidgets('keeps extreme full-image geometry for PhotoView transforms', (
      tester,
    ) async {
      final image = parse('''
        <a class="lightbox" href="full.png" data-target-width="2000" data-target-height="100">
          <img src="thumb.png" width="2000" height="100">
        </a>
      ''');

      // Thumbnail layout is bounded, but PhotoView needs the natural geometry.
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

        // The real image callback runs during a frame. Schedule that frame
        // explicitly instead of depending on an unrelated button animation.
        tester.binding.scheduleFrame();
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
        expect(tester.getSize(button), const Size.square(36));
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
      expect(button.variant, DButtonVariant.ghost);
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

      // The gallery must claim wheel input before PageView handles it.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(photoViewAt(0)),
          scrollDelta: const Offset(30, 100),
        ),
      );
      await tester.pumpAndSettle();

      expect(first.scale, lessThan(zoomedScale));
      expect(barText('1 of 3'), findsOneWidget);
      expect(barText('2 of 3'), findsNothing);
    });

    testWidgets('scrolling up over a toolbar button increases image scale', (
      tester,
    ) async {
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
      expect(barText('2 of 3'), findsOneWidget);
      expect(first.scale, closeTo(initialScale, 0.001));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(barText('1 of 3'), findsOneWidget);
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

    testWidgets('downloads the upload instead of opening its URL', (
      tester,
    ) async {
      final downloader = _FakeImageDownloader();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DToaster(child: child!),
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

    testWidgets('a renamed desktop image save does not report its suggestion', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('lightbox-save-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final destination = '${directory.path}/final-copy.png';
      final bytes = blankPng(width: 1, height: 1);
      final client = MockClient(
        (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      addTearDown(client.close);
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        client: client,
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore(const []),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        siteImages: repository,
      );
      addTearDown(shell.dispose);
      final environment = _RenamedImageDownloadEnvironment(destination);
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => DToaster(child: child!),
            home: LightboxGallery(
              images: [parse(singleImage)],
              initialIndex: 0,
              siteUrl: 'https://meta.discourse.org',
              imageDownloader: NativeLightboxImageDownloader(
                platform: Platform.isWindows
                    ? TargetPlatform.windows
                    : TargetPlatform.macOS,
                environment: environment,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.dIcon(DIcons.download));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(environment.savedPath, destination);
      expect(File(destination).readAsBytesSync(), bytes);
      expect(find.text('Saved final-copy.png.'), findsOneWidget);
      expect(find.text('Saved screenshot.png.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toolbar clears macOS chrome and stays outside the image', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpGallery(
        tester,
        images: LightboxImage.galleryFor(anchorIn(threeImages)),
      );
      final counter = barText('1 of 3');
      final imageViewport = tester.getRect(find.byType(PageView));
      expect(
        find.ancestor(
          of: find.dIcon(DIcons.xmark),
          matching: find.byType(DCard),
        ),
        findsNothing,
      );
      expect(tester.getRect(counter).left, greaterThanOrEqualTo(88));
      expect(
        tester.getRect(galleryButton('Zoom in')).bottom,
        lessThanOrEqualTo(imageViewport.top),
      );
      expect(tester.widget<RichText>(counter).text.style!.color, Colors.white);
      await tester.tap(galleryButton('Zoom in'));
      await tester.pump();
      expect(tester.getRect(find.byType(PageView)), imageViewport);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('draws top controls as white rounds over the backdrop', (
      tester,
    ) async {
      await pumpCooked(tester, singleImage);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      DButton button(DIconData icon) => tester.widget<DButton>(
        find.ancestor(of: find.dIcon(icon), matching: find.byType(DButton)),
      );

      for (final icon in [DIcons.download, DIcons.xmark]) {
        expect(button(icon).density, DButtonDensity.overMedia);
        expect(button(icon).foregroundColor, Colors.white);
        expect(
          button(icon).backgroundColor,
          Colors.white.withValues(alpha: .12),
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
      expect(barText('1 of 4'), findsOneWidget);
      expect(galleryButton('Zoom in'), findsOneWidget);
      expect(find.dIcon(DIcons.download), findsOneWidget);
      expect(find.dIcon(DIcons.xmark), findsOneWidget);
    });

    testWidgets('offers no download for an image that carries no link', (
      tester,
    ) async {
      await pumpCooked(tester, threeImages);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.download), findsNothing);
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

    group('vertical drag to close', () {
      Future<void> openOnPhone(WidgetTester tester) async {
        await pumpCookedOn(tester, singleImage, TargetPlatform.iOS);
        await tester.tap(thumbnail());
        await tester.pumpAndSettle();
      }

      // Ten steps a tenth of a second apart: every pause is long enough for
      // the velocity tracker to treat the finger as stopped, so the release
      // carries no velocity and only the distance decides.
      Future<void> dragSlowly(
        WidgetTester tester,
        Offset by, {
        PointerDeviceKind kind = PointerDeviceKind.touch,
      }) async {
        final pointer = await tester.startGesture(
          tester.getCenter(photoViewAt(0)),
          kind: kind,
        );
        for (var step = 1; step <= 10; step++) {
          await pointer.moveBy(
            by / 10,
            timeStamp: Duration(milliseconds: 100 * step),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pointer.up(timeStamp: const Duration(seconds: 1));
      }

      for (final (direction, distance) in [('down', 200.0), ('up', -200.0)]) {
        testWidgets('a finger dragging $direction closes the image', (
          tester,
        ) async {
          await openOnPhone(tester);

          await dragSlowly(tester, Offset(0, distance));
          await tester.pumpAndSettle();

          expect(find.byType(PhotoView), findsNothing);
        });
      }

      testWidgets('a short flick closes the image', (tester) async {
        await openOnPhone(tester);

        await tester.fling(photoViewAt(0), const Offset(0, 60), 1000);
        await tester.pumpAndSettle();

        expect(find.byType(PhotoView), findsNothing);
      });

      testWidgets('the image follows the finger and hides the controls', (
        tester,
      ) async {
        await openOnPhone(tester);
        final resting = tester.getCenter(photoViewAt(0));
        final chrome = find.ancestor(
          of: find.dIcon(DIcons.xmark),
          matching: find.byType(AnimatedOpacity),
        );

        final finger = await tester.startGesture(
          resting,
          kind: PointerDeviceKind.touch,
        );
        await finger.moveBy(const Offset(0, 30));
        await finger.moveBy(const Offset(0, 90));
        await tester.pump();

        expect(tester.getCenter(photoViewAt(0)).dy, resting.dy + 90);
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
        await finger.up();
        await tester.pumpAndSettle();
      });

      testWidgets('a short slow drag puts the image back', (tester) async {
        await openOnPhone(tester);
        final resting = tester.getCenter(photoViewAt(0));

        await dragSlowly(tester, const Offset(0, 50));
        await tester.pumpAndSettle();

        expect(find.byType(PhotoView), findsOneWidget);
        expect(tester.getCenter(photoViewAt(0)), resting);
        final chrome = find.ancestor(
          of: find.dIcon(DIcons.xmark),
          matching: find.byType(AnimatedOpacity),
        );
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);
      });

      testWidgets('a drag that reverses toward the start puts the image back', (
        tester,
      ) async {
        await openOnPhone(tester);
        final resting = tester.getCenter(photoViewAt(0));

        final finger = await tester.startGesture(
          resting,
          kind: PointerDeviceKind.touch,
        );
        var time = Duration.zero;
        for (final (distance, interval) in [
          for (var step = 0; step < 10; step++) (20.0, 50),
          for (var step = 0; step < 5; step++) (-20.0, 10),
        ]) {
          time += Duration(milliseconds: interval);
          await finger.moveBy(Offset(0, distance), timeStamp: time);
          await tester.pump(Duration(milliseconds: interval));
        }
        await finger.up(timeStamp: time);
        await tester.pumpAndSettle();

        expect(find.byType(PhotoView), findsOneWidget);
        expect(tester.getCenter(photoViewAt(0)), resting);
      });

      testWidgets('a zoomed image pans instead of closing', (tester) async {
        await openOnPhone(tester);
        await tester.tap(galleryButton('Zoom in'));
        await tester.pumpAndSettle();
        final controller = photoControllerAt(tester, 0);
        final zoomed = controller.scale!;

        await dragSlowly(tester, const Offset(0, 200));
        await tester.pumpAndSettle();

        expect(find.byType(PhotoView), findsOneWidget);
        expect(controller.scale, zoomed);
      });

      testWidgets('a mouse drag leaves the image open', (tester) async {
        await openOnPhone(tester);

        await dragSlowly(
          tester,
          const Offset(0, 200),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();

        expect(find.byType(PhotoView), findsOneWidget);
      });

      testWidgets('a two-finger pinch still zooms', (tester) async {
        await openOnPhone(tester);
        final controller = photoControllerAt(tester, 0);
        final initialScale = controller.scale!;
        final center = tester.getCenter(photoViewAt(0));
        final first = await tester.startGesture(
          center - const Offset(0, 40),
          pointer: 1,
          kind: PointerDeviceKind.touch,
        );
        final second = await tester.startGesture(
          center + const Offset(0, 40),
          pointer: 2,
          kind: PointerDeviceKind.touch,
        );

        for (var step = 0; step < 8; step++) {
          await first.moveBy(const Offset(0, -10));
          await second.moveBy(const Offset(0, 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await first.up();
        await second.up();
        await tester.pumpAndSettle();

        expect(find.byType(PhotoView), findsOneWidget);
        expect(controller.scale, greaterThan(initialScale));
      });
    });

    for (final reduceMotion in [false, true]) {
      testWidgets('stepping ${reduceMotion ? 'jumps under' : 'slides without'} '
          'Reduce Motion', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduceMotion);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pumpCooked(tester, threeImages);
        await tester.tap(thumbnail());
        await tester.pumpAndSettle();
        double page() =>
            tester.widget<PageView>(find.byType(PageView)).controller!.page!;
        expect(barText('1 of 3'), findsOneWidget);

        for (final (key, target, counter) in [
          (LogicalKeyboardKey.arrowRight, 1.0, '2 of 3'),
          (LogicalKeyboardKey.arrowLeft, 0.0, '1 of 3'),
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          if (reduceMotion) {
            expect(page(), target);
          } else {
            expect(page(), isNot(target));
            expect(tester.hasRunningAnimations, isTrue);
          }
          await tester.pumpAndSettle();
          expect(page(), target);
          expect(barText(counter), findsOneWidget);
        }
      });
    }

    testWidgets('offers arrows to a pointer', (tester) async {
      await pumpCookedOn(tester, threeImages, TargetPlatform.macOS);
      await tester.tap(thumbnail(1));
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.chevronLeft), findsOneWidget);
      expect(find.dIcon(DIcons.chevronRight), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.chevronRight));
      await tester.pumpAndSettle();
      expect(barText('3 of 3'), findsOneWidget);
    });

    testWidgets('draws arrows as white 44px rounds inset from the sides', (
      tester,
    ) async {
      await pumpCookedOn(tester, threeImages, TargetPlatform.macOS);
      await tester.tap(thumbnail(1));
      await tester.pumpAndSettle();

      final previous = find.ancestor(
        of: find.dIcon(DIcons.chevronLeft),
        matching: find.byType(DButton),
      );
      final next = find.ancestor(
        of: find.dIcon(DIcons.chevronRight),
        matching: find.byType(DButton),
      );
      final width = tester.getSize(find.byType(LightboxGallery)).width;

      for (final arrow in [previous, next]) {
        expect(tester.getSize(arrow), const Size.square(44));
        final button = tester.widget<DButton>(arrow);
        expect(button.foregroundColor, Colors.white);
        expect(button.backgroundColor, Colors.white.withValues(alpha: .12));
      }
      expect(tester.getSize(find.dIcon(DIcons.chevronLeft)).height, 16);
      expect(tester.getTopLeft(previous).dx, 16);
      expect(width - tester.getTopRight(next).dx, 16);
    });

    testWidgets('fades an arrow to a quarter at the end of the gallery', (
      tester,
    ) async {
      await pumpCookedOn(tester, threeImages, TargetPlatform.macOS);
      await tester.tap(thumbnail());
      await tester.pumpAndSettle();

      double drawnOpacity(DIconData icon) => tester
          .widgetList<Opacity>(
            find.ancestor(of: find.dIcon(icon), matching: find.byType(Opacity)),
          )
          .fold(1.0, (product, layer) => product * layer.opacity);

      expect(barText('1 of 3'), findsOneWidget);
      expect(drawnOpacity(DIcons.chevronLeft), moreOrLessEquals(.25));
      expect(drawnOpacity(DIcons.chevronRight), 1);

      await tester.tap(find.dIcon(DIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(barText('1 of 3'), findsOneWidget);
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

    group('top bar and thumbnail strip', () {
      List<LightboxImage> manyImages(int count) => [
        for (var index = 0; index < count; index++)
          parse(
            '<a class="lightbox" href="https://example.com/full-$index.png" '
            'title="photo-$index.png"><img '
            'src="https://example.com/thumb-$index.png" '
            'width="100" height="100"></a>',
          ),
      ];

      Finder thumbnailAt(int index) => find.byWidgetPredicate(
        (widget) =>
            widget is DImageThumbnail &&
            widget.semanticLabel.startsWith('Go to image ${index + 1} of'),
      );

      Future<void> useScreen(
        WidgetTester tester,
        Size size, {
        double bottomPadding = 0,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: bottomPadding);
        addTearDown(tester.view.reset);
      }

      double page(WidgetTester tester) =>
          tester.widget<PageView>(find.byType(PageView)).controller!.page!;

      testWidgets('one image names itself and has no strip or count', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester);

        expect(barText('screenshot.png'), findsOneWidget);
        expect(barText('of 1'), findsNothing);
        expect(find.byType(DImageThumbnail), findsNothing);
        expect(tester.getRect(find.byType(PageView)).bottom, 600 - 24);
      });

      testWidgets('many images count, name the current one and draw a strip', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(3), initialIndex: 1);

        expect(barText('2 of 3'), findsOneWidget);
        expect(barText('photo-1.png'), findsOneWidget);
        expect(barText('photo-0.png'), findsNothing);

        expect(find.byType(DImageThumbnail), findsNWidgets(3));
        expect(tester.getSize(thumbnailAt(0)), const Size.square(52));
        expect(
          [
            for (final index in [0, 1, 2])
              tester.widget<DImageThumbnail>(thumbnailAt(index)).selected,
          ],
          [false, true, false],
        );
        expect(
          tester.getRect(thumbnailAt(1)).left -
              tester.getRect(thumbnailAt(0)).right,
          6,
        );
        expect(tester.getBottomLeft(thumbnailAt(0)).dy, 600 - 18);
      });

      testWidgets('centres a strip that fits the window', (tester) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(3));

        final content = tester
            .getRect(thumbnailAt(0))
            .expandToInclude(tester.getRect(thumbnailAt(2)));
        expect(content.center.dx, 400);
      });

      testWidgets('a tap goes straight to that image', (tester) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(6));

        await tester.tap(thumbnailAt(5));
        await tester.pump();

        // Sliding across would have built every page in between.
        expect(page(tester), 5);
        expect(barText('6 of 6'), findsOneWidget);
        expect(barText('photo-5.png'), findsOneWidget);
        expect(fullImageAt(5), findsOneWidget);
        expect(fullImageAt(3), findsNothing);
        expect(tester.widget<DImageThumbnail>(thumbnailAt(5)).selected, isTrue);
        await tester.pumpAndSettle();
      });

      testWidgets('thumbnails use the small copy decoded for their size', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(3));

        final images = tester
            .widgetList<SiteImage>(
              find.descendant(
                of: find.byType(DImageThumbnail),
                matching: find.byType(SiteImage),
              ),
            )
            .toList();
        expect(images.map((image) => image.url), [
          for (final index in [0, 1, 2]) 'https://example.com/thumb-$index.png',
        ]);
        for (final image in images) {
          expect(image.coverDecodeSize, const Size.square(52));
          expect(image.fit, BoxFit.cover);
          expect(image.viewportAware, isTrue);
        }
      });

      testWidgets('a remote image with no small copy never fetches its full', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        const noCopy = LightboxImage(
          source: RemoteLightboxImage('https://example.com/original.png'),
          thumbnailSrc: null,
          title: 'chat.png',
          description: null,
          details: null,
          downloadHref: null,
          width: 100,
          height: 100,
          heroTag: 'no-copy',
        );
        await pumpGallery(tester, images: [...manyImages(1), noCopy]);

        expect(
          find.descendant(of: thumbnailAt(1), matching: find.byType(SiteImage)),
          findsNothing,
        );
        expect(
          find.descendant(of: thumbnailAt(1), matching: find.byType(DIcon)),
          findsOneWidget,
        );
      });

      testWidgets('a local image is decoded to cover its thumbnail', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        final directory = Directory.systemTemp.createTempSync('lightbox-strip');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/local.png')
          ..writeAsBytesSync(blankPng(width: 2000, height: 2000));
        final local = LightboxImage(
          source: LocalLightboxImage(file),
          thumbnailSrc: null,
          title: 'local.png',
          description: null,
          details: null,
          downloadHref: null,
          width: 100,
          height: 100,
          heroTag: 'local',
        );
        await pumpGallery(tester, images: [...manyImages(1), local]);

        final thumbnail = tester.widget<Image>(
          find.descendant(of: thumbnailAt(1), matching: find.byType(Image)),
        );
        expect(
          thumbnail.image,
          imageForCover(
            tester.element(thumbnailAt(1)),
            FileImage(file),
            logicalSize: const Size.square(52),
          ),
        );
      });

      testWidgets('a long gallery builds only the thumbnails near the screen', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(200), initialIndex: 100);

        final built = find.byType(DImageThumbnail).evaluate().length;
        expect(built, greaterThan(0));
        expect(built, lessThan(40));
      });

      testWidgets('opens with a far image already in view', (tester) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(200), initialIndex: 100);

        expect(tester.getCenter(thumbnailAt(100)).dx, 400);
      });

      for (final reduceMotion in [false, true]) {
        testWidgets('keeps the current thumbnail in view when paging'
            '${reduceMotion ? ' under Reduce Motion' : ''}', (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduceMotion);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          await useScreen(tester, const Size(800, 600));
          await pumpGallery(tester, images: manyImages(100));

          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .jumpToPage(60);
          await tester.pump();
          await tester.pump();
          if (reduceMotion) {
            expect(tester.getCenter(thumbnailAt(60)).dx, 400);
          }
          await tester.pumpAndSettle();

          expect(tester.getCenter(thumbnailAt(60)).dx, 400);
        });
      }

      testWidgets('stops at the ends instead of centring past them', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(100), initialIndex: 99);

        expect(tester.getRect(thumbnailAt(99)).right, 800 - 16);
      });

      testWidgets('a resized window keeps the current thumbnail in view', (
        tester,
      ) async {
        await useScreen(tester, const Size(1000, 600));
        await pumpGallery(tester, images: manyImages(100), initialIndex: 60);

        tester.view.physicalSize = const Size(500, 600);
        await tester.pump();
        await tester.pump();

        expect(tester.getCenter(thumbnailAt(60)).dx, 250);
      });

      testWidgets('hiding the controls hides the strip but keeps its room', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(3));
        final viewport = tester.getRect(find.byType(PageView));
        final strip = find.ancestor(
          of: thumbnailAt(0),
          matching: find.byType(AnimatedOpacity),
        );
        expect(tester.widget<AnimatedOpacity>(strip.first).opacity, 1);

        final photoView = find.byType(PhotoView);
        tester.widget<PhotoView>(photoView).onTapUp!(
          tester.element(photoView),
          TapUpDetails(kind: PointerDeviceKind.touch),
          const PhotoViewControllerValue(
            position: Offset.zero,
            scale: 1,
            rotation: 0,
            rotationFocusPoint: null,
          ),
        );
        await tester.pumpAndSettle();

        final opacities = tester
            .widgetList<AnimatedOpacity>(strip)
            .map((widget) => widget.opacity);
        expect(opacities, contains(0));
        expect(tester.getRect(find.byType(PageView)), viewport);

        final position = tester.getCenter(thumbnailAt(2));
        await tester.tapAt(position);
        await tester.pump();
        expect(page(tester), 0);
      });

      testWidgets(
        'a long filename stays on one line and keeps the image area',
        (tester) async {
          await useScreen(tester, const Size(390, 700));
          final long = 'a-very-long-screenshot-name-' * 8;
          final images = [
            parse(
              '<a class="lightbox" href="https://example.com/a.png" '
              'title="$long"><img src="https://example.com/a-t.png" '
              'width="100" height="100"></a>',
            ),
            ...manyImages(1),
          ];
          await pumpGallery(
            tester,
            images: images,
            platform: TargetPlatform.iOS,
          );
          final viewport = tester.getRect(find.byType(PageView));
          final name = tester.widget<RichText>(barText(long));

          expect(name.maxLines, 1);
          expect(name.overflow, TextOverflow.ellipsis);
          expect(tester.takeException(), isNull);

          await tester.tap(thumbnailAt(1));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(PageView)), viewport);
        },
      );

      testWidgets('a phone clears the home indicator below the strip', (
        tester,
      ) async {
        await useScreen(tester, const Size(390, 700), bottomPadding: 34);
        await pumpGallery(
          tester,
          images: manyImages(6),
          platform: TargetPlatform.iOS,
        );

        expect(tester.getBottomLeft(thumbnailAt(0)).dy, 700 - 34);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a single image on a phone leaves the home indicator clear', (
        tester,
      ) async {
        await useScreen(tester, const Size(390, 700), bottomPadding: 34);
        await pumpGallery(tester, platform: TargetPlatform.iOS);

        expect(tester.getRect(find.byType(PageView)).bottom, 700 - 34);
      });

      testWidgets('the size details stay in a caption without the filename', (
        tester,
      ) async {
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester);

        expect(find.text('1920×1080 234 KB'), findsOneWidget);
        // One match in the whole gallery: the caption no longer repeats it.
        expect(barText('screenshot.png'), findsOneWidget);
      });

      testWidgets('offers each thumbnail to assistive technology', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await useScreen(tester, const Size(800, 600));
        await pumpGallery(tester, images: manyImages(3), initialIndex: 1);

        final data = tester
            .getSemantics(find.bySemanticsLabel('Go to image 2 of 3'))
            .getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isSelected, Tristate.isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        semantics.dispose();
      });
    });

    testWidgets('leaves images Discourse did not lightbox alone', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p><img src="https://example.com/small.png" width="50" height="50"></p>',
      );

      expect(find.byType(LightboxThumbnail), findsNothing);
    });
  });
}

final class _RenamedImageDownloadEnvironment
    implements MediaDownloadEnvironment {
  _RenamedImageDownloadEnvironment(this.destination);

  final String destination;
  String? savedPath;

  @override
  Future<String?> chooseSavePath({
    required String suggestedName,
    ({String label, String extension})? fileType,
  }) async => destination;

  @override
  Future<void> saveBytes(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  }) async {
    File(path).writeAsBytesSync(bytes);
    savedPath = path;
  }

  @override
  Future<void> saveFile(File file, String path) =>
      throw UnsupportedError('Image downloads save from bytes');

  @override
  Future<Directory> temporaryDirectory() => throw UnimplementedError();

  @override
  Future<MediaShareOutcome> shareFile(
    File file, {
    String? filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();
}

final class _FakeImageDownloader implements LightboxImageDownloader {
  int calls = 0;
  String? url;
  String? title;
  String? siteUrl;

  @override
  Future<MediaDownloadResult> download({
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
    return const MediaDownloadSaved('screenshot.png');
  }
}
