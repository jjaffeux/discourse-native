import 'dart:ui'
    show Tristate, ViewFocusDirection, ViewFocusEvent, ViewFocusState;

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
      theme: (theme ?? AppTheme.light).copyWith(platform: TargetPlatform.macOS),
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

int _nextMouse = 20;
Future<TestGesture> _mouse(
  WidgetTester tester,
  Finder target, {
  Duration wait = const Duration(milliseconds: 250),
}) async {
  final mouse = TestGesture(
    dispatcher: tester.sendEventToBinding,
    kind: PointerDeviceKind.mouse,
    device: _nextMouse++,
  );
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(wait);
  return mouse;
}

enum _Hide { escape, lifecycle, viewFocus }

Finder get _hint => find.text('Information');
Finder _surface(Finder hint) =>
    find.ancestor(of: hint, matching: find.byType(SingleChildScrollView)).first;

void main() {
  testWidgets(
    'default source metrics, wrapped content and shortcut colors are live',
    (tester) async {
      for (final palette in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        final theme = palette.resolve(AppTheme.light);
        await _pump(
          tester,
          const DTooltip(
            message: 'Information',
            shortcut: DShortcut(SingleActivator(LogicalKeyboardKey.keyS)),
            child: _target,
          ),
          theme: theme,
          still: true,
        );
        await _mouse(tester, find.byType(DTooltip));
        await tester.pump();
        final style = DefaultTextStyle.of(tester.element(_hint)).style;
        expect(style.fontSize, 12);
        expect(style.height, DiscourseTypography.lineHeightCaption);
        expect(style.fontWeight, FontWeight.w400);
        expect(style.letterSpacing, 0);
        final tokens = theme.extension<DTokens>()!;
        expect(style.color, tokens.foreground);
        expect(
          tester.renderObject(find.byType(Overlay)),
          paints
            ..path(color: tokens.surface, style: PaintingStyle.fill)
            ..path(
              color: Color.lerp(tokens.surface, tokens.foreground, .12),
              style: PaintingStyle.stroke,
              strokeWidth: 1,
            ),
        );
        expect(tester.getSize(_surface(_hint)).height, 32);
        final kbd = tester.element(find.byType(DKbd));
        expect(DKbdTheme.maybeOf(kbd)!.foregroundColor, style.color);
        expect(DKbdTheme.maybeOf(kbd)!.backgroundColor, tokens.muted);
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
          DTooltip(message: 'Information', side: side, child: _target),
          direction: direction,
          still: true,
        );
        await _mouse(tester, find.byType(DTooltip));
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

                  child: _target,
                ),
              ),
            ),
          ),
        ),
        scale: 2,
        still: true,
      );
      await _mouse(tester, find.byType(DTooltip));
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
        child: const DTooltip(message: 'Information', child: _target),
      ),
      still: true,
    );
    await _mouse(tester, find.byType(DTooltip));
    expect(_hint, findsOneWidget);
    expect(tester.getRect(_surface(_hint)).height, 30);
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
        const DTooltip(message: 'Information', child: _target),
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

  for (final how in _Hide.values) {
    testWidgets(
      'a popup hidden under the pointer by ${how.name} does not stay hovered',
      (tester) async {
        await _pump(
          tester,
          const DTooltip(
            message: 'Information',
            dismissDelay: Duration(milliseconds: 200),
            child: _target,
          ),
        );
        final mouse = await _mouse(tester, find.text('Target'));
        await tester.pumpAndSettle();
        await mouse.moveTo(tester.getCenter(_surface(_hint)));
        await tester.pumpAndSettle();
        expect(_hint, findsOneWidget);

        // The popup leaves the tree under the pointer, so its region never
        // reports an exit.
        switch (how) {
          case _Hide.escape:
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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
        expect(_hint, findsNothing);

        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(find.text('Target')));
        await tester.pump(DTooltip.defaultHoverDelay);
        await tester.pumpAndSettle();
        expect(_hint, findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 199));
        expect(_hint, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(_hint, findsNothing);
      },
    );
  }

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
      await tester.pump(
        tester.widget<DTooltip>(find.byType(DTooltip)).touchDelay,
      );
      expect(_hint, findsNothing);
      await tester.tap(find.text('Target'));
      await tester.pump();
      expect(actions, 1);
      expect(_hint, findsNothing);
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

            shortcut: DShortcut(
              SingleActivator(LogicalKeyboardKey.keyS, control: true),
            ),
            child: _target,
          ),
          still: true,
        );
        await _mouse(tester, find.byType(DTooltip));
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
      for (final side in [DTooltipSide.left, DTooltipSide.top]) {
        await _pump(
          tester,
          DTooltip(
            key: ValueKey(side),
            message: 'Information',
            side: side,
            align: DTooltipAlign.start,

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
        await _mouse(tester, find.byType(DTooltip));
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
          paints..path(
            includes: [
              popup.center,
              tip +
                  (side == DTooltipSide.left
                      ? const Offset(5, 0)
                      : const Offset(0, 5)),
            ],
            excludes: [
              tip +
                  (side == DTooltipSide.left
                      ? const Offset(8, 0)
                      : const Offset(0, 8)),
            ],
            style: PaintingStyle.fill,
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
      var actions = 0;
      await _pump(
        tester,
        DTooltip(
          message: 'Information',

          child: DButton(
            label: const Text('Target'),
            onPressed: () => actions++,
          ),
        ),
        still: true,
      );
      await _mouse(tester, find.byType(DTooltip));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_hint, findsNothing);
      expect(
        find
            .byType(FadeTransition)
            .evaluate()
            .any(
              (element) =>
                  (element.widget as FadeTransition).opacity.status ==
                  AnimationStatus.reverse,
            ),
        isFalse,
      );
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
