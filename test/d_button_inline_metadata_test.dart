import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a row of inline metadata buttons registers no global keys', (
    tester,
  ) async {
    Future<int> keysWith(int buttons) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Wrap(
              children: [
                for (var i = 0; i < buttons; i++)
                  DButton(
                    key: ValueKey(i),
                    label: Text('Metadata $i'),
                    variant: DButtonVariant.inline,
                    density: DButtonDensity.inlineMetadata,
                    onPressed: () {},
                  ),
              ],
            ),
          ),
        ),
      );
      return tester.binding.buildOwner!.globalKeyCount;
    }

    final empty = await keysWith(0);
    expect(await keysWith(10), empty);
    expect(tester.takeException(), isNull);
  });

  for (final link in [false, true]) {
    testWidgets(
      'inline metadata retains activation and semantics (link=$link)',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var activations = 0;
        Future<void> show(bool enabled) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: DButton(
                label: const Text('Metadata'),
                variant: DButtonVariant.inline,
                density: DButtonDensity.inlineMetadata,
                isLink: link,
                focusNode: focus,
                onPressed: enabled ? () => activations++ : null,
              ),
            ),
          ),
        );
        await show(true);
        final button = find.byType(DButton);
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.flagsCollection.isButton, !link);
        expect(data.flagsCollection.isLink, link);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(data.label, 'Metadata');
        await tester.tap(button, kind: PointerDeviceKind.mouse);
        expect(activations, 1);
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(activations, 3);
        expect(focus.hasFocus, isTrue);
        await show(false);
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(button)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        await tester.tap(button, warnIfMissed: false);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activations, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inline metadata animates its keyboard focus ring', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton(
              focusNode: focus,
              density: DButtonDensity.inlineMetadata,
              variant: DButtonVariant.inline,
              label: const Text('Metadata'),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    DButtonDecoration painted() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<DButtonDecoration>()
        .single;
    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(painted().ringWidth, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(painted().ringWidth, 1);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'inline metadata preserves bounds and type at $platform/$scale',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: DButton(
                      label: const Text('Metadata'),
                      variant: DButtonVariant.inline,
                      density: DButtonDensity.inlineMetadata,
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          final button = find.byType(DButton);
          final surface = find.descendant(
            of: button,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is DButtonDecoration,
            ),
          );
          final style = DefaultTextStyle.of(
            tester.element(find.text('Metadata')),
          ).style;
          expect(style.fontSize, 12);
          expect(style.height, 1.5);
          expect(tester.getRect(button), tester.getRect(surface));
          expect(tester.getSize(button).height, 18 * scale);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a phone press reaches an inline metadata button 44 points '
      'across, not past it', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => DTouchTargets(child: child!),
        home: Scaffold(
          body: Center(
            child: DButton(
              label: const Text('Metadata'),
              variant: DButtonVariant.inline,
              density: DButtonDensity.inlineMetadata,
              onPressed: () => activations++,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(DButton));
    expect(rect.height, 18);
    await tester.tapAt(rect.topCenter.translate(0, -12.5));
    expect(activations, 1);
    await tester.tapAt(rect.bottomCenter.translate(0, 12.5));
    expect(activations, 2);
    await tester.tapAt(rect.topCenter.translate(0, -13.5));
    expect(activations, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an inline metadata button says its own label over its '
      'content, and holds its least height around a shorter one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton(
              label: const Text('3d', style: TextStyle(fontSize: 6)),
              semanticLabel: 'Share post #3',
              variant: DButtonVariant.inline,
              density: DButtonDensity.inlineMetadata,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final button = find.byType(DButton);
    final data = tester.getSemantics(button).getSemanticsData();
    expect(data.label, 'Share post #3');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(tester.getSize(button).height, 18);
    expect(
      tester.getCenter(find.text('3d')).dy,
      moreOrLessEquals(tester.getCenter(button).dy),
    );
    semantics.dispose();
  });

  testWidgets('an inline metadata button mounts seven render objects over '
      'its label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: DButton(
              label: const Text('Metadata'),
              variant: DButtonVariant.inline,
              density: DButtonDensity.inlineMetadata,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    var renderObjects = 0;
    void visit(Element element) {
      if (element is RenderObjectElement) renderObjects++;
      element.visitChildren(visit);
    }

    visit(tester.element(find.byType(DButton)));
    // The label's own RichText is the eighth.
    expect(renderObjects, 8);
  });

  testWidgets(
    'an inline metadata button that loses its action ignores the press',
    (tester) async {
      var activations = 0;
      Widget button({required bool enabled}) => MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton(
              label: const Text('Metadata'),
              variant: DButtonVariant.inline,
              density: DButtonDensity.inlineMetadata,
              onPressed: enabled ? () => activations++ : null,
            ),
          ),
        ),
      );
      await tester.pumpWidget(button(enabled: true));
      final center = tester.getCenter(find.byType(DButton));
      final press = await tester.startGesture(center);
      await tester.pump();
      await tester.pumpWidget(button(enabled: false));
      await press.up();
      await tester.pumpAndSettle();
      expect(activations, 0);

      await tester.pumpWidget(button(enabled: true));
      await tester.tapAt(center);
      await tester.pump();
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inline metadata hover is immediate and cancelled presses do not activate',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: DButton(
                label: const Text('Metadata'),
                variant: DButtonVariant.inline,
                density: DButtonDensity.inlineMetadata,
                onPressed: () => activations++,
              ),
            ),
          ),
        ),
      );
      final button = find.byType(DButton);
      Color? foreground() => DefaultTextStyle.of(
        tester.element(find.text('Metadata')),
      ).style.color;
      final resting = foreground();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump();
      expect(foreground(), isNot(resting));
      await mouse.down(tester.getCenter(button));
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(activations, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
