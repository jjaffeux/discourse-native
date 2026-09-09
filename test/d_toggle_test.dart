import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsValidationResult;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    ThemeData? theme,
    double scale = 1,
    bool reduced = false,
    bool rtl = false,
    double width = 240,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('uncontrolled state toggles by pointer keyboard and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final changes = <bool>[];
    await mount(
      tester,
      DToggle(
        initialPressed: true,
        onPressedChanged: changes.add,
        focusNode: focus,
        semanticLabel: 'Bold',
        child: const Text('Bold'),
      ),
    );

    await tester.tap(find.byType(DToggle));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.byType(DToggle));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(changes, [false, true, false, true]);
    expect(
      tester
          .getSemantics(find.byType(DToggle))
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('controlled state waits for parent and disabled blocks edits', (
    tester,
  ) async {
    var pressed = false;
    var changes = 0;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DToggle(
            pressed: pressed,
            onPressedChanged: (_) => changes++,
            semanticLabel: 'Italic',
            child: const Text('Italic'),
          );
        },
      ),
    );
    await tester.tap(find.byType(DToggle));
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(
      tester
          .getSemantics(find.byType(DToggle))
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isFalse,
    );
    update(() => pressed = true);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byType(DToggle))
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isTrue,
    );

    await mount(
      tester,
      DToggle(
        pressed: true,
        onPressedChanged: (_) => changes++,
        enabled: false,
        child: const Text('Disabled'),
      ),
    );
    await tester.tap(find.byType(DToggle));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, 1);
  });

  testWidgets('base-nova artwork stays compact inside touch targets', (
    tester,
  ) async {
    for (final entry in const [
      (DToggleSize.small, 28.0, 14.0),
      (DToggleSize.regular, 32.0, 16.0),
      (DToggleSize.large, 36.0, 16.0),
    ]) {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        await mount(
          tester,
          UnconstrainedBox(
            child: DToggle.iconOnly(
              icon: const Icon(Icons.format_bold),
              semanticLabel: 'Bold',
              size: entry.$1,
            ),
          ),
          theme: AppTheme.light.copyWith(platform: platform),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(DToggle)),
          Size.square(platform == TargetPlatform.iOS ? 48 : entry.$2),
        );
        expect(
          tester.getSize(
            find.descendant(
              of: find.byType(DToggle),
              matching: find.byType(AnimatedContainer),
            ),
          ),
          Size.square(entry.$2),
        );
        expect(
          tester.widget<IconTheme>(find.byType(IconTheme).last).data.size,
          entry.$3,
        );
      }
    }
  });

  testWidgets('selected hover press focus and invalid map to live tokens', (
    tester,
  ) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final tokens = DTokens.fromTheme(AppTheme.light).copyWith(
      muted: const Color(0xff123456),
      colors: AppTheme.light.colorScheme.copyWith(
        outlineVariant: const Color(0xff654321),
        primary: const Color(0xff246813),
        error: const Color(0xffaa0011),
      ),
    );
    final theme = AppTheme.light.copyWith(extensions: [tokens]);

    await mount(
      tester,
      DToggle(
        pressed: false,
        onPressedChanged: (_) {},
        focusNode: focus,
        variant: DToggleVariant.outline,
        child: const Text('Format'),
      ),
      theme: theme,
    );
    AnimatedContainer artwork() => tester.widget(
      find.descendant(
        of: find.byType(DToggle),
        matching: find.byType(AnimatedContainer),
      ),
    );
    BoxDecoration decoration() => artwork().decoration! as BoxDecoration;
    BoxDecoration foreground() =>
        artwork().foregroundDecoration! as BoxDecoration;
    expect(decoration().border!.top.color, const Color(0xff654321));
    expect(decoration().color, Colors.transparent);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(DToggle)));
    await tester.pumpAndSettle();
    expect(decoration().color, const Color(0xff123456));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();

    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(decoration().border!.top.color, const Color(0xff246813));
    expect(foreground().border!.top.width, 3);
    expect(foreground().border!.top.color.a, closeTo(.5, .01));

    await mount(
      tester,
      const DToggle(
        key: ValueKey('invalid-toggle'),
        initialPressed: true,
        invalid: true,
        child: Text('Invalid'),
      ),
      theme: theme,
    );
    expect(decoration().color, const Color(0xff123456));
    expect(decoration().border!.top.color, const Color(0xffaa0011));
    expect(
      tester
          .getSemantics(find.byType(DToggle))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );
  });

  testWidgets(
    'theme direction scale and reduced motion rebuild without reset',
    (tester) async {
      var dark = false;
      var rtl = false;
      var reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: reduced,
                ),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: const Scaffold(
                    body: SizedBox(
                      width: 112,
                      child: DToggle(
                        initialPressed: true,
                        icon: Icon(
                          Icons.bookmark_border,
                          key: ValueKey('icon'),
                        ),
                        child: Text(
                          'A very long bookmark label',
                          key: ValueKey('label'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSemantics(find.byType(DToggle))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      final ltrIcon = tester.getCenter(find.byKey(const ValueKey('icon'))).dx;
      final ltrLabel = tester.getCenter(find.byKey(const ValueKey('label'))).dx;
      expect(ltrIcon, lessThan(ltrLabel));

      update(() {
        dark = true;
        rtl = true;
        reduced = true;
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byKey(const ValueKey('icon'))).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('label'))).dx),
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero,
      );
      expect(
        tester
            .getSemantics(find.byType(DToggle))
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
    },
  );

  test('Toggle registers every frozen documented example', () {
    expect(componentExamples['toggle'], same(toggleExamples));
    expect(toggleExamples.examples.map((example) => example.title), [
      'Default',
      'Outline',
      'With Text',
      'Size',
      'Disabled',
      'RTL',
      'Ownership and states',
    ]);
  });

  testWidgets('all examples fit narrow 200 percent RTL and live palettes', (
    tester,
  ) async {
    for (final example in toggleExamples.examples) {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
      ]) {
        await mount(
          tester,
          SingleChildScrollView(child: Builder(builder: example.builder)),
          theme: theme,
          scale: 2,
          reduced: true,
          rtl: true,
          width: 216,
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });
}
