import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics name the explicit or inherited direction', () {
    List<String> properties(TextDirection? direction) =>
        DDirection(textDirection: direction, child: const SizedBox.shrink())
            .toDiagnosticsNode()
            .getProperties()
            .map((property) => property.toString())
            .toList();
    expect(properties(TextDirection.rtl), ['textDirection: rtl']);
    expect(properties(null), ['textDirection: inherited']);
  });

  testWidgets('missing scope is nullable only for maybeOf', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(DDirection.maybeOf(context), isNull);
          expect(() => DDirection.of(context), throwsFlutterError);
          return const SizedBox.shrink();
        },
      ),
    );

    await tester.pumpWidget(const DDirection(child: SizedBox.shrink()));
    expect(tester.takeException(), isA<FlutterError>());

    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        DDirection(
          textDirection: direction,
          child: const _ReadDirection('root'),
        ),
      );
      expect(find.text('root: ${direction.name}'), findsOneWidget);
    }
  });

  testWidgets('nearest native and library scopes agree and update live', (
    tester,
  ) async {
    final host = ValueNotifier(TextDirection.ltr);
    addTearDown(host.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: host,
        builder: (context, direction, child) =>
            Directionality(textDirection: direction, child: child!),
        child: const DDirection(
          child: Column(
            children: [
              _ReadDirection('host'),
              DDirection(
                textDirection: TextDirection.rtl,
                child: Column(
                  children: [
                    DDirection(child: _ReadDirection('inherited override')),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: _ReadDirection('native island'),
                    ),
                  ],
                ),
              ),
              _ReadDirection('sibling'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('host: ltr'), findsOneWidget);
    expect(find.text('sibling: ltr'), findsOneWidget);
    expect(find.text('inherited override: rtl'), findsOneWidget);
    expect(find.text('native island: ltr'), findsOneWidget);

    host.value = TextDirection.rtl;
    await tester.pump();
    expect(find.text('host: rtl'), findsOneWidget);
    expect(find.text('sibling: rtl'), findsOneWidget);
    expect(find.text('inherited override: rtl'), findsOneWidget);
    expect(find.text('native island: ltr'), findsOneWidget);
  });

  testWidgets('explicit and inherited changes retain edits, state and focus', (
    tester,
  ) async {
    final direction = ValueNotifier<TextDirection?>(null);
    final focus = FocusNode();
    addTearDown(direction.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ValueListenableBuilder(
            valueListenable: direction,
            builder: (context, value, child) =>
                DDirection(textDirection: value, child: child!),
            child: Scaffold(body: _RetainedEditor(focusNode: focus)),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Count: 0'));
    await tester.enterText(find.byType(TextField), 'مرحبا Ada');
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);

    for (final value in [TextDirection.ltr, TextDirection.rtl, null]) {
      direction.value = value;
      await tester.pump();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable
            .textDirection,
        value ?? TextDirection.rtl,
      );
      expect(editor.controller, same(controller));
      expect(editor.controller.text, 'مرحبا Ada');
      expect(
        editor.controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(find.text('Count: 1'), findsOneWidget);
      expect(focus.hasPrimaryFocus, isTrue);
    }

    await tester.enterText(find.byType(TextField), 'Still editable');
    expect(controller.text, 'Still editable');
    await tester.pumpWidget(const SizedBox.shrink());
    focus
        .requestFocus(); // The provider never disposes borrowed child resources.
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      '${direction.name} uses native layout, semantics and Tab order',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final first = FocusNode();
        final second = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        var activations = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: DDirection(
              textDirection: direction,
              child: Scaffold(
                body: Column(
                  children: [
                    const Text('Reading direction'),
                    Row(
                      children: [
                        TextButton(
                          focusNode: first,
                          onPressed: () => activations++,
                          child: const Text('First'),
                        ),
                        TextButton(
                          focusNode: second,
                          onPressed: () => activations++,
                          child: const Text('Second'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final firstX = tester.getCenter(find.text('First')).dx;
        final secondX = tester.getCenter(find.text('Second')).dx;
        expect(
          firstX,
          direction == TextDirection.ltr
              ? lessThan(secondX)
              : greaterThan(secondX),
        );
        expect(
          tester
              .getSemantics(find.text('Reading direction'))
              .getSemanticsData()
              .textDirection,
          direction,
        );
        first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(second.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(activations, 1);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(first.hasPrimaryFocus, isTrue);
        semantics.dispose();
      },
    );
  }
}

class _ReadDirection extends StatelessWidget {
  const _ReadDirection(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final direction = DDirection.of(context);
    expect(DDirection.maybeOf(context), direction);
    expect(Directionality.of(context), direction);
    return Text('$label: ${direction.name}');
  }
}

class _RetainedEditor extends StatefulWidget {
  const _RetainedEditor({required this.focusNode});

  final FocusNode focusNode;

  @override
  State<_RetainedEditor> createState() => _RetainedEditorState();
}

class _RetainedEditorState extends State<_RetainedEditor> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(focusNode: widget.focusNode),
      TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('Count: $_count'),
      ),
    ],
  );
}
