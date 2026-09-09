import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  Size size = const Size(800, 600),
  TextDirection direction = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: textScaler,
      disableAnimations: disableAnimations,
      viewInsets: viewInsets,
    ),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Widget _sheet<T>({
  DSheetSide side = DSheetSide.right,
  DSheetController<T>? controller,
  bool? open,
  ValueChanged<DSheetChangeDetails<T>>? onOpenChanged,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
  bool showCloseButton = true,
}) => DSheet<T>(
  controller: controller,
  open: open,
  onOpenChanged: onOpenChanged,
  dismissOnBarrier: dismissOnBarrier,
  dismissOnEscape: dismissOnEscape,
  initialFocusNode: initialFocusNode,
  finalFocusNode: finalFocusNode,
  trigger: DSheetTrigger(
    builder: (context, show) => DButton(
      onPressed: show,
      variant: DButtonVariant.outline,
      label: const Text('Open'),
    ),
  ),
  content: DSheetContent(
    side: side,
    showCloseButton: showCloseButton,
    semanticLabel: 'Example sheet',
    children: [
      const DSheetHeader(
        children: [
          DSheetTitle(child: Text('Example sheet')),
          DSheetDescription(child: Text('Useful complementary content.')),
        ],
      ),
      const DSheetBody(child: Text('Body')),
      DSheetFooter(
        children: [
          DSheetClose<T>(
            result: null,
            builder: (context, close) => DButton(
              onPressed: close,
              variant: DButtonVariant.outline,
              label: const Text('Done'),
            ),
          ),
        ],
      ),
    ],
  ),
);

