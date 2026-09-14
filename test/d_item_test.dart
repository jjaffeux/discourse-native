import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
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
}) => MaterialApp(
  theme: theme ?? ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
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
    'base-nova sizes preserve border-box insets, type and media alignment',
    (tester) async {
      for (final (size, image, inset, gap, textSize, contentGap) in [
        (DItemSize.standard, 40.0, 13.0, 10.0, 14.0, 4.0),
        (DItemSize.sm, 32.0, 13.0, 10.0, 14.0, 4.0),
        (DItemSize.xs, 24.0, 11.0, 8.0, 12.0, 0.0),
      ]) {
        await tester.pumpWidget(host(sample(size)));
        expect(tester.getSize(find.byKey(mediaKey)), Size.square(image));
        expect(tester.getTopLeft(find.byKey(mediaKey)).dx, inset);
        expect(tester.getTopLeft(find.byKey(titleKey)).dx, inset + image + gap);
        expect(
          tester.getTopLeft(find.byKey(mediaKey)).dy,
          (size == DItemSize.xs ? 9 : 11) + 2,
        );
        final title = tester.renderObject<RenderParagraph>(
          find.byKey(titleKey),
        );
        final description = tester.renderObject<RenderParagraph>(
          find.byKey(descriptionKey),
        );
        expect(title.text.style!.fontSize, 14);
        expect(title.text.style!.height, 1.375);
        expect(description.text.style!.fontSize, textSize);
        expect(description.text.style!.height, 1.5);
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
    'live translucent tokens multiply alpha and proportionally size radius',
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
        expect(decoration.color!.a, closeTo(tokens.muted.a * .5, .001));
        expect(decoration.borderRadius, BorderRadius.circular(radius));
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
        pixel(focused, 6, 18),
        isNot(pixel(before, 6, 18)),
        reason: '3px ring is exterior',
      );
      expect(
        pixel(focused, 4, 18),
        pixel(before, 4, 18),
        reason: 'ring ends at 3px',
      );
      await tester.pumpWidget(content(false));
      await tester.pumpAndSettle();
      final disabled = await pixels();
      expect(pixel(disabled, 6, 18), pixel(before, 6, 18));
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
      expect(tester.getTopRight(find.byKey(mediaKey)).dx, 448 - 13);
      expect(
        tester.getTopRight(find.byKey(titleKey)).dx,
        lessThan(tester.getTopLeft(find.byKey(mediaKey)).dx),
      );
    },
  );
}
