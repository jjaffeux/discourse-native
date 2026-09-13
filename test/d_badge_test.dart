import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact counts keep full text and semantics at large scales', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final scale in [1.0, 2.0, 3.0]) {
        await _pump(
          tester,
          const DBadge(
            size: DBadgeSize.compact,
            semanticLabel: '123 unread',
            child: Text('99+'),
          ),
          width: 150,
          scale: scale,
          rtl: true,
        );
        final bounds = tester.getRect(find.byType(DBadge));
        final labelBounds = tester.getRect(find.text('99+'));
        expect(bounds.height, closeTo(14 * scale + 2, 0.01));
        expect(bounds.width, closeTo(labelBounds.width + 10, 0.01));
        expect(bounds.contains(labelBounds.topLeft), isTrue);
        expect(bounds.contains(labelBounds.bottomRight), isTrue);
        expect(find.bySemanticsLabel('123 unread'), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('99+'))
              .didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'static badges have compact geometry and no activation or tab stop',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(tester, const DBadge(child: Text('Badge')));
        expect(tester.getSize(find.byType(DBadge)).height, 20);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Badge'),
        );
        final style = (paragraph.text as TextSpan).style!;
        expect(style.fontSize, 12);
        expect(style.height, 16 / 12);
        expect(style.fontWeight, FontWeight.w500);
        final node = tester.getSemantics(find.text('Badge'));
        expect(node.flagsCollection.isButton, isFalse);
        expect(node.flagsCollection.isLink, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(
          FocusManager.instance.primaryFocus?.context?.widget,
          isNot(isA<DBadge>()),
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'action keyboard activation, disabling and borrowed focus lifecycle',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var count = 0;
      Widget badge(bool enabled) => DBadge.action(
        focusNode: focus,
        onPressed: enabled ? () => count++ : null,
        child: const Text('Count'),
      );
      await _pump(tester, badge(true));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.tap(find.text('Count'));
      expect(count, 3);
      await _pump(tester, badge(false));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.text('Count'));
      expect(count, 3);
      await _pump(tester, const SizedBox());
      await _pump(tester, badge(true));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pointer activation transfers keyboard ownership to the clicked badge',
    (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      var firstCount = 0;
      var secondCount = 0;
      try {
        await _pump(
          tester,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DBadge.action(
                focusNode: first,
                onPressed: () => firstCount++,
                child: const Text('First'),
              ),
              DBadge.action(
                focusNode: second,
                onPressed: () => secondCount++,
                child: const Text('Second'),
              ),
            ],
          ),
        );
        first.requestFocus();
        await tester.pump();
        await tester.tap(find.text('Second'));
        await tester.pump();
        expect(second.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(firstCount, 0);
        expect(secondCount, 3);
      } finally {
        await tester.pumpWidget(const SizedBox());
        first.dispose();
        second.dispose();
      }
    },
  );

  testWidgets('link semantics expose destination and only Enter activates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var count = 0;
      final uri = Uri.parse('https://example.invalid/details');
      await _pump(
        tester,
        DBadge.link(
          url: uri,
          semanticLabel: 'Details',
          onPressed: () => count++,
          child: const Text('Open'),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Details'));
      expect(node.flagsCollection.isLink, isTrue);
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().linkUrl, uri);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(count, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(count, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('disabled and invalid statuses retain a single accessible name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        const DBadge.action(
          onPressed: null,
          invalid: true,
          semanticLabel: 'Cannot publish',
          semanticValue: 'Invalid status',
          leading: Icon(Icons.error, semanticLabel: 'Decoration'),
          child: Text('Publish'),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Cannot publish'));
      expect(node.flagsCollection.isEnabled != Tristate.none, isTrue);
      expect(node.flagsCollection.isEnabled == Tristate.isTrue, isFalse);
      expect(node.getSemanticsData().value, 'Invalid status');
      expect(
        node.getSemanticsData().validationResult,
        SemanticsValidationResult.invalid,
      );
      expect(find.bySemanticsLabel('Decoration'), findsNothing);
      expect(
        _decoration(tester).border!.top.color,
        AppTheme.light.colorScheme.error,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'hover changes actionable outline and clears after pointer exits',
    (tester) async {
      await _pump(
        tester,
        DBadge.link(
          variant: DBadgeVariant.outline,
          onPressed: () {},
          child: const Text('Open'),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Open')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DBadge));
      expect(_decoration(tester).color, DTokens.of(context).muted);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_decoration(tester).color, Colors.transparent);
    },
  );

  testWidgets(
    'static ghost and link badges paint hover while other static variants ignore the pointer',
    (tester) async {
      var primaryBuilds = 0;
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DBadge(variant: DBadgeVariant.ghost, child: Text('Ghost')),
            const DBadge(variant: DBadgeVariant.link, child: Text('Link')),
            DBadge(
              child: Builder(
                builder: (_) {
                  primaryBuilds++;
                  return const Text('Primary');
                },
              ),
            ),
          ],
        ),
      );
      final tokens = DTokens.of(tester.element(find.text('Ghost')));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Ghost')));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester, 'Ghost').color, tokens.muted);
      expect(_styleOf(tester, 'Ghost').color, tokens.mutedForeground);
      await mouse.moveTo(tester.getCenter(find.text('Link')));
      await tester.pumpAndSettle();
      expect(_decorationOf(tester, 'Ghost').color, Colors.transparent);
      expect(_styleOf(tester, 'Ghost').color, tokens.foreground);
      expect(_decorationOf(tester, 'Link').color, Colors.transparent);
      expect(_styleOf(tester, 'Link').decoration, TextDecoration.underline);
      final settledBuilds = primaryBuilds;
      await mouse.moveTo(tester.getCenter(find.text('Primary')));
      await tester.pumpAndSettle();
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_styleOf(tester, 'Link').decoration, TextDecoration.none);
      expect(_decorationOf(tester, 'Primary').color, tokens.primary);
      expect(primaryBuilds, settledBuilds);
    },
  );

  testWidgets(
    'switching a hovered static badge away from ghost drops the stale hover',
    (tester) async {
      Widget badge(DBadgeVariant variant) =>
          DBadge(variant: variant, child: const Text('Status'));
      await _pump(tester, badge(DBadgeVariant.ghost));
      final state = tester.state(find.byType(DBadge));
      final tokens = DTokens.of(tester.element(find.byType(DBadge)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Status')));
      await tester.pumpAndSettle();
      expect(_decoration(tester).color, tokens.muted);
      await _pump(tester, badge(DBadgeVariant.primary));
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await _pump(tester, badge(DBadgeVariant.ghost));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(DBadge)), same(state));
      expect(_decoration(tester).color, Colors.transparent);
      await mouse.moveTo(tester.getCenter(find.text('Status')));
      await tester.pumpAndSettle();
      expect(_decoration(tester).color, tokens.muted);
    },
  );

  testWidgets('decoration transitions use the reference 150ms ease timing', (
    tester,
  ) async {
    await _pump(
      tester,
      const DBadge(child: Text('Badge')),
      reducedMotion: false,
    );
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(container.duration, const Duration(milliseconds: 150));
    expect(container.curve, const Cubic(.4, 0, .2, 1));
    await _pump(tester, const DBadge(child: Text('Badge')));
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
  });

  testWidgets('badge text takes part in an enclosing selection area', (
    tester,
  ) async {
    SelectedContent? selection;
    await _pump(
      tester,
      SelectionArea(
        onSelectionChanged: (content) => selection = content,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Before'),
            DBadge(child: Text('Badge')),
            Text('After'),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.text('Before')),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getBottomRight(find.text('After')));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(selection?.plainText, 'BeforeBadgeAfter');
  });

  for (final variant in DBadgeVariant.values) {
    testWidgets(
      '${variant.name} follows four live palettes without remounting',
      (tester) async {
        State? original;
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
          StyleguideTheme.plum.resolve(AppTheme.light),
        ]) {
          await _pump(
            tester,
            DBadge(variant: variant, child: const Text('Status')),
            theme: theme,
          );
          final state = tester.state(find.byType(DBadge));
          original ??= state;
          expect(state, same(original));
          final t = DTokens.of(tester.element(find.byType(DBadge)));
          final expected = switch (variant) {
            DBadgeVariant.primary => t.primary,
            DBadgeVariant.secondary => t.muted,
            DBadgeVariant.destructive => t.destructive.withValues(
              alpha: theme.brightness == Brightness.dark ? .2 : .1,
            ),
            _ => Colors.transparent,
          };
          expect(_decoration(tester).color, expected);
        }
      },
    );
  }

  testWidgets(
    'configured radii and extreme text keep reference curvature without clipping',
    (tester) async {
      for (final radius in [0.0, 1.0, 4.0, 12.0]) {
        final theme = AppTheme.light.copyWith(
          extensions: [
            AppTheme.light.extension<DTokens>()!.copyWith(radius: radius),
          ],
        );
        await _pump(
          tester,
          const DBadge(child: Text('A label that grows across several lines')),
          theme: theme,
          width: 140,
          scale: 3,
        );
        expect(
          _decoration(tester).borderRadius,
          BorderRadius.circular(radius * 2.6),
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.byType(Text))
              .didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('both badge sizes retain an independently tappable 48px target', (
    tester,
  ) async {
    for (final size in DBadgeSize.values) {
      var activated = false;
      await _pump(
        tester,
        DBadge.action(
          size: size,
          onPressed: () => activated = true,
          child: const Text('Go'),
        ),
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
      );
      final bounds = tester.getRect(find.byType(DBadge));
      expect(bounds.height, 48);
      expect(bounds.width, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(find.byType(AnimatedContainer)).height,
        size == DBadgeSize.compact ? 16 : 20,
      );
      await tester.tapAt(bounds.topCenter + const Offset(0, 2));
      expect(activated, isTrue);
    }
  });

  testWidgets(
    'large RTL label wraps with fixed decorative slots and loading value',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          const DBadge(
            leading: DSpinner(semanticLabel: null),
            trailing: Icon(Icons.check, size: 80),
            semanticValue: 'Loading',
            liveRegion: true,
            child: Text('تم التحقق من حالة الحساب وجميع المعلومات المطلوبة'),
          ),
          width: 200,
          scale: 2,
          rtl: true,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(DBadge)).height, greaterThan(20));
        expect(
          tester
              .renderObject<RenderParagraph>(find.byType(Text))
              .didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.getCenter(find.byType(DSpinner)).dx,
          greaterThan(tester.getCenter(find.byType(Text)).dx),
        );
        final slot = find
            .ancestor(
              of: find.byType(DSpinner),
              matching: find.byType(SizedBox),
            )
            .first;
        expect(tester.getSize(slot), const Size(12, 12));
        expect(
          tester.getSemantics(find.byType(Text)).getSemanticsData().value,
          'Loading',
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration!
        as BoxDecoration;
BoxDecoration _decorationOf(WidgetTester tester, String text) =>
    tester
            .widget<AnimatedContainer>(
              find.ancestor(
                of: find.text(text),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration!
        as BoxDecoration;
TextStyle _styleOf(WidgetTester tester, String text) =>
    (tester.renderObject<RenderParagraph>(find.text(text)).text as TextSpan)
        .style!;
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double width = 400,
  double scale = 1,
  bool rtl = false,
  bool reducedMotion = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: theme ?? AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reducedMotion,
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Align(child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}
