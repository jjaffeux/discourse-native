import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  double width = 448,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
  bool focusPolicy = false,
  bool accessibleNavigation = false,
}) => MaterialApp(
  theme: theme ?? ThemeData(platform: TargetPlatform.macOS),
  builder: focusPolicy ? (_, child) => DFocusHighlight(child: child!) : null,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
        accessibleNavigation: accessibleNavigation,
      ),
      child: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);
const titleKey = Key('title');
const mediaKey = Key('media');
const descriptionKey = Key('description');
Widget sample(DItemSize size) => DItem(
  size: size,
  variant: DItemVariant.outline,
  children: const [
    DItemMedia(
      key: mediaKey,
      variant: DItemMediaVariant.image,
      child: ColoredBox(color: Colors.blue),
    ),
    DItemContent(
      children: [
        DItemTitle(child: Text('Title', key: titleKey)),
        DItemDescription(child: Text('Description', key: descriptionKey)),
      ],
    ),
  ],
);

void main() {
  testWidgets(
    'hover callbacks follow pointer entry and exit without activation',
    (tester) async {
      final events = <bool>[];
      var pressed = 0;
      await tester.pumpWidget(
        host(
          DItem(
            onPressed: () => pressed++,
            onHoverChanged: events.add,
            children: const [Text('Hover item')],
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(tester.getCenter(find.byType(DItem)));
      await tester.pump();
      expect(events, [true]);
      expect(pressed, 0);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();
      expect(events, [true, false]);
      await tester.pumpWidget(
        host(
          DItem(
            enabled: false,
            onPressed: () => pressed++,
            onHoverChanged: events.add,
            children: const [Text('Hover item')],
          ),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.byType(DItem)));
      await tester.pump();
      expect(events, [true, false]);
      await mouse.removePointer();
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'corner action reveals and activates independently in $direction',
      (tester) async {
        final rowFocus = FocusNode();
        final actionFocus = FocusNode();
        addTearDown(rowFocus.dispose);
        addTearDown(actionFocus.dispose);
        var selections = 0;
        var actions = 0;
        const actionKey = Key('corner-action');
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            DItem(
              focusNode: rowFocus,
              onPressed: () => selections++,
              cornerAction: DButton.iconOnly(
                key: actionKey,
                focusNode: actionFocus,
                size: DButtonSize.small,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete saved item',
                onPressed: () => actions++,
              ),
              header: const DItemHeader(child: SizedBox(height: 72)),
              children: const [
                DItemContent(children: [Text('Saved item')]),
              ],
            ),
            direction: direction,
          ),
        );
        final action = find.byKey(actionKey);
        double opacity() => tester
            .widget<Opacity>(
              find.ancestor(of: action, matching: find.byType(Opacity)),
            )
            .opacity;
        expect(opacity(), 0);
        expect(
          tester.getSemantics(action),
          matchesSemantics(
            label: 'Delete saved item',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: const Offset(700, 500));
        await mouse.moveTo(tester.getCenter(find.text('Saved item')));
        await tester.pump();
        expect(opacity(), 1);
        final rowRect = tester.getRect(find.byType(DItem));
        final actionRect = tester.getRect(action);
        expect(actionRect.top, rowRect.top + DSpacing.sm);
        expect(
          direction == TextDirection.ltr ? actionRect.right : actionRect.left,
          direction == TextDirection.ltr
              ? rowRect.right - DSpacing.sm
              : rowRect.left + DSpacing.sm,
        );
        await tester.tap(action);
        await tester.pump();
        expect(actions, 1);
        expect(selections, 0);
        await mouse.moveTo(const Offset(700, 500));
        rowFocus.requestFocus();
        await tester.pump();
        expect(opacity(), 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(selections, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(actionFocus.hasPrimaryFocus, isTrue);
        expect(opacity(), 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(actions, 2);
        expect(selections, 1);
        actionFocus.unfocus();
        await tester.pump();
        expect(opacity(), 0);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'corner actions stay visible for touch and accessible navigation',
    (tester) async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        await tester.pumpWidget(
          host(
            DItem(
              cornerAction: DButton.iconOnly(
                key: const Key('corner-action'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete saved item',
                size: DButtonSize.small,
                onPressed: () {},
              ),
              header: const DItemHeader(child: SizedBox(height: 100)),
              children: const [
                DItemContent(children: [Text('Saved item')]),
              ],
            ),
            width: 220,
            scale: 2,
            direction: TextDirection.rtl,
            theme: ThemeData(platform: platform),
            accessibleNavigation: platform == TargetPlatform.macOS,
          ),
        );
        final action = find.byKey(const Key('corner-action'));
        expect(
          tester
              .widget<Opacity>(
                find.ancestor(of: action, matching: find.byType(Opacity)),
              )
              .opacity,
          1,
        );
        if (platform == TargetPlatform.iOS) {
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final direction in TextDirection.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'full-width row states paint immediately in $direction/$brightness',
        (tester) async {
          final theme = ThemeData(
            brightness: brightness,
            platform: TargetPlatform.macOS,
          );
          final tokens = DTokens.fromTheme(theme);
          var selected = false;
          await tester.pumpWidget(
            host(
              StatefulBuilder(
                builder: (context, setState) => DItem(
                  shape: DItemShape.fullWidth,
                  selectionStyle: DItemSelectionStyle.leadingAccent,
                  selected: selected,
                  showSelectionIndicator: false,
                  onPressed: () => setState(() => selected = !selected),
                  children: const [
                    DItemContent(children: [Text('Full-width topic')]),
                  ],
                ),
              ),
              direction: direction,
              theme: theme,
            ),
          );
          Container surface() => tester.widget<Container>(
            find.descendant(
              of: find.byType(DItem),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container && widget.decoration is BoxDecoration,
              ),
            ),
          );
          final initialRect = tester.getRect(find.byType(DItem));
          expect(initialRect.width, 448);
          expect(
            (surface().decoration! as BoxDecoration).color,
            Colors.transparent,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: const Offset(700, 500));
          await mouse.moveTo(tester.getCenter(find.text('Full-width topic')));
          await tester.pump();
          for (final duration in [
            Duration.zero,
            const Duration(milliseconds: 50),
          ]) {
            await tester.pump(duration);
            final paint = surface().decoration! as BoxDecoration;
            expect(paint.color, tokens.primary.withValues(alpha: .06));
            expect(paint.borderRadius, BorderRadius.zero);
          }
          await tester.tap(find.text('Full-width topic'));
          await tester.pump();
          expect(
            (surface().decoration! as BoxDecoration).color,
            tokens.primary.withValues(alpha: .12),
          );
          final border =
              (surface().foregroundDecoration! as BoxDecoration).border!
                  as BorderDirectional;
          expect(border.start, BorderSide(color: tokens.primary, width: 3));
          expect(border.end, BorderSide.none);
          expect(tester.getRect(find.byType(DItem)), initialRect);
          await mouse.moveTo(const Offset(700, 500));
          await tester.pump();
          expect(
            (surface().decoration! as BoxDecoration).color,
            tokens.primary.withValues(alpha: .12),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(selected, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('card hover follows its themed surface corners', (tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(700, 500));
    for (final brightness in Brightness.values) {
      for (final radius in [0.0, 4.0, 12.0]) {
        final base = ThemeData(brightness: brightness);
        await tester.pumpWidget(
          host(
            DCard(
              spacing: 0,
              child: DItem(
                shape: DItemShape.card,
                onPressed: () {},
                children: const [
                  DItemContent(children: [Text('Topic')]),
                ],
              ),
            ),
            theme: base.copyWith(
              extensions: [DTokens.fromTheme(base).copyWith(radius: radius)],
            ),
          ),
        );
        await mouse.moveTo(tester.getCenter(find.text('Topic')));
        await tester.pump();
        final card = tester.widget<Material>(
          find.descendant(
            of: find.byType(DCard),
            matching: find.byType(Material),
          ),
        );
        final item = tester.widget<Container>(
          find.descendant(
            of: find.byType(DItem),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          ),
        );
        final decoration = item.decoration! as BoxDecoration;
        expect(decoration.color!.a, greaterThan(0));
        expect(decoration.borderRadius, card.borderRadius);
        await mouse.moveTo(const Offset(700, 500));
        await tester.pump();
      }
    }
  });

  testWidgets('outline border override leaves selection accent intact', (
    tester,
  ) async {
    const restingBorder = Color(0xFF7689A0);
    for (final brightness in Brightness.values) {
      final theme = ThemeData(brightness: brightness);
      final tokens = DTokens.fromTheme(theme);
      var selected = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DItem(
              variant: DItemVariant.outline,
              borderColor: restingBorder,
              selectionStyle: DItemSelectionStyle.outline,
              selected: selected,
              showSelectionIndicator: false,
              onPressed: () => setState(() => selected = true),
              children: const [Text('Outlined item')],
            ),
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      Container surface() => tester.widget<Container>(
        find.descendant(
          of: find.byType(DItem),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        ),
      );
      expect(
        (surface().decoration! as BoxDecoration).border!.top.color,
        restingBorder,
      );
      await tester.tap(find.text('Outlined item'));
      await tester.pump();
      expect(
        (surface().foregroundDecoration! as BoxDecoration).border,
        Border.all(color: tokens.primary, width: 2),
      );
    }
  });

  testWidgets('neutral rows keep hover subtle and selection borderless', (
    tester,
  ) async {
    final strategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(700, 500));
    final focus = FocusNode();
    addTearDown(focus.dispose);
    for (final brightness in Brightness.values) {
      final theme = ThemeData(brightness: brightness);
      final tokens = DTokens.fromTheme(theme);
      var selected = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DItem(
              focusNode: focus,
              selected: selected,
              selectionStyle: DItemSelectionStyle.neutral,
              showSelectionIndicator: false,
              onPressed: () => setState(() => selected = !selected),
              children: const [
                DItemContent(children: [DItemTitle(child: Text('Topic'))]),
              ],
            ),
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      BoxDecoration painted() =>
          tester
                  .renderObject<RenderDecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(DItem),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final bounds = tester.getRect(find.text('Topic'));
      await mouse.moveTo(tester.getCenter(find.text('Topic')));
      await tester.pump();
      final hovered = painted();
      expect(hovered.color!.a, inExclusiveRange(0, .1));
      expect(hovered.border!.top.color, Colors.transparent);
      expect(
        (hovered.borderRadius! as BorderRadius).topLeft.x,
        greaterThan(tokens.radius),
      );
      await tester.pump(const Duration(milliseconds: 75));
      expect(painted(), hovered);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();
      expect(painted().color, Colors.transparent);
      await tester.tap(find.text('Topic'));
      focus.unfocus();
      await tester.pump();
      expect(painted().color!.a, inExclusiveRange(0, .1));
      expect(painted().border!.top.color, Colors.transparent);
      expect(tester.getRect(find.text('Topic')), bounds);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(painted().border!.top.color, tokens.focusRing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'outline selection and pointer hover stay independent of keyboard focus',
    (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(700, 500));
      for (final (brightness, shape) in [
        for (final brightness in Brightness.values)
          for (final shape in DItemShape.values) (brightness, shape),
      ]) {
        final theme = ThemeData(brightness: brightness);
        final tokens = DTokens.fromTheme(theme);
        var selected = 0;
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) => DItemGroup(
                children: [
                  for (var i = 0; i < 2; i++)
                    DItem(
                      key: ValueKey(i),
                      shape: shape,
                      selected: i == selected,
                      selectionStyle: DItemSelectionStyle.outline,
                      showSelectionIndicator: false,
                      onPressed: () => setState(() => selected = i),
                      children: [
                        DItemContent(
                          children: [DItemTitle(child: Text('Topic $i'))],
                        ),
                      ],
                    ),
                ],
              ),
            ),
            theme: theme,
            focusPolicy: true,
          ),
        );
        await tester.pumpAndSettle();
        Container surface(int i) => tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey(i)),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          ),
        );
        final positions = [
          for (var i = 0; i < 2; i++) tester.getRect(find.text('Topic $i')),
        ];
        expect(
          (surface(0).decoration! as BoxDecoration).color,
          Colors.transparent,
        );
        expect(
          (surface(0).foregroundDecoration! as BoxDecoration).border,
          Border.all(color: tokens.primary, width: 2),
        );
        expect(
          (surface(0).decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(switch (shape) {
            DItemShape.card => DRadius.panel,
            DItemShape.fullWidth => 0,
            DItemShape.standard => 10,
          }),
        );
        await mouse.moveTo(tester.getCenter(find.text('Topic 1')));
        await tester.pump();
        for (final duration in [
          Duration.zero,
          const Duration(milliseconds: 75),
          const Duration(milliseconds: 75),
        ]) {
          await tester.pump(duration);
          expect(
            (surface(1).decoration! as BoxDecoration).color,
            tokens.foreground.withValues(
              alpha: brightness == Brightness.light ? .09 : .05,
            ),
          );
          expect(surface(1).foregroundDecoration, isNull);
          expect(
            (surface(1).decoration! as BoxDecoration).border!.top.color,
            Colors.transparent,
          );
          expect(tester.getRect(find.text('Topic 1')), positions[1]);
        }
        await mouse.moveTo(const Offset(700, 500));
        await tester.pump();
        await tester.tap(find.text('Topic 1'));
        await tester.pump();
        for (final duration in [
          Duration.zero,
          const Duration(milliseconds: 40),
        ]) {
          await tester.pump(duration);
          expect(surface(0).foregroundDecoration, isNull);
          expect(
            (surface(1).foregroundDecoration! as BoxDecoration).border,
            Border.all(color: tokens.primary, width: 2),
          );
          for (var i = 0; i < 2; i++) {
            expect(
              (surface(i).decoration! as BoxDecoration).color,
              Colors.transparent,
            );
            expect(tester.getRect(find.text('Topic $i')), positions[i]);
          }
        }
        await mouse.moveTo(tester.getCenter(find.text('Topic 1')));
        await tester.pump();
        expect(
          (surface(1).decoration! as BoxDecoration).color,
          tokens.foreground.withValues(
            alpha: brightness == Brightness.light ? .09 : .05,
          ),
        );
        expect(surface(1).foregroundDecoration, isNotNull);
        await mouse.moveTo(const Offset(700, 500));
        await tester.pump();
        expect(
          (surface(1).decoration! as BoxDecoration).color,
          Colors.transparent,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'controlled selection adds and removes its indicator and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      for (final brightness in Brightness.values) {
        for (final (selected, showIndicator) in [
          (false, true),
          (true, true),
          (true, false),
          (false, false),
        ]) {
          await tester.pumpWidget(
            host(
              DItem(
                selected: selected,
                showSelectionIndicator: showIndicator,
                onPressed: () {},
                children: const [
                  DItemContent(
                    children: [DItemTitle(child: Text('Current topic'))],
                  ),
                ],
              ),
              theme: ThemeData(brightness: brightness),
              width: 280,
              direction: TextDirection.rtl,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byType(DIcon),
            selected && showIndicator ? findsOneWidget : findsNothing,
          );
          expect(
            tester
                    .getSemantics(find.byType(DItem))
                    .flagsCollection
                    .isSelected ==
                ui.Tristate.isTrue,
            selected,
          );
          expect(tester.takeException(), isNull);
        }
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'Linear sizes preserve border-box insets, type and media alignment',
    (tester) async {
      for (final (size, image, inset, gap, textSize, contentGap) in [
        (DItemSize.standard, 40.0, 16.0, 12.0, 12.5, 4.0),
        (DItemSize.sm, 32.0, 12.0, 12.0, 12.5, 4.0),
        (DItemSize.xs, 24.0, 10.0, 8.0, 12.5, 0.0),
      ]) {
        await tester.pumpWidget(host(sample(size)));
        expect(tester.getSize(find.byKey(mediaKey)), Size.square(image));
        expect(tester.getTopLeft(find.byKey(mediaKey)).dx, inset);
        expect(tester.getTopLeft(find.byKey(titleKey)).dx, inset + image + gap);
        expect(
          tester.getTopLeft(find.byKey(mediaKey)).dy,
          (size == DItemSize.xs
                  ? 8
                  : size == DItemSize.sm
                  ? 10
                  : 12) +
              2,
        );
        final title = tester.renderObject<RenderParagraph>(
          find.byKey(titleKey),
        );
        final description = tester.renderObject<RenderParagraph>(
          find.byKey(descriptionKey),
        );
        expect(title.text.style!.fontSize, 14.5);
        expect(title.text.style!.height, 1.35);
        expect(description.text.style!.fontSize, textSize);
        expect(description.text.style!.height, 1.45);
        expect(
          tester.getTopLeft(find.byKey(descriptionKey)).dy -
              tester.getBottomLeft(find.byKey(titleKey)).dy,
          closeTo(contentGap, .01),
        );
      }
    },
  );

  testWidgets(
    'row and secondary button isolate pointer and keyboard activation',
    (tester) async {
      final row = FocusNode();
      final action = FocusNode();
      addTearDown(row.dispose);
      addTearDown(action.dispose);
      var opened = 0;
      var saved = 0;
      await tester.pumpWidget(
        host(
          DItem(
            link: true,
            focusNode: row,
            onPressed: () => opened++,
            children: [
              const DItemContent(
                children: [DItemTitle(child: Text('Project'))],
              ),
              DItemActions(
                children: [
                  DButton(
                    focusNode: action,
                    label: const Text('Save'),
                    onPressed: () => saved++,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      expect((opened, saved), (0, 1));
      action.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((opened, saved), (0, 2));
      row.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(
        (opened, saved),
        (1, 2),
        reason: 'anchor-like rows activate on Enter, not Space',
      );
      await tester.tap(find.text('Project'));
      expect((opened, saved), (2, 2));
      await tester.pumpWidget(host(const Text('Removed')));
      expect(() => row.requestFocus(), returnsNormally);
    },
  );

  testWidgets('button-like row activates with Enter and Space', (tester) async {
    final row = FocusNode();
    addTearDown(row.dispose);
    var activated = 0;
    await tester.pumpWidget(
      host(
        DItem(
          focusNode: row,
          onPressed: () => activated++,
          children: const [
            DItemContent(children: [DItemTitle(child: Text('Open project'))]),
          ],
        ),
      ),
    );

    row.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(activated, 2);
  });

  testWidgets(
    'composed final Checkbox owns Space and pointer without activating its row',
    (tester) async {
      final checkboxFocus = FocusNode();
      addTearDown(checkboxFocus.dispose);
      var opened = 0;
      var checked = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DItem(
              onPressed: () => opened++,
              link: true,
              children: [
                const DItemContent(
                  children: [DItemTitle(child: Text('Project'))],
                ),
                DItemActions(
                  children: [
                    DCheckbox(
                      value: checked,
                      focusNode: checkboxFocus,
                      semanticLabel: 'Track project',
                      onChanged: (value) => setState(() => checked = value!),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DCheckbox));
      await tester.pump();
      expect((opened, checked), (0, true));
      checkboxFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect((opened, checked), (0, false));
      await tester.tap(find.text('Project'));
      await tester.pump();
      expect((opened, checked), (1, false));
    },
  );

  testWidgets(
    'disabled row retains independently enabled child action and no tab stop',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var open = 0;
      var save = 0;
      await tester.pumpWidget(
        host(
          DItem(
            enabled: false,
            link: true,
            focusNode: node,
            onPressed: () => open++,
            children: [
              const DItemContent(
                children: [DItemTitle(child: Text('Unavailable'))],
              ),
              DItemActions(
                children: [
                  DButton(onPressed: () => save++, label: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Unavailable'));
      await tester.tap(find.text('Save'));
      expect((open, save), (0, 1));
      expect(node.canRequestFocus, isFalse);
    },
  );

  testWidgets(
    'item surfaces follow live tokens with consistent Linear corners',
    (tester) async {
      for (final radius in [4.0, 10.0]) {
        final theme = ThemeData();
        final tokens = DTokens.fromTheme(
          theme,
        ).copyWith(radius: radius, muted: const Color(0x80664422));
        await tester.pumpWidget(
          host(
            const DItem(variant: DItemVariant.muted),
            theme: theme.copyWith(extensions: [tokens]),
          ),
        );
        await tester.pumpAndSettle();
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byType(DItem),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          ),
        );
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.color, tokens.surface);
        expect(decoration.borderRadius, BorderRadius.circular(10));
      }
    },
  );

  testWidgets(
    'group spacing, separator margin and list semantics remain distinct',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const DItemGroup(
            children: [
              DItem(key: Key('one'), size: DItemSize.sm),
              DItemSeparator(),
              DItem(key: Key('two')),
            ],
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('two'))).dy -
            tester.getBottomLeft(find.byKey(const Key('one'))).dy,
        10 + 17 + 10,
      );
      final nodes = tester.widgetList<Semantics>(find.byType(Semantics));
      expect(
        nodes.where((n) => n.properties.role == SemanticsRole.list).length,
        1,
      );
      expect(
        nodes.where((n) => n.properties.role == SemanticsRole.listItem).length,
        2,
      );
      semantics.dispose();
    },
  );

  testWidgets('narrow RTL large text reflows without losing child form state', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? saved;
    final item = DItem(
      header: const DItemHeader(child: Text('Header')),
      footer: const DItemFooter(child: Text('Footer')),
      children: [
        const DItemMedia(
          child: SizedBox.square(dimension: 32, child: Text('M')),
        ),
        DItemContent(
          children: [
            const DItemTitle(
              child: Text('A title that must wrap at large text sizes'),
            ),
            Form(
              key: form,
              child: DInput(
                initialValue: 'Initial',
                onSaved: (value) => saved = value,
              ),
            ),
          ],
        ),
        const DItemActions(children: [Text('Action')]),
      ],
    );
    await tester.pumpWidget(host(SingleChildScrollView(child: item)));
    await tester.enterText(find.byType(DInput), 'Edited');
    await tester.pumpWidget(
      host(
        SingleChildScrollView(child: item),
        width: 180,
        scale: 2,
        direction: TextDirection.rtl,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Edited'), findsOneWidget);
    form.currentState!.save();
    expect(saved, 'Edited');
    form.currentState!.reset();
    await tester.pump();
    expect(find.text('Initial'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Action')).dy,
      greaterThan(tester.getBottomLeft(find.byType(DInput)).dy),
    );
  });

  testWidgets(
    'keyboard focus paints only the exterior ring and clears on disabling',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      final boundaryKey = GlobalKey();
      Widget content(bool enabled) => host(
        RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DItem(
                enabled: enabled,
                focusNode: node,
                onPressed: () {},
                variant: DItemVariant.muted,
              ),
            ),
          ),
        ),
      );
      Future<List<int>> pixels() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = bytes!.buffer.asUint8List().toList();
          image.dispose();
          return result;
        }))!;
      }

      List<int> pixel(List<int> data, int x, int y) =>
          data.sublist((y * 448 + x) * 4, (y * 448 + x) * 4 + 4);
      await tester.pumpWidget(content(true));
      final before = await pixels();
      node.requestFocus();
      await tester.pumpAndSettle();
      final focused = await pixels();
      expect(
        pixel(focused, 40, 18),
        pixel(before, 40, 18),
        reason: 'focus must not tint translucent interior',
      );
      expect(
        pixel(focused, 5, 24),
        isNot(pixel(before, 5, 24)),
        reason: '1px ring has a 2px exterior gap',
      );
      expect(
        pixel(focused, 4, 18),
        pixel(before, 4, 18),
        reason: 'ring ends at 3px',
      );
      await tester.pumpWidget(content(false));
      await tester.pumpAndSettle();
      final disabled = await pixels();
      expect(pixel(disabled, 5, 24), pixel(before, 5, 24));
    },
  );

  testWidgets(
    'large text and explicit unlimited notes clear inherited truncation',
    (tester) async {
      const content = DefaultTextStyle(
        style: TextStyle(),
        maxLines: 1,
        child: DItem(
          children: [
            DItemContent(
              children: [
                DItemTitle(
                  child: Text('Long title that must remain completely visible'),
                ),
                DItemDescription(
                  maxLines: null,
                  child: Text(
                    'Complete note that must wrap across every required line',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpWidget(host(content, width: 300, scale: 2));
      expect(tester.takeException(), isNull);
      final largeTitle = tester.renderObject<RenderParagraph>(
        find.text('Long title that must remain completely visible'),
      );
      final largeNote = tester.renderObject<RenderParagraph>(
        find.text('Complete note that must wrap across every required line'),
      );
      expect(largeTitle.maxLines, isNull);
      expect(largeTitle.overflow, TextOverflow.clip);
      expect(largeNote.maxLines, isNull);
      expect(largeNote.overflow, TextOverflow.clip);
      expect(largeTitle.size.height, greaterThan(38));
      expect(largeNote.size.height, greaterThan(80));
      await tester.pumpWidget(host(content));
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text('Long title that must remain completely visible'),
            )
            .maxLines,
        1,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text(
                'Complete note that must wrap across every required line',
              ),
            )
            .maxLines,
        isNull,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text(
                'Complete note that must wrap across every required line',
              ),
            )
            .overflow,
        TextOverflow.clip,
      );
    },
  );

  testWidgets(
    'RTL reverses media and content without mirroring child artwork',
    (tester) async {
      await tester.pumpWidget(
        host(sample(DItemSize.standard), direction: TextDirection.rtl),
      );
      expect(tester.getTopRight(find.byKey(mediaKey)).dx, 448 - 16);
      expect(
        tester.getTopRight(find.byKey(titleKey)).dx,
        lessThan(tester.getTopLeft(find.byKey(mediaKey)).dx),
      );
    },
  );

  testWidgets('whole-row drag drops its payload and preserves tap', (
    tester,
  ) async {
    var taps = 0;
    String? dropped;
    await tester.pumpWidget(
      host(
        Column(
          children: [
            DItem(
              dragData: 'topic-42',
              onPressed: () => taps++,
              children: const [
                DItemContent(children: [Text('Drag topic')]),
              ],
            ),
            const SizedBox(height: 40),
            DDragRegion<String>(
              accepts: (data) => data == 'topic-42',
              onMove: (_, _) {},
              onDrop: (data, _) => dropped = data,
              onLeave: () {},
              child: const SizedBox(height: 100, child: Text('Target')),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Drag topic'));
    expect(taps, 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Drag topic')),
    );
    await gesture.moveTo(tester.getCenter(find.text('Target')));
    await gesture.up();
    await tester.pump();
    expect(dropped, 'topic-42');
    expect(taps, 1);
  });
}
