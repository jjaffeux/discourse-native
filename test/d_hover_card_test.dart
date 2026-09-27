import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ignores global pointer events while inactive and resumes after reparenting',
    (tester) async {
      final cardKey = GlobalKey();
      final controller = DHoverCardController();
      addTearDown(controller.dispose);
      final card = DHoverCard(
        key: cardKey,
        controller: controller,
        trigger: DHoverCardTrigger(
          builder: (context, state) => DButton(
            focusNode: state.focusNode,
            onPressed: () {},
            label: const Text('Reparented destination'),
          ),
        ),
        content: const DHoverCardContent(child: Text('Reparented preview')),
      );
      Widget layout(bool moved) => _app(
        Row(
          children: [
            Expanded(child: moved ? const SizedBox.shrink() : card),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (!moved) return const SizedBox.shrink();
                  // The first sibling has deactivated the card, but it is still mounted.
                  expect(cardKey.currentContext!.mounted, isTrue);
                  GestureBinding.instance.pointerRouter.route(
                    const PointerDownEvent(position: Offset(4, 4)),
                  );
                  return card;
                },
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(layout(false));
      // Only an open card observes global pointers, so open it before the
      // move to route a press while it is inactive.
      controller.open();
      await tester.pumpAndSettle();
      await tester.pumpWidget(layout(true));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);
      expect(find.text('Reparented preview'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(find.text('Reparented preview'), findsNothing);
    },
  );

  testWidgets('only open or pending cards observe global pointer events', (
    tester,
  ) async {
    final router = GestureBinding.instance.pointerRouter;
    final controllers = [
      for (var index = 0; index < 20; index += 1) DHoverCardController(),
    ];
    for (final controller in controllers) {
      addTearDown(controller.dispose);
    }
    Widget cards({required bool mounted}) => _app(
      Wrap(
        children: [
          if (mounted)
            for (var index = 0; index < controllers.length; index += 1)
              DHoverCard(
                controller: controllers[index],
                trigger: DHoverCardTrigger(
                  builder: (context, state) => TextButton(
                    focusNode: state.focusNode,
                    onPressed: () {},
                    child: Text('Idle $index'),
                  ),
                ),
                content: DHoverCardContent(child: Text('Preview $index')),
              ),
        ],
      ),
    );

    await tester.pumpWidget(cards(mounted: false));
    final idle = router.debugGlobalRouteCount;
    await tester.pumpWidget(cards(mounted: true));
    expect(router.debugGlobalRouteCount, idle);

    controllers.first.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, idle + 1);
    controllers.first.close();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, idle);

    // A pending opening listens for a press on its trigger.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Idle 1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.debugGlobalRouteCount, idle + 1);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(router.debugGlobalRouteCount, idle);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Preview 1'), findsNothing);

    controllers.last.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, idle + 1);
    await tester.pumpWidget(cards(mounted: false));
    expect(router.debugGlobalRouteCount, idle);
  });

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

  testWidgets(
    'the close delay keeps its deadline while the pointer moves outside the pair',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const _Card(
            delay: Duration.zero,
            closeDelay: Duration(milliseconds: 200),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Destination')));
      await tester.pumpAndSettle();
      expect(find.text('Supplementary preview'), findsOneWidget);
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 150));
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('Supplementary preview'), findsOneWidget);
      await mouse.moveTo(const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('Supplementary preview'), findsNothing);
    },
  );

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

  for (final how in _Hide.values) {
    testWidgets(
      'content hidden under the pointer by ${how.name} does not stay hovered',
      (tester) async {
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
        await mouse.moveTo(tester.getCenter(find.byType(DHoverCardContent)));
        await tester.pumpAndSettle();
        expect(find.text('Supplementary preview'), findsOneWidget);

        // The content leaves the tree under the pointer, so its region never
        // reports an exit.
        switch (how) {
          case _Hide.escape:
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case _Hide.controller:
            controller.close();
          case _Hide.lifecycle:
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          case _Hide.viewFocus:
            for (final state in [
              ViewFocusState.unfocused,
              ViewFocusState.focused,
            ]) {
              tester.binding.handleViewFocusChanged(
                ViewFocusEvent(
                  viewId: tester.view.viewId,
                  state: state,
                  direction: ViewFocusDirection.undefined,
                ),
              );
              await tester.pump();
            }
        }
        await tester.pumpAndSettle();
        expect(find.text('Supplementary preview'), findsNothing);

        await mouse.moveTo(const Offset(4, 4));
        await tester.pump();
        await mouse.moveTo(tester.getCenter(find.text('Destination')));
        await tester.pumpAndSettle();
        expect(find.text('Supplementary preview'), findsOneWidget);
        await mouse.moveTo(const Offset(4, 4));
        await tester.pump(const Duration(milliseconds: 99));
        expect(find.text('Supplementary preview'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Supplementary preview'), findsNothing);
      },
    );
  }

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

  testWidgets('a card opened from another card keeps that card open', (
    tester,
  ) async {
    final panel = DHoverCardController();
    addTearDown(panel.dispose);
    await tester.pumpWidget(_app(_NestedCards(controller: panel)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await _openNested(tester, mouse, 'Alice');

    // The nested content lies outside the parent's trigger, content and the
    // corridor between them.
    await mouse.moveTo(tester.getCenter(find.text('Alice preview')));
    await tester.pump(const Duration(seconds: 2));
    expect(panel.isOpen, isTrue);
    expect(find.text('Alice preview'), findsOneWidget);

    await mouse.moveTo(tester.getCenter(find.text('Bob')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(panel.isOpen, isTrue);
    expect(find.text('Alice preview'), findsNothing);
    expect(find.text('Bob preview'), findsOneWidget);

    // Back on the parent's own content, the nested card closes alone.
    await mouse.moveTo(tester.getCenter(find.text('Bob preview')));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Reactors')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(panel.isOpen, isTrue);
    expect(find.text('Bob preview'), findsNothing);
  });

  testWidgets('leaving nested cards closes each after its own delay', (
    tester,
  ) async {
    final panel = DHoverCardController();
    addTearDown(panel.dispose);
    await tester.pumpWidget(_app(_NestedCards(controller: panel)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await _openNested(tester, mouse, 'Alice');
    await mouse.moveTo(tester.getCenter(find.text('Alice preview')));
    await tester.pump();

    await mouse.moveTo(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('Alice preview'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Alice preview'), findsNothing);

    // The parent's delay starts once the nested card has closed.
    await tester.pump(const Duration(milliseconds: 349));
    expect(panel.isOpen, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(panel.isOpen, isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Reactors'), findsNothing);
  });

  testWidgets('a pending close waits for a nested card opened meanwhile', (
    tester,
  ) async {
    final panel = DHoverCardController();
    final alice = DHoverCardController();
    addTearDown(panel.dispose);
    addTearDown(alice.dispose);
    await tester.pumpWidget(
      _app(_NestedCards(controller: panel, alice: alice)),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Reactions')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    await mouse.moveTo(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 100));
    alice.open();
    await tester.pump(const Duration(milliseconds: 400));
    expect(panel.isOpen, isTrue);
    expect(find.text('Alice preview'), findsOneWidget);
  });

  testWidgets('Escape closes a nested card before its parent', (tester) async {
    await tester.pumpWidget(_app(const _NestedCards()));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await _openNested(tester, mouse, 'Alice');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Reactors'), findsOneWidget);
    expect(find.text('Alice preview'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Reactors'), findsNothing);
  });

  testWidgets('an unrelated card closes a nested card and its parent', (
    tester,
  ) async {
    final elsewhere = DHoverCardController();
    addTearDown(elsewhere.dispose);
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SimpleNamedCard(
              trigger: 'Elsewhere',
              content: 'Elsewhere preview',
              controller: elsewhere,
            ),
            const _NestedCards(),
          ],
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await _openNested(tester, mouse, 'Alice');

    elsewhere.open();
    await tester.pump();
    expect(find.text('Elsewhere preview'), findsOneWidget);
    expect(find.text('Reactors'), findsNothing);
    expect(find.text('Alice preview'), findsNothing);
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

enum _Hide { escape, controller, lifecycle, viewFocus }

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
  const _SimpleNamedCard({
    required this.trigger,
    required this.content,
    this.controller,
  });

  final String trigger;
  final String content;
  final DHoverCardController? controller;

  @override
  Widget build(BuildContext context) => DHoverCard(
    controller: controller,
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

// A reaction pill's panel whose reactors each preview a profile.
class _NestedCards extends StatelessWidget {
  const _NestedCards({this.controller, this.alice});

  final DHoverCardController? controller;
  final DHoverCardController? alice;

  @override
  Widget build(BuildContext context) => DHoverCard(
    controller: controller,
    trigger: DHoverCardTrigger(
      delay: const Duration(milliseconds: 250),
      closeDelay: const Duration(milliseconds: 500),
      builder: (context, state) => TextButton(
        focusNode: state.focusNode,
        onPressed: () {},
        child: const Text('Reactions'),
      ),
    ),
    content: DHoverCardContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Reactors'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SimpleNamedCard(
                trigger: 'Alice',
                content: 'Alice preview',
                controller: alice,
              ),
              const _SimpleNamedCard(trigger: 'Bob', content: 'Bob preview'),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> _openNested(
  WidgetTester tester,
  TestGesture mouse,
  String reactor,
) async {
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.text('Reactions')));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
  await mouse.moveTo(tester.getCenter(find.text('Reactors')));
  await tester.pump();
  await mouse.moveTo(tester.getCenter(find.text(reactor)));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  expect(find.text('Reactors'), findsOneWidget);
  expect(find.text('$reactor preview'), findsOneWidget);
}

Widget _app(Widget child, {Size size = const Size(800, 600)}) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: Scaffold(body: Center(child: child)),
  ),
);
