import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final closing in [false, true]) {
    testWidgets(
      'ticker suspension removes ${closing ? 'a closing' : 'an open'} popover',
      (tester) async {
        final enabled = ValueNotifier(true);
        final controller = DPopoverController();
        final reasons = <DPopoverChangeReason>[];
        final completions = <bool>[];
        addTearDown(enabled.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (context, value, child) =>
                  TickerMode(enabled: value, child: child!),
              child: _TestPopover(
                controller: controller,
                onReason: reasons.add,
                onComplete: completions.add,
              ),
            ),
          ),
        );
        controller.open();
        await tester.pumpAndSettle();
        expect(find.text('Popover title'), findsOneWidget);
        if (closing) {
          controller.close();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 75));
          expect(find.text('Popover title'), findsOneWidget);
        }

        enabled.value = false;
        await tester.pump();
        await tester.pumpAndSettle();
        expect(controller.isOpen, isFalse);
        expect(find.text('Popover title', skipOffstage: false), findsNothing);
        expect(
          reasons.where((reason) => reason == DPopoverChangeReason.lifecycle),
          hasLength(closing ? 0 : 1),
        );
        expect(completions, [true, false]);
        controller.open();
        await tester.pump();
        expect(controller.isOpen, isFalse);
        expect(find.text('Popover title'), findsNothing);

        enabled.value = true;
        await tester.pumpAndSettle();
        expect(find.text('Popover title'), findsNothing);
        controller.open();
        await tester.pumpAndSettle();
        expect(find.text('Popover title'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('only an open anchored popover observes global pointer events', (
    tester,
  ) async {
    final router = GestureBinding.instance.pointerRouter;
    final controllers = [
      for (var index = 0; index < 20; index += 1) DPopoverController(),
    ];
    for (final controller in controllers) {
      addTearDown(controller.dispose);
    }
    final reasons = <DPopoverChangeReason>[];
    Widget popovers({required bool mounted}) => _app(
      Wrap(
        children: [
          if (mounted)
            for (final controller in controllers)
              _TestPopover(controller: controller, onReason: reasons.add),
        ],
      ),
    );

    await tester.pumpWidget(popovers(mounted: false));
    final idle = router.debugGlobalRouteCount;
    await tester.pumpWidget(popovers(mounted: true));
    expect(router.debugGlobalRouteCount, idle);

    controllers.first.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, idle + 1);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(reasons.last, DPopoverChangeReason.outsidePress);
    expect(router.debugGlobalRouteCount, idle);

    controllers[1].open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, idle + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(reasons.last, DPopoverChangeReason.escape);
    expect(controllers[1].isOpen, isFalse);
    expect(router.debugGlobalRouteCount, idle);

    controllers.last.open();
    await tester.pumpAndSettle();
    expect(router.debugGlobalRouteCount, idle + 1);
    await tester.pumpWidget(popovers(mounted: false));
    expect(router.debugGlobalRouteCount, idle);
  });

  testWidgets('a mobile sheet popover never observes global pointer events', (
    tester,
  ) async {
    final router = GestureBinding.instance.pointerRouter;
    final controller = DPopoverController();
    addTearDown(controller.dispose);
    Widget sheet({required bool mounted}) => MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: Center(
          child: mounted
              ? DPopover(
                  controller: controller,
                  sheetOnMobile: true,
                  content: const DPopoverContent(
                    semanticLabel: 'Sheet popover',
                    child: Text('Sheet body'),
                  ),
                  child: DPopoverTrigger(
                    builder: (context, trigger) => DButton(
                      label: const Text('Open sheet'),
                      focusNode: trigger.focusNode,
                      onPressed: trigger.toggle,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpWidget(sheet(mounted: false));
    final idle = router.debugGlobalRouteCount;
    await tester.pumpWidget(sheet(mounted: true));
    controller.open();
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsOneWidget);
    expect(router.debugGlobalRouteCount, idle);
  });

  testWidgets('app suspension finishes a partially dismissed popover', (
    tester,
  ) async {
    final controller = DPopoverController();
    final completions = <bool>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_TestPopover(controller: controller, onComplete: completions.add)),
    );
    controller.open();
    await tester.pumpAndSettle();
    controller.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(find.text('Popover title'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Popover title'), findsNothing);
    expect(completions, [true, false]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsNothing);
  });

  testWidgets('reparented custom anchor re-registers without closing', (
    tester,
  ) async {
    final moved = ValueNotifier(false);
    addTearDown(moved.dispose);
    final anchor = DPopoverAnchor(
      key: GlobalKey(),
      child: const Text('Anchor'),
    );
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: moved,
          builder: (context, right, child) => DPopover(
            defaultOpen: true,
            content: const DPopoverContent(child: Text('Reparented content')),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 120, child: right ? null : anchor),
                SizedBox(width: 120, child: right ? anchor : null),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(DPopoverContent));
    moved.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Reparented content'), findsOneWidget);
    final after = tester.getRect(find.byType(DPopoverContent));
    expect(after.left, greaterThan(before.left + 100));
  });

  testWidgets('removing an open custom anchor avoids inactive layout reads', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, child) => DPopover(
            defaultOpen: true,
            content: const DPopoverContent(child: Text('Anchored content')),
            child: show
                ? const DPopoverAnchor(child: Text('Anchor'))
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anchored content'), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Anchored content'), findsNothing);
  });

  testWidgets('pressing inside a custom anchor does not dismiss its popover', (
    tester,
  ) async {
    final reasons = <DPopoverChangeReason>[];
    var presses = 0;
    await tester.pumpWidget(
      _app(
        DPopover(
          defaultOpen: true,
          onOpenChange: (_, reason) => reasons.add(reason),
          content: const DPopoverContent(child: Text('Anchored content')),
          child: DPopoverAnchor(
            child: DButton(
              label: const Text('Anchor action'),
              onPressed: () => presses += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anchor action'));
    await tester.pumpAndSettle();

    expect(presses, 1);
    expect(find.text('Anchored content'), findsOneWidget);
    expect(reasons, isNot(contains(DPopoverChangeReason.outsidePress)));
  });

  testWidgets(
    'uncontrolled trigger opens, focuses content, and Escape restores',
    (tester) async {
      await tester.pumpWidget(_app(const _TestPopover()));

      final trigger = tester.widget<DButton>(
        find.widgetWithText(DButton, 'Open'),
      );
      trigger.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Popover title'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Popover title'), findsNothing);
      expect(trigger.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('topmost popover owns Escape ahead of ancestor shortcuts', (
    tester,
  ) async {
    var ancestorEscapes = 0;
    await tester.pumpWidget(
      _app(
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              ancestorEscapes += 1;
            },
          },
          child: const _TestPopover(),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Popover title'), findsNothing);
    expect(ancestorEscapes, 0);
  });

  testWidgets('touch opening does not summon the nested text editor', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _TestPopover()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
  });

  testWidgets('outside press and close composition report distinct reasons', (
    tester,
  ) async {
    final reasons = <DPopoverChangeReason>[];
    await tester.pumpWidget(_app(_TestPopover(onReason: reasons.add)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(reasons.last, DPopoverChangeReason.outsidePress);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(reasons.last, DPopoverChangeReason.closePress);
  });

  testWidgets('nested popover owns Escape and pointer interaction first', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _NestedPopoverTest()));
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open child'));
    await tester.pumpAndSettle();

    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Child content'), findsOneWidget);
    await tester.tap(find.text('Use child'));
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Child content'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Child content'), findsNothing);
    expect(find.text('Parent content'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsNothing);
  });

  testWidgets('nested MenuAnchor dismisses before its parent popover', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MenuPopoverTest()));
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Menu choice'), findsOneWidget);
    expect(find.text('Parent content'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Menu choice'), findsNothing);
    expect(find.text('Parent content'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    final parentRect = tester.getRect(find.byType(DPopoverContent));
    final secondChoiceRect = tester.getRect(find.text('Second choice'));
    expect(parentRect.overlaps(secondChoiceRect), isFalse);
    await tester.tap(find.text('Second choice'));
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Selected: second'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsNothing);
  });

  testWidgets('nested Select owns choices and Escape before parent', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _SelectPopoverTest()));
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First choice'));
    await tester.pumpAndSettle();

    final parentRect = tester.getRect(find.byType(DPopoverContent).first);
    final outsideChoiceRect = tester.getRect(find.text('Outside choice'));
    expect(parentRect.overlaps(outsideChoiceRect), isFalse);

    await tester.tap(find.text('Outside choice'));
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsOneWidget);
    expect(find.text('Outside choice'), findsOneWidget);

    await tester.tap(find.text('Outside choice'));
    await tester.pumpAndSettle();
    expect(find.text('First choice'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('First choice'), findsNothing);
    expect(find.text('Parent content'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Parent content'), findsNothing);
  });

  testWidgets('outside field keeps focus after pointer dismissal', (
    tester,
  ) async {
    final outsideFocus = FocusNode();
    addTearDown(outsideFocus.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 700,
          height: 500,
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.bottomCenter,
                child: _TestPopover(),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 260,
                  child: TextField(
                    focusNode: outsideFocus,
                    decoration: const InputDecoration(
                      labelText: 'Outside field',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Outside field'));
    await tester.pumpAndSettle();

    expect(find.text('Popover title'), findsNothing);
    expect(outsideFocus.hasFocus, isTrue);
  });

  testWidgets('controlled state only changes when its owner accepts request', (
    tester,
  ) async {
    final open = ValueNotifier(false);
    final accept = ValueNotifier(false);
    addTearDown(open.dispose);
    addTearDown(accept.dispose);
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: accept,
          builder: (context, accepts, child) => ValueListenableBuilder<bool>(
            valueListenable: open,
            builder: (context, value, child) => _TestPopover(
              open: value,
              onOpen: (requested, reason) {
                if (accepts) open.value = requested;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsNothing);

    accept.value = true;
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsOneWidget);
  });

  testWidgets('controlled lifecycle dismissal reports and resynchronizes', (
    tester,
  ) async {
    final reasons = <DPopoverChangeReason>[];
    final controller = DPopoverController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        _TestPopover(open: true, controller: controller, onReason: reasons.add),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.isOpen, isFalse);
    expect(reasons, contains(DPopoverChangeReason.lifecycle));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    expect(find.text('Popover title'), findsOneWidget);
  });

  testWidgets('controller is borrowed and ignores calls after detaching', (
    tester,
  ) async {
    final controller = DPopoverController();
    final mounted = ValueNotifier(true);
    addTearDown(() {
      mounted.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: mounted,
          builder: (context, value, child) => value
              ? _TestPopover(controller: controller)
              : const Text('Removed'),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    mounted.value = false;
    await tester.pumpAndSettle();
    controller.open();
    expect(controller.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom start geometry uses 6px gap and logical RTL alignment', (
    tester,
  ) async {
    Future<void> verify(TextDirection direction) async {
      await tester.pumpWidget(
        _app(
          Directionality(
            key: ValueKey(direction),
            textDirection: direction,
            child: const Align(
              alignment: Alignment.center,
              child: _TestPopover(align: DPopoverAlign.start),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final trigger = tester.getRect(find.widgetWithText(DButton, 'Open'));
      final popup = tester.getRect(find.byType(DPopoverContent));
      expect(popup.top, closeTo(trigger.bottom + 6, 0.1));
      if (direction == TextDirection.ltr) {
        expect(popup.left, closeTo(trigger.left, 0.1));
      } else {
        expect(popup.right, closeTo(trigger.right, 0.1));
      }
    }

    await verify(TextDirection.ltr);
    await verify(TextDirection.rtl);
  });

  testWidgets('collision flips at an edge and constrains a narrow viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 220,
          height: 180,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _TestPopover(
              width: 288,
              collisionBoundary: Rect.fromLTWH(290, 210, 220, 180),
            ),
          ),
        ),
        size: const Size(220, 180),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final trigger = tester.getRect(find.widgetWithText(DButton, 'Open'));
    final popup = tester.getRect(find.byType(DPopoverContent));
    expect(popup.bottom, lessThanOrEqualTo(trigger.top - 4 + 0.1));
    expect(popup.left, greaterThanOrEqualTo(295));
    expect(popup.right, lessThanOrEqualTo(505));
  });

  testWidgets('custom placement receives geometry and remains collision-safe', (
    tester,
  ) async {
    DPopoverPlacement? placement;
    await tester.pumpWidget(
      _app(
        _TestPopover(
          placementResolver: (value) {
            placement = value;
            return const Offset(-1000, -1000);
          },
        ),
        size: const Size(320, 240),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(placement, isNotNull);
    expect(placement!.target, isNot(Rect.zero));
    expect(placement!.contentSize, isNot(Size.zero));
    expect(placement!.defaultOffset, isNot(const Offset(-1000, -1000)));
    expect(placement!.direction, TextDirection.ltr);
    final popup = tester.getRect(find.byType(DPopoverContent));
    expect(popup.left, greaterThanOrEqualTo(placement!.boundary.left));
    expect(popup.top, greaterThanOrEqualTo(placement!.boundary.top));
  });

  testWidgets('custom anchor moves while the open overlay tracks it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MovingAnchorTest()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final state = tester.state<_MovingAnchorTestState>(
      find.byType(_MovingAnchorTest),
    );
    expect(state._controller.isOpen, isTrue);
    expect(tester.takeException(), isNull);
    expect(find.byType(DPopoverContent, skipOffstage: false), findsOneWidget);
    final before = tester.getRect(find.byType(DPopoverContent));
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(DPopoverContent));
    expect(after.left, greaterThan(before.left + 100));
  });

  testWidgets('reopening uses an anchor moved while the popover was closed', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MovingAnchorTest()));
    final state = tester.state<_MovingAnchorTestState>(
      find.byType(_MovingAnchorTest),
    );
    state._controller.open();
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byType(DPopoverContent));
    state._controller.close();
    await tester.pumpAndSettle();
    state.moveRight();
    await tester.pumpAndSettle();
    expect(find.byType(DPopoverContent), findsNothing);
    state._controller.open();
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(DPopoverContent));
    expect(after.left, greaterThan(before.left + 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening follows an anchor moved in the frame that opens it', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _MovingAnchorTest()));
    final state = tester.state<_MovingAnchorTestState>(
      find.byType(_MovingAnchorTest),
    );
    state.moveRight();
    state._controller.open();
    await tester.pumpAndSettle();

    final anchor = tester.getRect(find.byType(DPopoverAnchor));
    final popup = tester.getRect(find.byType(DPopoverContent));
    expect(popup.center.dx, moreOrLessEquals(anchor.center.dx, epsilon: 1));
    expect(popup.top, greaterThanOrEqualTo(anchor.bottom));
  });

  testWidgets('closed popovers skip anchor transforms while painting', (
    tester,
  ) async {
    final repaint = ValueNotifier(0);
    addTearDown(repaint.dispose);
    final controllers = [
      for (var index = 0; index < 20; index += 1) DPopoverController(),
    ];
    for (final controller in controllers) {
      addTearDown(controller.dispose);
    }
    await tester.pumpWidget(
      _app(
        _TransformProbe(
          child: Wrap(
            children: [
              for (final controller in controllers)
                DPopover(
                  controller: controller,
                  content: const DPopoverContent(child: Text('Content')),
                  child: DPopoverTrigger(
                    builder: (context, trigger) => CustomPaint(
                      size: const Size.square(24),
                      painter: _RepaintProbe(repaint),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final probe = tester.renderObject<_RenderTransformProbe>(
      find.byType(_TransformProbe),
    );
    Future<int> walksWhileRepainting() async {
      probe.walks = 0;
      repaint.value += 1;
      await tester.pump();
      // An anchor that stayed put must not schedule another placement pass.
      expect(tester.binding.hasScheduledFrame, isFalse);
      return probe.walks;
    }

    expect(await walksWhileRepainting(), 0);

    controllers.first.open();
    await tester.pumpAndSettle();
    expect(await walksWhileRepainting(), 1);

    controllers.first.close();
    await tester.pumpAndSettle();
    expect(await walksWhileRepainting(), 0);
  });

  testWidgets('surface keeps independent semantics and reads live theme', (
    tester,
  ) async {
    final dark = ValueNotifier(false);
    addTearDown(dark.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (context, value, child) => MaterialApp(
          theme: value ? AppTheme.dark : AppTheme.light,
          home: const Scaffold(body: Center(child: _TestPopover())),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final semantics = tester.getSemantics(find.byType(DPopoverContent));
    expect(semantics.label, contains('Test popover'));
    expect(find.byType(TextField), findsOneWidget);
    final surface = _surfaceDecoration(tester);
    expect(surface.boxShadow, isEmpty);
    final light = surface.color;

    dark.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Popover title'), findsOneWidget);
    expect(_surfaceDecoration(tester).color, isNot(light));
  });

  testWidgets('large text and reduced motion remain bounded', (tester) async {
    await tester.pumpWidget(
      _app(
        const MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: _TestPopover(width: 210),
        ),
        size: const Size(240, 400),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text('Popover title'), findsOneWidget);
    expect(
      tester.getSize(find.byType(DPopoverContent)).width,
      lessThanOrEqualTo(230),
    );
    expect(tester.takeException(), isNull);
  });
}

BoxDecoration _surfaceDecoration(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(DPopoverContent),
        matching: find.byType(DecoratedBox),
      ),
    )
    .map((widget) => widget.decoration)
    .whereType<BoxDecoration>()
    .firstWhere(
      (decoration) => decoration.borderRadius == BorderRadius.circular(10),
    );

Widget _app(Widget child, {Size size = const Size(800, 600)}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(size: size),
    child: Scaffold(body: Center(child: child)),
  ),
);

class _TestPopover extends StatelessWidget {
  const _TestPopover({
    this.open,
    this.onOpen,
    this.onReason,
    this.onComplete,
    this.controller,
    this.align = DPopoverAlign.center,
    this.width = 220,
    this.collisionBoundary,
    this.placementResolver,
  });

  final bool? open;
  final DPopoverOpenChange? onOpen;
  final ValueChanged<DPopoverChangeReason>? onReason;
  final ValueChanged<bool>? onComplete;
  final DPopoverController? controller;
  final DPopoverAlign align;
  final double width;
  final Rect? collisionBoundary;
  final DPopoverPlacementResolver? placementResolver;

  @override
  Widget build(BuildContext context) => DPopover(
    open: open,
    controller: controller,
    onOpenChangeComplete: onComplete,
    onOpenChange: (value, reason) {
      onReason?.call(reason);
      onOpen?.call(value, reason);
    },
    content: DPopoverContent(
      width: width,
      align: align,
      collisionBoundary: collisionBoundary,
      placementResolver: placementResolver,
      semanticLabel: 'Test popover',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DPopoverHeader(
            children: [
              DPopoverTitle(child: Text('Popover title')),
              DPopoverDescription(child: Text('Description')),
            ],
          ),
          const TextField(decoration: InputDecoration(labelText: 'Width')),
          DPopoverClose(
            builder: (context, close) =>
                DButton(label: const Text('Close'), onPressed: close),
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open'),
        variant: DButtonVariant.outline,
        hasPopup: true,
        expanded: trigger.open,
        focusNode: trigger.focusNode,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _NestedPopoverTest extends StatelessWidget {
  const _NestedPopoverTest();

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent content'),
          DPopover(
            content: DPopoverContent(
              width: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Child content'),
                  DButton(label: const Text('Use child'), onPressed: () {}),
                ],
              ),
            ),
            child: DPopoverTrigger(
              builder: (context, trigger) => DButton(
                label: const Text('Open child'),
                focusNode: trigger.focusNode,
                hasPopup: true,
                expanded: trigger.open,
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open parent'),
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _MenuPopoverTest extends StatefulWidget {
  const _MenuPopoverTest();

  @override
  State<_MenuPopoverTest> createState() => _MenuPopoverTestState();
}

class _MenuPopoverTestState extends State<_MenuPopoverTest> {
  String _selected = 'none';

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent content'),
          MenuAnchor(
            alignmentOffset: const Offset(180, 0),
            menuChildren: [
              MenuItemButton(
                onPressed: () => setState(() => _selected = 'first'),
                child: const Text('Menu choice'),
              ),
              MenuItemButton(
                onPressed: () => setState(() => _selected = 'second'),
                child: const Text('Second choice'),
              ),
            ],
            builder: (context, controller, child) => DButton(
              label: const Text('Open menu'),
              hasPopup: true,
              onPressed: controller.open,
            ),
          ),
          Text('Selected: $_selected'),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open parent'),
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _SelectPopoverTest extends StatefulWidget {
  const _SelectPopoverTest();

  @override
  State<_SelectPopoverTest> createState() => _SelectPopoverTestState();
}

class _SelectPopoverTestState extends State<_SelectPopoverTest> {
  String _selected = 'first';

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Parent content'),
          DSelect<String>.controlled(
            value: _selected,
            entries: const [
              DSelectOption(
                value: null,
                label: 'Select an option',
                child: Text('Select an option'),
              ),
              DSelectOption(
                value: 'first',
                label: 'First choice',
                child: Text('First choice'),
              ),
              DSelectOption(
                value: 'outside',
                label: 'Outside choice',
                child: Text('Outside choice'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selected = value);
            },
          ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: const Text('Open parent'),
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _MovingAnchorTest extends StatefulWidget {
  const _MovingAnchorTest();

  @override
  State<_MovingAnchorTest> createState() => _MovingAnchorTestState();
}

class _MovingAnchorTestState extends State<_MovingAnchorTest> {
  bool _right = false;
  final _controller = DPopoverController();

  void moveRight() => setState(() => _right = true);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 600,
    height: 180,
    child: DPopover(
      controller: _controller,
      content: DPopoverContent(
        width: 140,
        side: DPopoverSide.bottom,
        align: DPopoverAlign.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Moving content'),
            DButton(label: const Text('Move'), onPressed: moveRight),
          ],
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: _right ? Alignment.topRight : Alignment.topLeft,
            child: const DPopoverAnchor(child: SizedBox.square(dimension: 20)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DPopoverTrigger(
              builder: (context, trigger) => DButton(
                label: const Text('Open'),
                focusNode: trigger.focusNode,
                onPressed: trigger.toggle,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TransformProbe extends SingleChildRenderObjectWidget {
  const _TransformProbe({required super.child});

  @override
  _RenderTransformProbe createRenderObject(BuildContext context) =>
      _RenderTransformProbe();
}

// Counts the transform walks its descendants make through it while painting.
// Semantics and the overlay's layout builder walk too, but in other phases.
class _RenderTransformProbe extends RenderProxyBox {
  int walks = 0;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (owner!.debugDoingPaint) walks += 1;
    super.applyPaintTransform(child, transform);
  }
}

class _RepaintProbe extends CustomPainter {
  _RepaintProbe(Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_RepaintProbe oldDelegate) => false;
}
