import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/control_style.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder controlSemantics([Finder? target]) => find
    .descendant(
      of: target ?? find.byType(DToggle),
      matching: find.byType(MergeSemantics),
    )
    .first;

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

  testWidgets('chat reaction density matches the mockup pill', (tester) async {
    await mount(
      tester,
      const DToggle(
        density: DToggleDensity.chatReaction,
        variant: DToggleVariant.outline,
        icon: Icon(Icons.favorite),
        child: Text('2'),
      ),
    );
    final artwork = find.descendant(
      of: find.byType(DToggle),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(artwork).height, 24);
    final decoration =
        tester.widget<AnimatedContainer>(artwork).decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(999));
    expect(
      tester.getRect(find.byIcon(Icons.favorite)).left -
          tester.getRect(artwork).left,
      10,
    );
    expect(tester.getSize(find.byIcon(Icons.favorite)).width, 12);
  });

  for (final dark in [false, true]) {
    {
      testWidgets(
        'chat reactions stay flat through interaction ($dark, flat)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final theme = dark ? AppTheme.dark : AppTheme.light;
          var toggles = 0;
          final focus = FocusNode();
          addTearDown(focus.dispose);
          Future<void> render({
            bool selected = false,
            bool enabled = true,
            double scale = 1,
            bool rtl = false,
            bool reduced = false,
          }) => mount(
            tester,
            Align(
              child: DToggle(
                density: DToggleDensity.chatReaction,
                variant: DToggleVariant.outline,
                pressed: selected,
                enabled: enabled,
                focusNode: focus,
                semanticLabel: '2 heart reactions',
                onPressedChanged: (_) => toggles++,
                icon: const Icon(Icons.favorite),
                child: const Text('2'),
              ),
            ),
            theme: theme,
            scale: scale,
            rtl: rtl,
            reduced: reduced,
          );
          await render();
          final toggle = find.byType(DToggle);
          final artwork = find.descendant(
            of: toggle,
            matching: find.byType(AnimatedContainer),
          );
          final tokens = DTokens.of(tester.element(toggle));
          BoxDecoration decoration() =>
              tester.widget<AnimatedContainer>(artwork).decoration!
                  as BoxDecoration;
          void checkFlat(bool active) {
            expect(
              decoration().color,
              Color.lerp(
                tokens.colors.surface,
                tokens.foreground,
                active ? .15 : .10,
              ),
            );
            expect(
              decoration().border!.top.color,
              Color.lerp(
                tokens.colors.surface,
                tokens.foreground,
                active ? .32 : .22,
              ),
            );
            expect(decoration().border!.top.width, 1);
            expect(decoration().gradient, isNull);
            expect(decoration().boxShadow, isNull);
          }

          checkFlat(false);
          expect(tester.getSize(toggle).height, 24);
          expect(tester.getSize(toggle), tester.getSize(artwork));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text('2'),
              matching: find.byType(RichText),
            ),
          );
          expect(paragraph.text.style!.fontSize, 12);
          expect(paragraph.text.style!.fontWeight, FontWeight.w400);
          expect(
            paragraph.text.style!.color,
            Color.lerp(tokens.colors.surface, tokens.foreground, .62),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(toggle));
          await tester.pump();
          checkFlat(true);
          await mouse.removePointer();
          await tester.pump();
          final press = await tester.startGesture(tester.getCenter(toggle));
          await tester.pump(const Duration(milliseconds: 110));
          checkFlat(true);
          await press.up();
          await tester.pump();
          expect(toggles, 1);
          final rect = tester.getRect(toggle);
          await tester.tapAt(Offset(rect.right + 1, rect.center.dy));
          expect(toggles, 1, reason: 'outside visible artwork is not a target');
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(toggles, 2);
          await render(selected: true);
          checkFlat(true);
          expect(
            tester.getSemantics(controlSemantics()),
            matchesSemantics(
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              hasToggledState: true,
              isToggled: true,
              isFocusable: true,
              isFocused: true,
              label: '2 heart reactions',
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          await render(selected: true, enabled: false);
          await tester.tap(toggle);
          expect(toggles, 2);
          checkFlat(true);
          await render(scale: 2, rtl: true, reduced: true);
          expect(tester.getSize(toggle).height, 42);
          expect(
            tester.getRect(find.byIcon(Icons.favorite)).left,
            greaterThan(tester.getRect(find.text('2')).right),
          );
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('icon toggles fit collapsing widths in both directions', (
    tester,
  ) async {
    for (final rtl in [false, true]) {
      for (final position in DToggleIconPosition.values) {
        for (final width in [240.0, 40.0, 21.385, 1.0, 0.0]) {
          await mount(
            tester,
            DToggle(
              density: DToggleDensity.standard,
              variant: DToggleVariant.outline,
              iconPosition: position,
              icon: const Icon(Icons.favorite),
              child: const Text('1'),
            ),
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            rtl: rtl,
            width: width,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'width=$width, rtl=$rtl, iconPosition=$position',
          );
        }
      }
    }
  });

  testWidgets(
    'a label keeps all the width its icon leaves before ellipsizing',
    (tester) async {
      const text = 'Darker sidebar';
      RenderParagraph label() => tester.renderObject(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      );
      for (final rtl in [false, true]) {
        for (final position in DToggleIconPosition.values) {
          final reason = 'rtl=$rtl, iconPosition=$position';
          Future<void> mountAt(double width) => mount(
            tester,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DToggle(
                iconPosition: position,
                icon: const Icon(Icons.favorite),
                child: const Text(text),
              ),
            ),
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            rtl: rtl,
            width: width,
          );
          await mountAt(400);
          final natural = tester.getSize(find.byType(DToggle)).width;
          final labelWidth = label().size.width;
          final iconWidth = tester.getSize(find.byIcon(Icons.favorite)).width;

          // The label needs more than half the content width, which an even
          // split of the row would have ellipsized.
          await mountAt(natural);
          expect(label().didExceedMaxLines, isFalse, reason: reason);
          expect(label().size.width, labelWidth, reason: reason);

          await mountAt(natural - 24);
          expect(label().didExceedMaxLines, isTrue, reason: reason);
          expect(
            tester.getSize(find.byIcon(Icons.favorite)).width,
            iconWidth,
            reason: reason,
          );
          final icon = tester.getRect(find.byIcon(Icons.favorite));
          final labelRect = tester.getRect(find.text(text));
          expect(
            (position == DToggleIconPosition.start) != rtl
                ? icon.right <= labelRect.left
                : icon.left >= labelRect.right,
            isTrue,
            reason: reason,
          );
          expect(tester.takeException(), isNull, reason: reason);
        }
      }
    },
  );

  testWidgets('reaction density grows for scaled counts in RTL', (
    tester,
  ) async {
    await mount(
      tester,
      const DToggle(
        density: DToggleDensity.standard,
        icon: Icon(Icons.favorite),
        child: Text('12345'),
      ),
      scale: 3,
      rtl: true,
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
    );
    final artwork = find.descendant(
      of: find.byType(DToggle),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(artwork).height, greaterThan(48));
    expect(
      tester
          .getRect(artwork)
          .contains(tester.getBottomLeft(find.text('12345'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
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
          .getSemantics(controlSemantics())
          .getSemanticsData()
          .flagsCollection
          .isToggled,
      Tristate.isFalse,
    );
    update(() => pressed = true);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(controlSemantics())
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

    final focus = FocusNode();
    addTearDown(focus.dispose);
    await mount(
      tester,
      DToggle(
        pressed: false,
        focusNode: focus,
        semanticLabel: 'Controlled value',
        child: const Text('Controlled without observer'),
      ),
    );
    await tester.tap(find.byType(DToggle));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(
      tester
          .getSemantics(controlSemantics())
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(controlSemantics())
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
  });

  for (final iconOnly in [false, true]) {
    testWidgets(
      'long press is secondary and respects read-only / disabled ($iconOnly)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var longPresses = 0;
        final changes = <bool>[];
        var enabled = true;
        var readOnly = false;
        late StateSetter update;
        await mount(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return iconOnly
                  ? DToggle.iconOnly(
                      icon: const Icon(Icons.favorite),
                      semanticLabel: 'Reaction',
                      focusNode: focus,
                      enabled: enabled,
                      readOnly: readOnly,
                      onPressedChanged: changes.add,
                      onLongPress: () => longPresses++,
                      semanticLongPressHint: 'show who reacted',
                    )
                  : DToggle(
                      semanticLabel: 'Reaction',
                      focusNode: focus,
                      enabled: enabled,
                      readOnly: readOnly,
                      onPressedChanged: changes.add,
                      onLongPress: () => longPresses++,
                      semanticLongPressHint: 'show who reacted',
                      child: const Text('Reaction'),
                    );
            },
          ),
        );
        final toggle = find.byType(DToggle);
        await tester.longPress(toggle);
        await tester.pumpAndSettle();
        expect(longPresses, 1);
        expect(changes, isEmpty);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(changes, [true]);

        update(() => readOnly = true);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.longPress(toggle);
        await tester.pumpAndSettle();
        final node = tester.getSemantics(controlSemantics(toggle));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.longPress),
          isTrue,
        );
        node.owner!.performAction(node.id, SemanticsAction.longPress);
        await tester.pumpAndSettle();
        expect(longPresses, 3);
        expect(changes, [true]);
        expect(focus.hasFocus, isTrue);
        expect(
          node.getSemanticsData().flagsCollection.isToggled,
          Tristate.isTrue,
        );

        update(() => enabled = false);
        await tester.pumpAndSettle();
        await tester.longPress(toggle);
        await tester.pumpAndSettle();
        expect(longPresses, 3);
        expect(
          tester
              .getSemantics(controlSemantics(toggle))
              .getSemanticsData()
              .hasAction(SemanticsAction.longPress),
          isFalse,
        );
        expect(changes, [true]);
        semantics.dispose();
      },
    );
  }

  testWidgets('Native artwork uses the platform scale inside touch targets', (
    tester,
  ) async {
    for (final entry in const [
      (DToggleSize.small, 24.0, 12.0, 40.0),
      (DToggleSize.regular, 30.0, 12.0, 30.0),
      (DToggleSize.large, 40.0, 16.0, 48.0),
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
          Size.square(platform == TargetPlatform.iOS ? entry.$4 : entry.$2),
        );
        expect(
          tester.getSize(
            find.descendant(
              of: find.byType(DToggle),
              matching: find.byType(AnimatedContainer),
            ),
          ),
          Size.square(platform == TargetPlatform.iOS ? entry.$4 : entry.$2),
        );
        expect(
          tester.widget<IconTheme>(find.byType(IconTheme).last).data.size,
          entry.$3,
        );
      }
    }
  });

  testWidgets('mouse hover survives the application focus-outline policy', (
    tester,
  ) async {
    await mount(
      tester,
      const DFocusHighlight(
        child: DToggle(
          variant: DToggleVariant.outline,
          child: Text('Reaction'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    BoxDecoration surface() =>
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(DToggle),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;
    final resting = surface().color;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(DToggle)));
    await tester.pumpAndSettle();
    expect(surface().color, isNot(resting));
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(surface().color, resting);
    await mouse.removePointer();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'inline chrome uses only color for hover and press (dark: $dark)',
      (tester) async {
        final strategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.macOS,
        );
        final tokens = DTokens.fromTheme(theme);
        var changes = 0;
        await mount(
          tester,
          UnconstrainedBox(
            child: DToggle.iconOnly(
              density: DToggleDensity.chrome,
              variant: DToggleVariant.inline,
              icon: const Icon(Icons.view_sidebar_outlined),
              selectedIcon: const Icon(Icons.view_sidebar),
              semanticLabel: 'Split view',
              focusNode: focus,
              onPressedChanged: (_) => changes++,
            ),
          ),
          theme: theme,
        );
        final toggle = find.byType(DToggle);
        final art = find.descendant(
          of: toggle,
          matching: find.byType(AnimatedContainer),
        );
        BoxDecoration surface() =>
            tester.widget<AnimatedContainer>(art).decoration! as BoxDecoration;
        Color? color() => IconTheme.of(
          tester.element(
            find.descendant(of: toggle, matching: find.byType(Icon)),
          ),
        ).color;
        expect(tester.getSize(art), const Size.square(32));
        expect(
          tester.getRect(
            find.descendant(of: toggle, matching: find.byType(GestureDetector)),
          ),
          tester.getRect(art),
        );
        expect(
          tester.getSize(find.byIcon(Icons.view_sidebar_outlined)),
          const Size.square(18),
        );
        expect(surface().color, Colors.transparent);
        final resting = color();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        final center = tester.getCenter(toggle);
        await mouse.moveTo(center);
        await tester.pump();
        expect(color(), tokens.foreground);
        expect(color(), isNot(resting));
        expect(surface().color, Colors.transparent);
        await mouse.down(center);
        await tester.pump();
        expect(surface().color, Colors.transparent);
        await mouse.up();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(changes, 1);
        expect(find.byIcon(Icons.view_sidebar), findsOneWidget);
        expect(color(), tokens.primary);
        expect(surface().color, Colors.transparent);
        final selected = color();
        await mouse.moveTo(center);
        await mouse.down(center);
        await tester.pump();
        expect(color(), isNot(selected));
        expect(surface().color, Colors.transparent);
        await mouse.cancel();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(changes, 1);
        focus.requestFocus();
        await tester.pump();
        expect(
          (tester.widget<AnimatedContainer>(art).foregroundDecoration!
                  as DControlDecoration)
              .ringColor,
          tokens.focusRing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(changes, 2);
        expect(surface().color, Colors.transparent);
        expect(
          tester
              .getSemantics(controlSemantics())
              .getSemanticsData()
              .flagsCollection
              .isToggled,
          Tristate.isFalse,
        );

        // The control must not react to a click in the surrounding gap.
        final outside = tester.getRect(art).topLeft - const Offset(1, 1);
        await tester.tapAt(outside);
        await tester.pump();
        expect(changes, 2);
        await mount(
          tester,
          DToggle.iconOnly(
            key: const ValueKey('disabled-inline'),
            enabled: false,
            density: DToggleDensity.chrome,
            variant: DToggleVariant.inline,
            icon: const Icon(Icons.view_sidebar_outlined),
            semanticLabel: 'Split view',
            onPressedChanged: (_) => changes++,
          ),
          theme: theme,
        );
        final disabledColor = color();
        await mouse.moveTo(tester.getCenter(toggle));
        await mouse.down(tester.getCenter(toggle));
        await tester.pump();
        expect(color(), disabledColor);
        expect(surface().color, Colors.transparent);
        await mouse.up();
        await tester.pump();
        expect(changes, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('icon-side padding and content gap match current base-nova', (
    tester,
  ) async {
    AnimatedContainer artwork() => tester.widget(
      find.descendant(
        of: find.byType(DToggle),
        matching: find.byType(AnimatedContainer),
      ),
    );

    for (final entry in const [
      (DToggleSize.small, 6.0),
      (DToggleSize.regular, 10.0),
      (DToggleSize.large, 8.0),
    ]) {
      await mount(
        tester,
        DToggle(
          size: entry.$1,
          icon: const Icon(Icons.format_italic, key: ValueKey('icon')),
          child: const Text('Italic', key: ValueKey('label')),
        ),
      );
      expect(
        artwork().padding,
        entry.$1 == DToggleSize.regular
            ? const EdgeInsets.symmetric(horizontal: 10)
            : EdgeInsetsDirectional.only(start: entry.$2, end: 10),
      );
      final iconRect = tester.getRect(find.byKey(const ValueKey('icon')));
      final labelRect = tester.getRect(find.byKey(const ValueKey('label')));
      expect(labelRect.left - iconRect.right, 4);

      await mount(
        tester,
        DToggle(
          size: entry.$1,
          iconPosition: DToggleIconPosition.end,
          icon: const Icon(Icons.format_italic),
          child: const Text('Italic'),
        ),
      );
      expect(
        artwork().padding,
        entry.$1 == DToggleSize.regular
            ? const EdgeInsets.symmetric(horizontal: 10)
            : EdgeInsetsDirectional.only(start: 10, end: entry.$2),
      );
    }

    await mount(tester, const DToggle(child: Text('Plain')));
    expect(artwork().padding, const EdgeInsets.symmetric(horizontal: 10));
  });

  test('Toggle registers every frozen documented example', () {
    expect(componentExamples['toggle'], same(toggleExamples));
    expect(toggleExamples.examples.map((example) => example.title), [
      'Post reactions',
      'Reaction',
      'Chat reaction',
      'Window control',
      'Panel layout preview',
      'Default',
      'Outline',
      'With Text',
      'Size',
      'Disabled',
      'Secondary long press',
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