void main() {
  testWidgets('uncontrolled trigger and typed close restore focus', (
    tester,
  ) async {
    final triggerFocus = FocusNode();
    addTearDown(triggerFocus.dispose);
    final changes = <DSheetChangeDetails<String>>[];
    await tester.pumpWidget(
      _host(
        DSheet<String>(
          onOpenChanged: changes.add,
          trigger: DSheetTrigger(
            builder: (context, open) => DButton(
              focusNode: triggerFocus,
              onPressed: open,
              label: const Text('Open'),
            ),
          ),
          content: DSheetContent(
            semanticLabel: 'Typed sheet',
            children: [
              const DSheetHeader(
                children: [DSheetTitle(child: Text('Typed sheet'))],
              ),
              DSheetFooter(
                children: [
                  DSheetClose<String>(
                    result: 'chosen',
                    builder: (context, close) =>
                        DButton(onPressed: close, label: const Text('Choose')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    triggerFocus.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(changes.single.reason, DSheetChangeReason.trigger);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(changes.last.result, 'chosen');
    expect(changes.last.reason, DSheetChangeReason.close);
    expect(triggerFocus.hasFocus, isTrue);
  });

  testWidgets('physical sides match base-nova edge geometry', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final side in const [
      DSheetSide.top,
      DSheetSide.right,
      DSheetSide.bottom,
      DSheetSide.left,
    ]) {
      await tester.pumpWidget(_host(_sheet<void>(side: side)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(DSheetContent));
      switch (side) {
        case DSheetSide.top:
          expect(rect.top, 0);
          expect(rect.width, 800);
        case DSheetSide.right:
          expect(rect.right, 800);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.bottom:
          expect(rect.bottom, 600);
          expect(rect.width, 800);
        case DSheetSide.left:
          expect(rect.left, 0);
          expect(rect.width, 384);
          expect(rect.height, 600);
        case DSheetSide.start || DSheetSide.end:
          fail('Logical sides are not in this loop.');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('side width is 75 percent below the 640 breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(_sheet<void>(), size: const Size(320, 640)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 240);
  });

  testWidgets('explicit side width is clamped only by the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 288,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 288);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 480,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 320);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 640);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            sidePanelWidth: 480,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 384);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            side: DSheetSide.top,
            sidePanelWidth: 100,
            children: [DSheetBody(child: Text('Body'))],
          ),
        ),
        size: const Size(800, 640),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 800);
  });

  testWidgets('logical sides resolve with current RTL direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_sheet<void>(side: DSheetSide.start), direction: TextDirection.rtl),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(DSheetContent)).right, 800);
  });

  testWidgets('corner close stays physically right in RTL', (tester) async {
    await tester.pumpWidget(
      _host(_sheet<void>(), direction: TextDirection.rtl),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(DSheetContent));
    final close = tester.getRect(find.byTooltip('Close'));
    expect(close.right, closeTo(sheet.right - 12, .01));
  });

  testWidgets('title matches the reference text-base leading', (tester) async {
    await tester.pumpWidget(_host(_sheet<void>()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final titleContext = tester.element(find.text('Example sheet'));
    final style = DefaultTextStyle.of(titleContext).style;
    expect(style.fontSize, 16);
    expect(style.height, 24 / 16);
    expect(style.fontWeight, FontWeight.w500);
  });

  testWidgets('no close button and disabled dismissal remain open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _sheet<void>(
          showCloseButton: false,
          dismissOnBarrier: false,
          dismissOnEscape: false,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);
    await tester.tapAt(const Offset(8, 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Example sheet'), findsOneWidget);
  });

  testWidgets('barrier and Escape report Sheet dismissal reasons', (
    tester,
  ) async {
    final changes = <DSheetChangeDetails<void>>[];
    await tester.pumpWidget(_host(_sheet<void>(onOpenChanged: changes.add)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 300));
    await tester.pumpAndSettle();
    expect(changes.last.reason, DSheetChangeReason.barrier);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(changes.last.reason, DSheetChangeReason.escape);
  });

  testWidgets('controller coalesces submit and closes its open session', (
    tester,
  ) async {
    final controller = DSheetController<String>();
    addTearDown(controller.dispose);
    final gate = Completer<String>();
    await tester.pumpWidget(_host(_sheet<String>(controller: controller)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final first = controller.submit(() => gate.future);
    final second = controller.submit(() async => 'wrong');
    expect(identical(first, second), isTrue);
    gate.complete('saved');
    await first;
    await tester.pumpAndSettle();
    expect(find.text('Example sheet'), findsNothing);
  });

  testWidgets('live theme and direction update an open sheet', (tester) async {
    var dark = false;
    var direction = TextDirection.ltr;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          final scheme = ColorScheme.fromSeed(
            seedColor: dark ? Colors.purple : Colors.orange,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
          return _host(
            _sheet<void>(side: DSheetSide.end),
            direction: direction,
            theme: ThemeData(colorScheme: scheme),
          );
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final before = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(tester.getRect(find.byType(DSheetContent)).right, 800);
    update(() {
      dark = true;
      direction = TextDirection.rtl;
    });
    await tester.pumpAndSettle();
    final after = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(DSheetContent),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(after.color, isNot(before.color));
    expect(tester.getRect(find.byType(DSheetContent)).left, 0);
  });

  testWidgets('narrow 200 percent text and keyboard insets remain bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        _sheet<void>(),
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(DSheetContent));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
  });

  testWidgets('keyboard inset scrolls a capped fixed-height bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        DSheet<void>(
          trigger: DSheetTrigger(
            builder: (context, open) =>
                DButton(onPressed: open, label: const Text('Open')),
          ),
          content: const DSheetContent(
            side: DSheetSide.bottom,
            topBottomMaxHeightFactor: .85,
            children: [
              DSheetHeader(children: [DSheetTitle(child: Text('Room chat'))]),
              SizedBox(height: 448, child: TextField()),
            ],
          ),
        ),
        size: const Size(320, 640),
        viewInsets: const EdgeInsets.only(bottom: 300),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(DSheetContent),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(find.byType(DSheetContent)).bottom, 640);
  });

  testWidgets('showDSheet uses nearest Navigator and returns typed result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      _host(
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (nestedContext) => Builder(
              builder: (context) => DButton(
                onPressed: () async {
                  result = await showDSheet<String>(
                    context: context,
                    sidePanelWidth: 288,
                    builder: (context, controller) => DSheetContent(
                      children: [
                        DSheetClose<String>(
                          result: 'result',
                          builder: (context, close) => DButton(
                            onPressed: close,
                            label: const Text('Return'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                label: const Text('Helper'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Helper'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DSheetContent)).width, 288);
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(result, 'result');
  });
}
