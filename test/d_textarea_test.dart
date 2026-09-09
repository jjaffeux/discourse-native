import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 320, child: child),
    ),
  ),
);

void main() {
  testWidgets('unadorned editor never absorbs page heading or action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        Column(
          children: [
            const Text('Surrounding heading'),
            DTextarea(hintText: 'Message'),
            TextButton(onPressed: () {}, child: const Text('Send')),
          ],
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(EditableText));
    expect(node.rect.size, tester.getSize(find.byType(TextField)));
    expect(node.label, isNot(contains('Surrounding heading')));
    SemanticsNode? ancestor = tester.getSemantics(find.text('Send'));
    while (ancestor != null) {
      expect(ancestor.getSemanticsData().flagsCollection.isTextField, isFalse);
      ancestor = ancestor.parent;
    }
    handle.dispose();
  });

  for (final layout in ['single', 'column', 'row']) {
    testWidgets(
      '$layout editors exclude sibling headings and actions from their semantics',
      (tester) async {
        final handle = tester.ensureSemantics();
        final count = layout == 'single' ? 1 : 2;
        final fields = List.generate(
          count,
          (i) => DTextarea(
            labelText: 'Message $i',
            initialValue: 'Draft $i',
            isRequired: true,
            errorText: 'Error $i',
            helperText: 'Help $i',
          ),
        );
        await tester.pumpWidget(
          host(
            Column(
              children: [
                Semantics(header: true, child: const Text('Heading')),
                if (layout == 'row')
                  Row(
                    children: [
                      for (final field in fields) Expanded(child: field),
                    ],
                  )
                else
                  ...fields,
                TextButton(
                  onPressed: () {},
                  child: const Text('Independent action'),
                ),
              ],
            ),
          ),
        );
        for (var i = 0; i < count; i++) {
          final editable = find.byType(EditableText).at(i);
          final node = tester.getSemantics(editable);
          expect(node.rect.size, tester.getSize(find.byType(TextField).at(i)));
          expect(node.label, 'Message $i');
          expect(node.value, 'Draft $i');
          expect(node.getSemanticsData().flagsCollection.isTextField, isTrue);
          expect(
            node.getSemanticsData().flagsCollection.isRequired,
            Tristate.isTrue,
          );
          expect(
            node.getSemanticsData().validationResult,
            SemanticsValidationResult.invalid,
          );
          expect(node.label, isNot(contains('Heading')));
          expect(node.label, isNot(contains('Independent action')));
        }
        final action = tester.getSemantics(find.text('Independent action'));
        expect(action.getSemanticsData().flagsCollection.isButton, isTrue);
        SemanticsNode? ancestor = action;
        while (ancestor != null) {
          expect(
            ancestor.getSemanticsData().flagsCollection.isTextField,
            isFalse,
          );
          ancestor = ancestor.parent;
        }
        expect(
          tester
              .getSemantics(find.text('Heading'))
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(
          tester.getSemantics(find.text('Error 0')).label,
          contains('Error 0'),
        );
        handle.dispose();
      },
    );
  }

  testWidgets('grows from 64px with content and caps at maxLines', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(DTextarea(controller: controller)));
    expect(tester.getSize(find.byType(DTextarea)).height, 64);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.style.fontSize, 14);
    expect(editable.style.height, 20 / 14);
    controller.text = 'one\ntwo\nthree\nfour\nfive';
    await tester.pump();
    expect(tester.getSize(find.byType(DTextarea)).height, 118);
    await tester.pumpWidget(
      host(DTextarea(controller: controller, maxLines: 3)),
    );
    expect(tester.getSize(find.byType(DTextarea)).height, 78);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Form saves validates and resets to mount text after value updates',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? saved;
      final changes = <String>[];
      Widget build(String value) => host(
        Form(
          key: form,
          child: DTextarea(
            value: value,
            onChanged: changes.add,
            onSaved: (text) => saved = text,
            validator: (text) => text!.isEmpty ? 'Required message' : null,
          ),
        ),
      );
      await tester.pumpWidget(build('original'));
      await tester.pumpWidget(build('parent update'));
      form.currentState!.save();
      expect(saved, 'parent update');
      await tester.enterText(find.byType(TextField), '');
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required message'), findsOneWidget);
      form.currentState!.reset();
      await tester.pump();
      expect(find.text('original'), findsOneWidget);
      expect(find.text('Required message'), findsNothing);
      form.currentState!.save();
      expect(saved, 'original');
      expect(changes, ['', 'original']);
    },
  );

  testWidgets('equal controlled text preserves selection and IME composition', (
    tester,
  ) async {
    Widget build(String value) => host(DTextarea(value: value));
    await tester.pumpWidget(build('draft'));
    await tester.tap(find.byType(TextField));
    const editing = TextEditingValue(
      text: 'draft',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 3),
    );
    tester.testTextInput.updateEditingValue(editing);
    await tester.pump();
    await tester.pumpWidget(build('draft'));
    var editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.value, editing);
    await tester.pumpWidget(build('replacement'));
    editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.selection.baseOffset, 11);
    expect(editable.controller.value.composing, TextRange.empty);
  });

  testWidgets(
    'switches borrowed controllers and preserves local editing ownership',
    (tester) async {
      final first = TextEditingController(text: 'first');
      final second = TextEditingController(text: 'second');
      final focus = FocusNode();
      final scroll = ScrollController();
      final undo = UndoHistoryController();
      addTearDown(() {
        first.dispose();
        second.dispose();
        focus.dispose();
        scroll.dispose();
        undo.dispose();
      });
      Widget build(TextEditingController? controller) => host(
        DTextarea(
          controller: controller,
          focusNode: focus,
          scrollController: scroll,
          undoController: undo,
        ),
      );
      await tester.pumpWidget(build(first));
      first.value = const TextEditingValue(
        text: 'first',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 3),
      );
      await tester.pumpWidget(build(null));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.value,
        first.value,
      );
      await tester.pumpWidget(build(second));
      first.text = 'detached';
      await tester.pump();
      expect(find.text('second'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      second.text = 'still usable';
      focus.addListener(() {});
      scroll.addListener(() {});
      undo.addListener(() {});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'label focuses native editing and disabling removes keyboard focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget build(bool enabled) => host(
        DTextarea(labelText: 'Message', focusNode: focus, enabled: enabled),
      );
      await tester.pumpWidget(build(true));
      await tester.tap(find.text('Message'));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.text('Message'), warnIfMissed: false);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    },
  );

  testWidgets('native keyboard inserts newline and Tab traverses', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(() {
      first.dispose();
      second.dispose();
    });
    await tester.pumpWidget(
      host(
        Column(
          children: [
            DTextarea(focusNode: first),
            DTextarea(focusNode: second),
          ],
        ),
      ),
    );
    first.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'one\ntwo');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(second.hasFocus, isTrue);
  });

  testWidgets('required invalid and read-only semantics remain native', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      host(
        DTextarea(
          labelText: 'Message',
          isRequired: true,
          errorText: 'Explain the issue',
          readOnly: true,
          initialValue: 'Fixed message',
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(EditableText));
    expect(
      node.getSemanticsData().validationResult,
      SemanticsValidationResult.invalid,
    );
    expect(
      node,
      matchesSemantics(
        isTextField: true,
        isMultiline: true,
        isReadOnly: true,
        isRequired: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        label: 'Message',
        value: 'Fixed message',
        textDirection: TextDirection.ltr,
        hasFocusAction: true,
        hasRequiredState: true,
        validationResult: SemanticsValidationResult.invalid,
        hasDidGainAccessibilityFocusAction: true,
        hasDidLoseAccessibilityFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('grapheme limit counter tracks editing and programmatic text', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        DTextarea(
          controller: controller,
          maxLength: 3,
          showCounter: true,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '👩‍💻abc');
    expect(controller.text, '👩‍💻ab');
    await tester.pump();
    expect(find.text('3/3'), findsOneWidget);
    controller.text = 'hi';
    await tester.pump();
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets(
    'the box takes the text cursor and a press in its padding focuses the editor',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      Widget build(bool enabled) => host(
        DTextarea(focusNode: focus, hintText: 'Message', enabled: enabled),
      );
      await tester.pumpWidget(build(true));
      final surface = find.byType(AnimatedContainer);
      expect(
        tester.getTopLeft(find.byType(TextField)),
        tester.getTopLeft(surface) + const Offset(11, 9),
      );
      final padding = tester.getTopLeft(surface) + const Offset(4, 4);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: padding);
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
      );
      await tester.tapAt(padding);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.forbidden,
      );
      await tester.tapAt(padding);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    },
  );

  testWidgets(
    'border color eases over 150 milliseconds while the ring paints at once',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(host(DTextarea(focusNode: focus)));
      final tokens = DTokens.of(tester.element(find.byType(TextField)));
      Color border() {
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(AnimatedContainer),
            matching: find.byType(DecoratedBox),
          ),
        );
        return ((box.decoration as BoxDecoration).border! as Border).top.color;
      }

      CustomPainter? ring() => tester
          .widget<CustomPaint>(
            find
                .ancestor(
                  of: find.byType(AnimatedContainer),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .foregroundPainter;
      expect(ring(), isNull);
      expect(border(), tokens.colors.outlineVariant);
      focus.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(ring(), isNotNull);
      expect(border(), tokens.colors.outlineVariant);
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        border(),
        Color.lerp(
          tokens.colors.outlineVariant,
          tokens.focusRing,
          Curves.fastOutSlowIn.transform(.5),
        ),
      );
      await tester.pump(const Duration(milliseconds: 75));
      expect(border(), tokens.focusRing);
      focus.unfocus();
      await tester.pump();
      await tester.pump();
      expect(ring(), isNull);
      expect(border(), tokens.focusRing);
      await tester.pump(const Duration(milliseconds: 150));
      expect(border(), tokens.colors.outlineVariant);
    },
  );
}
