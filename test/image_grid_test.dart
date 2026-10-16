import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/image_grid.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cooked_html_test.dart' show onePixelGif, pumpCooked, pumpCookedInShell;
import 'support/blank_png.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

String item(String name, {int width = 600, int height = 400}) =>
    '<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/$name.png" title="$name.png">'
    '<img src="https://example.com/$name-t.png" width="$width" height="$height">'
    '<div class="meta"><span class="informations">1800×1200 240 KB</span></div>'
    '</a></div>';

String grid(int count, {String? mode, int width = 600, int height = 400}) {
  final attrs = mode == null ? '' : ' data-mode="$mode"';
  return '<div class="d-image-grid"$attrs>'
      '${[for (var i = 0; i < count; i++) item('img$i', width: width, height: height)].join()}'
      '</div>';
}

dom.Element gridIn(String source) =>
    html.parse(source).querySelector('div.d-image-grid')!;

ImageGridData parse(String source) => ImageGridData.from(gridIn(source));

Future<void> pumpGrid(
  WidgetTester tester,
  String source, {
  double width = 800,
  double devicePixelRatio = 1,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  await pumpCooked(tester, source);
  await tester.pumpAndSettle();
}

Future<void> pumpHydrationGrid(
  WidgetTester tester,
  String source,
  List<Uri> requests, {
  Widget Function(Widget grid)? wrap,
  double devicePixelRatio = 1,
}) async {
  final deterministicLoading = WidgetFactory.debugDeterministicLoadingWidget;
  WidgetFactory.debugDeterministicLoadingWidget = true;
  addTearDown(() {
    WidgetFactory.debugDeterministicLoadingWidget = deterministicLoading;
  });
  tester.view.physicalSize = Size(
    800 * devicePixelRatio,
    600 * devicePixelRatio,
  );
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  final bytes = blankPng(width: 8, height: 8);
  final lifecycle = SiteLifecycle();
  final repository = SiteImageRepository(
    credentials: FakeApiCredentialReader(),
    lifecycle: lifecycle,
    client: MockClient((request) async {
      requests.add(request.url);
      return http.Response.bytes(
        request.url.path.endsWith('.gif') ? onePixelGif : bytes,
        200,
      );
    }),
  );
  // Parsing is synchronous so the fixture isolates mounting and repository
  // submissions rather than the HTML package's background parse scheduling.
  final cooked = CookedHtml(
    html: source,
    siteUrl: 'https://example.com',
    buildAsync: false,
  );
  await pumpCookedInShell(
    tester,
    '',
    lifecycle: lifecycle,
    siteImages: repository,
    child: wrap?.call(cooked) ?? cooked,
  );
}

Finder gridImage(String name) => find.byWidgetPredicate(
  (widget) => widget is SiteImage && widget.url.endsWith('/$name'),
);

class _KeptAliveGrid extends StatefulWidget {
  const _KeptAliveGrid({required this.child});

  final Widget child;

  @override
  State<_KeptAliveGrid> createState() => _KeptAliveGridState();
}

class _KeptAliveGridState extends State<_KeptAliveGrid>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

void main() {
  group('ImageGridData', () {
    test('reads the mode, defaulting to the mosaic', () {
      expect(parse(grid(3)).mode, ImageGridMode.grid);
      expect(parse(grid(3, mode: 'grid')).mode, ImageGridMode.grid);
      expect(parse(grid(3, mode: 'carousel')).mode, ImageGridMode.carousel);
    });

    test('takes items out of the paragraphs markdown wrapped them in', () {
      final data = parse(
        '<div class="d-image-grid"><p>${item('a')}<br>${item('b')}</p>${item('c')}</div>',
      );

      expect(data.items, hasLength(3));
      expect(data.items.map((i) => i.image!.title), [
        'a.png',
        'b.png',
        'c.png',
      ]);
    });

    test('keeps grid items that never got a lightbox', () {
      final data = parse(
        '<div class="d-image-grid">${item('big')}<img src="https://example.com/tiny.png" width="50" height="50"></div>',
      );

      expect(data.items, hasLength(2));
      expect(data.items[1].isLightbox, isFalse);
      expect(data.items[1].plainSrc, 'https://example.com/tiny.png');
    });

    test('keeps a plain image description for assistive technology', () {
      final data = parse(
        '<div class="d-image-grid">${item('big')}'
        '<img src="https://example.com/tiny.png" alt="A tiny diagram" width="50" height="50">'
        '</div>',
      );

      expect(data.items.last.description, 'A tiny diagram');
    });

    test('measures an item by the size the markup declares', () {
      final data = parse(grid(1, width: 600, height: 400));

      expect(data.items.single.mosaicHeightUnit, closeTo(400 / 600, 0.0001));
      expect(data.items.single.carouselAspectRatio, closeTo(600 / 400, 0.0001));
    });

    test('bounds hostile declared and intrinsic dimensions', () {
      ImageGridItem withDimensions(String width, String height) => parse(
        '<div class="d-image-grid"><img src="image.png" '
        'width="$width" height="$height"></div>',
      ).items.single;

      for (final pair in const [
        ('0', '1'),
        ('-1', '1'),
        ('NaN', '1'),
        ('Infinity', '1'),
      ]) {
        final image = withDimensions(pair.$1, pair.$2);
        expect(image.declared, isNull, reason: '${pair.$1}x${pair.$2}');
        expect(image.mosaicHeightUnit, 1, reason: '${pair.$1}x${pair.$2}');
      }

      expect(withDimensions('1e308', '1').carouselAspectRatio, 4);
      expect(withDimensions('1', '1e308').carouselAspectRatio, 0.25);
      expect(
        withDimensions('1e308', '1e308').declared,
        const Size(10000, 10000),
      );

      final invalidIntrinsic = parse(
        '<div class="d-image-grid" data-mode="carousel">'
        '<div><img src="image.png"><span class="informations">'
        'NaN×1 1 MB</span></div></div>',
      );
      expect(invalidIntrinsic.items.single.intrinsic, isNull);
      expect(
        invalidIntrinsic.items.single.carouselAspectRatio,
        closeTo(4 / 3, 0.0001),
      );
    });

    test('counts anything unmeasurable as square, the way columns.js does', () {
      final data = parse(
        '<div class="d-image-grid"><blockquote>not an image</blockquote></div>',
      );

      expect(data.items.single.mosaicHeightUnit, 1);
    });

    test('falls back to the uploaded size, then to 4:3, for a carousel', () {
      final noAttributes = parse(
        '<div class="d-image-grid" data-mode="carousel">'
        '<div class="lightbox-wrapper"><a class="lightbox" href="a.png">'
        '<img src="t.png"><div class="meta"><span class="informations">1800×1200 1 MB</span></div>'
        '</a></div></div>',
      );
      expect(
        noAttributes.items.single.carouselAspectRatio,
        closeTo(1800 / 1200, 0.0001),
      );

      final nothing = parse(
        '<div class="d-image-grid" data-mode="carousel">'
        '<div class="lightbox-wrapper"><a class="lightbox" href="a.png"><img src="t.png"></a></div>'
        '</div>',
      );
      expect(
        nothing.items.single.carouselAspectRatio,
        closeTo(1024 / 768, 0.0001),
      );
    });

    test('a carousel collects images, not children', () {
      final data = parse(
        '<div class="d-image-grid" data-mode="carousel">'
        '<p>${item('a')}</p>'
        '<img src="e.png" class="emoji">'
        '<aside class="onebox"><img src="icon.png" class="thumbnail"></aside>'
        '${item('b')}'
        '</div>',
      );

      expect(data.items.map((i) => i.image?.title), ['a.png', 'b.png']);
    });
  });

  group('ImageGridMosaic.distribute', () {
    test('sends each item to the shortest column so far', () {
      expect(ImageGridMosaic.distribute([1, 1, 1], 3), [
        [0],
        [1],
        [2],
      ]);
    });

    test('lets a short item share a column with another short one', () {
      expect(ImageGridMosaic.distribute([3, 1, 1, 1], 3), [
        [0],
        [1, 3],
        [2],
      ]);
    });

    test('ties go to the leftmost column, which keeps it deterministic', () {
      expect(ImageGridMosaic.distribute([1, 1], 2), [
        [0],
        [1],
      ]);
    });

    test('keeps written order within a column', () {
      final columns = ImageGridMosaic.distribute([1, 1, 1, 1, 1, 1], 2);

      for (final column in columns) {
        expect(column, orderedEquals([...column]..sort()));
      }
    });
  });

  group('the mosaic', () {
    testWidgets(
      'a 100-image cooked grid hydrates only its initial cache region',
      (tester) async {
        final requests = <Uri>[];
        await pumpHydrationGrid(tester, grid(100), requests);
        expect(find.byType(ImageGridMosaic), findsOneWidget);
        expect(
          tester
              .widget<ImageGridMosaic>(find.byType(ImageGridMosaic))
              .data
              .items,
          hasLength(100),
        );

        final mounted = tester.widgetList<SiteImage>(find.byType(SiteImage));
        debugPrint(
          'F07 initial mounted=${mounted.length} requests=${requests.length}',
        );
        expect(mounted.length, inInclusiveRange(9, 21));
        expect(requests.length, mounted.length);
        expect(requests.any((url) => url.path == '/img99-t.png'), isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('jumping hydrates the tail without changing grid extent', (
      tester,
    ) async {
      final requests = <Uri>[];
      await pumpHydrationGrid(tester, grid(100), requests);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      final extent = position.maxScrollExtent;
      final size = tester.getSize(find.byType(ImageGridMosaic));
      final first = tester.element(gridImage('img0-t.png'));

      final initialRequests = requests.length;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(requests.length, greaterThan(initialRequests));
      expect(gridImage('img99-t.png'), findsNothing);

      position.jumpTo(extent);
      await tester.pumpAndSettle();

      expect(gridImage('img99-t.png'), findsOneWidget);
      expect(gridImage('img45-t.png'), findsNothing);
      expect(tester.element(gridImage('img0-t.png')), same(first));
      expect(tester.getSize(find.byType(ImageGridMosaic)), size);
      expect(position.maxScrollExtent, extent);
      final visitedRequests = requests.length;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(requests.length, visitedRequests);
      expect(tester.element(gridImage('img0-t.png')), same(first));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a hydrated thumbnail opens every image in original DOM order',
      (tester) async {
        final requests = <Uri>[];
        await pumpHydrationGrid(tester, grid(100), requests);
        expect(gridImage('img99-t.png'), findsNothing);
        final tile = find.ancestor(
          of: gridImage('img3-t.png'),
          matching: find.byType(ImageGridTile),
        );
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(InkWell)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        try {
          final gallery = tester.widget<LightboxGallery>(
            find.byType(LightboxGallery),
          );
          expect(gallery.initialIndex, 3);
          expect(gallery.images.map((image) => image.title), [
            for (var index = 0; index < 100; index++) 'img$index.png',
          ]);
          expect(find.text('4 / 100'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pump();
          expect(find.text('5 / 100'), findsOneWidget);
          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .jumpToPage(99);
          await tester.pump();
          await tester.pump();
          expect(find.text('100 / 100'), findsOneWidget);
          expect(find.text('img99.png'), findsOneWidget);
          expect(requests.any((url) => url.path == '/img99.png'), isTrue);
        } finally {
          Navigator.of(tester.element(find.byType(LightboxGallery))).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pump();
        }
      },
    );

    testWidgets('newly hydrated plain images keep srcset and GIF pause state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final requests = <Uri>[];
        final source = grid(100)
            .replaceFirst(
              item('img99'),
              '<img src="https://example.com/plain.png" width="600" height="400" '
              'srcset="https://example.com/plain.png, https://example.com/plain_2x.png 2x" '
              'alt="The final diagram">',
            )
            .replaceFirst(
              item('img0'),
              item('img0').replaceAll('.png', '.gif'),
            );
        await pumpHydrationGrid(tester, source, requests, devicePixelRatio: 2);
        await tester.tap(find.bySemanticsLabel('Pause GIF'));
        await tester.pump();
        final gif = tester.element(gridImage('img0-t.gif'));
        expect(find.bySemanticsLabel('Play GIF'), findsOneWidget);
        expect(gridImage('plain.png'), findsNothing);
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(gridImage('plain_2x.png'), findsOneWidget);
        final plain = tester.widget<SiteImage>(gridImage('plain_2x.png'));
        expect(plain.cacheWidth, lessThanOrEqualTo(600));
        expect(plain.gifPlaybackControls, isTrue);
        expect(find.bySemanticsLabel('The final diagram'), findsOneWidget);
        position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.element(gridImage('img0-t.gif')), same(gif));
        expect(find.bySemanticsLabel('Play GIF'), findsOneWidget);
        expect(find.bySemanticsLabel('Pause GIF'), findsNothing);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'ancestor layout shifts and view resizing hydrate new regions',
      (tester) async {
        final prefix = ValueNotifier<double>(2000);
        addTearDown(prefix.dispose);
        final requests = <Uri>[];
        await pumpHydrationGrid(
          tester,
          grid(100),
          requests,
          wrap: (cooked) => ValueListenableBuilder<double>(
            valueListenable: prefix,
            child: RepaintBoundary(child: cooked),
            builder: (context, height, child) => Column(
              children: [
                SizedBox(height: height),
                child!,
              ],
            ),
          ),
        );
        expect(requests, isEmpty);
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        expect(position.pixels, 0);
        prefix.value = 0;
        await tester.pumpAndSettle();
        expect(gridImage('img0-t.png'), findsOneWidget);
        expect(position.pixels, 0);
        final initialRequests = requests.length;
        tester.view.physicalSize = const Size(800, 1200);
        await tester.pumpAndSettle();
        expect(requests.length, greaterThan(initialRequests));
        expect(gridImage('img99-t.png'), findsNothing);
      },
    );

    testWidgets(
      'nested viewports and replaced scroll positions bound hydration',
      (tester) async {
        final inner = ScrollController();
        final replacement = ScrollController(initialScrollOffset: 4000);
        addTearDown(inner.dispose);
        addTearDown(replacement.dispose);
        final controller = ValueNotifier<ScrollController>(inner);
        addTearDown(controller.dispose);
        final requests = <Uri>[];
        await pumpHydrationGrid(
          tester,
          grid(100),
          requests,
          wrap: (cooked) => Column(
            children: [
              const SizedBox(height: 900),
              SizedBox(
                height: 300,
                child: ValueListenableBuilder<ScrollController>(
                  valueListenable: controller,
                  child: cooked,
                  builder: (context, scroll, child) => SingleChildScrollView(
                    controller: scroll,
                    physics: identical(scroll, inner)
                        ? const ClampingScrollPhysics()
                        : const BouncingScrollPhysics(),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        );
        expect(
          requests,
          isEmpty,
          reason: 'the inner viewport is entirely clipped',
        );
        final outer = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        outer.jumpTo(outer.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(requests.length, inInclusiveRange(3, 12));
        expect(gridImage('img60-t.png'), findsNothing);
        final originalPosition = inner.position;
        controller.value = replacement;
        await tester.pump();
        expect(replacement.position, isNot(same(originalPosition)));
        replacement.jumpTo(4000);
        await tester.pumpAndSettle();
        expect(gridImage('img69-t.png'), findsOneWidget);
        expect(gridImage('img99-t.png'), findsNothing);
      },
    );

    testWidgets('unvisited mixed text remains registered for selection', (
      tester,
    ) async {
      final requests = <Uri>[];
      String? selected;
      final source = grid(100).replaceFirst(
        item('img99'),
        '<blockquote>Selectable tail text</blockquote>',
      );
      await pumpHydrationGrid(
        tester,
        source,
        requests,
        wrap: (cooked) => SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: cooked,
        ),
      );
      final text = find.text('Selectable tail text', findRichText: true);
      expect(text, findsOneWidget);
      final element = tester.element(text);
      final selection = tester.state<SelectionAreaState>(
        find.byType(SelectionArea),
      );
      selection.selectableRegion.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(selected, contains('Selectable tail text'));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.element(text), same(element));
      expect(selected, contains('Selectable tail text'));
    });

    testWidgets('offstage grids defer hydration until they are shown', (
      tester,
    ) async {
      final hidden = ValueNotifier<bool>(true);
      addTearDown(hidden.dispose);
      final requests = <Uri>[];
      await pumpHydrationGrid(
        tester,
        grid(100),
        requests,
        wrap: (cooked) => ValueListenableBuilder<bool>(
          valueListenable: hidden,
          child: cooked,
          builder: (context, offstage, child) =>
              Offstage(offstage: offstage, child: child),
        ),
      );
      expect(requests, isEmpty);
      hidden.value = false;
      await tester.pumpAndSettle();
      expect(requests.length, inInclusiveRange(9, 21));
    });

    testWidgets(
      'sliver-kept-alive grids do not hydrate stale viewport geometry',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final requests = <Uri>[];
        await pumpHydrationGrid(
          tester,
          grid(100),
          requests,
          wrap: (cooked) => SizedBox(
            height: 600,
            child: ListView.builder(
              controller: scroll,
              itemCount: 2,
              itemBuilder: (context, index) => index == 0
                  ? _KeptAliveGrid(child: cooked)
                  : const SizedBox(height: 2000),
            ),
          ),
        );
        final initialRequests = requests.length;
        final first = tester.element(gridImage('img0-t.png'));
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          find.byType(ImageGridMosaic, skipOffstage: false),
          findsOneWidget,
        );
        expect(requests.length, initialRequests);
        await tester.pump();
        expect(requests.length, initialRequests);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.element(gridImage('img0-t.png')), same(first));
        expect(requests.length, initialRequests);
      },
    );

    testWidgets(
      'edited grids hydrate new DOM identities after a complete grid',
      (tester) async {
        final count = ValueNotifier<int>(3);
        addTearDown(count.dispose);
        final requests = <Uri>[];
        await pumpHydrationGrid(
          tester,
          '',
          requests,
          wrap: (_) => ValueListenableBuilder<int>(
            valueListenable: count,
            builder: (context, value, child) => ImageGridMosaic(
              data: parse(grid(value).replaceAll('/img', '/edited$value')),
              siteUrl: 'https://example.com',
            ),
          ),
        );
        expect(find.byType(SiteImage), findsNWidgets(3));
        final originalState = tester.state(find.byType(ImageGridMosaic));
        count.value = 100;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ImageGridMosaic)), same(originalState));
        expect(gridImage('edited1000-t.png'), findsOneWidget);
        expect(gridImage('edited10099-t.png'), findsNothing);
        expect(
          find.byType(SiteImage).evaluate().length,
          inInclusiveRange(9, 21),
        );
      },
    );

    testWidgets('draws a grid instead of a stack of images', (tester) async {
      await pumpGrid(tester, grid(3));

      expect(find.byType(ImageGridMosaic), findsOneWidget);
      expect(find.byType(ImageGridTile), findsNWidgets(3));
    });

    testWidgets('exposes plain-image alt text and bounds its decode width', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await pumpGrid(
        tester,
        '<div class="d-image-grid">${item('big')}'
        '<img src="https://example.com/tiny.png" alt="A tiny diagram" width="50" height="50">'
        '</div>',
        width: 500,
      );

      expect(find.bySemanticsLabel('A tiny diagram'), findsOneWidget);
      final provider = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<ResizeImage>()
          .singleWhere(
            (provider) => (provider.imageProvider as NetworkImage).url.contains(
              'tiny.png',
            ),
          );
      expect(provider.width, lessThanOrEqualTo(500));
      expect(provider.allowUpscaling, isFalse);
      semantics.dispose();
    });

    testWidgets('draws a plain image from its srcset', (tester) async {
      await pumpGrid(
        tester,
        '<div class="d-image-grid">${item('big')}'
        '<img src="https://example.com/plain.png" width="300" height="200" '
        'srcset="https://example.com/plain.png, '
        'https://example.com/plain_450.png 1.5x, '
        'https://example.com/plain_600.png 2x">'
        '</div>',
        devicePixelRatio: 2,
      );

      final urls = tester
          .widgetList<SiteImage>(
            find.descendant(
              of: find.byType(ImageGridTile),
              matching: find.byType(SiteImage),
            ),
          )
          .map((image) => image.url);
      expect(
        urls,
        unorderedEquals([
          'https://example.com/big-t.png',
          'https://example.com/plain_600.png',
        ]),
      );
    });

    testWidgets('uses three columns when there is room', (tester) async {
      await pumpGrid(tester, grid(3), width: 800);

      final tiles = tester.widgetList<ImageGridTile>(
        find.byType(ImageGridTile),
      );
      expect(tiles, hasLength(3));
      final tops = find
          .byType(ImageGridTile)
          .evaluate()
          .map(
            (e) =>
                tester.getTopLeft(find.byWidget(e.widget as ImageGridTile)).dy,
          );
      expect(tops.toSet(), hasLength(1));
    });

    testWidgets('drops to two columns when the post is narrow', (tester) async {
      await pumpGrid(tester, grid(3), width: 500);

      final rects = find
          .byType(ImageGridTile)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget as ImageGridTile)))
          .toList();
      expect(rects.map((r) => r.left).toSet(), hasLength(2));
      expect(rects.map((r) => r.top).toSet(), hasLength(2));
    });

    testWidgets('uses two columns for both two and four items', (tester) async {
      for (final count in [2, 4]) {
        await pumpGrid(tester, grid(count), width: 900);

        final lefts = find
            .byType(ImageGridTile)
            .evaluate()
            .map(
              (e) => tester
                  .getTopLeft(find.byWidget(e.widget as ImageGridTile))
                  .dx,
            )
            .toSet();
        expect(lefts, hasLength(2), reason: '$count items');
      }
    });

    testWidgets('ends every column at the same height', (tester) async {
      await pumpGrid(
        tester,
        '<div class="d-image-grid">'
        '${item('tall', width: 400, height: 900)}'
        '${item('wide', width: 900, height: 300)}'
        '${item('square', width: 500, height: 500)}'
        '</div>',
        width: 800,
      );

      final rects = find
          .byType(ImageGridTile)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget as ImageGridTile)))
          .toList();
      final columnBottoms = <double, double>{};
      for (final rect in rects) {
        columnBottoms[rect.left] = (columnBottoms[rect.left] ?? 0) > rect.bottom
            ? columnBottoms[rect.left]!
            : rect.bottom;
      }

      expect(columnBottoms.values.toSet(), hasLength(1));
    });

    // A grid wraps whatever Markdown it was given, and a quote or an onebox
    // among the images is taller than the square it was counted as.
    testWidgets('clips an item taller than its tile instead of overflowing', (
      tester,
    ) async {
      await pumpGrid(
        tester,
        '<div class="d-image-grid">${item('a')}${item('b')}'
        '<blockquote><p>${'A quoted line that wraps. ' * 30}</p></blockquote>'
        '</div>',
        width: 400,
      );

      expect(tester.takeException(), isNull);
      final quote = find.textContaining('A quoted line', findRichText: true);
      final tile = tester.getRect(
        find.ancestor(of: quote, matching: find.byType(ImageGridTile)),
      );
      expect(
        tile.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(ImageGridMosaic)).bottom),
      );
      // Laid out at its own height rather than squeezed into the tile.
      expect(tester.getSize(quote).height, greaterThan(tile.height));
    });

    testWidgets('leaves a grid of one image stacked', (tester) async {
      await pumpGrid(tester, grid(1));

      expect(find.byType(ImageGridMosaic), findsNothing);
      expect(find.byType(LightboxThumbnail), findsOneWidget);
    });

    testWidgets('opens the gallery in written order, not column order', (
      tester,
    ) async {
      // Unlike the web client, this renderer does not reorder the DOM nodes.
      await pumpGrid(tester, grid(6), width: 800);

      await tester.tap(
        find.descendant(
          of: find.byType(ImageGridTile).at(1),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4 / 6'), findsOneWidget);
      expect(find.text('img3.png'), findsOneWidget);
    });
  });

  group('the carousel', () {
    testWidgets('changing slides does not recenter the outer topic scroll', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final outer = ScrollController();
      addTearDown(outer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: ListView(
              controller: outer,
              children: [
                const SizedBox(height: 500),
                ImageGridCarousel(data: parse(grid(3, mode: 'carousel'))),
                const SizedBox(height: 500),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      outer.jumpTo(450);
      await tester.pump();
      final before = outer.offset;

      await tester.tap(find.byKey(const ValueKey('image-carousel-next')));
      await tester.pumpAndSettle();

      expect(outer.offset, before);
    });

    testWidgets('draws a track instead of a mosaic', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      expect(find.byType(ImageGridCarousel), findsOneWidget);
      expect(find.byType(ImageGridMosaic), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('the next control advances one image', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      await tester.tap(find.dIcon(DIcons.chevronRight));
      await tester.pumpAndSettle();

      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(controller.page! % 3, 1);
    });

    testWidgets('controls use visible bounds and explicit semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      for (final key in const [
        ValueKey('image-carousel-previous'),
        ValueKey('image-carousel-next'),
      ]) {
        final target = find.byKey(key);
        final size = tester.getSize(target);
        expect(size.width, 30);
        expect(size.height, 30);
        final data = tester.getSemantics(target).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      }

      expect(find.bySemanticsLabel('Previous image'), findsOneWidget);
      expect(find.bySemanticsLabel('Next image'), findsOneWidget);

      for (var image = 1; image <= 3; image++) {
        final target = find.byKey(ValueKey('image-carousel-dot-$image'));
        expect(
          tester.getSize(target),
          Size(
            image == 1 ? DCarouselDot.selectedWidth : DCarouselDot.diameter,
            DCarouselDot.diameter,
          ),
        );
        final bounds = tester.getRect(target);
        for (final outside in [
          bounds.topCenter - const Offset(0, 1),
          bounds.bottomCenter + const Offset(0, 1),
        ]) {
          await tester.tapAt(outside);
          await tester.pumpAndSettle();
          expect(
            tester.widget<PageView>(find.byType(PageView)).controller!.page! %
                3,
            0,
          );
        }
        final data = tester.getSemantics(target).getSemanticsData();
        expect(data.label, 'Go to image $image of 3');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(
          data.flagsCollection.isSelected,
          image == 1 ? Tristate.isTrue : Tristate.isFalse,
        );
      }

      semantics.dispose();
    });

    testWidgets('dot buttons activate with Enter and Space', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;

      final second = tester.widget<DCarouselDot>(
        find.byKey(const ValueKey('image-carousel-dot-2')),
      );
      second.focusNode!.requestFocus();
      await tester.pump();
      expect(second.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.page! % 3, 1);

      final third = tester.widget<DCarouselDot>(
        find.byKey(const ValueKey('image-carousel-dot-3')),
      );
      third.focusNode!.requestFocus();
      await tester.pump();
      expect(third.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.page! % 3, 2);
    });

    testWidgets('ten natural dot targets fit a narrow carousel', (
      tester,
    ) async {
      await pumpGrid(tester, grid(10, mode: 'carousel'), width: 320);

      expect(tester.takeException(), isNull);
      for (var image = 1; image <= 10; image++) {
        expect(
          tester.getSize(find.byKey(ValueKey('image-carousel-dot-$image'))),
          Size(
            image == 1 ? DCarouselDot.selectedWidth : DCarouselDot.diameter,
            DCarouselDot.diameter,
          ),
        );
      }
    });

    testWidgets('wraps around at both ends', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;

      await tester.tap(find.dIcon(DIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(controller.page! % 3, 2);

      await tester.tap(find.dIcon(DIcons.chevronRight));
      await tester.pumpAndSettle();
      expect(controller.page! % 3, 0);
    });

    testWidgets('counts instead of dotting once there are too many', (
      tester,
    ) async {
      await pumpGrid(tester, grid(10, mode: 'carousel'));
      expect(find.text('1 / 10'), findsNothing);

      await pumpGrid(tester, grid(11, mode: 'carousel'));
      expect(find.text('1 / 11'), findsOneWidget);
    });

    testWidgets('offers no controls for a single image', (tester) async {
      await pumpGrid(tester, grid(1, mode: 'carousel'));

      expect(find.byType(ImageGridCarousel), findsOneWidget);
      expect(find.dIcon(DIcons.chevronRight), findsNothing);
    });

    testWidgets('clamps the page when an edited grid removes images', (
      tester,
    ) async {
      Future<void> pump(int count) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ImageGridCarousel(
                data: parse(grid(count, mode: 'carousel')),
              ),
            ),
          ),
        ),
      );

      await pump(3);
      final originalController = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      originalController.jumpToPage(2);
      await tester.pump();
      expect(originalController.page, 2);

      await pump(1);
      await tester.pump();

      final updatedController = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(updatedController, isNot(same(originalController)));
      expect(updatedController.page, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('moves on the arrow keys once the track has focus', (
      tester,
    ) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      final node = Focus.of(
        tester.element(find.byType(PageView)),
        scopeOk: true,
      );
      node.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(controller.page! % 3, 1);
    });

    testWidgets('opens the gallery from a slide', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      await tester.tap(
        find.descendant(
          of: find.byType(ImageGridTile).first,
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
    });
  });
}
