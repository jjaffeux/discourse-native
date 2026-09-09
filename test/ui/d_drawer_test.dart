import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  Size size = const Size(800, 600),
  bool disableAnimations = true,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Widget _drawer<T>({
  DDrawerController<T>? controller,
  bool? open,
  ValueChanged<DDrawerChangeDetails<T>>? onOpenChanged,
  DDrawerSwipeDirection direction = DDrawerSwipeDirection.down,
  DDrawerModalMode modalMode = DDrawerModalMode.modal,
  bool disablePointerDismissal = false,
  List<DDrawerSnapPoint> snapPoints = const [],
  DDrawerSnapPoint? snapPoint,
  ValueChanged<DDrawerSnapChangeDetails>? onSnapPointChanged,
  Widget? body,
  T? result,
}) => DDrawer<T>(
  controller: controller,
  open: open,
  onOpenChanged: onOpenChanged,
  swipeDirection: direction,
  modalMode: modalMode,
  disablePointerDismissal: disablePointerDismissal,
  snapPoints: snapPoints,
  snapPoint: snapPoint,
  onSnapPointChanged: onSnapPointChanged,
  showSwipeHandle: true,
  trigger: DDrawerTrigger(
    builder: (context, open) =>
        DButton(onPressed: open, label: const Text('Open drawer')),
  ),
  content: DDrawerContent(
    semanticLabel: 'Example drawer',
    children: [
      const DDrawerHeader(
        children: [
          DDrawerTitle(child: Text('Example drawer')),
          DDrawerDescription(child: Text('Swipe or close this drawer.')),
        ],
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: body ?? const Text('Drawer body'),
      ),
      DDrawerFooter(
        children: [
          DDrawerClose<T>(
            result: result,
            builder: (context, close) =>
                DButton(onPressed: close, label: const Text('Close drawer')),
          ),
        ],
      ),
    ],
  ),
);

