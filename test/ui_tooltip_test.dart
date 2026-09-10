import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = SizedBox(
  width: 80,
  height: 40,
  child: Center(child: Text('Target')),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool still = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            textScaler: TextScaler.linear(scale),
            disableAnimations: still,
          ),
          child: Directionality(
            textDirection: direction,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<TestGesture> _mouse(
  WidgetTester tester,
  Finder target, {
  Duration wait = const Duration(milliseconds: 250),
}) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(wait);
  return mouse;
}

Finder get _hint => find.text('Information');
Finder _surface(Finder hint) =>
    find.ancestor(of: hint, matching: find.byType(SingleChildScrollView)).first;

void main() {
  testWidgets(
    'default source metrics, wrapped content and shortcut colors are live',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      for (final palette in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        final theme = palette.resolve(AppTheme.light);
        await _pump(
          tester,
          DTooltip(
            controller: controller,
            message: 'Information',
            shortcut: const DShortcut(SingleActivator(LogicalKeyboardKey.keyS)),
            child: _target,
          ),
          theme: theme,
          still: true,
        );
        controller.show();
        await tester.pump();
        final style = DefaultTextStyle.of(tester.element(_hint)).style;
        expect(style.fontSize, 12);
        expect(style.height, 16 / 12);
        expect(style.fontWeight, FontWeight.w400);
        expect(style.letterSpacing, 0);
        expect(style.color, theme.extension<DTokens>()!.background);
        expect(tester.getSize(_surface(_hint)).height, 32);
        final kbd = tester.element(find.byType(DKbd));
        expect(DKbdTheme.maybeOf(kbd)!.foregroundColor, style.color);
        expect(
          tester.getTopLeft(_hint).dx - tester.getTopLeft(_surface(_hint)).dx,
          12,
        );
        final target = tester.getRect(find.text('Target'));
        expect(tester.getRect(_surface(_hint)).bottom, lessThan(target.top));
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    for (final side in DTooltipSide.values) {
      testWidgets('${side.name} resolves in ${direction.name} with a 4px gap', (
        tester,
      ) async {
        await _pump(
          tester,
          DTooltip(
            message: 'Information',
            side: side,
            defaultOpen: true,
            child: _target,
          ),
          direction: direction,
          still: true,
        );
        final anchor = tester.getRect(find.byType(DTooltip));
        final popup = tester.getRect(_surface(_hint));
        final actual = switch (side) {
          DTooltipSide.inlineStart =>
            direction == TextDirection.ltr
                ? DTooltipSide.left
                : DTooltipSide.right,
          DTooltipSide.inlineEnd =>
            direction == TextDirection.ltr
                ? DTooltipSide.right
                : DTooltipSide.left,
          _ => side,
        };
        switch (actual) {
          case DTooltipSide.top:
            expect(anchor.top - popup.bottom, 4);
          case DTooltipSide.bottom:
            expect(popup.top - anchor.bottom, 4);
          case DTooltipSide.left:
            expect(anchor.left - popup.right, 4);
          default:
            expect(popup.left - anchor.right, 4);
        }
      });
    }
  }

  testWidgets('start and end alignment and offsets follow text direction', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      for (final align in [DTooltipAlign.start, DTooltipAlign.end]) {
        await _pump(
          tester,
          DTooltip(
            key: ValueKey('$direction$align'),
            message: 'Information',
            defaultOpen: true,
            align: align,
            sideOffset: 8,
            alignOffset: 4,
            child: _target,
          ),
          direction: direction,
          still: true,
        );
        final anchor = tester.getRect(find.byType(DTooltip));
        final popup = tester.getRect(_surface(_hint));
        expect(anchor.top - popup.bottom, 8);
        final offset = direction == TextDirection.ltr ? 4 : -4;
        if ((align == DTooltipAlign.start) ==
            (direction == TextDirection.ltr)) {
          expect(popup.left, anchor.left + offset);
        } else {
          expect(popup.right, anchor.right + offset);
        }
      }
    }
  });

  testWidgets(
    'flips from the top edge and stays inside a nested narrow overlay at 200 percent',
    (tester) async {
      await _pump(
        tester,
        SizedBox(
          key: const ValueKey('preview'),
          width: 180,
          height: 200,
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Align(
                alignment: Alignment.topLeft,
                child: DTooltip(
                  message:
                      'A long explanation that wraps with enlarged accessible text without leaving this preview.',
                  defaultOpen: true,
                  child: _target,
                ),
              ),
            ),
          ),
        ),
        scale: 2,
        still: true,
      );
      await tester.pump();
      final anchor = tester.getRect(find.byType(DTooltip));
      final hint = find.textContaining('A long explanation');
      final rect = tester.getRect(_surface(hint));
      final boundary = tester.getRect(find.byKey(const ValueKey('preview')));
      expect(rect.top, anchor.bottom + 4);
      expect(rect.left, greaterThanOrEqualTo(boundary.left + 5));
      expect(rect.right, lessThanOrEqualTo(boundary.right - 5));
      expect(rect.bottom, lessThanOrEqualTo(boundary.bottom - 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a clipped trigger can show its popup in the nearest overlay', (
    tester,
  ) async {
    await _pump(
      tester,
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: const DTooltip(
          message: 'Information',
          defaultOpen: true,
          child: _target,
        ),
      ),
      still: true,
    );
    expect(_hint, findsOneWidget);
    expect(tester.getRect(_surface(_hint)).height, 28);
    expect(
      tester.getRect(_surface(_hint)).bottom,
      tester.getRect(find.byType(DTooltip)).top - 4,
    );
  });

  for (final grouped in [false, true]) {
    testWidgets('default hover waits 250 ms (provider: $grouped)', (
      tester,
    ) async {
      const tooltip = DTooltip(message: 'Information', child: _target);
      await _pump(
        tester,
        grouped ? const DTooltipProvider(child: tooltip) : tooltip,
        still: true,
      );
      await _mouse(tester, find.text('Target'), wait: Duration.zero);
      expect(_hint, findsNothing);
      await tester.pump(const Duration(milliseconds: 249));
      expect(_hint, findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_hint, findsOneWidget);
    });
  }

  testWidgets('leaving early cancels hover and re-entry starts a full delay', (
    tester,
  ) async {
    await _pump(
      tester,
      const DTooltip(message: 'Information', child: _target),
      still: true,
    );
    final mouse = await _mouse(
      tester,
      find.text('Target'),
      wait: const Duration(milliseconds: 200),
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_hint, findsNothing);
    await mouse.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 249));
    expect(_hint, findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_hint, findsOneWidget);
  });

  testWidgets('group delay is skipped only during its warm interval', (
    tester,
  ) async {
    await _pump(
      tester,
      DTooltipProvider(
        delay: const Duration(milliseconds: 600),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final label in ['One', 'Two'])
              DTooltip(
                message: '$label hint',
                child: SizedBox(width: 80, height: 40, child: Text(label)),
              ),
          ],
        ),
      ),
      still: true,
    );
    final mouse = await _mouse(tester, find.text('One'), wait: Duration.zero);
    await tester.pump(const Duration(milliseconds: 599));
    expect(find.text('One hint'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('One hint'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text('Two')));
    await tester.pump();
    expect(find.text('Two hint'), findsOneWidget);
    expect(find.text('One hint'), findsNothing);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 401));
    await mouse.moveTo(tester.getCenter(find.text('One')));
    await tester.pump(const Duration(milliseconds: 599));
    expect(find.text('One hint'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('One hint'), findsOneWidget);
  });

  testWidgets(
    'popup and pointer bridge remain hoverable until the pointer leaves',
    (tester) async {
      await _pump(
        tester,
        const DTooltip(message: 'Information', sideOffset: 12, child: _target),
        still: true,
      );
      final mouse = await _mouse(tester, find.text('Target'));
      final popup = tester.getRect(_surface(_hint));
      final anchor = tester.getRect(find.byType(DTooltip));
      await mouse.moveTo(Offset(anchor.center.dx, anchor.top - 6));
      await tester.pump(const Duration(seconds: 1));
      expect(_hint, findsOneWidget);
      await mouse.moveTo(popup.center);
      await tester.pump(const Duration(seconds: 1));
      expect(_hint, findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'keyboard focus opens, Escape dismisses without blurring or closing a parent route',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var actions = 0;
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          child: DButton(
            focusNode: focus,
            label: const Text('Target'),
            onPressed: () => actions++,
          ),
        ),
        still: true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(_hint, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_hint, findsNothing);
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(actions, 1);
    },
  );

  testWidgets(
    'disabled trigger is explainable by Tab while its action stays disabled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          const DTooltip(
            message: 'Information',
            focusable: true,
            child: DButton(label: Text('Target'), onPressed: null),
          ),
          still: true,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_hint, findsOneWidget);
        expect(
          tester.getSemantics(find.byType(DButton)).flagsCollection.isEnabled ==
              Tristate.isTrue,
          isFalse,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'touch long press does not activate and closes after release delay',
    (tester) async {
      var actions = 0;
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          touchDelay: const Duration(milliseconds: 900),
          child: DButton(
            label: const Text('Target'),
            onPressed: () => actions++,
          ),
        ),
        still: true,
      );
      await tester.longPress(find.text('Target'));
      await tester.pump();
      expect(actions, 0);
      expect(_hint, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      expect(_hint, findsNothing);
      await tester.tap(find.text('Target'));
      await tester.pump();
      expect(actions, 1);
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'controlled state reports requests and cannot be changed by its controller',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      final requests = <(bool, DTooltipChangeReason)>[];
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, value, _) => DTooltip(
            message: 'Information',
            controller: controller,
            open: value,
            onOpenChange: (value, reason) => requests.add((value, reason)),
            child: _target,
          ),
        ),
        still: true,
      );
      controller.show();
      await tester.pump();
      expect(_hint, findsNothing);
      expect(requests, [(true, DTooltipChangeReason.imperative)]);
      open.value = true;
      await tester.pump();
      await tester.pump();
      expect(_hint, findsOneWidget);
      controller.hide();
      await tester.pump();
      expect(_hint, findsOneWidget);
      expect(requests.last, (false, DTooltipChangeReason.imperative));
      open.value = false;
      await tester.pump();
      await tester.pump();
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'controller selects multiple triggers and detached calls never replay',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      controller.show();
      Widget triggers() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final id in ['One', 'Two'])
            DTooltip(
              message: '$id hint',
              triggerId: id,
              controller: controller,
              child: Text(id),
            ),
        ],
      );
      await _pump(tester, triggers(), still: true);
      expect(controller.isOpen, isFalse);
      controller.show(triggerId: 'Two');
      await tester.pump();
      expect(find.text('Two hint'), findsOneWidget);
      expect(controller.activeTriggerId, 'Two');
      controller.show(triggerId: 'One');
      await tester.pump();
      expect(find.text('One hint'), findsOneWidget);
      expect(find.text('Two hint'), findsNothing);
      await _pump(tester, const SizedBox(), still: true);
      expect(controller.isOpen, isFalse);
      controller.show();
      await _pump(tester, triggers(), still: true);
      expect(controller.isOpen, isFalse);
      expect(find.text('One hint'), findsNothing);
    },
  );

  testWidgets(
    'semantics describes a shortcut once and excludes popup content',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          const DTooltip(
            message: 'Information',
            defaultOpen: true,
            shortcut: DShortcut(
              SingleActivator(LogicalKeyboardKey.keyS, control: true),
            ),
            child: _target,
          ),
          still: true,
        );
        expect(
          tester.getSemantics(find.text('Target')).getSemanticsData().tooltip,
          'Information, Control + S',
        );
        expect(find.bySemanticsLabel('Information'), findsNothing);
        await _pump(
          tester,
          const DTooltip(
            message: 'Information',
            excludeFromSemantics: true,
            child: _target,
          ),
          still: true,
        );
        expect(
          tester.getSemantics(find.text('Target')).getSemanticsData().tooltip,
          '',
        );
        expect(find.byTooltip('Information'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('scrolling tracks the anchor then removes an offscreen popup', (
    tester,
  ) async {
    final scroll = ScrollController();
    final controller = DTooltipController();
    addTearDown(scroll.dispose);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      SizedBox(
        width: 300,
        height: 250,
        child: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              const SizedBox(height: 80),
              DTooltip(
                message: 'Information',
                controller: controller,
                child: _target,
              ),
              const SizedBox(height: 700),
            ],
          ),
        ),
      ),
      still: true,
    );
    controller.show();
    await tester.pump();
    final before = tester.getTopLeft(_hint).dy;
    scroll.jumpTo(10);
    await tester.pump();
    expect(tester.getTopLeft(_hint).dy, before - 10);
    scroll.jumpTo(300);
    await tester.pump();
    await tester.pump();
    expect(_hint, findsNothing);
    expect(controller.isOpen, isFalse);
  });

  testWidgets(
    'hidden panes and lifecycle cancel pending and open hints without remounting controls',
    (tester) async {
      final visible = ValueNotifier(true);
      final controller = DTooltipController();
      addTearDown(visible.dispose);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, value, _) => TooltipVisibility(
            visible: value,
            child: DTooltip(
              message: 'Information',
              controller: controller,
              hoverDelay: const Duration(milliseconds: 500),
              child: _target,
            ),
          ),
        ),
        still: true,
      );
      await _mouse(tester, find.text('Target'));
      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_hint, findsNothing);
      visible.value = true;
      await tester.pump();
      controller.show();
      await tester.pump();
      expect(_hint, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_hint, findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_hint, findsNothing);
    },
  );

  testWidgets('cursor tracking moves a popup without activating its child', (
    tester,
  ) async {
    await _pump(
      tester,
      const DTooltip(
        message: 'Information',
        trackCursorAxis: DTooltipTrackCursor.x,
        child: _target,
      ),
      still: true,
    );
    final mouse = await _mouse(tester, find.text('Target'));
    final before = tester.getTopLeft(_hint);
    await mouse.moveTo(
      tester.getCenter(find.text('Target')) + const Offset(20, 0),
    );
    await tester.pump();
    expect(tester.getTopLeft(_hint).dx, before.dx + 20);
  });

  testWidgets(
    'replacing an open borrowed controller updates listeners and keeps hide usable',
    (tester) async {
      final first = DTooltipController();
      final second = DTooltipController();
      final selected = ValueNotifier<DTooltipController?>(first);
      final present = ValueNotifier(true);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(selected.dispose);
      addTearDown(present.dispose);
      final firstEvents = <bool>[];
      final secondEvents = <bool>[];
      first.addListener(() => firstEvents.add(first.isOpen));
      second.addListener(() => secondEvents.add(second.isOpen));
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([first, second]),
              builder: (_, _) => Text('${first.isOpen}/${second.isOpen}'),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: present,
              builder: (_, visible, _) => visible
                  ? ValueListenableBuilder<DTooltipController?>(
                      valueListenable: selected,
                      builder: (_, controller, _) => DTooltip(
                        message: 'Information',
                        controller: controller,
                        child: _target,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        still: true,
      );
      first.show();
      await tester.pumpAndSettle();
      expect(find.text('true/false'), findsOneWidget);

      selected.value = second;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(first.isOpen, isFalse);
      expect(second.isOpen, isTrue);
      expect(find.text('false/true'), findsOneWidget);
      expect(firstEvents, [true, false]);
      expect(secondEvents, [true]);
      second.hide();
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);

      second.show();
      await tester.pumpAndSettle();
      present.value = false;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(second.isOpen, isFalse);
      expect(find.text('false/false'), findsOneWidget);
      expect(secondEvents, [true, false, true, false]);
      // Neither borrowed handle is disposed by its former trigger.
      first.addListener(() {});
      second.addListener(() {});
      second.show();
      await tester.pumpAndSettle();
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'a handle attached to an already-open controlled tooltip requests its parent',
    (tester) async {
      final controller = DTooltipController();
      final selected = ValueNotifier<DTooltipController?>(null);
      final open = ValueNotifier(true);
      addTearDown(controller.dispose);
      addTearDown(selected.dispose);
      addTearDown(open.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<DTooltipController?>(
          valueListenable: selected,
          builder: (_, handle, _) => ValueListenableBuilder<bool>(
            valueListenable: open,
            builder: (_, value, _) => DTooltip(
              message: 'Information',
              controller: handle,
              triggerId: 'controlled',
              open: value,
              onOpenChange: (next, reason) {
                expect(reason, DTooltipChangeReason.imperative);
                open.value = next;
              },
              child: _target,
            ),
          ),
        ),
        still: true,
      );
      selected.value = controller;
      await tester.pumpAndSettle();
      expect(controller.activeTriggerId, 'controlled');
      controller.hide();
      await tester.pumpAndSettle();
      expect(open.value, isFalse);
      expect(controller.isOpen, isFalse);
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'immediate dismissal removes an exit in progress including a controlled close',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          controller: controller,
          child: _target,
        ),
      );
      controller.show();
      await tester.pumpAndSettle();
      controller.hide();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_hint, findsOneWidget);
      controller.dismiss();
      await tester.pump();
      expect(_hint, findsNothing);
      final open = ValueNotifier(true);
      addTearDown(open.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (_, value, _) => DTooltip(
            message: 'Information',
            controller: controller,
            open: value,
            onOpenChange: (value, _) => open.value = value,
            child: _target,
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(_hint, findsOneWidget);
      controller.dismiss();
      await tester.pump();
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'pressing and scrolling inside the popup keeps it open while outside press dismisses',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          controller: controller,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < 40; i++) Text('Line $i')],
          ),
          child: _target,
        ),
        still: true,
      );
      controller.show();
      await tester.pump();
      final surface = _surface(find.text('Line 0'));
      await tester.tapAt(tester.getCenter(surface));
      await tester.pump();
      expect(controller.isOpen, isTrue);
      final initialY = tester.getTopLeft(find.text('Line 0')).dy;
      await tester.drag(surface, const Offset(0, -80));
      await tester.pump();
      expect(controller.isOpen, isTrue);
      expect(tester.getTopLeft(find.text('Line 0')).dy, lessThan(initialY));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(controller.isOpen, isFalse);
    },
  );

  testWidgets(
    'tap trigger preserves the button action and ignores scroll gestures',
    (tester) async {
      var actions = 0;
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          triggerMode: TooltipTriggerMode.tap,
          child: DButton(
            label: const Text('Target'),
            onPressed: () => actions++,
          ),
        ),
        still: true,
      );
      await tester.tap(find.text('Target'));
      await tester.pump();
      expect(actions, 1);
      expect(_hint, findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pump();
      await tester.drag(find.text('Target'), const Offset(0, 50));
      await tester.pump();
      expect(actions, 1);
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'an imperatively opened popup survives unrelated pointer movement until the pointer leaves its trigger',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          controller: controller,
          child: _target,
        ),
        still: true,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      controller.show();
      await tester.pump();
      expect(_hint, findsOneWidget);
      await mouse.moveTo(const Offset(40, 40));
      await tester.pump();
      await mouse.moveTo(const Offset(60, 90));
      await tester.pump();
      expect(_hint, findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.text('Target')));
      await tester.pump();
      expect(_hint, findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'the close delay keeps its deadline while the pointer moves outside the pair',
    (tester) async {
      await _pump(
        tester,
        const DTooltip(
          message: 'Information',
          dismissDelay: Duration(milliseconds: 200),
          child: _target,
        ),
        still: true,
      );
      final mouse = await _mouse(tester, find.text('Target'));
      expect(_hint, findsOneWidget);
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 150));
      await mouse.moveTo(const Offset(30, 30));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_hint, findsOneWidget);
      await mouse.moveTo(const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 20));
      expect(_hint, findsNothing);
    },
  );

  testWidgets(
    'side arrows sit at the popup middle while top arrows follow the anchor',
    (tester) async {
      const arrow = Rect.fromLTWH(-5, -5, 10, 10);
      for (final side in [DTooltipSide.left, DTooltipSide.top]) {
        await _pump(
          tester,
          DTooltip(
            key: ValueKey(side),
            message: 'Information',
            side: side,
            align: DTooltipAlign.start,
            defaultOpen: true,
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Information'),
                Text('Second line'),
                Text('Third line'),
              ],
            ),
            child: _target,
          ),
          still: true,
        );
        await tester.pump();
        final popup = tester.getRect(_surface(_hint));
        final anchor = tester.getRect(find.byType(DTooltip));
        final tip = side == DTooltipSide.left
            ? Offset(
                popup.left + (popup.width - 1),
                popup.top + popup.height / 2,
              )
            : Offset(anchor.center.dx, popup.top + (popup.height - 2));
        expect(popup.height, greaterThan(anchor.height));
        expect(
          tester.renderObject(find.byType(Overlay)),
          paints
            ..translate(x: tip.dx, y: tip.dy)
            ..rotate(angle: math.pi / 4)
            ..rrect(
              rrect: RRect.fromRectAndRadius(arrow, const Radius.circular(2)),
            ),
          reason: side.name,
        );
      }
    },
  );

  testWidgets(
    'the focusable wrapper paints a 3px half-opacity ring outside the trigger',
    (tester) async {
      await _pump(
        tester,
        const DTooltip(
          message: 'Information',
          focusable: true,
          child: DButton(
            label: Text('Target'),
            variant: DButtonVariant.outline,
            onPressed: null,
          ),
        ),
        still: true,
      );
      final ring = find
          .ancestor(
            of: find.byType(DButton),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final tokens = DTokens.of(tester.element(ring));
      final inner = tokens.borderRadius.toRRect(
        Offset.zero & tester.getSize(ring),
      );
      final ringPaint = paints
        ..drrect(
          outer: inner.inflate(3),
          inner: inner,
          color: tokens.focusRing.withValues(alpha: .5),
        );
      expect(tester.renderObject(ring), isNot(ringPaint));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_hint, findsOneWidget);
      expect(tester.renderObject(ring), ringPaint);
    },
  );

  testWidgets(
    'keycap tint multiplies the background alpha by its light and dark factors',
    (tester) async {
      const background = Color(0x80FFFFFF);
      for (final (theme, factor) in [
        (AppTheme.light, .2),
        (AppTheme.dark, .1),
      ]) {
        final tokens = theme.extension<DTokens>()!;
        await _pump(
          tester,
          DTooltip(
            key: ValueKey(theme.brightness),
            message: 'Information',
            defaultOpen: true,
            shortcut: const DShortcut(SingleActivator(LogicalKeyboardKey.keyS)),
            child: _target,
          ),
          theme: theme.copyWith(
            extensions: [
              ...theme.extensions.values.where((e) => e is! DTokens),
              tokens.copyWith(background: background),
            ],
          ),
          still: true,
        );
        await tester.pump();
        final keycaps = DKbdTheme.maybeOf(tester.element(find.byType(DKbd)))!;
        expect(keycaps.foregroundColor, background);
        expect(
          keycaps.backgroundColor,
          background.withValues(alpha: background.a * factor),
          reason: theme.brightness.name,
        );
      }
    },
  );

  testWidgets('nested tooltips open only the innermost trigger', (
    tester,
  ) async {
    await _pump(
      tester,
      const DTooltip(
        message: 'Outer',
        child: Padding(
          padding: EdgeInsets.all(20),
          child: DTooltip(message: 'Information', child: _target),
        ),
      ),
      still: true,
    );
    await _mouse(tester, find.text('Target'));
    expect(_hint, findsOneWidget);
    expect(find.text('Outer'), findsNothing);
  });

  testWidgets(
    'reduced motion removes an open exit immediately and disabled tooltip leaves the action usable',
    (tester) async {
      final controller = DTooltipController();
      addTearDown(controller.dispose);
      var actions = 0;
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          controller: controller,
          child: DButton(
            label: const Text('Target'),
            onPressed: () => actions++,
          ),
        ),
        still: true,
      );
      controller.show();
      await tester.pump();
      controller.hide();
      await tester.pump();
      expect(_hint, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      await _pump(
        tester,
        DTooltip(
          message: 'Information',
          disabled: true,
          child: DButton(
            label: const Text('Target'),
            onPressed: () => actions++,
          ),
        ),
        still: true,
      );
      await tester.tap(find.text('Target'));
      await tester.pump();
      expect(actions, 1);
      expect(_hint, findsNothing);
    },
  );
}
