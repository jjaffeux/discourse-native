import 'dart:async';

import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:flutter/widgets.dart' show TextEditingValue, TextSelection;
import 'package:flutter_test/flutter_test.dart';

ComposerSuggestion user(String username) => ComposerSuggestion(
  kind: ComposerTriggerKind.mention,
  value: username,
  label: username,
);

ComposerSuggestion emoji(String name) => ComposerSuggestion(
  kind: ComposerTriggerKind.emoji,
  value: name,
  label: name,
);

/// A category or tag, keyed by the ref the site would have us write.
ComposerSuggestion place(String ref) => ComposerSuggestion(
  kind: ComposerTriggerKind.hashtag,
  value: ref,
  label: ref,
);

TextEditingValue typed(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  late List<String> asked;
  late List<String> askedHashtags;
  late ComposerAutocomplete popup;
  Completer<void>? gate;
  Completer<void>? hashtagGate;
  Map<String, List<ComposerSuggestion>> people = {};
  Map<String, List<ComposerSuggestion>> places = {};

  ComposerAutocomplete open() {
    asked = [];
    askedHashtags = [];
    return popup = ComposerAutocomplete(
      search: (
        users: (term) async {
          asked.add(term);
          if (gate != null) await gate!.future;
          return people[term] ?? const [];
        },
        hashtags: (term) async {
          askedHashtags.add(term);
          if (hashtagGate != null) await hashtagGate!.future;
          return places[term] ?? const [];
        },
        emojis: (query) async => [
          for (final name in const ['smile', 'smirk', 'sad'])
            if (name.startsWith(query)) emoji(name),
        ],
      ),
    );
  }

  setUp(() {
    gate = null;
    hashtagGate = null;
    people = {
      'sa': [user('sam'), user('sally')],
      'sam': [user('sam')],
    };
    places = {
      'ran': [place('random'), place('random::tag')],
      'parent:ch': [place('parent:child')],
    };
    open();
  });

  tearDown(() => popup.dispose());

  group('emoji', () {
    testWidgets('loads emoji through the same race-safe async path', (
      tester,
    ) async {
      popup.update(typed('a :sm'));

      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      expect(popup.isOpen, isTrue);
      expect(popup.suggestions.map((s) => s.value), ['smile', 'smirk']);
    });

    test('stays shut on a colon that is only punctuation', () {
      popup.update(typed('Note: '));
      expect(popup.isOpen, isFalse);
    });

    testWidgets(
      'closes when nothing matches, rather than showing an empty box',
      (tester) async {
        popup.update(typed('a :zz'));
        await tester.pump(ComposerAutocomplete.debounce);
        await tester.pump();
        expect(popup.isOpen, isFalse);
      },
    );
  });

  group('mentions', () {
    testWidgets('waits out the debounce before asking', (tester) async {
      popup.update(typed('hey @sa'));
      expect(asked, isEmpty);

      await tester.pump(ComposerAutocomplete.debounce);
      expect(asked, ['sa']);
      expect(popup.suggestions.map((s) => s.value), ['sam', 'sally']);
    });

    testWidgets('collapses a burst of typing into one search', (tester) async {
      for (final text in ['hey @s', 'hey @sa', 'hey @sam']) {
        popup.update(typed(text));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(ComposerAutocomplete.debounce);

      // Three keystrokes, one request — and it is the one for what is on
      // screen now, not for what was there when the timer was first armed.
      expect(asked, ['sam']);
    });

    testWidgets('a pending mention cannot replace an emoji list', (
      tester,
    ) async {
      popup.update(typed('hey @sa'));
      await tester.pump(const Duration(milliseconds: 50));

      popup.update(typed('a :sm'));
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      expect(asked, isEmpty);
      expect(popup.suggestions.map((suggestion) => suggestion.value), [
        'smile',
        'smirk',
      ]);
    });

    testWidgets('bounds slow searches and retains only the newest query', (
      tester,
    ) async {
      gate = Completer<void>();

      for (final query in ['s', 'sa', 'sam', 'sally']) {
        popup.update(typed('hey @$query'));
        await tester.pump(ComposerAutocomplete.debounce);
      }

      expect(asked, ['s', 'sa']);

      gate!.complete();
      await tester.pump();

      expect(asked, ['s', 'sa', 'sally']);
      expect(asked, isNot(contains('sam')));
    });

    testWidgets('discards an answer the query has moved past', (tester) async {
      gate = Completer<void>();

      popup.update(typed('hey @sa'));
      await tester.pump(ComposerAutocomplete.debounce);
      expect(asked, ['sa']);

      // Kept typing while the first answer was still in flight.
      popup.update(typed('hey @sam'));
      await tester.pump(ComposerAutocomplete.debounce);

      gate!.complete();
      await tester.pump();

      expect(popup.suggestions.map((s) => s.value), ['sam']);
    });
  });

  group('hashtags', () {
    testWidgets('waits out the debounce before asking', (tester) async {
      popup.update(typed('see #ran'));
      expect(askedHashtags, isEmpty);

      await tester.pump(ComposerAutocomplete.debounce);
      expect(askedHashtags, ['ran']);
      expect(popup.suggestions.map((s) => s.value), ['random', 'random::tag']);
    });

    testWidgets('keeps searching past a subcategory colon', (tester) async {
      // The whole point of the second backward walk: the site is asked about
      // `parent:ch`, not about `ch`, which would find the wrong thing.
      popup.update(typed('see #parent:ch'));
      await tester.pump(ComposerAutocomplete.debounce);

      expect(askedHashtags, ['parent:ch']);
      expect(popup.suggestions.map((s) => s.value), ['parent:child']);
    });

    testWidgets('collapses a burst of typing into one search', (tester) async {
      for (final text in ['see #r', 'see #ra', 'see #ran']) {
        popup.update(typed(text));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(ComposerAutocomplete.debounce);

      expect(askedHashtags, ['ran']);
    });

    testWidgets('discards an answer the query has moved past', (tester) async {
      hashtagGate = Completer<void>();

      popup.update(typed('see #r'));
      await tester.pump(ComposerAutocomplete.debounce);
      popup.update(typed('see #ran'));
      await tester.pump(ComposerAutocomplete.debounce);

      hashtagGate!.complete();
      await tester.pump();

      expect(popup.suggestions.map((s) => s.value), ['random', 'random::tag']);
    });

    testWidgets('does not share a timer with a mention', (tester) async {
      // Two kinds down one debounced path, so this is worth saying out loud:
      // typing a hashtag must not cancel a mention search that is pending.
      popup.update(typed('hey @sa'));
      await tester.pump(ComposerAutocomplete.debounce);
      expect(asked, ['sa']);

      popup.update(typed('hey @sam and #ran'));
      await tester.pump(ComposerAutocomplete.debounce);

      expect(askedHashtags, ['ran']);
      expect(popup.suggestions.map((s) => s.value), ['random', 'random::tag']);
    });

    testWidgets('an emoji list landing does not blank the row', (tester) async {
      // `refresh()` re-runs the synchronous half. A hashtag's answer came
      // from the site and is not stale because a different list arrived.
      popup.update(typed('see #ran'));
      await tester.pump(ComposerAutocomplete.debounce);
      expect(popup.suggestions, hasLength(2));

      popup.refresh();

      expect(popup.suggestions, hasLength(2));
      expect(popup.isOpen, isTrue);
    });
  });

  group('the highlight', () {
    testWidgets('wraps around rather than stopping at the ends', (
      tester,
    ) async {
      popup.update(typed('a :sm'));
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(popup.selectedIndex, 0);

      popup.moveSelection(1);
      expect(popup.selected?.value, 'smirk');

      popup.moveSelection(1);
      expect(popup.selected?.value, 'smile');

      popup.moveSelection(-1);
      expect(popup.selected?.value, 'smirk');
    });

    test(
      'reports that there was nothing to move, so the key falls through',
      () {
        expect(popup.moveSelection(1), isFalse);
      },
    );

    testWidgets('a late key cannot move a disposed list', (tester) async {
      popup.update(typed('a :sm'));
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(popup.isOpen, isTrue);

      popup.dispose();

      expect(popup.moveSelection(1), isFalse);

      // The tearDown would otherwise dispose it twice.
      popup = open();
    });
  });

  group('dismissing', () {
    testWidgets('survives the next keystroke on the same run', (tester) async {
      popup.update(typed('a :sm'));
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      popup.dismiss();
      expect(popup.isOpen, isFalse);

      // Otherwise Escape reads as a key that does not work: the list would
      // close and the very next letter would put it straight back.
      popup.update(typed('a :smi'));
      expect(popup.isOpen, isFalse);
    });

    testWidgets('lets the next run open one', (tester) async {
      popup.update(typed('a :sm'));
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      popup.dismiss();

      popup.update(typed('a :sm and :sm'));
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(popup.isOpen, isTrue);
    });
  });

  testWidgets('a late answer does not wake a disposed composer', (
    tester,
  ) async {
    gate = Completer<void>();
    popup.update(typed('hey @sa'));
    await tester.pump(ComposerAutocomplete.debounce);

    popup.dispose();
    gate!.complete();
    await tester.pump();

    // Reaching a disposed ChangeNotifier throws, so getting here is the test.
    expect(popup.isOpen, isFalse);

    // The tearDown would otherwise dispose it twice.
    popup = open();
  });
}
