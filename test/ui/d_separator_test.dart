import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final orientation in Axis.values) {
    testWidgets(
      '${orientation.name} default is a one-pixel square-ended border rule',
      (tester) async {
        await _pump(
          tester,
          SizedBox(
            width: 384,
            height: 96,
            child: Align(child: DSeparator(orientation: orientation)),
          ),
        );
        final horizontal = orientation == Axis.horizontal;
        expect(
          tester.getSize(find.byType(DSeparator)),
          horizontal ? const Size(384, 1) : const Size(1, 96),
        );
        expect(
          tester.getSize(_paintedLine()),
          horizontal ? const Size(384, 1) : const Size(1, 96),
        );
        final decoration = _decoration(tester, find.byType(DSeparator));
        final side = horizontal
            ? decoration.border!.bottom
            : (decoration.border! as Border).left;
        expect(side.width, 1);
        expect(
          side.color,
          DTokens.of(tester.element(find.byType(DSeparator))).border,
        );
        expect(decoration.borderRadius, BorderRadius.zero);
      },
    );

    testWidgets('${orientation.name} fills its bounded length', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 200,
          height: 120,
          child: Align(
            child: DSeparator(orientation: orientation, thickness: 3, space: 9),
          ),
        ),
      );
      final horizontal = orientation == Axis.horizontal;
      expect(
        tester.getSize(find.byType(DSeparator)),
        horizontal ? const Size(200, 9) : const Size(9, 120),
      );
      expect(
        tester.getSize(_paintedLine()),
        horizontal ? const Size(200, 3) : const Size(3, 120),
      );
      expect(
        tester.getCenter(_paintedLine()),
        tester.getCenter(find.byType(DSeparator)),
      );
    });

    testWidgets('${orientation.name} handles finite and unbounded parents', (
      tester,
    ) async {
      for (final length in [null, 80.0]) {
        await _pump(
          tester,
          UnconstrainedBox(
            child: DSeparator(orientation: orientation, length: length),
          ),
        );
        final size = tester.getSize(find.byType(DSeparator));
        expect(
          orientation == Axis.horizontal ? size.width : size.height,
          length ?? 0,
        );
        expect(tester.takeException(), isNull);
      }
      await _pump(
        tester,
        SizedBox(
          width: 40,
          height: 40,
          child: DSeparator(orientation: orientation, length: 80),
        ),
      );
      expect(tester.getSize(find.byType(DSeparator)), const Size(40, 40));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'vertical lines fill a 20px row and an intrinsic-height row of two-line items',
    (tester) async {
      await _pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20,
              child: Row(
                key: ValueKey('fixed-row'),
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  Text('Blog'),
                  DSeparator(
                    key: ValueKey('fixed-line'),
                    orientation: Axis.vertical,
                  ),
                  Text('Docs'),
                ],
              ),
            ),
            IntrinsicHeight(
              child: Row(
                key: ValueKey('intrinsic-row'),
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('Settings'), Text('Manage preferences')],
                  ),
                  DSeparator(
                    key: ValueKey('intrinsic-line'),
                    orientation: Axis.vertical,
                  ),
                  Text('Account'),
                ],
              ),
            ),
          ],
        ),
      );
      final fixedRow = tester.getRect(find.byKey(const ValueKey('fixed-row')));
      final fixedLine = tester.getRect(
        _paintedLine(find.byKey(const ValueKey('fixed-line'))),
      );
      expect(fixedRow.height, 20);
      expect(fixedLine.top, fixedRow.top);
      expect(fixedLine.height, 20);
      expect(fixedLine.width, 1);
      expect(fixedLine.left - tester.getRect(find.text('Blog')).right, 16);

      final intrinsicRow = tester.getRect(
        find.byKey(const ValueKey('intrinsic-row')),
      );
      final intrinsicLine = tester.getRect(
        _paintedLine(find.byKey(const ValueKey('intrinsic-line'))),
      );
      expect(
        intrinsicRow.height,
        tester.getSize(find.text('Settings')).height +
            tester.getSize(find.text('Manage preferences')).height,
      );
      expect(intrinsicLine.top, intrinsicRow.top);
      expect(intrinsicLine.height, intrinsicRow.height);
      expect(tester.getCenter(find.text('Account')).dy, intrinsicRow.center.dy);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a vertical line collapses inside a row of unbounded height without an error',
    (tester) async {
      await _pump(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Blog'),
                DSeparator(orientation: Axis.vertical),
                Text('Docs'),
              ],
            ),
          ],
        ),
      );
      expect(tester.getSize(find.byType(DSeparator)), const Size(1, 0));
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      '${direction.name} mirrors horizontal but not vertical insets',
      (tester) async {
        for (final orientation in Axis.values) {
          await _pump(
            tester,
            DDirection(
              textDirection: direction,
              child: DSeparator(
                orientation: orientation,
                length: 100,
                indent: 24,
                endIndent: 8,
              ),
            ),
          );
          final outer = tester.getRect(find.byType(DSeparator));
          final line = tester.getRect(_paintedLine());
          if (orientation == Axis.horizontal) {
            expect(line.width, 68);
            expect(
              line.left - outer.left,
              direction == TextDirection.ltr ? 24 : 8,
            );
          } else {
            expect(line.height, 68);
            expect(line.top - outer.top, 24);
          }
        }
      },
    );
  }

  testWidgets('intrinsic rows stretch the line alongside scaled wrapping text', (
    tester,
  ) async {
    await _pump(
      tester,
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: SizedBox(
          width: 240,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DSeparator(orientation: Axis.vertical, space: 16),
                Expanded(
                  child: Text(
                    'A native boundary beside text that wraps onto many lines.',
                    key: ValueKey('wrapping-text'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final textSize = tester.getSize(
      find.byKey(const ValueKey('wrapping-text')),
    );
    expect(textSize.height, greaterThan(100));
    expect(tester.getSize(_paintedLine()).height, textSize.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounted lines read live host and site tokens with an override', (
    tester,
  ) async {
    final theme = ValueNotifier(AppTheme.light);
    addTearDown(theme.dispose);
    const override = Color(0xFFDC5F37);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: theme,
        builder: (context, value, child) => MaterialApp(
          theme: value,
          themeAnimationDuration: Duration.zero,
          home: child,
        ),
        child: const Scaffold(
          body: Column(
            children: [
              DSeparator(key: ValueKey('themed')),
              DSeparator(
                key: ValueKey('custom'),
                color: override,
                thickness: 3,
                radius: BorderRadius.all(Radius.circular(2)),
              ),
            ],
          ),
        ),
      ),
    );
    for (final value in [
      AppTheme.dark,
      StyleguideTheme.forest.resolve(AppTheme.light),
      StyleguideTheme.plum.resolve(AppTheme.light),
      ThemeData.light(),
    ]) {
      theme.value = value;
      await tester.pumpAndSettle();
      final line = find.byKey(const ValueKey('themed'));
      expect(
        _decoration(tester, line).border!.bottom.color,
        DTokens.of(tester.element(line)).border,
      );
      final custom = _decoration(tester, find.byKey(const ValueKey('custom')));
      expect(custom.border!.bottom.color, override);
      expect(custom.borderRadius, const BorderRadius.all(Radius.circular(2)));
    }
  });

  testWidgets('a hairline paints a stroke in the border color', (tester) async {
    await _pump(
      tester,
      const SizedBox(width: 120, child: DSeparator(thickness: 0)),
    );
    expect(tester.getSize(find.byType(DSeparator)), const Size(120, 1));
    expect(
      tester.renderObject(_paintedLine()),
      paints..path(
        color: DTokens.of(tester.element(find.byType(DSeparator))).border,
        style: PaintingStyle.stroke,
        strokeWidth: 0,
      ),
    );
  });

  test('a hairline rejects rounded ends before it can fail to paint', () {
    expect(
      () => DSeparator(
        thickness: 0,
        radius: const BorderRadius.all(Radius.circular(2)),
      ),
      throwsAssertionError,
    );
    expect(
      const DSeparator(
        thickness: 1,
        radius: BorderRadius.all(Radius.circular(2)),
      ).radius,
      const BorderRadius.all(Radius.circular(2)),
    );
  });

  testWidgets(
    'meaningful boundaries have a static label and decorative ones vanish',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final meaningful in [false, true, false]) {
          await _pump(
            tester,
            DSeparator(
              decorative: !meaningful,
              semanticLabel: meaningful ? 'End of account options' : null,
            ),
          );
          final boundary = find.bySemanticsLabel('End of account options');
          expect(boundary, meaningful ? findsOneWidget : findsNothing);
          if (meaningful) {
            final data = tester.getSemantics(boundary).getSemanticsData();
            expect(data.textDirection, TextDirection.ltr);
            for (final action in SemanticsAction.values) {
              expect(
                data.hasAction(action),
                isFalse,
                reason: action.toString(),
              );
            }
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('pointer events and Tab pass through a meaningful separator', (
    tester,
  ) async {
    final first = FocusNode();
    final last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    var taps = 0;
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            focusNode: first,
            onPressed: () {},
            child: const Text('First'),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              TextButton(
                focusNode: last,
                onPressed: () => taps++,
                child: const Text('Last'),
              ),
              const DSeparator(
                decorative: false,
                semanticLabel: 'Boundary',
                length: 120,
                space: 48,
              ),
            ],
          ),
        ],
      ),
    );
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(last.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tapAt(tester.getCenter(find.text('Last')));
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('native menu intrinsic layout and keyboard skip separators', (
    tester,
  ) async {
    final trigger = FocusNode();
    final theme = ValueNotifier(AppTheme.light);
    addTearDown(trigger.dispose);
    addTearDown(theme.dispose);
    String? selected;
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: theme,
        builder: (context, value, _) => MaterialApp(
          theme: value,
          home: Scaffold(
            body: MenuAnchor(
              childFocusNode: trigger,
              menuChildren: [
                MenuItemButton(
                  onPressed: () => selected = 'First',
                  child: const Text('First'),
                ),
                const DSeparator(key: ValueKey('menu-rule')),
                MenuItemButton(
                  onPressed: () => selected = 'Second',
                  child: const Text('Second'),
                ),
              ],
              builder: (context, controller, child) => TextButton(
                focusNode: trigger,
                onPressed: controller.open,
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final line = find.byKey(const ValueKey('menu-rule'));
    expect(tester.getSize(line).width, greaterThan(50));
    theme.value = StyleguideTheme.plum.resolve(AppTheme.light);
    await tester.pumpAndSettle();
    expect(
      _decoration(tester, line).border!.bottom.color,
      DTokens.of(tester.element(line)).border,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'Second');
    expect(line, findsNothing);
    expect(trigger.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}

Finder _paintedLine([Finder? separator]) => find.descendant(
  of: separator ?? find.byType(DSeparator),
  matching: find.byType(DecoratedBox),
);

BoxDecoration _decoration(WidgetTester tester, Finder separator) =>
    tester.widget<DecoratedBox>(_paintedLine(separator)).decoration
        as BoxDecoration;

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ),
);
