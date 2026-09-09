import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DQuestionnaireChoice<Object> choice(
    String value, {
    String? description,
    bool enabled = true,
  }) => DQuestionnaireChoice<Object>(
    value: value,
    label: Text(value),
    description: description == null ? null : Text(description),
    enabled: enabled,
  );

  DQuestionnaireItem item(
    String id, {
    bool required = true,
    bool multiple = false,
    List<DQuestionnaireChoice<Object>>? choices,
    DQuestionnaireInputConfiguration? input,
    DQuestionnaireEnabledPredicate? enabledWhen,
  }) => DQuestionnaireItem(
    id: id,
    title: Text('Question $id'),
    description: Text('Description $id'),
    required: required,
    multiple: multiple,
    choices: choices ?? [choice('A'), choice('B')],
    input: input,
    enabledWhen: enabledWhen,
  );

  Widget app(
    Widget child, {
    Size size = const Size(700, 700),
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
    bool reduceMotion = false,
  }) => MaterialApp(
    theme: ThemeData.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );

  testWidgets('validates, focuses answers and navigates through typed state', (
    tester,
  ) async {
    DQuestionnaireSnapshot? submitted;
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 420,
          child: DQuestionnaire(
            items: [item('one'), item('two')],
            onSubmit: (answers) => submitted = answers,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Question 1 of 2'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Choose an answer to continue.'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

    await tester.tap(find.text('B').first);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Question two'), findsOneWidget);
    expect(find.text('Question 2 of 2'), findsOneWidget);
    await tester.tap(find.text('A').first);
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(submitted?.valueFor<String>('one'), 'B');
    expect(submitted?.valueFor<String>('two'), 'A');
  });

  testWidgets('multiple choice, explicit skip and reset preserve statuses', (
    tester,
  ) async {
    final controller = DQuestionnaireController(
      items: [
        item('many', multiple: true),
        item('optional', required: false),
        item('end'),
      ],
    );
    await tester.pumpWidget(
      app(
        DQuestionnaire(
          items: controller.items,
          controller: controller,
          showReset: true,
        ),
      ),
    );

    await tester.tap(find.text('A').first);
    await tester.tap(find.text('B').first);
    expect(controller.answerFor('many').valuesAs<String>(), ['A', 'B']);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(controller.answerFor('optional').isSkipped, isTrue);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(controller.currentItemId, 'many');
    expect(controller.answerFor('optional').isEmpty, isTrue);
  });

  testWidgets('letter shortcuts select without advancing and ignore editing', (
    tester,
  ) async {
    final controller = DQuestionnaireController(
      items: [
        item(
          'one',
          input: const DQuestionnaireInputConfiguration(
            label: 'Another answer',
            placeholder: 'Describe it',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      app(
        DQuestionnaire(
          items: controller.items,
          controller: controller,
          shortcuts: DQuestionnaireShortcutMode.letters,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(controller.answerFor('one').valueAs<String>(), 'B');
    expect(controller.currentItemId, 'one');

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'a custom answer');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(controller.answerFor('one').freeform, 'a custom answer');
    expect(controller.answerFor('one').values, isEmpty);
  });

  testWidgets('submit shortcut does not interrupt active IME composition', (
    tester,
  ) async {
    var submissions = 0;
    final controller = DQuestionnaireController(
      items: [
        item(
          'one',
          input: const DQuestionnaireInputConfiguration(label: 'Answer'),
        ),
      ],
    );
    await tester.pumpWidget(
      app(
        DQuestionnaire(
          items: controller.items,
          controller: controller,
          onSubmit: (_) => submissions++,
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'é',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(submissions, 0);
    expect(controller.answerFor('one').freeform, 'é');
  });

  testWidgets('answer arrows wrap and Enter advances from a selected answer', (
    tester,
  ) async {
    final controller = DQuestionnaireController(
      items: [item('one'), item('two')],
    );
    await tester.pumpWidget(
      app(DQuestionnaire(items: controller.items, controller: controller)),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.answerFor('one').valueAs<String>(), 'B');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.answerFor('one').valueAs<String>(), 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.currentItemId, 'two');
  });

  testWidgets('skipping the last optional item submits its explicit status', (
    tester,
  ) async {
    DQuestionnaireSnapshot? submitted;
    await tester.pumpWidget(
      app(
        DQuestionnaire(
          items: [item('optional', required: false)],
          onSubmit: (answers) => submitted = answers,
        ),
      ),
    );
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(submitted?.answerFor('optional').isSkipped, isTrue);
  });

  testWidgets('conditional item and controlled rejection remain truthful', (
    tester,
  ) async {
    var accept = false;
    final controller = DQuestionnaireController(
      items: [
        item('runtime', choices: [choice('local'), choice('cloud')]),
        item(
          'region',
          enabledWhen: (state) => state.valueFor<String>('runtime') == 'cloud',
        ),
        item('end'),
      ],
    );
    await tester.pumpWidget(
      app(
        DQuestionnaire(
          items: controller.items,
          controller: controller,
          onCurrentItemChanged: (_) => accept,
        ),
      ),
    );

    expect(find.text('Question 1 of 2'), findsOneWidget);
    await tester.tap(find.text('cloud'));
    await tester.pump();
    expect(find.text('Question 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Question runtime'), findsOneWidget);
    accept = true;
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Question region'), findsOneWidget);
  });

  testWidgets('narrow 200 percent RTL reduced-motion layout stays usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        DQuestionnaire(
          animateItems: true,
          shortcuts: DQuestionnaireShortcutMode.numbers,
          items: [
            item(
              'one',
              required: false,
              choices: [
                choice(
                  'A deliberately long wrapping answer',
                  description: 'Supporting detail also remains readable.',
                ),
                choice('Another answer'),
              ],
            ),
            item('two'),
          ],
        ),
        size: const Size(280, 700),
        textScale: 2,
        direction: TextDirection.rtl,
        reduceMotion: true,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Previous'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('choice semantics expose group selection and invalid errors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(app(DQuestionnaire(items: [item('one')])));
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(
      tester.getSemantics(find.text('A').first),
      matchesSemantics(
        hasCheckedState: true,
        isChecked: false,
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        label: 'A',
      ),
    );
    expect(find.text('Choose an answer to continue.'), findsOneWidget);
    handle.dispose();
  });
}
