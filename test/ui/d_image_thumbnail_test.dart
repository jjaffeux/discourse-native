import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/application_component_catalogue.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _thumbnail => find.byType(DImageThumbnail);

Future<void> _pump(
  WidgetTester tester, {
  bool selected = false,
  bool reduced = false,
  Color? outlineColor,
  VoidCallback? onPressed,
  FocusNode? focusNode,
}) => tester.pumpWidget(
  DFocusHighlight(
    child: MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: Center(
            child: DImageThumbnail(
              semanticLabel: 'Go to image 1 of 3',
              selected: selected,
              outlineColor: outlineColor,
              focusNode: focusNode,
              onPressed: onPressed ?? () {},
              child: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    ),
  ),
);

AnimatedOpacity _opacity(WidgetTester tester) => tester.widget(
  find.descendant(of: _thumbnail, matching: find.byType(AnimatedOpacity)),
);

BoxDecoration _outline(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find.descendant(
                of: _thumbnail,
                matching: find.byType(DecoratedBox),
              ),
            )
            .decoration
        as BoxDecoration;

Rect _outlineRect(WidgetTester tester) => tester.getRect(
  find.descendant(of: _thumbnail, matching: find.byType(DecoratedBox)),
);

void main() {
  testWidgets('draws 52 square with the image clipped to 6px corners', (
    tester,
  ) async {
    await _pump(tester);

    expect(tester.getSize(_thumbnail), const Size.square(52));
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: _thumbnail, matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('an unselected thumbnail recedes with no outline', (
    tester,
  ) async {
    await _pump(tester);

    expect(_opacity(tester).opacity, .45);
    expect(_outline(tester).border!.top.color, Colors.transparent);
  });

  testWidgets('the selected thumbnail is outlined 2px outside its bounds', (
    tester,
  ) async {
    await _pump(tester, selected: true, outlineColor: Colors.white);

    expect(_opacity(tester).opacity, 1);
    expect(_outline(tester).border!.top.color, Colors.white);
    expect(_outline(tester).border!.top.width, 2);
    expect(
      _outlineRect(tester),
      tester.getRect(_thumbnail).inflate(DImageThumbnail.outlineExtent),
    );
  });

  testWidgets('the outline defaults to the theme foreground', (tester) async {
    await _pump(tester, selected: true);

    expect(
      _outline(tester).border!.top.color,
      DTokens.of(tester.element(_thumbnail)).foreground,
    );
  });

  testWidgets('selecting fades over 150ms unless motion is reduced', (
    tester,
  ) async {
    await _pump(tester);
    expect(_opacity(tester).duration, const Duration(milliseconds: 150));

    await _pump(tester, reduced: true);
    expect(_opacity(tester).duration, Duration.zero);
  });

  testWidgets('a press selects, and the outline never takes it', (
    tester,
  ) async {
    var presses = 0;
    await _pump(tester, selected: true, onPressed: () => presses++);

    await tester.tap(_thumbnail);
    expect(presses, 1);

    await tester.tapAt(tester.getRect(_thumbnail).topLeft - const Offset(3, 3));
    expect(presses, 1);
  });

  testWidgets('keyboard focus shows the ring and Enter selects', (
    tester,
  ) async {
    var presses = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await _pump(tester, focusNode: focusNode, onPressed: () => presses++);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    focusNode.requestFocus();
    await tester.pump();
    expect(
      _outline(tester).border!.top.color,
      DTokens.of(tester.element(_thumbnail)).focusRing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('announces a selected button that can be activated', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, selected: true);

    final data = tester
        .getSemantics(find.bySemanticsLabel('Go to image 1 of 3'))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  test('has a styleguide entry with examples', () {
    expect(
      applicationComponentCatalogue.map((entry) => entry.id),
      contains('image-thumbnail'),
    );
    expect(componentExamples['image-thumbnail'], isNotNull);
  });
}
