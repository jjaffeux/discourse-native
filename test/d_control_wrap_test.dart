import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/control_wrap_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Rect artwork(WidgetTester tester, String label) => tester.getRect(
  find.descendant(
    of: find.byKey(ValueKey(label)),
    matching: find.byType(DControlArtwork),
  ),
);

void main() {
  testWidgets('control wrap styleguide example is interactive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Builder(builder: controlWrapExamples.examples.first.builder),
        ),
      ),
    );
    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(find.text('+1'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Bookmark'));
    await tester.pump();
    expect(find.text('Bookmark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded rows measure the visible controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: DControlWrap(
              wrap: false,
              children: [
                DButton.iconOnly(
                  key: const ValueKey('previous'),
                  size: DControlSize.chip,
                  icon: const DIcon(DIcons.chevronLeft),
                  tooltip: 'Previous',
                  onPressed: () {},
                ),
                const DControlExpanded(
                  child: Text('Caption', textAlign: TextAlign.center),
                ),
                DButton.iconOnly(
                  key: const ValueKey('next'),
                  size: DControlSize.chip,
                  icon: const DIcon(DIcons.chevronRight),
                  tooltip: 'Next',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getRect(find.byKey(const ValueKey('previous'))).left, 0);
    expect(tester.getRect(find.byKey(const ValueKey('next'))).right, 320);
    expect(tester.getCenter(find.text('Caption')).dx, 160);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('aligned rows leave surrounding gaps inactive in $direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: Builder(
                  builder: controlWrapExamples.examples.last.builder,
                ),
              ),
            ),
          ),
        ),
      );
      Rect surface(String tooltip) => tester.getRect(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(DControlArtwork),
        ),
      );
      final previous = surface('Previous month');
      final next = surface('Next month');
      final caption = tester.getRect(find.text('Month 9'));
      expect(caption.center.dx, 160);
      expect(previous.center.dy, next.center.dy);
      expect(
        direction == TextDirection.ltr ? previous.left : previous.right,
        direction == TextDirection.ltr ? 16 : 304,
      );
      expect(
        direction == TextDirection.ltr ? next.right : next.left,
        direction == TextDirection.ltr ? 304 : 16,
      );
      // These points sit beyond the painted row, inside the padded parent.
      await tester.tapAt(previous.topCenter - const Offset(0, 8));
      await tester.pump();
      expect(find.text('Month 9'), findsOneWidget);
      await tester.tapAt(next.topCenter - const Offset(0, 8));
      await tester.pump();
      expect(find.text('Month 9'), findsOneWidget);
      final today = tester.getRect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Today'),
            matching: find.byType(DButton),
          ),
          matching: find.byType(DControlArtwork),
        ),
      );
      expect(today.top - next.bottom, 10);
      await tester.tapAt(next.center);
      await tester.pump();
      expect(find.text('Month 10'), findsOneWidget);
      await tester.tapAt(today.bottomCenter + const Offset(0, 8));
      await tester.pump();
      expect(find.text('Month 10'), findsOneWidget);
      await tester.tapAt(today.center);
      await tester.pump();
      expect(find.text('Month 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final direction in TextDirection.values) {
      testWidgets('painted control gaps on $platform in $direction', (
        tester,
      ) async {
        final presses = <String>[];
        Widget badge(String label) => DBadge.action(
          key: ValueKey(label),
          size: DBadgeSize.control,
          semanticLabel: label,
          onPressed: () => presses.add(label),
          child: Text(label),
        );
        Future<void> pump(double width, double scale) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: width,
                      child: DControlWrap(children: [badge('a'), badge('b')]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (final scale in [1.0, 2.0]) {
          await pump(300, scale);
          final a = artwork(tester, 'a');
          final b = artwork(tester, 'b');
          expect(a.top, b.top);
          expect(
            direction == TextDirection.ltr
                ? b.left - a.right
                : a.left - b.right,
            closeTo(8, .001),
          );
          await pump(70, scale);
          final upper = artwork(tester, 'a');
          final lower = artwork(tester, 'b');
          expect(lower.top - upper.bottom, closeTo(8, .001));
          if (platform != TargetPlatform.macOS) {
            for (final label in ['a', 'b']) {
              final target = tester.getSize(find.byKey(ValueKey(label)));
              expect(target, artwork(tester, label).size);
            }
            if (scale == 1) {
              await tester.tapAt(Offset(upper.center.dx, upper.bottom + 1));
              await tester.tapAt(Offset(lower.center.dx, lower.top - 1));
              expect(presses, isEmpty);
            }
          }
          await tester.tapAt(upper.center);
          expect(presses.last, 'a');
          await tester.tapAt(lower.center);
          expect(presses.last, 'b');
          presses.clear();
          expect(tester.takeException(), isNull);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(presses, ['a']);
      });
    }
  }

  testWidgets('nested tag row retains its painted gap when controls wrap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 170,
              child: DControlWrap(
                children: [
                  DControlWrap(
                    wrap: false,
                    children: [
                      for (final label in ['tag', '1'])
                        DBadge.action(
                          key: ValueKey(label),
                          size: DBadgeSize.control,
                          onPressed: () {},
                          child: Text(label),
                        ),
                    ],
                  ),
                  DButtonGroup(
                    children: [
                      DButton.iconOnly(
                        key: const ValueKey('bookmark'),
                        size: DButtonSize.filter,
                        variant: DButtonVariant.outline,
                        icon: const Icon(Icons.bookmark),
                        tooltip: 'Bookmark',
                        onPressed: () {},
                      ),
                      DButton.iconOnly(
                        size: DButtonSize.filter,
                        variant: DButtonVariant.outline,
                        icon: const Icon(Icons.notifications),
                        tooltip: 'Notifications',
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      artwork(tester, '1').left - artwork(tester, 'tag').right,
      closeTo(8, .001),
    );
    expect(
      artwork(tester, 'bookmark').top - artwork(tester, 'tag').bottom,
      closeTo(8, .001),
    );
    expect(tester.takeException(), isNull);
  });
}
