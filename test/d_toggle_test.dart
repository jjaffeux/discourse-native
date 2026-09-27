import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/toggle_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/control_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsValidationResult;
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

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets('reaction density balances content on $platform', (
      tester,
    ) async {
      var changes = 0;
      var inspections = 0;
      await mount(
        tester,
        DToggle(
          density: DToggleDensity.reaction,
          variant: DToggleVariant.outline,
          icon: const Icon(Icons.favorite),
          onPressedChanged: (_) => changes++,
          onLongPress: () => inspections++,
          child: const Text('123'),
        ),
        theme: AppTheme.light.copyWith(platform: platform),
      );
      final artwork = find.descendant(
        of: find.byType(DToggle),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(artwork).height, 28);
      final icon = tester.element(find.byIcon(Icons.favorite));
      expect(IconTheme.of(icon).size, 18);
      expect(
        DefaultTextStyle.of(tester.element(find.text('123'))).style.fontSize,
        12,
      );
      final bounds = tester.getRect(artwork);
      final iconBounds = tester.getRect(find.byIcon(Icons.favorite));
      final labelBounds = tester.getRect(find.text('123'));
      // The outline adds one pixel outside the eight-pixel content inset.
      expect(iconBounds.left - bounds.left, 9);
      expect(bounds.right - labelBounds.right, closeTo(9, .01));
      if (platform != TargetPlatform.macOS) {
        final gesture = find.descendant(
          of: find.byType(DToggle),
          matching: find.byType(GestureDetector),
        );
        expect(tester.getRect(gesture), bounds);
      }
      await tester.tap(find.text('123'));
      await tester.pump();
      expect(changes, 1);
      await tester.longPress(find.text('123'));
      await tester.pump();
      expect(inspections, 1);
      expect(changes, 1);
    });
  }

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

  testWidgets('icon toggles fit collapsing widths in both directions', (
    tester,
  ) async {
    for (final rtl in [false, true]) {
      for (final position in DToggleIconPosition.values) {
        for (final width in [240.0, 40.0, 21.385, 1.0, 0.0]) {
          await mount(
            tester,
            DToggle(
              density: DToggleDensity.reaction,
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
        density: DToggleDensity.reaction,
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
    final node = tester.getSemantics(controlSemantics());
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(changes, [false, true, false, true]);
    expect(
      tester
          .getSemantics(controlSemantics())
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
      (DToggleSize.regular, 34.0, 14.0, 44.0),
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
      border: const Color(0xff654321),
      colors: AppTheme.light.colorScheme.copyWith(
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
    DControlDecoration foreground() =>
        artwork().foregroundDecoration! as DControlDecoration;
    expect(decoration().border!.top.color, tokens.buttonTheme.outline.border);
    expect(decoration().color, tokens.buttonTheme.outline.background);
    expect(decoration().border!.top.width, 1);
    expect(
      decoration().borderRadius,
      BorderRadius.circular(tokens.buttonTheme.radius),
    );
    expect(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.byType(DToggle),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!
          .color,
      tokens.buttonTheme.outline.foreground,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(DToggle)));
    await tester.pumpAndSettle();
    expect(decoration().color, tokens.buttonTheme.outline.hover);
    expect(
      decoration().border!.top.color,
      tokens.buttonTheme.outline.hoverBorder,
    );
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();

    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(decoration().border!.top.color, tokens.buttonTheme.outline.border);
    expect(foreground().ringWidth, 1);
    expect(foreground().ringColor, tokens.focusRing);

    await mount(
      tester,
      const DToggle.iconOnly(
        key: ValueKey('selected-outline-toggle'),
        pressed: true,
        variant: DToggleVariant.outline,
        semanticLabel: 'Reaction',
        icon: Icon(Icons.favorite_border),
      ),
      theme: theme,
    );
    expect(decoration().color, tokens.buttonTheme.outline.hover);
    expect(
      decoration().border!.top.color,
      tokens.buttonTheme.outline.hoverBorder,
    );
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.favorite_border))).color,
      tokens.buttonTheme.outline.foreground,
    );

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
    expect(decoration().color, DControlStyle.rowHover(tokens));
    expect(decoration().border!.top.color, const Color(0xffaa0011));
    expect(
      tester
          .getSemantics(controlSemantics())
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );
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
      (DToggleSize.regular, 8.0),
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
        EdgeInsetsDirectional.only(start: entry.$2, end: 10),
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
        EdgeInsetsDirectional.only(start: 10, end: entry.$2),
      );
    }

    await mount(tester, const DToggle(child: Text('Plain')));
    expect(artwork().padding, const EdgeInsets.symmetric(horizontal: 10));
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
            .getSemantics(controlSemantics())
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
            .getSemantics(controlSemantics())
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
      'Reaction',
      'Chat reaction',
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
