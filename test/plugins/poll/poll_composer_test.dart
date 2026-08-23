import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePollComposerBlocks', () {
    test('retains exact ranges, quoted attributes, order, and CRLF source', () {
      const source =
          'before\r\n\r\n'
          '[poll  future = "two words" name=team type=multiple min=1 max=2]\r\n'
          '# Lunch choice\r\n\r\n'
          '* Soup\r\n'
          '* Salad\r\n'
          '[/poll]\r\n\r\n'
          'after';

      final block = parsePollComposerBlocks(source).single;
      expect(block.start, source.indexOf('[poll'));
      expect(block.end, source.indexOf('\r\n\r\nafter'));
      expect(block.source, source.substring(block.start, block.end));
      expect(block.lineEnding, '\r\n');
      expect(block.name, 'team');
      expect(block.type, ComposerPollType.multiple);
      expect(block.titleSource, 'Lunch choice');
      expect(block.optionSources, ['Soup', 'Salad']);
      expect(block.attributes.map((attribute) => attribute.name), [
        'future',
        'name',
        'type',
        'min',
        'max',
      ]);
      expect(block.attribute('FUTURE'), 'two words');
      expect(block.attributes.first.raw, '  future = "two words"');
    });

    test('recognizes simple bullet variants and a number poll title', () {
      const source =
          '[poll]\n'
          '- One\n'
          '- Two\n'
          '[/poll]\n\n'
          '[poll type=number min=0 max=10 step=2]\n'
          '# Score\n'
          '[/poll]';
      final blocks = parsePollComposerBlocks(source);

      expect(blocks, hasLength(2));
      expect(blocks.first.type, ComposerPollType.regular);
      expect(blocks.first.optionSources, ['One', 'Two']);
      expect(blocks.last.type, ComposerPollType.number);
      expect(blocks.last.titleSource, 'Score');
      expect(blocks.last.optionSources, isEmpty);
    });

    test('accepts only the existing ASCII attribute-name grammar', () {
      const legal =
          '[poll _future-2=value Name9=value]\n'
          '* A\n'
          '* B\n'
          '[/poll]';
      final block = parsePollComposerBlocks(legal).single;
      expect(block.attributes.map((attribute) => attribute.name), [
        '_future-2',
        'Name9',
      ]);

      for (final name in ['9name', '-name', 'éname', 'naïve']) {
        final source = '[poll $name=value]\n* A\n* B\n[/poll]';
        expect(parsePollComposerBlocks(source), isEmpty, reason: name);
      }
    });

    test('leaves fenced, quoted, nested, malformed, and complex polls raw', () {
      const fenced = '```\n[poll]\n* A\n* B\n[/poll]\n```';
      const quoted = '> [poll]\n> * A\n> * B\n> [/poll]';
      const nested =
          '[poll]\n* A\n[poll name=poll2]\n* B\n* C\n[/poll]\n[/poll]';
      const duplicate = '[poll name=a NAME=b]\n* A\n* B\n[/poll]';
      const continuation = '[poll]\n* A\n  continued text\n* B\n[/poll]';
      const unknown = '[poll type=future_rank]\n* A\n* B\n[/poll]';

      for (final source in [
        fenced,
        quoted,
        nested,
        duplicate,
        continuation,
        unknown,
      ]) {
        expect(parsePollComposerBlocks(source), isEmpty, reason: source);
      }
    });

    test('an unmatched outer poll does not project an apparent inner poll', () {
      const source =
          '[poll]\n'
          'broken\n'
          '[poll name=poll2]\n'
          '* A\n'
          '* B\n'
          '[/poll]';
      expect(parsePollComposerBlocks(source), isEmpty);
    });
  });

  group('names', () {
    test('uses the lowest available name and reserves complex raw polls', () {
      const source =
          '[poll]\ncomplex body\n[/poll]\n'
          '[poll name=poll3]\n* A\n* B\n[/poll]\n'
          '[poll name="poll2"]\n* C\n* D\n[/poll]';
      expect(nextPollName(source), 'poll4');
    });

    test('does not reserve a poll opener inside fenced code', () {
      expect(nextPollName('```\n[poll]\n```'), 'poll');
    });
  });

  group('PollComposerDraft', () {
    test('an unchanged sheet returns every original code unit', () {
      const source =
          '[poll  future = "keep me" public = true name = lunch type=multiple max=2 min=1]\r\n'
          '#  Lunch  \r\n'
          '+ Soup  \r\n'
          '+ Salad\r\n'
          ' [/poll]';
      final block = parsePollComposerBlocks(source).single;
      final draft = PollComposerDraft.fromBlock(block);

      expect(draft.serialize(), source);
      expect(draft.copyWith(title: 'Lunch').serialize(), source);
    });

    test('an edit preserves unknown attributes, order, spelling, and quotes', () {
      const source =
          '[poll future = "keep me" public = "true" name=lunch type=multiple max=2 min=1]\r\n'
          '# Lunch\r\n'
          '* Soup\r\n'
          '* Salad\r\n'
          '[/poll]';
      final draft = PollComposerDraft.fromBlock(
        parsePollComposerBlocks(source).single,
      ).copyWith(publicVoters: false, title: 'Dinner');

      expect(
        draft.serialize(),
        '[poll future = "keep me" public = "false" name=lunch '
        'type=multiple max=2 min=1 results=always]\r\n'
        '# Dinner\r\n'
        '* Soup\r\n'
        '* Salad\r\n'
        '[/poll]',
      );
    });

    test('an edit retains whitespace around both source tags', () {
      const source =
          '[poll name=lunch   ]  \n'
          '* A\n'
          '* B\n'
          '[/poll]   ';
      final draft = PollComposerDraft.fromBlock(
        parsePollComposerBlocks(source).single,
      ).copyWith(title: 'Question');

      expect(
        draft.serialize(),
        '[poll name=lunch type=regular results=always public=false   ]  \n'
        '# Question\n'
        '* A\n'
        '* B\n'
        '[/poll]   ',
      );
    });

    test('new polls carry the native defaults', () {
      final draft = PollComposerDraft.newPoll(
        name: 'poll2',
        defaultPublic: true,
      ).copyWith(options: ['Soup', 'Salad'], title: 'Lunch');

      expect(
        draft.serialize(),
        '[poll name=poll2 type=regular status=open results=always '
        'public=true chartType=bar]\n'
        '# Lunch\n'
        '* Soup\n'
        '* Salad\n'
        '[/poll]',
      );
    });

    test('quotes a close timestamp that contains markup whitespace', () {
      final draft = PollComposerDraft.newPoll(
        name: 'poll',
        defaultPublic: true,
      ).copyWith(options: ['Soup', 'Salad'], close: '2026-08-30 18:00:00Z');

      expect(draft.serialize(), contains('close="2026-08-30 18:00:00Z"'));
      expect(parsePollComposerBlocks(draft.serialize()), hasLength(1));
    });

    test('preserves original whitespace inside an unchanged close value', () {
      const source =
          '[poll close=" 2026-08-30T18:00:00Z "]\n'
          '* Soup\n'
          '* Salad\n'
          '[/poll]';
      final draft = PollComposerDraft.fromBlock(
        parsePollComposerBlocks(source).single,
      ).copyWith(title: 'Lunch');

      expect(draft.serialize(), contains('close=" 2026-08-30T18:00:00Z "'));
    });

    test('validates options using exact trimmed source values', () {
      final base = PollComposerDraft.newPoll(name: 'poll', defaultPublic: true);
      expect(
        base
            .copyWith(options: ['Same', 'Same '])
            .validate(maximumOptions: 20, isStaff: false)
            .firstError,
        'Poll options must be unique.',
      );
      expect(
        base
            .copyWith(options: ['A', ' '])
            .validate(maximumOptions: 20, isStaff: false)
            .firstError,
        'Every option needs text.',
      );
    });

    test('validates multiple choice bounds', () {
      final draft =
          PollComposerDraft.newPoll(
            name: 'poll',
            defaultPublic: false,
          ).copyWith(
            type: ComposerPollType.multiple,
            options: ['A', 'B', 'C'],
            minimum: 3,
            maximum: 3,
          );
      expect(
        draft.validate(maximumOptions: 20, isStaff: false).errors,
        contains(startsWith('Multiple choice requires')),
      );
    });

    test('validates number bounds and generated option limit', () {
      final base = PollComposerDraft.newPoll(
        name: 'poll',
        defaultPublic: false,
      ).copyWith(type: ComposerPollType.number);
      expect(
        base
            .copyWith(minimum: 0, maximum: 100, step: 1)
            .validate(maximumOptions: 20, isStaff: false)
            .errors,
        contains('A poll can have at most 20 generated options.'),
      );
      expect(
        base
            .copyWith(minimum: 2, maximum: 2, step: 1)
            .validate(maximumOptions: 20, isStaff: false)
            .errors,
        contains('A number poll must generate at least two options.'),
      );
    });

    test('staff-only cannot be newly selected by a non-staff reader', () {
      final draft = PollComposerDraft.newPoll(
        name: 'poll',
        defaultPublic: false,
      ).copyWith(options: ['A', 'B'], results: PollResultMode.staffOnly);
      expect(
        draft.validate(maximumOptions: 20, isStaff: false).errors,
        contains('Only staff can make poll results staff-only.'),
      );
    });

    test('an existing staff-only value is retained for non-staff', () {
      const source = '[poll results=staff_only]\n* A\n* B\n[/poll]';
      final draft = PollComposerDraft.fromBlock(
        parsePollComposerBlocks(source).single,
      ).copyWith(title: 'Question');
      expect(
        draft.validate(maximumOptions: 20, isStaff: false).isValid,
        isTrue,
      );
      expect(draft.serialize(), contains('results=staff_only'));
    });
  });

  group('verified source mutations', () {
    const poll = '[poll]\n* A\n* B\n[/poll]';

    test('inserts with safe blank-line separation and places the caret', () {
      const source = 'before\nafter';
      final result = insertVerifiedPoll(
        current: const TextEditingValue(text: source),
        expectedDocument: source,
        expectedSelection: const TextSelection.collapsed(offset: 7),
        markup: poll,
      );

      expect(result.applied, isTrue);
      expect(result.value.text, 'before\n\n$poll\n\nafter');
      expect(result.value.selection.extentOffset, 9 + poll.length);
      expect(
        result.value.text.replaceRange(
          result.value.selection.start,
          result.value.selection.end,
          'next',
        ),
        'before\n\n$poll\nnext\nafter',
      );
    });

    test(
      'an end insertion owns a following line and leaves the caret on it',
      () {
        final result = insertVerifiedPoll(
          current: TextEditingValue.empty,
          expectedDocument: '',
          expectedSelection: const TextSelection.collapsed(offset: 0),
          markup: poll,
        );

        expect(result.applied, isTrue);
        expect(result.value.text, '$poll\n');
        expect(
          result.value.selection,
          const TextSelection.collapsed(offset: poll.length + 1),
        );

        final typed = result.value.text.replaceRange(
          result.value.selection.start,
          result.value.selection.end,
          'next',
        );
        expect(typed, '$poll\nnext');
        expect(parsePollComposerBlocks(typed), hasLength(1));
      },
    );

    test('the following caret consumes one complete CRLF', () {
      const source = 'before\r\nafter';
      final result = insertVerifiedPoll(
        current: const TextEditingValue(text: source),
        expectedDocument: source,
        expectedSelection: const TextSelection.collapsed(offset: 8),
        markup: poll,
      );

      expect(result.value.text, 'before\r\n\r\n$poll\r\n\r\nafter');
      expect(result.value.selection.extentOffset, 12 + poll.length);
    });

    test('replaces and removes exactly one verified source range', () {
      const source = 'before\n\n$poll\n\nafter';
      final block = parsePollComposerBlocks(source).single;
      final replaced = replaceVerifiedPoll(
        current: const TextEditingValue(text: source),
        expectedDocument: source,
        expectedBlock: block,
        replacement: '[poll type=number min=0 max=1]\n[/poll]',
      );
      expect(
        replaced.value.text,
        'before\n\n[poll type=number min=0 max=1]\n[/poll]\n\nafter',
      );
      expect(
        replaced.value.selection.extentOffset,
        'before\n\n[poll type=number min=0 max=1]\n[/poll]\n'.length,
      );

      final removed = removeVerifiedPoll(
        current: const TextEditingValue(text: source),
        expectedDocument: source,
        expectedBlock: block,
      );
      expect(removed.value.text, 'before\n\n\n\nafter');
    });

    test('editing an EOF poll keeps a real following caret line', () {
      final block = parsePollComposerBlocks(poll).single;
      const replacement = '[poll]\n* One\n* Two\n[/poll]';
      final result = replaceVerifiedPoll(
        current: const TextEditingValue(text: poll),
        expectedDocument: poll,
        expectedBlock: block,
        replacement: replacement,
      );

      expect(result.value.text, '$replacement\n');
      expect(
        result.value.selection,
        const TextSelection.collapsed(offset: replacement.length + 1),
      );
    });

    test('a changed document safely refuses to apply', () {
      const source = 'before\n\n$poll';
      final block = parsePollComposerBlocks(source).single;
      const current = TextEditingValue(text: 'changed\n\n$poll');

      final result = replaceVerifiedPoll(
        current: current,
        expectedDocument: source,
        expectedBlock: block,
        replacement: 'anything',
      );
      expect(result.applied, isFalse);
      expect(result.value, current);
      expect(result.message, contains('Nothing was changed'));
    });
  });

  group('leading boundary input', () {
    const formatter = PollComposerInputFormatter();
    const poll = '[poll]\n* A\n* B\n[/poll]';

    test('keeps typed and pasted text on a preceding line', () {
      for (final inserted in ['x', '[', ' ', 'pasted text']) {
        const old = TextEditingValue(
          text: poll,
          selection: TextSelection.collapsed(offset: 0),
        );
        final result = formatter.formatEditUpdate(
          old,
          TextEditingValue(
            text: '$inserted$poll',
            selection: TextSelection.collapsed(offset: inserted.length),
          ),
        );

        expect(result.text, '$inserted\n$poll');
        expect(result.selection.extentOffset, inserted.length);
        expect(parsePollComposerBlocks(result.text), hasLength(1));
      }
    });

    test('adds a new separator even when another line precedes the poll', () {
      const source = 'intro\n$poll';
      final block = parsePollComposerBlocks(source).single;
      final result = formatter.formatEditUpdate(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: block.start),
        ),
        TextEditingValue(
          text: source.replaceRange(block.start, block.start, 'x'),
          selection: TextSelection.collapsed(offset: block.start + 1),
        ),
      );

      expect(result.text, 'intro\nx\n$poll');
      expect(result.selection.extentOffset, 'intro\nx'.length);
    });

    test('handles inserted text matching an indented poll prefix', () {
      const indentedPoll = ' [poll]\n* A\n* B\n [/poll]';
      const old = TextEditingValue(
        text: indentedPoll,
        selection: TextSelection.collapsed(offset: 0),
      );
      final result = formatter.formatEditUpdate(
        old,
        const TextEditingValue(
          text: '  [poll]\n* A\n* B\n [/poll]',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );

      expect(result.text, ' \n$indentedPoll');
      expect(result.selection.extentOffset, 1);
      expect(parsePollComposerBlocks(result.text), hasLength(1));
    });

    test('uses the poll CRLF and leaves the caret before both code units', () {
      const crlfPoll = '[poll]\r\n* A\r\n* B\r\n[/poll]';
      const source = 'intro\r\n$crlfPoll';
      final block = parsePollComposerBlocks(source).single;
      final result = formatter.formatEditUpdate(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: block.start),
        ),
        TextEditingValue(
          text: source.replaceRange(block.start, block.start, 'x'),
          selection: TextSelection.collapsed(offset: block.start + 1),
        ),
      );

      expect(result.text, 'intro\r\nx\r\n$crlfPoll');
      expect(result.selection.extentOffset, 'intro\r\nx'.length);
    });

    test('reuses a pasted line ending without adding another', () {
      for (final inserted in ['pasted\n', 'pasted\r\n']) {
        const old = TextEditingValue(
          text: poll,
          selection: TextSelection.collapsed(offset: 0),
        );
        final result = formatter.formatEditUpdate(
          old,
          TextEditingValue(
            text: '$inserted$poll',
            selection: TextSelection.collapsed(offset: inserted.length),
          ),
        );

        expect(result.text, '$inserted$poll');
        expect(
          result.selection.extentOffset,
          inserted.length - (inserted.endsWith('\r\n') ? 2 : 1),
        );
      }
    });

    test(
      'preserves the first IME composition without adding another break',
      () {
        const old = TextEditingValue(
          text: poll,
          selection: TextSelection.collapsed(offset: 0),
        );
        final first = formatter.formatEditUpdate(
          old,
          const TextEditingValue(
            text: 'k$poll',
            selection: TextSelection.collapsed(offset: 1),
            composing: TextRange(start: 0, end: 1),
          ),
        );
        final composed = formatter.formatEditUpdate(
          first,
          const TextEditingValue(
            text: 'か\n$poll',
            selection: TextSelection.collapsed(offset: 1),
            composing: TextRange(start: 0, end: 1),
          ),
        );

        expect(first.text, 'k\n$poll');
        expect(first.composing, const TextRange(start: 0, end: 1));
        expect(composed.text, 'か\n$poll');
        expect(composed.composing, const TextRange(start: 0, end: 1));
      },
    );

    test('keeps replacement text ending at the poll on a separate line', () {
      const source = '\n$poll';
      const old = TextEditingValue(
        text: source,
        selection: TextSelection(baseOffset: 0, extentOffset: 1),
      );
      final result = formatter.formatEditUpdate(
        old,
        const TextEditingValue(
          text: '\n[$poll',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(result.text, '\n[\n$poll');
      expect(result.selection.extentOffset, 2);
      expect(parsePollComposerBlocks(result.text), hasLength(1));
    });
  });
}
