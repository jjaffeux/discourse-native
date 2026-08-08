import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('serializes draft saves and keeps only the newest queued text', (
    tester,
  ) async {
    final gates = [Completer<void>(), Completer<void>()];
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        final index = saves.length;
        saves.add(save);
        await gates[index].future;
        return save.sequence + 1;
      },
    )..draftSequence = 4;

    composer.text.text = 'first';
    await tester.pump(ComposerController.draftDebounce);
    expect(saves.map((save) => save.draft.reply), ['first']);

    composer.text.text = 'second';
    await tester.pump(ComposerController.draftDebounce);
    composer.text.text = 'latest';
    await tester.pump(ComposerController.draftDebounce);

    expect(saves, hasLength(1));
    expect(saves.single.isCurrent(), isFalse);

    gates.first.complete();
    await tester.pump();

    expect(saves.map((save) => save.draft.reply), ['first', 'latest']);
    expect(saves.last.sequence, 5);
    expect(saves.last.isCurrent(), isTrue);

    gates.last.complete();
    await tester.pump();
    expect(composer.draftSequence, 6);

    composer.dispose();
  });

  testWidgets('flushes debounced text before submission continues', (
    tester,
  ) async {
    final gate = Completer<void>();
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        await gate.future;
        return 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'not debounced yet';
    final finishing = composer.finishDraftSaves();
    await tester.pump();

    expect(saves.map((save) => save.draft.reply), ['not debounced yet']);

    gate.complete();
    await finishing;
    expect(composer.draftPending, isFalse);
  });

  testWidgets('a failed autocomplete search closes stale suggestions', (
    tester,
  ) async {
    final composer = ComposerController(
      _target,
      search: (
        users: (query) async {
          if (query == 'sa') {
            return const [
              ComposerSuggestion(
                kind: ComposerTriggerKind.mention,
                value: 'sam',
                label: 'Sam',
              ),
            ];
          }
          throw StateError('search failed');
        },
        hashtags: (_) async => const [],
        emojis: (_) => const [],
      ),
    );
    addTearDown(composer.dispose);

    composer.text.value = _typed('hello @sa');
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();
    expect(composer.autocomplete.suggestions.single.label, 'Sam');

    composer.text.value = _typed('hello @sam');
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();

    expect(composer.autocomplete.suggestions, isEmpty);
    expect(composer.autocomplete.isOpen, isFalse);
  });

  test('restoring a draft does not count idle time as typing', () {
    var now = DateTime.utc(2026, 8, 8, 12);
    final composer = ComposerController(_target, now: () => now);
    addTearDown(composer.dispose);

    composer.restore(const ComposerDraft(reply: 'restored'));
    now = now.add(const Duration(seconds: 4));
    composer.text.text = 'restored once';

    expect(composer.typingDuration, Duration.zero);

    now = now.add(const Duration(seconds: 1));
    composer.text.text = 'restored twice';
    expect(composer.typingDuration, const Duration(seconds: 1));
  });

  testWidgets('clearing an enqueued reply does not save an empty draft', (
    tester,
  ) async {
    final saves = <ComposerDraftSave>[];
    final composer = ComposerController(
      _target,
      onSaveDraft: (save) async {
        saves.add(save);
        return 1;
      },
    );
    addTearDown(composer.dispose);

    composer.text.text = 'accepted for review';
    composer.enqueued(null);

    expect(composer.text.text, isEmpty);
    expect(composer.draftPending, isFalse);
    await tester.pump(ComposerController.draftDebounce);
    expect(saves, isEmpty);
  });

  test('an enqueued reply starts fresh timing for the new document', () {
    var now = DateTime.utc(2026, 8, 8, 12);
    final composer = ComposerController(_target, now: () => now);
    addTearDown(composer.dispose);

    composer.text.text = 'first';
    now = now.add(const Duration(seconds: 2));
    composer.text.text = 'first reply';
    expect(composer.typingDuration, const Duration(seconds: 2));
    expect(composer.openDuration, const Duration(seconds: 2));

    now = now.add(const Duration(seconds: 3));
    composer.enqueued(null);

    expect(composer.typingDuration, Duration.zero);
    expect(composer.openDuration, Duration.zero);
  });

  testWidgets('an enqueued reply retries draft sync as a new document', (
    tester,
  ) async {
    var saveAttempts = 0;
    final composer = ComposerController(
      _target,
      onSaveDraft: (_) async {
        saveAttempts++;
        throw const WriteException(WriteFailure.unreachable);
      },
    );
    addTearDown(composer.dispose);

    for (
      var attempt = 0;
      attempt < ComposerController.maxDraftFailures;
      attempt++
    ) {
      composer.text.text = 'reply $attempt';
      await composer.flushDraft();
    }
    expect(composer.draftsGaveUp, isTrue);

    composer.enqueued(null);
    expect(composer.draftsGaveUp, isFalse);

    composer.text.text = 'new reply';
    await composer.flushDraft();
    expect(saveAttempts, ComposerController.maxDraftFailures + 1);
  });
}

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

TextEditingValue _typed(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);
