import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _ground = Color(0xff224466);
const _ink = Color(0xffee8844);
const _body = ValueKey('headed-body');
const _title = ValueKey('headed-title');
const _controls = ValueKey('headed-controls');
final _capture = GlobalKey();

Future<void> _mount(
  WidgetTester tester,
  ScrollController scroll, {
  bool floating = true,
  bool shared = false,
  bool foldAtTop = false,
  bool dark = false,
  double scale = 1,
  Size size = const Size(1100, 800),
  TextDirection direction = TextDirection.ltr,
  FocusNode? controlFocus,
  Widget? controls,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = dark ? AppTheme.dark : AppTheme.light;
  Widget list(EdgeInsets padding) => ListView.builder(
    key: _body,
    controller: scroll,
    padding: padding,
    itemExtent: 60,
    itemCount: 100,
    itemBuilder: (_, i) => ColoredBox(color: _ink, child: Text('Item $i')),
  );
  final page = DPageSurface.headed(
    title: const Text('Messages', key: _title),
    foldTitleAtTop: foldAtTop,
    controls:
        controls ??
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            key: _controls,
            focusNode: controlFocus,
            size: DButtonSize.filter,
            label: const Text('Inbox'),
            onPressed: () {},
          ),
        ),
    bodyBuilder: !floating
        ? null
        : (_, header) => ListView(
            key: _body,
            controller: scroll,
            padding: EdgeInsets.zero,
            children: [
              header.spacer,
              for (var i = 0; i < 100; i++)
                ColoredBox(
                  color: _ink,
                  child: SizedBox(height: 60, child: Text('Item $i')),
                ),
            ],
          ),
    child: floating ? null : list(EdgeInsets.zero),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(
        platform: size.width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS,
        textTheme: theme.textTheme.apply(fontFamily: 'HeaderReview'),
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: RepaintBoundary(
            key: _capture,
            child: ColoredBox(
              color: _ground,
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!,
                child: shared
                    ? DScrollChrome(
                        identity: 'messages',
                        floatingFooter: true,
                        footerBuilder: (_) => const SizedBox(height: 40),
                        child: page,
                      )
                    : page,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, double amount) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byKey(_body)),
      scrollDelta: Offset(0, amount),
    ),
  );
  await tester.pumpAndSettle();
}

Future<ui.Image> _render(WidgetTester tester) async => (await tester.runAsync(
  () => tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
      .toImage(),
))!;

Future<void> _export(WidgetTester tester, String name) async {
  final dir = Platform.environment['PAGE_HEADER_EXPORT_DIR'];
  if (dir == null) return;
  final image = await _render(tester);
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  image.dispose();
}