void main() {
  testWidgets('open completion reports after both route transitions', (
    tester,
  ) async {
    final completions = <bool>[];
    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          initiallyOpen: true,
          onOpenChangeComplete: completions.add,
          trigger: DDrawerTrigger(
            builder: (_, open) =>
                TextButton(onPressed: open, child: const Text('Open')),
          ),
          content: DDrawerContent(
            children: [
              DDrawerClose<void>(
                builder: (_, close) =>
                    TextButton(onPressed: close, child: const Text('Finish')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(completions, [true]);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(completions, [true, false]);
  });

  testWidgets(
    'uncontrolled lifecycle returns a typed result and restores focus',
    (tester) async {
      final changes = <DDrawerChangeDetails<String>>[];
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          Focus(
            focusNode: focus,
            child: _drawer<String>(onOpenChanged: changes.add, result: 'done'),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Open drawer'));
      await tester.pumpAndSettle();
      expect(find.text('Example drawer'), findsOneWidget);
      expect(changes.single.reason, DDrawerChangeReason.trigger);

      await tester.tap(find.text('Close drawer'));
      await tester.pumpAndSettle();
      expect(find.text('Example drawer'), findsNothing);
      expect(changes.last.result, 'done');
      expect(changes.last.reason, DDrawerChangeReason.close);
      expect(focus.hasFocus, isTrue);
    },
  );

  testWidgets('base-nova bottom and side geometry use exposed-edge styling', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_drawer<void>(open: true)));
    await tester.pumpAndSettle();
    final bottom = tester.getRect(find.byType(DDrawerContent));
    expect(bottom.left, 0);
    expect(bottom.right, 800);
    expect(bottom.bottom, 600);
    expect(bottom.height, lessThanOrEqualTo(504));

    await tester.pumpWidget(
      _host(_drawer<void>(open: true, direction: DDrawerSwipeDirection.right)),
    );
    await tester.pumpAndSettle();
    final side = tester.getRect(find.byType(DDrawerContent));
    expect(side.width, 384);
    expect(side.right, 800);
    expect(side.height, 600);
  });

  testWidgets('logical start follows RTL', (tester) async {
    await tester.pumpWidget(
      _host(
        _drawer<void>(open: true, direction: DDrawerSwipeDirection.start),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(DDrawerContent));
    expect(rect.right, 800);
    expect(rect.width, 384);
  });

  testWidgets('touch swipe dismisses and reports swipe reason', (tester) async {
    DDrawerChangeDetails<void>? close;
    await tester.pumpWidget(
      _host(
        _drawer<void>(
          open: true,
          onOpenChanged: (details) {
            if (!details.open) close = details;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(DDrawerSwipeHandle), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(close?.reason, DDrawerChangeReason.swipe);
  });

  testWidgets('a shallow slow swipe rebounds instead of dismissing', (
    tester,
  ) async {
    DDrawerChangeDetails<void>? close;
    await tester.pumpWidget(
      _host(
        _drawer<void>(
          open: true,
          onOpenChanged: (details) {
            if (!details.open) close = details;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byType(DDrawerSwipeHandle),
      const Offset(0, 24),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
    expect(close, isNull);
    expect(find.text('Example drawer'), findsOneWidget);
  });

  testWidgets('snap points settle sequentially and remain controllable', (
    tester,
  ) async {
    const compact = DDrawerSnapPoint.fraction(.4);
    const expanded = DDrawerSnapPoint.fraction(1);
    final controller = DDrawerController<void>(
      initiallyOpen: true,
      initialSnapPoint: compact,
    );
    addTearDown(controller.dispose);
    final changes = <DDrawerSnapChangeDetails>[];
    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          controller: controller,
          snapPoints: const [compact, expanded],
          snapToSequentialPoints: true,
          onSnapPointChanged: changes.add,
          showSwipeHandle: true,
          trigger: DDrawerTrigger(
            builder: (_, open) =>
                DButton(onPressed: open, label: const Text('Open drawer')),
          ),
          content: const DDrawerContent(
            children: [
              DDrawerHeader(
                children: [DDrawerTitle(child: Text('Snap drawer'))],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final compactTop = tester.getTopLeft(find.byType(DDrawerContent)).dy;
    expect(compactTop, closeTo(360, 2));
    await tester.drag(find.byType(DDrawerSwipeHandle), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(controller.snapPoint, expanded);
    expect(changes.last.reason, DDrawerSnapChangeReason.swipe);
    expect(tester.getTopLeft(find.byType(DDrawerContent)).dy, closeTo(0, 2));
  });

  testWidgets('fraction snap points resolve from the viewport with an inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          initiallyOpen: true,
          snapPoints: const [DDrawerSnapPoint.fraction(.5)],
          trigger: DDrawerTrigger(
            builder: (_, open) => const SizedBox.shrink(),
          ),
          content: const DDrawerContent(
            inset: 20,
            children: [DDrawerTitle(child: Text('Inset snap drawer'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(DDrawerContent)).dy, closeTo(300, 2));
  });

  testWidgets('canceled controlled close rebounds without unmounting', (
    tester,
  ) async {
    DDrawerChangeDetails<void>? request;
    await tester.pumpWidget(
      _host(
        _drawer<void>(
          open: true,
          onOpenChanged: (details) {
            request = details;
            details.cancel();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(DDrawerSwipeHandle), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(request?.reason, DDrawerChangeReason.swipe);
    expect(find.text('Example drawer'), findsOneWidget);
  });

  testWidgets('non-modal drawer allows interaction with the page', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: 20,
                bottom: 20,
                child: TextButton(
                  onPressed: () => presses++,
                  child: const Text('Page action'),
                ),
              ),
              _drawer<void>(
                open: true,
                direction: DDrawerSwipeDirection.right,
                modalMode: DDrawerModalMode.nonModal,
                disablePointerDismissal: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page action'));
    await tester.pump();
    expect(presses, 1);
    expect(find.text('Example drawer'), findsOneWidget);
  });

  testWidgets('non-modal outside press reaches page and requests dismissal', (
    tester,
  ) async {
    var presses = 0;
    var open = true;
    DDrawerChangeReason? reason;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        SizedBox.expand(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  Positioned(
                    left: 20,
                    bottom: 20,
                    child: TextButton(
                      onPressed: () => presses++,
                      child: const Text('Outside action'),
                    ),
                  ),
                  _drawer<void>(
                    open: open,
                    direction: DDrawerSwipeDirection.right,
                    modalMode: DDrawerModalMode.nonModal,
                    onOpenChanged: (details) {
                      reason = details.reason;
                      update(() => open = details.open);
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outside action'));
    await tester.pumpAndSettle();
    expect(presses, 1);
    expect(reason, DDrawerChangeReason.outsidePress);
    expect(find.text('Example drawer'), findsNothing);
  });

  testWidgets('scrollable hands dismiss-edge overscroll to the drawer', (
    tester,
  ) async {
    DDrawerChangeReason? reason;
    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          initiallyOpen: true,
          onOpenChanged: (details) {
            if (!details.open) reason = details.reason;
          },
          showSwipeHandle: true,
          trigger: DDrawerTrigger(
            builder: (_, open) =>
                TextButton(onPressed: open, child: const Text('Open')),
          ),
          content: DDrawerContent(
            height: 420,
            children: [
              const DDrawerHeader(
                children: [DDrawerTitle(child: Text('Scrollable'))],
              ),
              DDrawerScrollArea(
                child: Column(
                  children: List.generate(
                    30,
                    (index) => SizedBox(height: 40, child: Text('Row $index')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('Row 0'), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(reason, DDrawerChangeReason.swipe);
  });

  testWidgets('swipe area opens only its attached controller', (tester) async {
    final controller = DDrawerController<void>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox.expand(
          child: Stack(
            children: [
              DDrawer<void>(
                controller: controller,
                swipeDirection: DDrawerSwipeDirection.right,
                trigger: DDrawerTrigger(
                  builder: (_, open) =>
                      TextButton(onPressed: open, child: const Text('Open')),
                ),
                content: const DDrawerContent(
                  children: [DDrawerTitle(child: Text('Edge opened'))],
                ),
              ),
              Positioned(
                right: 0,
                top: 100,
                width: 24,
                height: 200,
                child: DDrawerSwipeArea<void>(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(788, 150), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('Edge opened'), findsOneWidget);
  });

  testWidgets('provider indent observes mounted drawers', (tester) async {
    await tester.pumpWidget(
      _host(
        DDrawerProvider(
          child: Column(
            children: [
              DDrawerIndent(builder: (_, active, _) => Text('Active: $active')),
              _drawer<void>(),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Active: false'), findsOneWidget);
    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();
    expect(find.text('Active: true'), findsOneWidget);
  });

  testWidgets('trap-focus leaves outside pointer active but loops Tab', (
    tester,
  ) async {
    var presses = 0;
    final firstFocus = FocusNode();
    final lastFocus = FocusNode();
    addTearDown(firstFocus.dispose);
    addTearDown(lastFocus.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: 20,
                bottom: 20,
                child: TextButton(
                  onPressed: () => presses++,
                  child: const Text('Outside trap action'),
                ),
              ),
              _drawer<void>(
                open: true,
                direction: DDrawerSwipeDirection.right,
                modalMode: DDrawerModalMode.trapFocus,
                disablePointerDismissal: true,
                body: Column(
                  children: [
                    TextButton(
                      focusNode: firstFocus,
                      onPressed: () {},
                      child: const Text('First focus'),
                    ),
                    TextButton(
                      focusNode: lastFocus,
                      onPressed: () {},
                      child: const Text('Last focus'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outside trap action'));
    expect(presses, 1);
    lastFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);
    expect(find.text('Example drawer'), findsOneWidget);
  });

  testWidgets('non-modal focus-out dismissal restores page focus', (
    tester,
  ) async {
    final inside = FocusNode();
    final outside = FocusNode();
    addTearDown(inside.dispose);
    addTearDown(outside.dispose);
    var open = true;
    DDrawerChangeReason? reason;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        SizedBox.expand(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  TextButton(
                    focusNode: outside,
                    onPressed: () {},
                    child: const Text('Outside focus'),
                  ),
                  DDrawer<void>(
                    open: open,
                    modalMode: DDrawerModalMode.nonModal,
                    swipeDirection: DDrawerSwipeDirection.right,
                    initialFocusNode: inside,
                    onOpenChanged: (details) {
                      reason = details.reason;
                      update(() => open = details.open);
                    },
                    trigger: DDrawerTrigger(
                      builder: (_, show) => const SizedBox.shrink(),
                    ),
                    content: DDrawerContent(
                      children: [
                        TextButton(
                          focusNode: inside,
                          onPressed: () {},
                          child: const Text('Inside focus'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(inside.hasFocus, isTrue);
    outside.requestFocus();
    await tester.pumpAndSettle();
    expect(reason, DDrawerChangeReason.focusOut);
    expect(find.text('Inside focus'), findsNothing);
    expect(outside.hasFocus, isTrue);
  });

  testWidgets('open drawer receives live theme and direction updates', (
    tester,
  ) async {
    var dark = false;
    var rtl = false;
    late StateSetter update;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          final scheme = ColorScheme.fromSeed(
            seedColor: dark ? Colors.purple : Colors.orange,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
          return MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: _drawer<void>(
                open: true,
                direction: DDrawerSwipeDirection.end,
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    final before = tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(DDrawerContent),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;
    update(() {
      dark = true;
      rtl = true;
    });
    await tester.pumpAndSettle();
    final after = tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(DDrawerContent),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;
    expect(after, isNot(before));
    expect(tester.getRect(find.byType(DDrawerContent)).left, 0);
  });

  testWidgets('showDDrawer returns a typed close result', (tester) async {
    String? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDDrawer<String>(
                context: context,
                builder: (_, _) => DDrawerContent(
                  children: [
                    DDrawerClose<String>(
                      result: 'accepted',
                      builder: (_, close) => TextButton(
                        onPressed: close,
                        child: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Show helper'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show helper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(result, 'accepted');
  });

  testWidgets('Escape closes only the frontmost nested drawer', (tester) async {
    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          initiallyOpen: true,
          trigger: DDrawerTrigger(
            builder: (_, open) => TextButton(
              onPressed: open,
              child: const Text('Parent trigger'),
            ),
          ),
          content: DDrawerContent(
            children: [
              const DDrawerTitle(child: Text('Parent drawer')),
              _drawer<void>(body: const Text('Nested body')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();
    expect(find.text('Example drawer'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Example drawer'), findsNothing);
    expect(find.text('Parent drawer'), findsOneWidget);
  });

  testWidgets('nested swipe reveals the mounted parent content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          initiallyOpen: true,
          trigger: DDrawerTrigger(
            builder: (_, open) => TextButton(
              onPressed: open,
              child: const Text('Parent trigger'),
            ),
          ),
          content: DDrawerContent(
            children: [
              const DDrawerTitle(child: Text('Parent drawer')),
              _drawer<void>(body: const Text('Nested body')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    AnimatedOpacity parentOpacity() => tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Parent drawer'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );

    expect(parentOpacity().opacity, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DDrawerSwipeHandle).last),
    );
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    expect(parentOpacity().opacity, 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(parentOpacity().opacity, 0);
    expect(find.text('Example drawer'), findsOneWidget);
  });

  testWidgets('nested stack depth propagates through every mounted parent', (
    tester,
  ) async {
    Widget nestedDrawer(String title, String trigger, {Widget? child}) =>
        DDrawer<void>(
          trigger: DDrawerTrigger(
            builder: (_, open) =>
                TextButton(onPressed: open, child: Text(trigger)),
          ),
          content: DDrawerContent(
            children: [
              DDrawerTitle(child: Text(title)),
              ?child,
            ],
          ),
        );

    await tester.pumpWidget(
      _host(
        DDrawer<void>(
          initiallyOpen: true,
          trigger: DDrawerTrigger(
            builder: (_, open) => const SizedBox.shrink(),
          ),
          content: DDrawerContent(
            children: [
              const DDrawerTitle(child: Text('Root drawer')),
              nestedDrawer(
                'Child drawer',
                'Open child',
                child: nestedDrawer('Grandchild drawer', 'Open grandchild'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open child'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open grandchild'));
    await tester.pumpAndSettle();

    final rootScales = tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.text('Root drawer'),
            matching: find.byType(Transform),
          ),
        )
        .map((widget) => widget.transform.storage[0])
        .where((scale) => scale < .999)
        .toList();
    expect(rootScales, contains(closeTo(.9, .001)));
  });
}
