import 'dart:ui' show SemanticsRole, SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    double? value = 25,
    double min = 0,
    double max = 100,
    bool rtl = false,
    bool reduced = true,
    ThemeData? theme,
    double scale = 1,
    double width = 200,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              child: DProgress(
                value: value,
                min: min,
                max: max,
                label: const DProgressLabel(
                  child: Text('Uploading attachments'),
                ),
                valueLabel: const DProgressValue(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Finder fill() => find.descendant(
    of: find.byType(DProgressIndicator),
    matching: find.byType(ColoredBox),
  );

  testWidgets('clamps custom range and exposes numeric read-only semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final (input, width, percentage) in [
        (50.0, 0.0, '0'),
        (150.0, 100.0, '50'),
        (250.0, 200.0, '100'),
      ]) {
        await pump(tester, value: input, min: 100, max: 200);
        await tester.pump();
        expect(tester.getSize(fill()).width, width);
        final data = tester
            .getSemantics(find.byType(DProgress))
            .getSemanticsData();
        expect(data.value, percentage);
        expect(data.minValue, '0');
        expect(data.maxValue, '100');
        expect(data.role, SemanticsRole.progressBar);
        expect(data.label, 'Uploading attachments');
        expect(data.hasAction(SemanticsAction.increase), isFalse);
        expect(find.text('$percentage%'), findsOneWidget);
      }
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('track is 4px with 12px header gap and logical-start fill', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.getSize(find.byType(DProgressTrack)), const Size(200, 4));
    expect(tester.getSize(fill()).width, 50);
    expect(
      tester.getTopLeft(fill()).dx,
      tester.getTopLeft(find.byType(DProgressTrack)).dx,
    );
    expect(
      tester.getTopLeft(find.byType(DProgressTrack)).dy -
          tester.getBottomLeft(find.byType(Wrap)).dy,
      12,
    );
    await pump(tester, rtl: true);
    expect(
      tester.getTopRight(fill()).dx,
      tester.getTopRight(find.byType(DProgressTrack)).dx,
    );
  });
  testWidgets(
    'unknown and non-finite values have no fabricated range and respect reduced motion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final value in [null, double.nan, double.infinity]) {
          await pump(tester, value: value);
          final data = tester
              .getSemantics(find.byType(DProgress))
              .getSemanticsData();
          expect(data.value, '');
          expect(data.minValue, isNull);
          expect(find.text('—'), findsOneWidget);
          final before = tester.getRect(fill());
          await tester.pump(const Duration(seconds: 1));
          expect(tester.getRect(fill()), before);
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
        await pump(tester, value: null, reduced: false);
        final start = tester.getRect(fill());
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.getRect(fill()).left, greaterThan(start.left));
        await pump(tester, value: 80, reduced: true);
        await tester.pumpAndSettle();
        expect(tester.getSize(fill()).width, 160);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets('live palette and narrow scaled labels preserve public state', (
    tester,
  ) async {
    await pump(tester, width: 100, scale: 2);
    expect(tester.takeException(), isNull);
    final light = tester.widget<ColoredBox>(fill()).color;
    await pump(
      tester,
      width: 100,
      scale: 2,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: Brightness.dark,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(fill()).color, isNot(light));
    expect(tester.takeException(), isNull);
    expect(find.text('25%'), findsOneWidget);
  });
  testWidgets(
    'determinate transition ends at target and reduced motion applies immediately',
    (tester) async {
      await pump(tester, value: 0, reduced: false);
      await pump(tester, value: 100, reduced: false);
      await tester.pump(const Duration(milliseconds: 75));
      expect(tester.getSize(fill()).width, inExclusiveRange(0, 200));
      await tester.pump(const Duration(milliseconds: 75));
      expect(tester.getSize(fill()).width, 200);
      await pump(tester, value: 25);
      await tester.pump();
      expect(tester.getSize(fill()).width, 50);
    },
  );

  testWidgets(
    'bare progress respects a constrained loading strip and extreme finite ranges',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(width: 200, height: 2, child: DProgress(value: 50)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DProgressTrack)).height, 2);
      await pump(tester, min: -1e308, max: 1e308, value: 0);
      expect(tester.getSize(fill()).width, 100);
    },
  );
  testWidgets(
    'inherited ticker suppression stops unknown progress and re-enables safely',
    (tester) async {
      Future<void> frame(bool enabled) => tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: enabled,
            child: const Center(
              child: SizedBox(
                width: 200,
                child: DProgress(semanticsLabel: 'Loading'),
              ),
            ),
          ),
        ),
      );
      await frame(true);
      await tester.pump(const Duration(milliseconds: 300));
      await frame(false);
      final stopped = tester.getRect(fill());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(fill()), stopped);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await frame(true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(fill()), isNot(stopped));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
