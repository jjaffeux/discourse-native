import 'dart:typed_data';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = ValueKey('screen');
const _page = ValueKey('page');

Widget _app({
  required bool hosted,
  required DSheetController<void> controller,
  VoidCallback? onPageBuild,
  bool withSheet = true,
}) {
  Widget page = Builder(
    builder: (context) {
      onPageBuild?.call();
      return Scaffold(
        key: _page,
        // A page reads inherited values, which a re-parented page rebuilds.
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: !withSheet
              ? null
              : DSheet<void>(
                  controller: controller,
                  trigger: DSheetTrigger(
                    builder: (context, open) =>
                        DButton(onPressed: open, label: const Text('Open')),
                  ),
                  content: const DSheetContent(
                    side: DSheetSide.bottom,
                    variant: DSheetVariant.page,
                    showCloseButton: false,
                    semanticLabel: 'Sheet',
                    children: [
                      DSheetHeader(children: []),
                      Text('Body'),
                    ],
                  ),
                ),
        ),
      );
    },
  );
  if (hosted) {
    page = DDialogBackgroundHost(builder: DSheet.routeBackground, child: page);
  }
  return RepaintBoundary(
    key: _screen,
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: page,
    ),
  );
}

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screen),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  testWidgets('a hosted page recedes beneath a sheet as a delegated one does', (
    tester,
  ) async {
    final frames = <bool, List<Uint8List>>{};
    final pageRects = <bool, List<Rect>>{};
    late DTokens tokens;
    for (final hosted in [false, true]) {
      final controller = DSheetController<void>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(hosted: hosted, controller: controller));
      await tester.pumpAndSettle();
      final captured = frames[hosted] = [];
      final rects = pageRects[hosted] = [];
      Future<void> capture() async {
        rects.add(tester.getRect(find.byKey(_page)));
        captured.add(await _capture(tester));
      }

      controller.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 150));
      await capture();
      await tester.pumpAndSettle();
      await capture();
      if (hosted) {
        tokens = DTokens.of(tester.element(find.byKey(_page)));
      }
      controller.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 90));
      await capture();
      await tester.pumpAndSettle();
      await capture();
      await tester.pumpWidget(const SizedBox.shrink());
    }

    final full = pageRects[true]!.last;
    expect(pageRects[true]![0].width, lessThan(full.width * .99));
    expect(pageRects[true]![1].width, closeTo(full.width * .94, .01));
    expect(pageRects[true]![2].width, lessThan(full.width * .99));
    expect(pageRects[true], pageRects[false]);
    // The receded page uncovers the well, tinted as the page is.
    final opening = frames[true]!.first;
    final width = full.width.round();
    final depth = (1 - pageRects[true]!.first.width / full.width) / .06;
    final margin = Color.alphaBlend(
      tokens.colors.scrim.withValues(alpha: .24 * depth),
      tokens.wellFill,
    );
    Color pixel(int x, int y) {
      final i = (y * width + x) * 4;
      return Color.fromARGB(
        opening[i + 3],
        opening[i],
        opening[i + 1],
        opening[i + 2],
      );
    }

    final corner = pixel(2, 2);
    expect(corner.r, closeTo(margin.r, 1 / 255));
    expect(corner.g, closeTo(margin.g, 1 / 255));
    expect(corner.b, closeTo(margin.b, 1 / 255));
    for (var i = 0; i < frames[true]!.length; i++) {
      expect(frames[true]![i], frames[false]![i], reason: 'frame $i');
    }
  });

  testWidgets('a hosted page follows a sheet pulled down as a delegated one', (
    tester,
  ) async {
    final frames = <bool, List<Uint8List>>{};
    for (final hosted in [false, true]) {
      final controller = DSheetController<void>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(hosted: hosted, controller: controller));
      controller.open();
      await tester.pumpAndSettle();
      final captured = frames[hosted] = [];
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      for (final step in [20.0, 40.0, 40.0]) {
        await gesture.moveBy(Offset(0, step));
        await tester.pump(const Duration(milliseconds: 16));
        captured.add(await _capture(tester));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      captured.add(await _capture(tester));
      await tester.pumpWidget(const SizedBox.shrink());
    }
    for (var i = 0; i < frames[true]!.length; i++) {
      expect(frames[true]![i], frames[false]![i], reason: 'frame $i');
    }
  });

  testWidgets('a hosted page comes back as a delegated one when its sheet is '
      'removed', (tester) async {
    final rects = <bool, List<Rect>>{};
    for (final hosted in [false, true]) {
      final controller = DSheetController<void>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(hosted: hosted, controller: controller));
      controller.open();
      await tester.pumpAndSettle();
      final seen = rects[hosted] = [tester.getRect(find.byKey(_page))];
      // Taking the sheet's owner away removes its route without a closing
      // transition.
      await tester.pumpWidget(
        _app(hosted: hosted, controller: controller, withSheet: false),
      );
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(tester.getRect(find.byKey(_page)));
      }
      expect(find.text('Body'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(rects[true]!.first.width, lessThan(rects[true]!.last.width));
    expect(rects[true], rects[false]);
  });

  testWidgets('a hosted page is not rebuilt as a sheet opens and closes', (
    tester,
  ) async {
    final controller = DSheetController<void>();
    addTearDown(controller.dispose);
    var builds = 0;
    await tester.pumpWidget(
      _app(hosted: true, controller: controller, onPageBuild: () => builds++),
    );
    await tester.pumpAndSettle();
    expect(builds, 1);

    controller.open();
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    controller.close();
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
    expect(builds, 1);
  });

  testWidgets('an uncovered host passes on the taps its page leaves', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
            const DDialogBackgroundHost(
              builder: DSheet.routeBackground,
              child: SizedBox.expand(),
            ),
          ],
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    expect(taps, 1);
  });

  testWidgets('a sheet menu is not rebuilt while its trigger settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: DDialogBackgroundHost(
          builder: DSheet.routeBackground,
          child: Scaffold(
            body: Center(
              child: DDropdownMenu(
                sheetOnMobile: true,
                mobileSheetVariant: DSheetVariant.adaptiveMenu,
                content: const DDropdownMenuContent(
                  semanticLabel: 'Actions',
                  children: [Text('Action')],
                ),
                child: DDropdownMenuTrigger(
                  builder: (context, state) => DButton(
                    key: const ValueKey('trigger'),
                    onPressed: state.toggle,
                    label: const Text('Menu'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    var contentBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is DSheetContent) contentBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    // The trigger's press settles over the sheet's opening frames.
    await tester.tap(find.byKey(const ValueKey('trigger')));
    await tester.pump();
    await tester.pump();
    final opened = contentBuilds;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Action'), findsOneWidget);
    expect(contentBuilds - opened, 0);
  });
}
