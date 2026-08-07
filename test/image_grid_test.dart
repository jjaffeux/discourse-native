import 'package:discourse_native/src/shell/image_grid.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'cooked_html_test.dart' show pumpCooked;
import 'support/finders.dart';

/// One `[grid]` item as Discourse cooks it: the lightbox wrapper, and an `img`
/// carrying the size it was resized to.
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

/// The grid at a stated width, which is what decides the column count.
Future<void> pumpGrid(
  WidgetTester tester,
  String source, {
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpCooked(tester, source);
  await tester.pumpAndSettle();
}

void main() {
  group('ImageGridData', () {
    test('reads the mode, defaulting to the mosaic', () {
      expect(parse(grid(3)).mode, ImageGridMode.grid);
      expect(parse(grid(3, mode: 'grid')).mode, ImageGridMode.grid);
      expect(parse(grid(3, mode: 'carousel')).mode, ImageGridMode.carousel);
    });

    test('takes items out of the paragraphs markdown wrapped them in', () {
      // `_prepareItems` unwraps a `<p>`, and never counts `br`/`p` themselves.
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
      // Under 100x100 Discourse writes no wrapper, so a grid holds bare imgs.
      final data = parse(
        '<div class="d-image-grid">${item('big')}<img src="https://example.com/tiny.png" width="50" height="50"></div>',
      );

      expect(data.items, hasLength(2));
      expect(data.items[1].isLightbox, isFalse);
      expect(data.items[1].plainSrc, 'https://example.com/tiny.png');
    });

    test('measures an item by the size the markup declares', () {
      final data = parse(grid(1, width: 600, height: 400));

      expect(data.items.single.mosaicHeightUnit, closeTo(400 / 600, 0.0001));
      expect(data.items.single.carouselAspectRatio, closeTo(600 / 400, 0.0001));
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
      // `buildCarouselItems` skips decoration and dedupes to the wrapper.
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
      // Three equal items across three columns: one each.
      expect(ImageGridMosaic.distribute([1, 1, 1], 3), [
        [0],
        [1],
        [2],
      ]);
    });

    test('lets a short item share a column with another short one', () {
      // A tall first item means columns 2 and 3 stay shorter and take more.
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
    testWidgets('draws a grid instead of a stack of images', (tester) async {
      await pumpGrid(tester, grid(3));

      expect(find.byType(ImageGridMosaic), findsOneWidget);
      expect(find.byType(ImageGridTile), findsNWidgets(3));
    });

    testWidgets('uses three columns when there is room', (tester) async {
      await pumpGrid(tester, grid(3), width: 800);

      final tiles = tester.widgetList<ImageGridTile>(
        find.byType(ImageGridTile),
      );
      expect(tiles, hasLength(3));
      // Three abreast: every tile shares a top edge.
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
      // Two abreast plus one below: two distinct left edges, two distinct tops.
      expect(rects.map((r) => r.left).toSet(), hasLength(2));
      expect(rects.map((r) => r.top).toSet(), hasLength(2));
    });

    testWidgets('uses two columns for two or four items whatever the room', (
      tester,
    ) async {
      // `Columns#count` — a 2x2 block reads better than a row of four.
      await pumpGrid(tester, grid(4), width: 900);

      final lefts = find
          .byType(ImageGridTile)
          .evaluate()
          .map(
            (e) =>
                tester.getTopLeft(find.byWidget(e.widget as ImageGridTile)).dx,
          )
          .toSet();
      expect(lefts, hasLength(2));
    });

    testWidgets('ends every column at the same height', (tester) async {
      // The stretch the stylesheet gets from flex, which is the whole point of
      // the mosaic looking like a block rather than a ragged edge.
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

    testWidgets('leaves a grid of one image stacked', (tester) async {
      // `minCount: 2` — the web client marks it disabled and the CSS bails.
      await pumpGrid(tester, grid(1));

      expect(find.byType(ImageGridMosaic), findsNothing);
      expect(find.byType(LightboxThumbnail), findsOneWidget);
    });

    testWidgets('opens the gallery in written order, not column order', (
      tester,
    ) async {
      // This is the reason `lib/columns.js` stamps `data-lightbox-position`.
      // Six equal images across three columns lay out column-major — the
      // grid's second tile is the fourth image written — and the web client
      // has to undo that ordering before it can open the gallery, because
      // `Columns` moved the nodes. Nothing here moves a node, so the gallery
      // reads written order straight off the document.
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
    testWidgets('draws a track instead of a mosaic', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      expect(find.byType(ImageGridCarousel), findsOneWidget);
      expect(find.byType(ImageGridMosaic), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('shows a dot per image and moves between them', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));

      await tester.tap(find.dIcon(DIcons.chevronRight));
      await tester.pumpAndSettle();

      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      expect(controller.page, 1);
    });

    testWidgets('wraps around at both ends', (tester) async {
      await pumpGrid(tester, grid(3, mode: 'carousel'));
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;

      // Back from the first lands on the last, the way `prevIndex` does.
      await tester.tap(find.dIcon(DIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(controller.page, 2);

      await tester.tap(find.dIcon(DIcons.chevronRight));
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    testWidgets('counts instead of dotting once there are too many', (
      tester,
    ) async {
      // `MAX_DOTS` is 10.
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
      expect(controller.page, 1);
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
