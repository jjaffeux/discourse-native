import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/foundation/icons/d_native_icons.dart';
import 'package:discourse_native/src/shell/broken_image.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/image_grid.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cooked_html_test.dart' show pumpCookedInShell, renderedText;
import 'support/blank_png.dart';
import 'support/fakes.dart';

const _site = 'https://example.com';

String _lightbox(String name, {int width = 600, int height = 400}) =>
    '<div class="lightbox-wrapper"><a class="lightbox" '
    'href="$_site/$name.png" title="$name.png">'
    '<img src="$_site/$name-t.png" alt="$name" width="$width" '
    'height="$height"></a></div>';

SiteImageRepository _failing(SiteLifecycle lifecycle) {
  final repository = SiteImageRepository(
    credentials: FakeApiCredentialReader(),
    lifecycle: lifecycle,
    client: MockClient((_) async => http.Response('', 404)),
  );
  addTearDown(repository.dispose);
  return repository;
}

Future<void> _settle(WidgetTester tester, {int count = 1}) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (find.byType(BrokenImage).evaluate().length >= count) break;
  }
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpFailing(
  WidgetTester tester,
  Widget child, {
  double width = 800,
  int expected = 1,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lifecycle = SiteLifecycle();
  await pumpCookedInShell(
    tester,
    '',
    lifecycle: lifecycle,
    siteImages: _failing(lifecycle),
    child: child,
  );
  await _settle(tester, count: expected);
}

Future<void> _pumpCooked(
  WidgetTester tester,
  String source, {
  double width = 800,
  int expected = 1,
}) => _pumpFailing(
  tester,
  CookedHtml(html: source, siteUrl: _site, buildAsync: false),
  width: width,
  expected: expected,
);

void main() {
  group('the drawing', () {
    Future<void> pumpAlone(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('is a dashed box with the image icon and the words', (
      tester,
    ) async {
      await pumpAlone(
        tester,
        const Center(
          child: SizedBox(width: 300, height: 200, child: BrokenImage()),
        ),
      );

      final card = tester.widget<DCard>(find.byType(DCard));
      expect(card.dashedBorder, isTrue);
      expect(card.borderRadius, BorderRadius.circular(8));
      final context = tester.element(find.byType(BrokenImage));
      final tokens = DTokens.of(context);
      expect(card.backgroundColor, tokens.raisedBackground);

      final icon = tester.widget<DIcon>(find.byType(DIcon));
      expect(icon.icon, DNativeIcons.image);
      expect(icon.size, 18);
      expect(icon.color, tokens.mutedForeground);

      final text = tester.widget<Text>(find.text('Broken image'));
      expect(text.style?.fontSize, 12.5);
      expect(text.style?.color, tokens.mutedForeground);
      expect(
        tester.getTopLeft(find.text('Broken image')).dy -
            tester.getBottomLeft(find.byType(DIcon)).dy,
        6,
      );
    });

    testWidgets('centres its content in the slot it fills', (tester) async {
      await pumpAlone(
        tester,
        const Center(
          child: SizedBox(width: 300, height: 200, child: BrokenImage()),
        ),
      );

      expect(tester.getSize(find.byType(DCard)), const Size(300, 200));
      final box = tester.getCenter(find.byType(DCard));
      expect(tester.getCenter(find.text('Broken image')).dx, box.dx);
      final top = tester.getTopLeft(find.byType(DIcon)).dy;
      final bottom = tester.getBottomLeft(find.text('Broken image')).dy;
      expect((top + bottom) / 2, moreOrLessEquals(box.dy, epsilon: .5));
    });

    testWidgets('gives a slot with no size a capped 4:3 box', (tester) async {
      await pumpAlone(
        tester,
        const SingleChildScrollView(
          child: Align(alignment: Alignment.topLeft, child: BrokenImage()),
        ),
      );

      expect(tester.getSize(find.byType(DCard)), const Size(420, 315));
    });

    testWidgets('fits a tile too small for its words', (tester) async {
      await pumpAlone(
        tester,
        const Center(
          child: SizedBox(width: 40, height: 30, child: BrokenImage()),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text('Broken image')).width,
        lessThanOrEqualTo(40),
      );
    });

    testWidgets('announces itself as an image', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpAlone(
        tester,
        const Center(
          child: SizedBox(width: 300, height: 200, child: BrokenImage()),
        ),
      );

      expect(
        tester.getSemantics(find.byType(BrokenImage)),
        matchesSemantics(isImage: true, label: 'Broken image'),
      );
      semantics.dispose();
    });
  });

  group('a post image that fails to load', () {
    testWidgets('fills a single image at its declared size', (tester) async {
      await _pumpCooked(tester, _lightbox('one', width: 600, height: 400));

      expect(find.byType(BrokenImage), findsOneWidget);
      expect(tester.getSize(find.byType(BrokenImage)), const Size(600, 400));
      expect(find.text('Broken image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is no longer a button that opens the image', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCooked(tester, _lightbox('one'));

      expect(find.byType(DImagePreview), findsNothing);
      await tester.tap(find.text('Broken image'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(LightboxGallery), findsNothing);
      expect(find.bySemanticsLabel('Broken image'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Open image')), findsNothing);
      semantics.dispose();
    });

    testWidgets('keeps the image button when the picture has not failed', (
      tester,
    ) async {
      final lifecycle = SiteLifecycle();
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: lifecycle,
        client: MockClient(
          (_) async => http.Response.bytes(blankPng(width: 8, height: 8), 200),
        ),
      );
      addTearDown(repository.dispose);
      await pumpCookedInShell(
        tester,
        '',
        lifecycle: lifecycle,
        siteImages: repository,
        child: CookedHtml(
          html: _lightbox('one'),
          siteUrl: _site,
          buildAsync: false,
        ),
      );
      await _settle(tester);

      expect(find.byType(DImagePreview), findsOneWidget);
      expect(find.byType(BrokenImage), findsNothing);
    });

    testWidgets('squares off inside a grid of lightbox images', (tester) async {
      final grid =
          '<div class="d-image-grid">'
          '${_lightbox('a')}${_lightbox('b')}${_lightbox('c')}'
          '</div>';
      await _pumpCooked(tester, grid, expected: 3);

      expect(find.byType(ImageGridMosaic), findsOneWidget);
      expect(find.byType(BrokenImage), findsNWidgets(3));
      for (final card in tester.widgetList<DCard>(find.byType(DCard))) {
        expect(card.borderRadius, BorderRadius.zero);
      }
      expect(find.byType(DImagePreview), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fills a plain image inside a grid', (tester) async {
      const grid =
          '<div class="d-image-grid">'
          '<img src="$_site/a.png" alt="A" width="600" height="400">'
          '<img src="$_site/b.png" alt="B" width="600" height="400">'
          '</div>';
      await _pumpCooked(tester, grid, expected: 2);

      expect(find.byType(BrokenImage), findsNWidgets(2));
      for (final tile in find.byType(BrokenImage).evaluate()) {
        expect((tile.renderObject! as RenderBox).size.width, greaterThan(100));
      }
    });

    testWidgets('draws in a carousel slide', (tester) async {
      final grid =
          '<div class="d-image-grid" data-mode="carousel">'
          '${_lightbox('a')}${_lightbox('b')}'
          '</div>';
      await _pumpCooked(tester, grid);

      expect(find.byType(ImageGridCarousel), findsOneWidget);
      expect(find.byType(BrokenImage), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('replaces a plain image and is announced', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCooked(
        tester,
        '<p><img src="$_site/one.png" alt="A chart" width="600" '
        'height="400"></p>',
      );

      expect(find.byType(BrokenImage), findsOneWidget);
      expect(renderedText('A chart'), findsNothing);
      expect(find.bySemanticsLabel('Broken image'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('draws a box for an image with no declared size', (
      tester,
    ) async {
      await _pumpCooked(
        tester,
        '<p><img src="$_site/one.png" alt="Sizeless"></p>',
      );

      expect(find.byType(BrokenImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at text size still reads as its alt text', (tester) async {
      await _pumpFailing(
        tester,
        const CookedHtml(
          html:
              '<p>Before <img src="$_site/icon.png" alt="Icon" width="20" '
              'height="20"> after</p>',
          siteUrl: _site,
          buildAsync: false,
        ),
        expected: 0,
      );

      expect(find.byType(BrokenImage), findsNothing);
      expect(find.text('Icon'), findsOneWidget);
    });

    testWidgets('as an avatar keeps the avatar fallback', (tester) async {
      await _pumpFailing(
        tester,
        const CookedHtml(
          html:
              '<p><img class="avatar" src="$_site/sam.png" alt="Sam" '
              'width="64" height="64"></p>',
          siteUrl: _site,
          buildAsync: false,
        ),
        expected: 0,
      );

      expect(find.byType(BrokenImage), findsNothing);
      expect(find.byType(DAvatarFallback), findsOneWidget);
    });
  });

  testWidgets('a failed page in the full-screen viewer draws the same state', (
    tester,
  ) async {
    final image = LightboxImage.from(
      html.parse(_lightbox('one')).querySelector('a.lightbox')!,
    )!;
    await _pumpFailing(
      tester,
      SizedBox(
        height: 800,
        child: LightboxGallery(
          images: [image],
          initialIndex: 0,
          siteUrl: _site,
        ),
      ),
    );

    expect(find.byType(BrokenImage), findsOneWidget);
    expect(tester.getSize(find.byType(BrokenImage)), const Size(420, 315));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed animated image offers no playback controls', (
    tester,
  ) async {
    final lifecycle = SiteLifecycle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiteImage(
            url: '$_site/moving.gif',
            siteUrl: _site,
            repository: _failing(lifecycle),
            gifPlaybackControls: true,
            errorBuilder: (_, _, _) => const BrokenImage(),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byType(BrokenImage), findsOneWidget);
    expect(find.byKey(const ValueKey('gif-playback-toggle')), findsNothing);
  });
}
