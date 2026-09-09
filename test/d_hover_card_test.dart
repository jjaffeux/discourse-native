import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mouse uses the opening and closing delays', (tester) async {
    await tester.pumpWidget(_app(const _Card()));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Destination')));

    await tester.pump(const Duration(milliseconds: 599));
    expect(find.text('Supplementary preview'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Supplementary preview'), findsOneWidget);

    await mouse.moveTo(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('Supplementary preview'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Supplementary preview'), findsNothing);
  });

  testWidgets('pressing the trigger cancels a pending preview', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(
        DHoverCard(
          trigger: DHoverCardTrigger(
            builder: (context, state) => TextButton(
              focusNode: state.focusNode,
              onPressed: () => presses += 1,
              child: const Text('Pending destination'),
            ),
          ),
          content: const DHoverCardContent(child: Text('Stale preview')),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Pending destination')));
    await tester.pump(const Duration(milliseconds: 300));

    await mouse.down(tester.getCenter(find.text('Pending destination')));
    await mouse.up();
    await tester.pump();
    expect(presses, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Stale preview'), findsNothing);
  });

  testWidgets('pointer may cross the side gap and hover the content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const _Card(
          delay: Duration.zero,
          closeDelay: Duration(milliseconds: 100),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Destination')));
    await tester.pumpAndSettle();

    final trigger = tester.getRect(find.text('Destination'));
    final content = tester.getRect(find.byType(DHoverCardContent));
    expect(content.top, greaterThanOrEqualTo(trigger.bottom));
    await mouse.moveTo(
      Offset(content.center.dx, (trigger.bottom + content.top) / 2),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Supplementary preview'), findsOneWidget);

    await mouse.moveTo(content.center);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Supplementary preview'), findsOneWidget);
    await mouse.moveTo(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Supplementary preview'), findsNothing);
  });

  testWidgets('keyboard focus opens without moving focus and Escape closes', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(_app(_Card(focusNode: focusNode)));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(find.text('Supplementary preview'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(focusNode));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Supplementary preview'), findsNothing);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('popup stays absent from semantics and focus traversal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        DHoverCard(
          defaultOpen: true,
          trigger: DHoverCardTrigger(
            builder: (context, state) => TextButton(
              focusNode: state.focusNode,
              onPressed: () {},
              child: const Text('Real destination'),
            ),
          ),
          content: DHoverCardContent(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Visual-only details'),
                TextButton(onPressed: () {}, child: const Text('Not tabbable')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Real destination'), findsOneWidget);
    expect(find.bySemanticsLabel('Visual-only details'), findsNothing);
    expect(find.bySemanticsLabel('Not tabbable'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.text('Not tabbable'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('Not tabbable'),
    );
    semantics.dispose();
  });

  testWidgets('controlled state reports reasons and follows parent state', (
    tester,
  ) async {
    final reasons = <DHoverCardChangeReason>[];
    var open = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DHoverCard(
              open: open,
              onOpenChange: (value, reason) {
                reasons.add(reason);
                rebuild(() => open = value);
              },
              trigger: DHoverCardTrigger(
                delay: Duration.zero,
                builder: (context, state) => TextButton(
                  focusNode: state.focusNode,
                  onPressed: () {},
                  child: const Text('Controlled'),
                ),
              ),
              content: const DHoverCardContent(child: Text('Controlled body')),
            );
          },
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Controlled')));
    await tester.pumpAndSettle();
    expect(find.text('Controlled body'), findsOneWidget);
    expect(reasons, [DHoverCardChangeReason.triggerHover]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Controlled body'), findsNothing);
    expect(reasons.last, DHoverCardChangeReason.escape);
  });

  testWidgets('controller ignores detached calls and never disposes borrowed', (
    tester,
  ) async {
    final controller = DHoverCardController()..open();
    addTearDown(controller.dispose);
    var mounted = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return mounted ? _Card(controller: controller) : const SizedBox();
          },
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('Supplementary preview'), findsOneWidget);

    rebuild(() => mounted = false);
    await tester.pump();
    expect(controller.isOpen, isFalse);
    controller.close();
    controller.addListener(() {});
  });

  testWidgets('disable cancels a pending opening timer', (tester) async {
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DHoverCard(
              enabled: enabled,
              trigger: DHoverCardTrigger(
                builder: (context, state) => TextButton(
                  focusNode: state.focusNode,
                  onPressed: () {},
                  child: const Text('Delayed'),
                ),
              ),
              content: const DHoverCardContent(child: Text('Never opens')),
            );
          },
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Delayed')));
    rebuild(() => enabled = false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Never opens'), findsNothing);
  });

  testWidgets('disabling an open card hides it after the current build', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DHoverCard(
              defaultOpen: true,
              enabled: enabled,
              trigger: DHoverCardTrigger(
                builder: (context, state) => TextButton(
                  focusNode: state.focusNode,
                  onPressed: () {},
                  child: const Text('Disable open card'),
                ),
              ),
              content: const DHoverCardContent(child: Text('Open body')),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open body'), findsOneWidget);

    rebuild(() => enabled = false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Open body'), findsNothing);
  });

  testWidgets('controller replacement safely transfers the mounted owner', (
    tester,
  ) async {
    final controller = DHoverCardController();
    addTearDown(controller.dispose);
    var showSecond = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Card(controller: controller),
                if (showSecond) _Card(controller: controller),
              ],
            );
          },
        ),
      ),
    );
    controller.open();
    await tester.pump();
    expect(find.text('Supplementary preview'), findsOneWidget);

    rebuild(() => showSecond = true);
    await tester.pump();
    await tester.pump();
    expect(controller.isOpen, isFalse);
    expect(find.text('Supplementary preview'), findsNothing);

    controller.open();
    await tester.pump();
    expect(controller.isOpen, isTrue);
    expect(find.text('Supplementary preview'), findsOneWidget);
  });

  testWidgets('immediate transitions report completion exactly once', (
    tester,
  ) async {
    final completions = <bool>[];
    final controller = DHoverCardController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        DHoverCard(
          controller: controller,
          onOpenChangeComplete: completions.add,
          trigger: DHoverCardTrigger(
            builder: (context, state) => TextButton(
              focusNode: state.focusNode,
              onPressed: () {},
              child: const Text('Completion trigger'),
            ),
          ),
          content: const DHoverCardContent(child: Text('Completion body')),
        ),
      ),
    );

    controller.open();
    await tester.pump();
    controller.close();
    await tester.pump();

    expect(completions, [true, false]);
  });

  testWidgets('entering the pointer bridge cancels an earlier close timer', (
    tester,
  ) async {
    final controller = DHoverCardController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _Card(
          controller: controller,
          delay: Duration.zero,
          closeDelay: const Duration(milliseconds: 100),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Destination')));
    await tester.pumpAndSettle();

    final trigger = tester.getRect(find.text('Destination'));
    final content = tester.getRect(find.byType(DHoverCardContent));
    await mouse.moveTo(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 50));
    await mouse.moveTo(
      Offset(content.center.dx, (trigger.bottom + content.top) / 2),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(controller.isOpen, isTrue);
  });

  testWidgets('replacing a focused trigger node clears stale ownership', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var focusNode = first;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return _Card(focusNode: focusNode, closeDelay: Duration.zero);
          },
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.hasFocus, isTrue);
    expect(find.text('Supplementary preview'), findsOneWidget);

    rebuild(() => focusNode = second);
    await tester.pump();

    expect(second.hasFocus, isFalse);
    await tester.pump();
    expect(find.text('Supplementary preview'), findsNothing);
  });

  testWidgets('rapid trigger changes cancel stale timers and hand off cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SimpleNamedCard(trigger: 'First', content: 'First preview'),
            _SimpleNamedCard(trigger: 'Second', content: 'Second preview'),
          ],
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('First')));
    await tester.pump(const Duration(milliseconds: 300));
    await mouse.moveTo(tester.getCenter(find.text('Second')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('First preview'), findsNothing);
    expect(find.text('Second preview'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('First preview'), findsNothing);
    expect(find.text('Second preview'), findsOneWidget);

    await mouse.moveTo(tester.getCenter(find.text('First')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('First preview'), findsOneWidget);
    expect(find.text('Second preview'), findsNothing);
  });

  testWidgets('one group hands a strongly typed payload between triggers', (
    tester,
  ) async {
    final changes = <String>[];
    await tester.pumpWidget(
      _app(
        DHoverCardGroup<String>(
          items: [
            DHoverCardGroupItem(
              id: 'first',
              payload: 'First payload',
              delay: Duration.zero,
              builder: (context, state) => TextButton(
                focusNode: state.focusNode,
                onPressed: () {},
                child: Text(state.open ? 'First open' : 'First'),
              ),
            ),
            DHoverCardGroupItem(
              id: 'second',
              payload: 'Second payload',
              builder: (context, state) => TextButton(
                focusNode: state.focusNode,
                onPressed: () {},
                child: Text(state.open ? 'Second open' : 'Second'),
              ),
            ),
          ],
          builder: (context, triggers) =>
              Row(mainAxisSize: MainAxisSize.min, children: triggers),
          contentBuilder: (context, payload) =>
              DHoverCardContent(child: Text(payload)),
          onTriggerChange: (id, payload) => changes.add('$id:$payload'),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('First')));
    await tester.pumpAndSettle();
    expect(find.text('First payload'), findsOneWidget);
    expect(find.text('First open'), findsOneWidget);

    await mouse.moveTo(tester.getCenter(find.text('Second')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('First payload'), findsNothing);
    expect(find.text('Second payload'), findsOneWidget);
    expect(find.text('Second open'), findsOneWidget);
    expect(changes, ['second:Second payload']);
  });

  testWidgets('controlled group follows open and trigger id', (tester) async {
    var open = true;
    Object triggerId = 'second';
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DHoverCardGroup<int>(
              open: open,
              triggerId: triggerId,
              items: [
                DHoverCardGroupItem(
                  id: 'first',
                  payload: 1,
                  builder: (context, state) => TextButton(
                    focusNode: state.focusNode,
                    onPressed: () {},
                    child: const Text('One'),
                  ),
                ),
                DHoverCardGroupItem(
                  id: 'second',
                  payload: 2,
                  builder: (context, state) => TextButton(
                    focusNode: state.focusNode,
                    onPressed: () {},
                    child: const Text('Two'),
                  ),
                ),
              ],
              builder: (context, triggers) =>
                  Row(mainAxisSize: MainAxisSize.min, children: triggers),
              contentBuilder: (context, payload) =>
                  DHoverCardContent(child: Text('Payload $payload')),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payload 2'), findsOneWidget);

    rebuild(() {
      triggerId = 'first';
      open = true;
    });
    await tester.pumpAndSettle();
    expect(find.text('Payload 1'), findsOneWidget);
    expect(find.text('Payload 2'), findsNothing);

    rebuild(() => open = false);
    await tester.pumpAndSettle();
    expect(find.text('Payload 1'), findsNothing);
  });

  testWidgets(
    'inline start mirrors in RTL and collision keeps content visible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          const Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.center,
              child: DHoverCard(
                defaultOpen: true,
                trigger: DHoverCardTrigger(builder: _rtlTrigger),
                content: DHoverCardContent(
                  side: DPopoverSide.inlineStart,
                  width: 160,
                  child: Text('RTL content'),
                ),
              ),
            ),
          ),
          size: const Size(320, 240),
        ),
      );
      await tester.pumpAndSettle();
      final trigger = tester.getRect(find.text('المقصد'));
      final content = tester.getRect(find.byType(DHoverCardContent));
      expect(content.left, greaterThan(trigger.right));
      expect(content.left, greaterThanOrEqualTo(0));
      expect(content.right, lessThanOrEqualTo(320));
    },
  );

  testWidgets('open content shrinks at 200 percent in a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(216, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(216, 240),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: DHoverCard(
                defaultOpen: true,
                trigger: DHoverCardTrigger(builder: _rtlTrigger),
                content: DHoverCardContent(
                  child: Text(
                    'A long supplementary preview that wraps and scrolls.',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DHoverCardContent)).width,
      lessThanOrEqualTo(206),
    );
    expect(
      tester.getSize(find.byType(DHoverCardContent)).height,
      lessThanOrEqualTo(230),
    );
  });
}

