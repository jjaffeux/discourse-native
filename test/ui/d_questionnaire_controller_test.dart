import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DQuestionnaireChoice<Object> choice(String value, {bool enabled = true}) =>
      DQuestionnaireChoice<Object>(
        value: value,
        label: Text(value),
        enabled: enabled,
      );

  DQuestionnaireItem item(
    String id, {
    bool required = true,
    bool multiple = false,
    List<DQuestionnaireChoice<Object>>? choices,
    DQuestionnaireInputConfiguration? input,
    DQuestionnaireEnabledPredicate? enabledWhen,
    DQuestionnaireValidator? validator,
  }) => DQuestionnaireItem(
    id: id,
    title: Text(id),
    required: required,
    multiple: multiple,
    choices: choices ?? [choice('a'), choice('b')],
    input: input,
    enabledWhen: enabledWhen,
    validator: validator,
  );

  group('DQuestionnaireController answers', () {
    test('keeps single, multiple, freeform, empty and skipped distinct', () {
      final controller = DQuestionnaireController(
        items: [
          item('single'),
          item('multiple', multiple: true),
          item(
            'freeform',
            input: const DQuestionnaireInputConfiguration(label: 'Other'),
          ),
          item('optional', required: false),
        ],
      );

      controller.setSingle('single', 'a');
      controller.toggle('multiple', 'a');
      controller.toggle('multiple', 'b');
      controller.setFreeform('freeform', 'A specific answer');
      controller.setSingle('freeform', 'b');
      controller.setFreeform('freeform', 'Another answer');

      expect(controller.answerFor('single').valueAs<String>(), 'a');
      expect(controller.answerFor('multiple').valuesAs<String>(), ['a', 'b']);
      expect(controller.answerFor('freeform').values, isEmpty);
      expect(
        controller.answerFor('freeform').valueAs<String>(),
        'Another answer',
      );
      expect(controller.answerFor('optional').isEmpty, isTrue);
    });

    test(
      'optional unanswered requires explicit skip; required cannot skip',
      () async {
        final optional = DQuestionnaireController(
          items: [item('optional', required: false), item('end')],
        );

        expect(await optional.next(), isFalse);
        expect(optional.errorFor('optional'), contains('skip'));
        expect(await optional.skip(), isTrue);
        expect(optional.answerFor('optional').isSkipped, isTrue);
        expect(optional.currentItemId, 'end');

        final required = DQuestionnaireController(items: [item('required')]);
        expect(await required.skip(), isFalse);
        expect(required.answerFor('required').isEmpty, isTrue);
      },
    );

    test(
      'disabled fixed answers do not satisfy validation or submit',
      () async {
        final controller = DQuestionnaireController(
          items: [
            item(
              'scope',
              choices: [choice('disabled', enabled: false), choice('enabled')],
            ),
          ],
          initialState: DQuestionnaireSavedState(
            currentItemId: 'scope',
            answers: {
              'scope': DQuestionnaireAnswer.fixed(const ['disabled']),
            },
          ),
        );

        expect(await controller.validate('scope'), isFalse);
        expect(controller.submission.answers, isEmpty);
        controller.setSingle('scope', 'disabled');
        expect(controller.answerFor('scope').values, ['disabled']);
        controller.setSingle('scope', 'enabled');
        expect(await controller.validate('scope'), isTrue);
      },
    );
  });

  group('navigation and conditional items', () {
    test(
      'excludes hidden items and restores retained answers when enabled',
      () async {
        final controller = DQuestionnaireController(
          items: [
            item('runtime', choices: [choice('local'), choice('cloud')]),
            item(
              'region',
              enabledWhen: (state) =>
                  state.valueFor<String>('runtime') == 'cloud',
            ),
            item('approval'),
          ],
        );

        expect(controller.progress.total, 2);
        controller.setSingle('runtime', 'cloud');
        expect(controller.progress.total, 3);
        expect(await controller.next(), isTrue);
        controller.setSingle('region', 'a');
        expect(await controller.next(), isTrue);
        expect(controller.currentItemId, 'approval');

        controller.setSingle('runtime', 'local');
        expect(controller.visibleItems.map((value) => value.id), [
          'runtime',
          'approval',
        ]);
        expect(controller.submission.answers.containsKey('region'), isFalse);
        controller.setSingle('runtime', 'cloud');
        expect(controller.answerFor('region').valueAs<String>(), 'a');
      },
    );

    test(
      'previous never validates and submit returns to first invalid item',
      () async {
        final controller = DQuestionnaireController(
          items: [item('one'), item('two')],
        );
        controller.setSingle('one', 'a');
        expect(await controller.next(), isTrue);
        expect(await controller.previous(), isTrue);
        expect(controller.errorFor('two'), isNull);
        await controller.goTo('two');
        expect(await controller.validateForSubmission(), isNull);
        expect(controller.currentItemId, 'two');
        expect(controller.errorFor('two'), isNotNull);
      },
    );

    test(
      'navigation delegate explicitly accepts or rejects transitions',
      () async {
        var accept = false;
        final requests = <String>[];
        final controller = DQuestionnaireController(
          items: [item('one'), item('two')],
          navigationDelegate: (from, to, reason) {
            requests.add('$from->$to:${reason.name}');
            return accept;
          },
        );
        controller.setSingle('one', 'a');

        expect(await controller.next(), isFalse);
        expect(controller.currentItemId, 'one');
        accept = true;
        expect(await controller.next(), isTrue);
        expect(controller.currentItemId, 'two');
        expect(requests, ['one->two:next', 'one->two:next']);
      },
    );
  });

  group('resume and validation lifecycle', () {
    test(
      'saved state round-trips and reset restores the resumed draft',
      () async {
        final saved = DQuestionnaireSavedState(
          currentItemId: 'two',
          answers: {
            'one': DQuestionnaireAnswer.fixed(const ['a']),
            'two': DQuestionnaireAnswer.freeform('Saved note'),
            'three': const DQuestionnaireAnswer.skipped(),
          },
          visitedItemIds: const {'one', 'two'},
        );
        final json = saved.toJson();
        final restored = DQuestionnaireSavedState.fromJson(json);
        final controller = DQuestionnaireController(
          items: [
            item('one'),
            item(
              'two',
              input: const DQuestionnaireInputConfiguration(label: 'Note'),
            ),
            item('three', required: false),
          ],
          initialState: restored,
        );

        controller.setFreeform('two', 'Changed');
        await controller.goTo('three');
        controller.reset();

        expect(controller.currentItemId, 'two');
        expect(controller.answerFor('one').valueAs<String>(), 'a');
        expect(controller.answerFor('two').freeform, 'Saved note');
        expect(controller.answerFor('three').isSkipped, isTrue);
        expect(controller.visitedItemIds, containsAll(['one', 'two']));
      },
    );

    test(
      'input initial value is an answer and resets without host storage',
      () {
        final controller = DQuestionnaireController(
          items: [
            item(
              'note',
              input: const DQuestionnaireInputConfiguration(
                label: 'Note',
                initialValue: 'Initial note',
              ),
            ),
          ],
        );
        expect(controller.answerFor('note').freeform, 'Initial note');
        controller.setFreeform('note', 'Changed note');
        controller.reset();
        expect(controller.answerFor('note').freeform, 'Initial note');
      },
    );

    test('changing an answer cancels stale async validation', () async {
      final validation = Completer<String?>();
      var calls = 0;
      final controller = DQuestionnaireController(
        items: [
          item(
            'one',
            validator: (answer, state) {
              calls++;
              return validation.future;
            },
          ),
          item('two'),
        ],
      );
      controller.setSingle('one', 'a');
      final navigation = controller.next();
      expect(controller.isValidating, isTrue);
      controller.setSingle('one', 'b');
      expect(controller.isValidating, isFalse);
      validation.complete('Stale error');

      expect(await navigation, isFalse);
      expect(controller.currentItemId, 'one');
      expect(controller.errorFor('one'), isNull);
      expect(calls, 1);
    });

    test('custom and external errors block submission until cleared', () async {
      final controller = DQuestionnaireController(
        items: [
          item(
            'one',
            validator: (answer, state) =>
                answer.valueAs<String>() == 'a' ? 'Choose B.' : null,
          ),
        ],
      );
      controller.setSingle('one', 'a');
      expect(await controller.validateForSubmission(), isNull);
      expect(controller.errorFor('one'), 'Choose B.');
      controller.setSingle('one', 'b');
      controller.setExternalError('one', 'Host rejected this answer.');
      expect(await controller.validateForSubmission(), isNull);
      controller.setExternalError('one', null);
      expect(await controller.validateForSubmission(), isNotNull);
    });
  });
}
