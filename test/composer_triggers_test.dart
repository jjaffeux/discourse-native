import 'package:discourse_native/src/shell/composer_triggers.dart';
import 'package:flutter/widgets.dart' show TextEditingValue, TextSelection;
import 'package:flutter_test/flutter_test.dart';

/// A composer where `|` is the caret, so a case reads as what someone has
/// typed rather than as a string and an offset that have to be checked against
/// each other.
TextEditingValue typed(String annotated) {
  final caret = annotated.indexOf('|');
  final text = annotated.replaceFirst('|', '');
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// The trigger as `@query` or `:query`, or `-` for none — short enough to put
/// a table of cases in one place.
String triggerIn(String annotated) {
  final trigger = composerTriggerAt(typed(annotated));
  return trigger == null ? '-' : '${trigger.kind.sigil}${trigger.query}';
}

void main() {
  group('composerTriggerAt', () {
    test('opens once enough has been typed', () {
      expect(triggerIn('hey @s|'), '@s');
      expect(triggerIn('hey @sam|'), '@sam');
      expect(triggerIn('a :sm|'), ':sm');
    });

    test('waits for a second character before searching for an emoji', () {
      // A lone colon is punctuation. Every "Note: " in a reply would otherwise
      // open a list over the post being written.
      expect(triggerIn('Note:|'), '-');
      expect(triggerIn('Note: |'), '-');
      expect(triggerIn('a :s|'), '-');
    });

    test('opens on the first character of a mention', () {
      expect(triggerIn('@|'), '-');
      expect(triggerIn('@j|'), '@j');
    });

    test('is not an email address', () {
      expect(triggerIn('joffrey@example|'), '-');
      expect(triggerIn('write to me@discourse|'), '-');
    });

    test('does not reopen on a shortcode that is already finished', () {
      // The closing colon is preceded by a letter, so it does not start a word.
      expect(triggerIn('a :smile:|'), '-');
      expect(triggerIn('a :smile: |'), '-');
    });

    test('opens after the punctuation an aside starts with', () {
      expect(triggerIn('(@sa|'), '@sa');
      expect(triggerIn('"@sa|'), '@sa');
    });

    test('needs the caret at the end of the run', () {
      // Clicking back into a name already written is reading, not composing.
      expect(triggerIn('hey @s|am and'), '-');
      expect(triggerIn('hey @sam| and'), '@sam');
    });

    test('closes once the run is over', () {
      expect(triggerIn('hey @sam |'), '-');
      expect(triggerIn('hey @sam there|'), '-');
    });

    test('ignores a selection, which is not somebody typing', () {
      const value = TextEditingValue(
        text: 'hey @sam',
        selection: TextSelection(baseOffset: 4, extentOffset: 8),
      );
      expect(composerTriggerAt(value), isNull);
    });

    test('gives up on a run no username could be', () {
      final max = ComposerTriggerKind.mention.maximum;
      expect(triggerIn('@${'x' * (max + 1)}|'), '-');
      expect(triggerIn('@${'x' * max}|'), '@${'x' * max}');
    });

    test('opens on a hashtag', () {
      expect(triggerIn('see #|'), '-');
      expect(triggerIn('see #r|'), '#r');
      expect(triggerIn('see #random|'), '#random');
    });

    test('keeps going past the colon of a subcategory', () {
      // The walk stops at a colon, which leaves `#parent:child` looking like
      // an emoji called `child`. It is not, and the ref is what the site
      // cooks against — so a second walk goes looking for the `#`.
      expect(triggerIn('see #parent:|'), '#parent:');
      expect(triggerIn('see #parent:ch|'), '#parent:ch');
      expect(triggerIn('see #name::tag|'), '#name::tag');
      expect(triggerIn('see #a:b:c|'), '#a:b:c');
    });

    test('a shortcode is still a shortcode', () {
      // The rule above must not reach past anything that is not a hashtag.
      expect(triggerIn('a :sm|'), ':sm');
      expect(triggerIn('a :smile:|'), '-');
      expect(triggerIn('a :smile::sm|'), '-');
      expect(triggerIn('at 10:30|'), '-');
      expect(triggerIn('https://a.b|'), '-');
      expect(triggerIn('Note:|'), '-');
    });

    test('a hash inside a word is not a hashtag', () {
      expect(triggerIn('a#b|'), '-');
      expect(triggerIn('##foo|'), '-');
      expect(triggerIn('see /c/x#y|'), '-');
    });

    test('opens after aside punctuation, like the others', () {
      expect(triggerIn('(#su|'), '#su');
    });

    test('gives up on a run no hashtag could be', () {
      final max = ComposerTriggerKind.hashtag.maximum;
      expect(triggerIn('#${'x' * (max + 1)}|'), '-');
      expect(triggerIn('#${'x' * max}|'), '#${'x' * max}');
    });

    test('reports the range a completion would replace', () {
      final trigger = composerTriggerAt(typed('hey @sam|'))!;
      expect(trigger.start, 4);
      expect(trigger.end, 8);
      expect(trigger.kind, ComposerTriggerKind.mention);
    });

    test('a colon inside a word is not a shortcode', () {
      expect(triggerIn('at 10:30|'), '-');
      expect(triggerIn('https://a.b|'), '-');
    });
  });

  group('applyComposerCompletion', () {
    String accept(String annotated, String replacement) {
      final value = typed(annotated);
      final result = applyComposerCompletion(
        value,
        composerTriggerAt(value)!,
        replacement,
      );
      return result.text.replaceRange(
        result.selection.baseOffset,
        result.selection.baseOffset,
        '|',
      );
    }

    test('writes the whole thing, sigils and all', () {
      expect(accept('hey @sa|', 'sam'), 'hey @sam |');
      expect(accept('a :sm|', 'smile'), 'a :smile: |');
      expect(accept('see #ra|', 'random'), 'see #random |');
    });

    test('writes the ref a hashtag was offered under, not its slug', () {
      // `random::tag` and `parent:child` are what the site resolves; the slug
      // alone finds the wrong thing, or nothing.
      expect(accept('see #ra|', 'random::tag'), 'see #random::tag |');
      expect(accept('see #ch|', 'parent:child'), 'see #parent:child |');
    });

    test('what it writes for a hashtag no longer triggers either', () {
      final value = typed('see #ra|');
      final done = applyComposerCompletion(
        value,
        composerTriggerAt(value)!,
        'random::tag',
      );
      expect(composerTriggerAt(done), isNull);
    });

    test('leaves the caret past the space, ready to keep typing', () {
      expect(accept('@sa|', 'sam'), '@sam |');
    });

    test('does not add a second space to one already there', () {
      expect(accept('hey @sa| there', 'sam'), 'hey @sam |there');
    });

    test('what it writes no longer triggers', () {
      final value = typed('a :sm|');
      final done = applyComposerCompletion(
        value,
        composerTriggerAt(value)!,
        'smile',
      );
      // Otherwise accepting one suggestion opens the list again on the result.
      expect(composerTriggerAt(done), isNull);
    });
  });
}
