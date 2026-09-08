import 'dart:ui'
    show CheckedState, SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the label activates its native checkbox with one semantic name',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        bool checked = false;
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              onChanged: (value) => setState(() => checked = value ?? false),
              title: const DLabel(child: Text('Accept terms')),
            ),
          ),
        );
        final control = find.bySemanticsLabel('Accept terms');
        expect(control, findsOneWidget);
        var node = tester.getSemantics(control);
        expect(
          node.getSemanticsData().flagsCollection.isChecked,
          isNot(CheckedState.none),
        );
        expect(
          node.getSemanticsData().flagsCollection.isEnabled,
          Tristate.isTrue,
        );
        expect(
          node.getSemanticsData().flagsCollection.isChecked,
          CheckedState.isFalse,
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(
          tester.getSize(find.byType(CheckboxListTile)).height,
          greaterThanOrEqualTo(48),
        );

        await tester.tap(find.text('Accept terms'));
        await tester.pump();
        expect(checked, isTrue);
        node = tester.getSemantics(control);
        expect(
          node.getSemanticsData().flagsCollection.isChecked,
          CheckedState.isTrue,
        );
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            viewId: tester.view.viewId,
            nodeId: node.id,
            type: SemanticsAction.tap,
          ),
        );
        await tester.pump();
        expect(checked, isFalse);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('keyboard focus belongs to the control and skips the label', (
    tester,
  ) async {
    final checkboxFocus = FocusNode();
    final nextFocus = FocusNode();
    addTearDown(checkboxFocus.dispose);
    addTearDown(nextFocus.dispose);
    bool checked = false;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            CheckboxListTile(
              focusNode: checkboxFocus,
              autofocus: true,
              value: checked,
              onChanged: (value) => setState(() => checked = value ?? false),
              title: const DLabel(child: Text('Keyboard label')),
            ),
            DButton(
              focusNode: nextFocus,
              onPressed: () {},
              label: const Text('Next control'),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(checkboxFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(checked, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(nextFocus.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(checkboxFocus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(checkboxFocus.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    // Native owners borrow the nodes; the caller can still use them.
    checkboxFocus.addListener(() {});
  });

  testWidgets(
    'disabled label retains its name and checked state without actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          const CheckboxListTile(
            value: true,
            onChanged: null,
            title: DLabel(enabled: false, child: Text('Disabled label')),
          ),
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel('Disabled label'),
        );
        expect(
          node.getSemanticsData().flagsCollection.isEnabled,
          isNot(Tristate.none),
        );
        expect(
          node.getSemanticsData().flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        expect(
          node.getSemanticsData().flagsCollection.isChecked,
          CheckedState.isTrue,
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        await tester.tap(find.text('Disabled label'), warnIfMissed: false);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('disabled content cannot activate or take keyboard focus', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    int activations = 0;
    await _pump(
      tester,
      DLabel(
        enabled: false,
        child: DButton(
          focusNode: focus,
          onPressed: () => activations++,
          label: const Text('Nested action'),
        ),
      ),
    );
    await tester.tap(find.text('Nested action'), warnIfMissed: false);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(focus.hasFocus, isFalse);
    expect(activations, 0);
  });

  testWidgets(
    'reference metrics and explicit emphasis retain live theme colors',
    (tester) async {
      final theme = ValueNotifier(AppTheme.light);
      addTearDown(theme.dispose);
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
                DLabel(child: Text('Default')),
                DLabel(enabled: false, child: Text('Disabled')),
                DLabel(
                  style: TextStyle(fontStyle: FontStyle.italic),
                  child: Text('Emphasis'),
                ),
              ],
            ),
          ),
        ),
      );
      for (final value in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
        StyleguideTheme.plum.resolve(AppTheme.light),
        ThemeData.light(),
      ]) {
        theme.value = value;
        await tester.pump();
        final context = tester.element(find.text('Default'));
        final style = tester
            .renderObject<RenderParagraph>(find.text('Default'))
            .text
            .style!;
        expect(style.fontSize, 14);
        expect(style.height, 1);
        expect(style.fontWeight, FontWeight.w500);
        expect(style.letterSpacing, 0);
        expect(
          tester
              .widget<Opacity>(
                find.descendant(
                  of: find.widgetWithText(DLabel, 'Disabled'),
                  matching: find.byType(Opacity),
                ),
              )
              .opacity,
          0.5,
        );
        expect(style.color, DTokens.of(context).foreground);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Disabled'))
              .text
              .style!
              .color,
          DTokens.of(context).foreground,
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Emphasis'))
              .text
              .style!
              .fontStyle,
          FontStyle.italic,
        );
      }
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'rich text wraps at 200% in ${direction.name} despite ancestor truncation',
      (tester) async {
        await _pump(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: DDirection(
              textDirection: direction,
              child: const SizedBox(
                width: 160,
                child: DefaultTextStyle(
                  style: TextStyle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: DLabel(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'A long label with '),
                          TextSpan(
                            text: 'emphasis',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: ' which must remain completely readable.',
                          ),
                        ],
                      ),
                      key: ValueKey('rich'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('rich')),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(80));
        expect(paragraph.textDirection, direction);
        expect(paragraph.textAlign, TextAlign.start);
        expect(paragraph.textScaler.scale(14), 28);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('selection areas do not make labels selectable', (tester) async {
    await _pump(
      tester,
      const SelectionArea(
        child: Column(
          children: [
            Text('Selectable prose'),
            DLabel(child: Text('Control label')),
          ],
        ),
      ),
    );
    final label = tester.renderObject<RenderParagraph>(
      find.text('Control label'),
    );
    final prose = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('Selectable prose'),
        matching: find.byType(RichText),
      ),
    );
    expect(label.registrar, isNull);
    expect(prose.registrar, isNotNull);
  });

  testWidgets('activation may remove the native control and label together', (
    tester,
  ) async {
    bool visible = true;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => visible
            ? SwitchListTile.adaptive(
                value: false,
                onChanged: (_) => setState(() => visible = false),
                title: const DLabel(child: Text('Dismiss control')),
              )
            : const Text('Dismissed'),
      ),
    );
    await tester.tap(find.text('Dismiss control'));
    await tester.pumpAndSettle();
    expect(find.byType(DLabel), findsNothing);
    expect(find.text('Dismissed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  ),
);
