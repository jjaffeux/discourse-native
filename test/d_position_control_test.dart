import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'unfolds at trigger, slides then folds, outside/Escape dismiss (reduced=$reduced)',
      (tester) async {
        int selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: StatefulBuilder(
              builder: (context, setState) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: Align(
                    alignment: const Alignment(.8, -.8),
                    child: DPositionControl<int>(
                      triggerKey: const ValueKey('position'),
                      value: selected,
                      label: 'Position',
                      icon: const DIcon(DIcons.expand),
                      onChanged: (value) => setState(() => selected = value),
                      items: [
                        for (final value in [0, 1, 2])
                          DToggleGroupItem.iconOnly(
                            value: value,
                            semanticLabel: 'Position $value',
                            tooltip: 'Position $value',
                            icon: const DIcon(DIcons.expand),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final trigger = find.byKey(const ValueKey('position'));
        final origin = tester.getRect(trigger);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final first = find.byTooltip('Position 0');
        final last = find.byTooltip('Position 2');
        expect(tester.getRect(last).right, closeTo(origin.right, 1));
        expect(tester.getRect(first).center.dy, closeTo(origin.center.dy, 1));
        final indicator = find.byKey(
          const ValueKey('toggle-group-sliding-indicator'),
        );
        final before = tester.getRect(indicator);
        await tester.tap(last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 130));
        expect(selected, 2);
        if (!reduced) expect(find.byType(DToggleGroup<int>), findsOneWidget);
        if (!reduced) {
          expect(tester.getRect(indicator).left, greaterThan(before.left));
        }
        await tester.pumpAndSettle();
        expect(find.byType(DToggleGroup<int>), findsNothing);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(DToggleGroup<int>), findsNothing);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 300));
        await tester.pumpAndSettle();
        expect(find.byType(DToggleGroup<int>), findsNothing);
        expect(selected, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
