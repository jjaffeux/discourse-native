import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/tooltip_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final palette in [
    StyleguideTheme.light,
    StyleguideTheme.dark,
    StyleguideTheme.forest,
    StyleguideTheme.plum,
  ]) {
    testWidgets(
      '${palette.name} Tooltip examples fit narrow and wide previews at 200 percent in both directions',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final width in [240.0, 360.0, 900.0]) {
          tester.view.physicalSize = Size(width, 1100);
          for (final direction in TextDirection.values) {
            for (final example in tooltipExamples.examples) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: palette.resolve(AppTheme.light),
                  home: Scaffold(
                    body: MediaQuery(
                      data: MediaQueryData(
                        size: Size(width, 1100),
                        textScaler: const TextScaler.linear(2),
                        disableAnimations: true,
                      ),
                      child: DDirection(
                        textDirection: direction,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: KeyedSubtree(
                            key: ValueKey(example.title),
                            child: Builder(builder: example.builder),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '${example.title}: $width $direction',
              );
            }
          }
        }
      },
    );
  }

  testWidgets('usage example opens on hover and preserves its action counter', (
    tester,
  ) async {
    await _pump(tester, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Hover')));
    await tester.pumpAndSettle();
    expect(find.text('Add to library'), findsOneWidget);
    await tester.tap(find.text('Hover'));
    await tester.pumpAndSettle();
    expect(find.text('Added: 1'), findsOneWidget);
  });

  testWidgets(
    'keyboard example runs S through Actions and controlled hints accept Escape',
    (tester) async {
      await _pump(tester, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('Save Changes'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(find.text('Saved: 1'), findsOneWidget);
      await _pump(tester, 7);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Pin hint')));
      await tester.pumpAndSettle();
      expect(find.text('Pinned: false'), findsOneWidget);
      await mouse.down(tester.getCenter(find.text('Pin hint')));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Pinned: true'), findsOneWidget);
      expect(
        find.text(
          'This pinned hint uses the current palette, font and text scale.',
        ),
        findsOneWidget,
      );
      await mouse.down(tester.getCenter(find.text('Pin hint')));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Pinned: false'), findsOneWidget);
      await mouse.down(tester.getCenter(find.text('Pin hint')));
      await mouse.up();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Pinned: false'), findsOneWidget);
    },
  );

  testWidgets('controller example selects its second trigger and closes it', (
    tester,
  ) async {
    await _pump(tester, 8);
    await tester.tap(find.text('Open second'));
    await tester.pumpAndSettle();
    expect(find.text('second hint'), findsOneWidget);
    expect(find.text('first hint'), findsNothing);
    await tester.tap(find.text('Close hint'));
    await tester.pumpAndSettle();
    expect(find.text('second hint'), findsNothing);
  });
}

Future<void> _pump(WidgetTester tester, int index) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: Builder(
              key: ValueKey(index),
              builder: tooltipExamples.examples[index].builder,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