Widget _rtlTrigger(BuildContext context, DHoverCardTriggerState state) =>
    TextButton(
      focusNode: state.focusNode,
      onPressed: () {},
      child: const Text('المقصد'),
    );

class _Card extends StatelessWidget {
  const _Card({
    this.delay = const Duration(milliseconds: 600),
    this.closeDelay = const Duration(milliseconds: 300),
    this.focusNode,
    this.controller,
  });

  final Duration delay;
  final Duration closeDelay;
  final FocusNode? focusNode;
  final DHoverCardController? controller;

  @override
  Widget build(BuildContext context) => DHoverCard(
    controller: controller,
    trigger: DHoverCardTrigger(
      delay: delay,
      closeDelay: closeDelay,
      focusNode: focusNode,
      builder: (context, state) => TextButton(
        focusNode: state.focusNode,
        onPressed: () {},
        child: const Text('Destination'),
      ),
    ),
    content: const DHoverCardContent(child: Text('Supplementary preview')),
  );
}

class _SimpleNamedCard extends StatelessWidget {
  const _SimpleNamedCard({required this.trigger, required this.content});

  final String trigger;
  final String content;

  @override
  Widget build(BuildContext context) => DHoverCard(
    trigger: DHoverCardTrigger(
      builder: (context, state) => TextButton(
        focusNode: state.focusNode,
        onPressed: () {},
        child: Text(trigger),
      ),
    ),
    content: DHoverCardContent(child: Text(content)),
  );
}

Widget _app(Widget child, {Size size = const Size(800, 600)}) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: Scaffold(body: Center(child: child)),
  ),
);