Future<Color> _pixel(WidgetTester tester, int y) async {
  final image = await _render(tester);
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final at = (y * image.width + image.width - 20) * 4;
  final color = Color.fromARGB(
    data.getUint8(at + 3),
    data.getUint8(at),
    data.getUint8(at + 1),
    data.getUint8(at + 2),
  );
  image.dispose();
  return color;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'HeaderReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });

  for (final floating in [false, true]) {
    for (final shared in [false, true]) {
      testWidgets(
        'touch swipes retract and reveal the title (floating=$floating shared=$shared)',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await _mount(
            tester,
            scroll,
            floating: floating,
            shared: shared,
            size: const Size(390, 844),
          );
          final controlsTop = tester.getTopLeft(find.byKey(_controls)).dy;
          await tester.timedDrag(
            find.byKey(_body),
            const Offset(0, -300),
            const Duration(milliseconds: 300),
          );
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(200));
          expect(find.byKey(_title).hitTestable(), findsNothing);
          expect(find.byKey(_controls).hitTestable(), findsOneWidget);
          expect(
            tester.getTopLeft(find.byKey(_controls)).dy,
            lessThan(controlsTop),
          );
          await tester.pump(const Duration(milliseconds: 500));
          await tester.timedDrag(
            find.byKey(_body),
            const Offset(0, 160),
            const Duration(milliseconds: 300),
          );
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(0));
          expect(find.byKey(_title).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'title yields to controls (floating=$floating shared=$shared)',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final focus = FocusNode();
          addTearDown(focus.dispose);
          await _mount(
            tester,
            scroll,
            floating: floating,
            shared: shared,
            controlFocus: focus,
          );
          final body = tester.getRect(find.byKey(_body));
          final top = tester.getTopLeft(find.byKey(_controls)).dy;
          final semantics = tester.ensureSemantics();
          expect(find.byKey(_title).hitTestable(), findsOneWidget);
          await _wheel(tester, 260);
          expect(find.byKey(_title).hitTestable(), findsNothing);
          expect(find.byKey(_controls).hitTestable(), findsOneWidget);
          expect(tester.getTopLeft(find.byKey(_controls)).dy, lessThan(top));
          if (floating) {
            expect(tester.getRect(find.byKey(_body)), body);
            expect(scroll.offset, 260);
          }
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(find.byKey(_controls).hitTestable(), findsOneWidget);
          focus.unfocus();
          await tester.pump(const Duration(milliseconds: 500));
          await _wheel(tester, -160);
          expect(scroll.offset, greaterThan(0));
          expect(find.byKey(_title).hitTestable(), findsOneWidget);
          await _wheel(tester, 260);
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
          expect(find.byKey(_title).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  for (final shared in [false, true]) {
    testWidgets(
      'custom header can opt into short transcripts (shared=$shared)',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        Future<void> mount(double? minimum) async {
          final page = DPageSurface(
            framed: false,
            hideHeaderOnScroll: true,
            minimumScrollExtent: minimum,
            header: const SizedBox(
              height: 47,
              child: Text('Channel', key: _title),
            ),
            child: LayoutBuilder(
              builder: (_, viewport) => ListView(
                key: _body,
                controller: scroll,
                padding: EdgeInsets.zero,
                children: [SizedBox(height: viewport.maxHeight + 100)],
              ),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: shared
                  ? DScrollChrome(
                      identity: 'channel',
                      floatingFooter: true,
                      footerBuilder: (_) => const SizedBox(height: 40),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Offstage(
                            offstage: true,
                            child: TickerMode(
                              enabled: false,
                              child: DPageSurface.headed(
                                title: const Text('Retained page'),
                                controls: const SizedBox(height: 240),
                                child: ListView(
                                  children: const [SizedBox(height: 2000)],
                                ),
                              ),
                            ),
                          ),
                          page,
                        ],
                      ),
                    )
                  : page,
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(null);
        await _wheel(tester, 80);
        expect(find.byKey(_title).hitTestable(), findsOneWidget);
        scroll.jumpTo(0);
        await mount(0);
        final retainedTitle = find.text('Retained page', skipOffstage: false);
        final retainedTop = shared ? tester.getTopLeft(retainedTitle) : null;
        await _wheel(tester, 80);
        expect(find.byKey(_title).hitTestable(), findsNothing);
        if (shared) expect(tester.getTopLeft(retainedTitle), retainedTop);
        expect(tester.takeException(), isNull);
      },
    );
    for (final overflow in [119.0, 120.0, 121.0]) {
      testWidgets(
        'page threshold is 120px (overflow=$overflow shared=$shared)',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final page = DPageSurface.headed(
            title: const Text('Messages', key: _title),
            controls: DButton(
              key: _controls,
              label: const Text('Inbox'),
              onPressed: () {},
            ),
            child: LayoutBuilder(
              builder: (_, viewport) => ListView(
                key: _body,
                controller: scroll,
                padding: EdgeInsets.zero,
                children: [SizedBox(height: viewport.maxHeight + overflow)],
              ),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: SizedBox(
                width: 320,
                height: 600,
                child: shared
                    ? DScrollChrome(
                        identity: 'threshold',
                        floatingFooter: true,
                        footerBuilder: (_) => const SizedBox(height: 40),
                        child: page,
                      )
                    : page,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(scroll.position.maxScrollExtent, closeTo(overflow, .001));
          await _wheel(tester, 80);
          expect(
            find.byKey(_title).hitTestable(),
            overflow < 120 ? findsOneWidget : findsNothing,
          );
          expect(find.byKey(_controls).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('renders $size dark=$dark scale=$scale', (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          await _mount(tester, scroll, size: size, dark: dark, scale: scale);
          final name =
              '${size.width.toInt()}-${dark ? 'dark' : 'light'}-$scale';
          await _export(tester, '$name-top');
          final boundary = (tester.getBottomLeft(find.byKey(_controls)).dy + 14)
              .ceil();
          expect(await _pixel(tester, boundary + 3), _ink);
          scroll.jumpTo(20);
          await tester.pumpAndSettle();
          final soft = await _pixel(tester, boundary + 3);
          expect(soft, isNot(_ground));
          expect(soft, isNot(_ink));
          await _wheel(tester, 260);
          await _export(tester, '$name-down');
          expect(find.byKey(_title).hitTestable(), findsNothing);
          expect(find.byKey(_controls).hitTestable(), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 500));
          await _wheel(tester, -160);
          await _export(tester, '$name-up');
          expect(find.byKey(_title).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'title motion preserves the short-page fallback and scroll position',
    (tester) async {
      final layouts = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 300,
              child: DPageSurface.headed(
                title: const Text('Chats', key: _title),
                controls: const SizedBox(
                  height: 200,
                  child: Text('Directory controls'),
                ),
                adaptiveBodyBuilder: (_, bounded) {
                  layouts.add(bounded);
                  return bounded
                      ? ListView(children: const [SizedBox(height: 1200)])
                      : const SizedBox(height: 1200, width: 320);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(layouts, everyElement(isFalse));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(DPageSurface)),
          scrollDelta: const Offset(0, 140),
        ),
      );
      await tester.pumpAndSettle();
      expect(layouts, everyElement(isFalse));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
      expect(find.byKey(_title).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'indexed directories fold at the top through jumps and reversals',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _mount(tester, scroll, foldAtTop: true);
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      expect(find.byKey(_title).hitTestable(), findsNothing);
      await _wheel(tester, -120);
      expect(find.byKey(_title).hitTestable(), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(_title).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'enlarged controls remain reachable in a short viewport and RTL',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _mount(
        tester,
        scroll,
        floating: false,
        scale: 2,
        size: const Size(320, 240),
        direction: TextDirection.rtl,
        controls: Column(
          children: [
            for (var i = 0; i < 6; i++)
              DButton(label: Text('Filter $i'), onPressed: () {}),
          ],
        ),
      );
      expect(
        tester.getSize(find.byKey(_body)).height,
        greaterThanOrEqualTo(48),
      );
      final last = find.text('Filter 5');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
