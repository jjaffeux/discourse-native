import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
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

    test('code and comment examples neither project nor reserve names', () {
      const poll = '[poll]\n* A\n* B\n[/poll]';
      for (final (before, after) in const [
        ('[code]', '[/code]'),
        ('[CoDe]', '[/CODE]'),
        ('[code=js]', '[/code]'),
        ('[code language=js]', '[/code]'),
        ('[code lang="a b"]', '[/code]'),
        ('[code foo]', '[/code]'),
        ('[code ]', '[/code]'),
        ('[code]\n[code]', '[/code]\n[/code]'),
        ('[code]\n[code]', '[/code]'),
        ('<!--', '-->'),
        ('   <!--', '-->'),
        ('<!--', ''),
      ]) {
        final source = '$before\n$poll\n$after';
        expect(parsePollComposerBlocks(source), isEmpty, reason: source);
        expect(pollNamesInComposerSource(source), isEmpty, reason: source);
        expect(nextPollName(source), 'poll', reason: source);
      }
    });

    test('preserves active polls after literal code and comment markers', () {
      const poll = '[poll name=live]\r\n* A\r\n* B\r\n[/poll]';
      for (final prefix in const [
        '```\n[code]\n```',
        '~~~\n<!--\n~~~',
        '[code]\n```\n[/code]',
        '[code]\n<!--\n[/code]',
        '<!--\n[code]\n-->',
        '<!-->',
      ]) {
        final source = '😀\r\n$prefix\r\n$poll\r\n[/code]';
        final block = parsePollComposerBlocks(source).single;
        expect(block.start, source.indexOf('[poll name=live]'), reason: source);
        expect(block.end, block.start + poll.length, reason: source);
        expect(block.source, poll, reason: source);
        expect(block.lineEnding, '\r\n', reason: source);
        expect(pollNamesInComposerSource(source), {'live'}, reason: source);
      }
    });

    test('keeps quoted and unmatched or malformed code polls active', () {
      const poll = '[poll]\n* A\n* B\n[/poll]';
      for (final (before, after) in const [
        ('[quote]', '[/quote]'),
        ('[code]', ''),
        ('[code] trailing', '[/code]'),
        ('[code=]', '[/code]'),
        ('[code foo=]', '[/code]'),
        ('[code ] trailing', '[/code]'),
        ('[code]', '[/code] trailing'),
        ('before <!--', '-->'),
        ('    <!--', '-->'),
      ]) {
        final source = '$before\n$poll\n$after';
        expect(parsePollComposerBlocks(source).single.source, poll);
        expect(nextPollName(source), 'poll2', reason: source);
      }
    });

    test(
      'code and comment recognition agrees with the bundled cooker',
      () async {
        final service = OfflineCookingService();
        addTearDown(service.dispose);
        const poll = '[poll]\n* A\n* B\n[/poll]';
        for (final (before, after, active) in const [
          ('[code]', '[/code]', false),
          ('[code=js]', '[/code]', false),
          ('[code language=js]', '[/code]', false),
          ('<!--', '-->', false),
          ('<!--', '', false),
          ('[quote]', '[/quote]', true),
          ('[quote]\n[code]', '[/quote]\n[/code]', true),
          ('[QUOTE]\n[code]', '[/quote]\n[/code]', true),
          ('[QUOTE=Sam]\n[code]', '[/quote]\n[/code]', false),
          ('[QUOTE=Sam, post:1, topic:2]\n[code]', '[/quote]\n[/code]', false),
          ('[excerpt]\n[code]', '[/excerpt]\n[/code]', true),
          ('[grid]\n[code]', '[/grid]\n[/code]', true),
          ('[wrap]\n[code]', '[/wrap]\n[/code]', true),
          ('[excerpt]\n```\n[/excerpt]', '', true),
          ('[grid]\n```\n[/grid]', '', true),
          ('[wrap]\n```\n[/wrap]', '', true),
          ('[poll]\n[code]\n[/poll]', '[/code]', true),
          ('[poll]\n```\n[/poll]', '', true),
          ('[details]\n[code]', '[/details]\n[/code]', false),
          ('[spoiler]\n[code]', '[/spoiler]\n[/code]', false),
          ('[event]\n[code]', '[/event]\n[/code]', false),
          ('[quote=Sam, post:1, topic:2]\n[code]', '[/quote]\n[/code]', true),
          ('[quote]\n<!--\n[/quote]', '-->', false),
          ('[quote]\n<!--\n[/quote]\n-->', '', false),
          ('[quote]\n<!--\n-->\n[/quote]', '', true),
          ('[quote]\n```\n[/quote]', '', true),
          ('[code=]', '[/code]', true),
          ('[code foo=]', '[/code]', true),
          ('[code ] trailing', '[/code]', true),
          ('[code lang=“a b”]', '[/code]', false),
          ('[code]\n[code]', '[/code]', false),
          ('[code]', '', true),
          ('before <!--', '-->', true),
          ('<!-->', '', true),
          ('```\n[code]\n```', '[/code]', true),
          ('[code]\n<!--\n[/code]', '', true),
        ]) {
          final source = '$before\n$poll\n$after';
          final result = await service.cook(
            CookingRequest(
              raw: source,
              snapshot: CookingSnapshot(siteId: 'test', accountId: 'test'),
              configuration: CookingConfiguration(
                modules: [
                  CookingModule(id: 'poll', owner: 'poll', version: '1'),
                ],
              ),
            ),
          );
          expect(result.failure, isNull, reason: source);
          expect(result.html.contains('class="poll"'), active, reason: source);
          expect(
            parsePollComposerBlocks(source).isNotEmpty,
            active,
            reason: source,
          );
          expect(
            pollNamesInComposerSource(source),
            active ? {'poll'} : <String>{},
            reason: source,
          );
        }
      },
    );

    test(
      'preserves exact active polls after list-contained code and fences',
      () {
        for (final newline in const ['\n', '\r\n']) {
          final poll = '[poll]\n* A\n* B\n[/poll]'.replaceAll('\n', newline);
          for (final (marker, indent) in const [
            ('- a', '  '),
            ('1. a', '   '),
          ]) {
            for (final blankBefore in const ['', '\n']) {
              for (final blankAfter in const ['', '\n']) {
                for (final opener in const ['[code]', '```']) {
                  final prefix =
                      '$marker\n$blankBefore$indent$opener\n$blankAfter'
                          .replaceAll('\n', newline);
                  final source = '$prefix$poll$newline[/code]';
                  final blocks = parsePollComposerBlocks(source);
                  expect(blocks, hasLength(1), reason: source);
                  final block = blocks.single;
                  expect(block.start, prefix.length, reason: source);
                  expect(
                    block.end,
                    prefix.length + poll.length,
                    reason: source,
                  );
                  expect(block.source, poll, reason: source);
                  expect(block.lineEnding, newline, reason: source);
                  expect(pollNamesInComposerSource(source), {
                    'poll',
                  }, reason: source);
                  expect(nextPollName(source), 'poll2', reason: source);
                }
              }
            }
          }
        }
      },
    );

    test('retains poll offsets after literal markers in prior code', () {
      for (final newline in const ['\n', '\r\n']) {
        final poll = '[poll name=live]\n* A\n* B\n[/poll]'.replaceAll(
          '\n',
          newline,
        );
        for (final marker in const ['<!--', '```']) {
          final prefix = '[code]\n$marker\n[/code]\n- a\n\n  [code]\n'
              .replaceAll('\n', newline);
          final source = '$prefix$poll$newline[/code]';
          final blocks = parsePollComposerBlocks(source);
          expect(blocks, hasLength(1), reason: source);
          final block = blocks.single;
          expect(block.start, prefix.length, reason: source);
          expect(block.end, prefix.length + poll.length, reason: source);
          expect(block.source, poll, reason: source);
          expect(pollNamesInComposerSource(source), {'live'}, reason: source);
        }
      }
    });

    test('keeps indented root and list-contained code examples literal', () {
      const poll = '[poll]\n* A\n* B\n[/poll]';
      for (final indent in const ['  ', '   ']) {
        final source = '$indent[code]\n$poll\n[/code]';
        expect(parsePollComposerBlocks(source), isEmpty, reason: source);
        expect(pollNamesInComposerSource(source), isEmpty, reason: source);
        expect(nextPollName(source), 'poll', reason: source);
      }
      for (final (marker, indent) in const [('- a', '  '), ('1. a', '   ')]) {
        final example = '$indent${poll.replaceAll('\n', '\n$indent')}';
        final prefix = '$marker\n\n$indent[code]\n$example\n$indent[/code]\n\n';
        final source = '$prefix[poll name=live]\n* C\n* D\n[/poll]';
        final block = parsePollComposerBlocks(source).single;
        expect(block.start, prefix.length, reason: source);
        expect(block.end, source.length, reason: source);
        expect(block.source, source.substring(prefix.length), reason: source);
        expect(pollNamesInComposerSource(source), {'live'}, reason: source);
        expect(nextPollName(source), 'poll', reason: source);
      }
    });

    final relativeCases = <({String source, bool active})>[
      for (final (marker, indent, closers) in const [
        ('- a', '  ', [4, 5]),
        ('1. a', '   ', [4, 5, 6]),
      ])
        for (final closer in closers)
          (
            source:
                '$marker\n\n$indent[code]\n'
                '${indent}[poll name=live]\n$indent* A\n$indent* B\n'
                '$indent[/poll]\n${' ' * closer}[/code]',
            active: false,
          ),
      for (final tag in const ['quote', 'excerpt', 'grid', 'wrap'])
        (
          source:
              '- a\n\n  [$tag]\n  [code]\n    [/$tag]\n'
              '  [poll name=live]\n  * A\n  * B\n  [/poll]\n  [/code]',
          active: true,
        ),
    ];
    for (var index = 0; index < relativeCases.length; index++) {
      test('matches list-relative BBCode case $index', () {
        final example = relativeCases[index];
        final blocks = parsePollComposerBlocks(example.source);
        expect(blocks, hasLength(example.active ? 1 : 0));
        expect(
          pollNamesInComposerSource(example.source),
          example.active ? {'live'} : <String>{},
        );
        if (example.active) {
          final block = blocks.single;
          expect(block.start, example.source.indexOf('  [poll'));
          expect(block.end, example.source.indexOf('  [/poll]') + 9);
          expect(
            block.source,
            example.source.substring(block.start, block.end),
          );
          expect(block.openingIndent, '  ');
          expect(block.closingIndent, '  ');
        }
      });
    }

    test('list-relative BBCode agrees with the bundled cooker', () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      const poll = '[poll name=live]\n* A\n* B\n[/poll]';
      final cases = [
        ...relativeCases,
        (
          source:
              '- a\n\n  [code]\n  <!--\n  [poll name=example]\n'
              '  * C\n  * D\n  [/poll]\n    [/code]\n\n'
              '- b\n\n  [code]\n$poll\n[/code]',
          active: true,
        ),
        (
          source:
              '[code]\n    [/code]\n<!--\n[/code]\n'
              '- a\n\n  [code]\n$poll\n[/code]',
          active: true,
        ),
        (source: '- a\n\n  [code]\n<!--\n$poll\n[/code]', active: false),
        (source: '    [code]\n\n$poll\n    [/code]', active: true),
        (
          source:
              '- a\n\n  - b\n\n    [code]\n'
              '  [poll name=live]\n  * A\n  * B\n  [/poll]\n    [/code]',
          active: true,
        ),
        (
          source:
              '- a\n\n  [code]\n  [poll name=live]\n'
              '  * A\n  * B\n  [/poll]\n\t[/code]',
          active: false,
        ),
        (source: '[code]\n$poll\n\t[/code]', active: true),
      ];
      for (final example in cases) {
        final result = await service.cook(
          CookingRequest(
            raw: example.source,
            snapshot: CookingSnapshot(siteId: 'test', accountId: 'test'),
            configuration: CookingConfiguration(
              modules: [CookingModule(id: 'poll', owner: 'poll', version: '1')],
            ),
          ),
        );
        expect(result.failure, isNull, reason: example.source);
        expect(
          RegExp('class="poll"').allMatches(result.html).length,
          example.active ? 1 : 0,
          reason: example.source,
        );
        final blocks = parsePollComposerBlocks(example.source);
        expect(
          blocks,
          hasLength(example.active ? 1 : 0),
          reason: example.source,
        );
        expect(
          pollNamesInComposerSource(example.source),
          example.active ? {'live'} : <String>{},
          reason: example.source,
        );
        if (example.active) {
          final block = blocks.single;
          expect(
            block.start,
            example.source.lastIndexOf('[poll name=live]') -
                block.openingIndent.length,
          );
          expect(
            block.source,
            example.source.substring(block.start, block.end),
          );
        }
      }
    });

    test('list boundaries agree with the bundled cooker', () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      const poll = '[poll]\n* A\n* B\n[/poll]';
      for (final newline in const ['\n', '\r\n']) {
        for (final (before, after, active) in const [
          ('[code]\n```\n[/code]\n- a\n\n  [code]', '[/code]', true),
          ('[code]\n<!--\n[/code]\n- a\n\n  [code]', '[/code]', true),
          ('- a\n\n  [code]\n<!-- -->', '[/code]', true),
          (
            '- a\n\n  [code]\n<!--\n[poll name=example]\n* C\n* D\n[/poll]\n-->',
            '[/code]',
            true,
          ),
          ('- a\n\n  [code]\n<!--', '[/code]', false),
          ('- a\n\n  [code]\n<!--\n[/code]\n-->', '', true),
          ('- a\n\n  [code]', '[/code]', true),
          ('- a\n  [code]', '[/code]', true),
          ('- a\n\n  [code]\n', '[/code]', true),
          ('- a\n  [code]\n', '[/code]', true),
          ('1. a\n\n   [code]', '[/code]', true),
          ('1. a\n   [code]', '[/code]', true),
          ('1. a\n\n   [code]\n', '[/code]', true),
          ('1. a\n   [code]\n', '[/code]', true),
          ('- a\n\n  ```', '', true),
          ('- a\n  ```', '', true),
          ('1. a\n\n   ```', '', true),
          ('1. a\n   ```', '', true),
          (
            '- a\n\n  [code]\n  [poll name=example]\n  * C\n  * D\n'
                '  [/poll]\n  [/code]\n',
            '',
            true,
          ),
          (
            '1. a\n\n   [code]\n   [poll name=example]\n   * C\n   * D\n'
                '   [/poll]\n   [/code]\n',
            '',
            true,
          ),
          ('- a\n\n  <!--', '-->', false),
          ('- a\n\n  <!--', '', false),
          ('  [code]', '[/code]', false),
          ('   [code]', '[/code]', false),
        ]) {
          final source = '$before\n$poll\n$after'.replaceAll('\n', newline);
          final result = await service.cook(
            CookingRequest(
              raw: source,
              snapshot: CookingSnapshot(siteId: 'test', accountId: 'test'),
              configuration: CookingConfiguration(
                modules: [
                  CookingModule(id: 'poll', owner: 'poll', version: '1'),
                ],
              ),
            ),
          );
          expect(result.failure, isNull, reason: source);
          expect(
            RegExp('class="poll"').allMatches(result.html).length,
            active ? 1 : 0,
            reason: source,
          );
          expect(
            parsePollComposerBlocks(source).isNotEmpty,
            active,
            reason: source,
          );
          expect(
            pollNamesInComposerSource(source),
            active ? {'poll'} : <String>{},
            reason: source,
          );
        }
      }
    });

    test('preserves active polls at quote boundaries', () {
      const poll = '[poll name=live]\n* A\n* B\n[/poll]';
      for (final quote in const [
        '[quote]',
        '[quote="a user"]',
        '[quote=Sam, post:1, topic:2]',
      ]) {
        for (final source in [
          '$quote\n[code]\n$poll\n[/quote]\n[/code]',
          '$quote\n<!--\n-->\n[/quote]\n$poll',
          '$quote\n```\n[/quote]\n$poll',
        ]) {
          final blocks = parsePollComposerBlocks(source);
          expect(blocks, hasLength(1), reason: source);
          final block = blocks.single;
          expect(block.source, poll, reason: source);
          expect(block.start, source.indexOf(poll), reason: source);
          expect(pollNamesInComposerSource(source), {'live'}, reason: source);
        }
      }
    });

    test('keeps uppercase legacy quote examples literal', () {
      const poll = '[poll]\n* A\n* B\n[/poll]';
      for (final quote in const ['QUOTE=Sam', 'QUOTE=Sam, post:1, topic:2']) {
        final source = '[$quote]\n[code]\n$poll\n[/quote]\n[/code]';
        expect(parsePollComposerBlocks(source), isEmpty, reason: source);
        expect(pollNamesInComposerSource(source), isEmpty, reason: source);
        expect(nextPollName(source), 'poll', reason: source);
      }
    });

    test('preserves active polls at core BBCode boundaries', () {
      const poll = '[poll name=live]\r\n* A\r\n* B\r\n[/poll]';
      for (final tag in const ['excerpt', 'grid', 'wrap', 'poll']) {
        for (final source in [
          '[$tag]\r\n[code]\r\n[/$tag]\r\n$poll\r\n[/code]',
          '[$tag]\r\n```\r\n[/$tag]\r\n$poll',
        ]) {
          final blocks = parsePollComposerBlocks(source);
          expect(blocks, hasLength(1), reason: source);
          final block = blocks.single;
          expect(block.source, poll, reason: source);
          expect(block.start, source.indexOf(poll), reason: source);
          expect(block.end, block.start + poll.length, reason: source);
          expect(
            pollNamesInComposerSource(source),
            tag == 'poll' ? {'poll', 'live'} : {'live'},
            reason: source,
          );
        }
      }
    });

    test('leaves a long malformed code opener literal', () {
      final source = '[code ${'a' * 100}!]\n[poll]\n* A\n* B\n[/poll]\n[/code]';
      expect(parsePollComposerBlocks(source).single.name, 'poll');
      expect(nextPollName(source), 'poll2');
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

    group('close time zone', () {
      final base = PollComposerDraft.newPoll(
        name: 'poll',
        defaultPublic: true,
      ).copyWith(options: ['Soup', 'Salad']);

      String? writtenClose(PollComposerDraft draft) =>
          parsePollComposerBlocks(draft.serialize()).single.attribute('close');

      Matcher localWallTimeWithOffset(String wall) =>
          matches(RegExp('^${RegExp.escape(wall)}[+-]\\d\\d:\\d\\d\$'));

      test(
        'rejects changed overflowing ISO components before normalization',
        () {
          for (final entered in [
            '2027-01-32T12:00',
            '2027-01-32T12:00Z',
            '2027-01-30T25:61',
            '2027-01-30T25:61Z',
            '2027-02-29T12:00+05:30',
            '2027-04-31T12:00-04:00',
            '2027-00-15T12:00',
            '2027-13-15T12:00',
            '2027-01-00T12:00',
            '20270132T1200',
            '2027-01-30T24:01',
            '2027-01-30T24:00:00.1',
            '2027-01-30T12:00:61',
            '2027-01-30T12:00+24:00',
            '2027-01-30T12:00+05:60',
          ]) {
            expect(DateTime.tryParse(entered), isNotNull, reason: entered);
            expect(
              base
                  .copyWith(close: entered)
                  .validate(maximumOptions: 20, isStaff: false)
                  .errors,
              ['Automatic close must be a valid ISO-8601 date and time.'],
              reason: entered,
            );
          }
        },
      );

      test('retains accepted ISO forms and valid leap dates', () {
        for (final entered in [
          '2028-02-29T12:00',
          '2028-02-29T12:00Z',
          '2028-02-29T12:00+05:30',
          '2028-02-29T12:00-04:00',
          '2000-02-29T12:00',
          '20280229T120030.123456+0530',
          '2028-02-29 12:00:30,123456Z',
          '2027-01-30T24:00',
          '2027-01-30T24:00:00.000Z',
          '2027-01-30T23:59:60Z',
        ]) {
          expect(
            base
                .copyWith(close: entered)
                .validate(maximumOptions: 20, isStaff: false)
                .isValid,
            isTrue,
            reason: entered,
          );
        }
      });

      test(
        'untouched legacy overflowing close remains exact on other edits',
        () {
          const source =
              '[poll close=2027-01-32T12:00Z]\n* Soup\n* Salad\n[/poll]';
          final draft = PollComposerDraft.fromBlock(
            parsePollComposerBlocks(source).single,
          ).copyWith(title: 'Lunch');
          expect(
            draft.validate(maximumOptions: 20, isStaff: false).isValid,
            isTrue,
          );
          expect(draft.serialize(), contains('close=2027-01-32T12:00Z'));
          expect(
            draft
                .copyWith(close: '2027-01-30T25:61Z')
                .validate(maximumOptions: 20, isStaff: false)
                .isValid,
            isFalse,
          );
        },
      );

      test('an offset-less entry is written as local time with its offset', () {
        // Discourse parses a close value without an offset as UTC, so writing
        // the entry verbatim would close the poll at the wrong moment for
        // anyone outside UTC.
        for (final (entered, meant, wall) in [
          (
            '2026-08-30T18:00',
            DateTime(2026, 8, 30, 18),
            '2026-08-30T18:00:00',
          ),
          (
            '2026-01-15 09:30:15',
            DateTime(2026, 1, 15, 9, 30, 15),
            '2026-01-15T09:30:15',
          ),
          ('2026-08-30', DateTime(2026, 8, 30), '2026-08-30T00:00:00'),
        ]) {
          final draft = base.copyWith(close: entered);
          expect(
            draft.validate(maximumOptions: 20, isStaff: false).isValid,
            isTrue,
            reason: entered,
          );

          final written = writtenClose(draft)!;
          expect(written, localWallTimeWithOffset(wall), reason: entered);
          expect(
            DateTime.parse(written).isAtSameMomentAs(meant),
            isTrue,
            reason: '$entered was written as $written',
          );
        }
      });

      test('an entry with an explicit offset or Z is written as entered', () {
        for (final entered in [
          '2026-08-30T18:00:00Z',
          '2026-08-30T18:00:00+05:30',
          '2026-08-30T18:00-04:00',
        ]) {
          final draft = base.copyWith(close: entered);
          expect(
            draft.validate(maximumOptions: 20, isStaff: false).isValid,
            isTrue,
            reason: entered,
          );
          expect(writtenClose(draft), entered);
        }
      });

      test('an edited close gets an offset; an untouched one never moves', () {
        const source =
            '[poll name=lunch close=2026-08-30T18:00]\n'
            '* Soup\n'
            '* Salad\n'
            '[/poll]';
        final draft = PollComposerDraft.fromBlock(
          parsePollComposerBlocks(source).single,
        );

        // The server has already scheduled the stored value as UTC; an edit
        // elsewhere in the poll must not reinterpret it.
        expect(
          writtenClose(draft.copyWith(title: 'Lunch')),
          '2026-08-30T18:00',
        );

        final written = writtenClose(
          draft.copyWith(close: '2026-09-01T12:00'),
        )!;
        expect(written, localWallTimeWithOffset('2026-09-01T12:00:00'));
        expect(
          DateTime.parse(written).isAtSameMomentAs(DateTime(2026, 9, 1, 12)),
          isTrue,
        );
      });

      test('a written close reads back into the editor unchanged', () {
        final source = base.copyWith(close: '2026-08-30T18:00').serialize();
        final reopened = PollComposerDraft.fromBlock(
          parsePollComposerBlocks(source).single,
        );

        expect(reopened.close, localWallTimeWithOffset('2026-08-30T18:00:00'));
        expect(
          DateTime.parse(
            reopened.close,
          ).isAtSameMomentAs(DateTime(2026, 8, 30, 18)),
          isTrue,
        );
        expect(
          reopened.validate(maximumOptions: 20, isStaff: false).isValid,
          isTrue,
        );
        expect(reopened.serialize(), source);
        expect(
          reopened.copyWith(title: 'Lunch').serialize(),
          contains('close=${reopened.close}'),
        );
      });
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
      // The blank line after the poll is a structural gap that holds no
      // caret; typing continues the following paragraph.
      expect(result.value.selection.extentOffset, 10 + poll.length);
      expect(
        result.value.text.replaceRange(
          result.value.selection.start,
          result.value.selection.end,
          'next ',
        ),
        'before\n\n$poll\n\nnext after',
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

    test('the following caret consumes a complete CRLF blank line', () {
      const source = 'before\r\nafter';
      final result = insertVerifiedPoll(
        current: const TextEditingValue(text: source),
        expectedDocument: source,
        expectedSelection: const TextSelection.collapsed(offset: 8),
        markup: poll,
      );

      expect(result.value.text, 'before\r\n\r\n$poll\r\n\r\nafter');
      expect(result.value.selection.extentOffset, 14 + poll.length);
    });

    test('the following caret passes one line break or one blank line', () {
      // Further empty lines are the author's own and can hold the caret.
      for (final (following, gap) in [
        ('\nafter', 1),
        ('\n\nafter', 2),
        ('\n\n\nafter', 2),
        ('\r\n\r\n\r\nafter', 4),
      ]) {
        final source = '$poll$following';
        final result = replaceVerifiedPoll(
          current: TextEditingValue(text: source),
          expectedDocument: source,
          expectedBlock: parsePollComposerBlocks(source).single,
          replacement: poll,
        );

        expect(result.value.text, source);
        expect(
          result.value.selection,
          TextSelection.collapsed(offset: poll.length + gap),
          reason: jsonEncode(following),
        );
      }
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
        'before\n\n[poll type=number min=0 max=1]\n[/poll]\n\n'.length,
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

    test('inserts a separator before an indented poll-like prefix', () {
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
