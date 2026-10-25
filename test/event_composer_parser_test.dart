import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

const _event = '[event start="2026-09-08 12:00"]\nAgenda\n[/event]';
const _unfinished = '[event start="2026-09-08 12:00"]\n';

void main() {
  test('stray backticks do not hide a separate event block', () {
    for (final closer in ['`', '``']) {
      final source = '`unclosed\n$_event\n$closer';
      expect(parseEventBlocks(source).map((block) => block.source), [_event]);
      expect(hasEventMarkup(source), isTrue);
    }
  });

  test('unfinished and nested events keep the existing raw fallback', () {
    expect(parseEventBlocks(_unfinished * 64), isEmpty);
    expect(hasEventMarkup(_unfinished * 64), isTrue);

    final source = '${_unfinished * 64}$_event\n[/event]\n$_event\ntrailing';
    final blocks = parseEventBlocks(source);
    expect(blocks.map((block) => block.source), [_event, _event]);
    expect(blocks.first.start, _unfinished.length * 64);
    expect(blocks.last.end, source.length - '\ntrailing'.length);

    for (final nested in ['[event', '[EVENTUAL]', '[event start=x]']) {
      expect(
        parseEventBlocks('[event start=x]description $nested\n[/event]'),
        isEmpty,
        reason: nested,
      );
    }
    expect(parseEventBlocks('[event start=x]$_event'), isEmpty);
  });

  test('malformed openers do not hide a later valid event', () {
    for (final malformed in [
      '[event start="unfinished]\n',
      '[event start=x START=y]bad[/event]\n',
      '[event name="No start"]bad[/event]\n',
      '[event start=""]bad[/event]\n',
      '[event start=x broken]bad[/event]\n',
    ]) {
      final source = '$malformed$_event';
      final block = parseEventBlocks(source).single;
      expect(block.source, _event, reason: malformed);
      expect(block.start, malformed.length, reason: malformed);
    }
  });

  test('indented mixed-case CRLF blocks preserve offsets and replacements', () {
    const raw =
        '[EvEnT start = \'2026-09-08 12:00\' name="[event] and [/event]" '
        'future.Flag=abc showLocalTime="true"]\r\nAgenda\r\n[/EVENT]';
    const prefix = 'Before\r\n   ';
    const suffix = '\r\nTrailing [event';
    const source = '$prefix$raw$suffix';
    final block = parseEventBlocks(source).single;
    expect(block.start, prefix.length);
    expect(block.end, prefix.length + raw.length);
    expect(source.substring(block.start, block.end), raw);
    expect(block.description, '\r\nAgenda\r\n');
    expect(raw.substring(block.openEnd, block.closeStart), block.description);
    expect(raw.substring(block.closeStart), '[/EVENT]');
    expect(block.attribute('show-local-time'), 'true');
    for (final attribute in block.attributes) {
      expect(
        raw.substring(attribute.start, attribute.end).trimLeft(),
        startsWith(attribute.name),
      );
      expect(
        raw.substring(attribute.valueStart, attribute.valueEnd),
        contains(attribute.value),
      );
    }
    expect(block.replace({}), raw);
    expect(
      source.replaceRange(
        block.start,
        block.end,
        block.replace({'name': 'Updated [A]', 'future-flag': null}),
      ),
      source
          .replaceFirst('name="[event] and [/event]"', 'name="Updated [A]"')
          .replaceFirst(' future.Flag=abc', ''),
    );
  });

  test('replacement keeps unchanged spelling and quotes what it writes', () {
    const raw = "[event start='2026-09-08 12:00' name=Call]\nAgenda\n[/event]";
    final block = parseEventBlocks(raw).single;
    expect(block.replace({'start': '2026-09-08 12:00', 'name': 'Call'}), raw);
    expect(
      block.replace({'name': ''}),
      "[event start='2026-09-08 12:00']\nAgenda\n[/event]",
    );
    expect(
      block.replace({'name': 'The "Big" one'}),
      "[event start='2026-09-08 12:00' name='The \"Big\" one']\nAgenda\n[/event]",
    );
    expect(
      block.replace({'name': "Lee's call"}),
      "[event start='2026-09-08 12:00' name=\"Lee's call\"]\nAgenda\n[/event]",
    );
  });

  test('custom fields round-trip through the attribute upstream stores', () {
    // By setting name: the key the web composer writes (raw-event-helper's
    // camelCase) and the attribute Parser.custom_field_data_attribute stores
    // the field from. Both lowercase the setting before its separators become
    // word breaks, so letter case alone never separates words.
    const upstream = {
      'roomNumber': ('roomnumber', 'data-roomnumber'),
      'roomnumber': ('roomnumber', 'data-roomnumber'),
      'ROOM_NUMBER': ('roomNumber', 'data-room-number'),
      'room_number': ('roomNumber', 'data-room-number'),
      'room-number': ('roomNumber', 'data-room-number'),
      'room.number': ('roomNumber', 'data-room-number'),
      'room_1': ('room1', 'data-room1'),
    };
    for (final MapEntry(key: field, value: (web, stored)) in upstream.entries) {
      final attribute = eventCustomFieldAttributeName(field);
      expect(_cooked(web), stored, reason: '$field as the web writes it');

      final authored = parseEventBlocks(
        '[event start=x $web="12"]\n[/event]',
      ).single;
      expect(authored.attribute(attribute), '12', reason: field);
      expect(
        authored.replace({attribute: '14'}),
        '[event start=x $web="14"]\n[/event]',
        reason: field,
      );

      final written = parseEventBlocks(
        parseEventBlocks(_event).single.replace({attribute: '12'}),
      ).single;
      expect(_cooked(written.attributes.last.name), stored, reason: field);
      expect(written.attribute(attribute), '12', reason: field);
    }

    // A hand-typed `roomNumber=` cooks to data-room-number, which is not where
    // upstream stores the `roomNumber` field from.
    expect(_cooked('roomNumber'), isNot(upstream['roomNumber']!.$2));
    expect(
      parseEventBlocks(
        '[event start=x roomNumber="12"]\n[/event]',
      ).single.attribute(eventCustomFieldAttributeName('roomNumber')),
      isNull,
    );
  });

  test('overlapping exclusions leave subsequent actual blocks detectable', () {
    for (final (before, after) in [
      ('```text\n', '\n```'),
      ('~~~~\n~~~\n', '\n~~~~'),
      ('[quote=x]\n[code]\n', '\n[/quote]\n[/code]'),
      ('[code foo]\n', '\n[/code]'),
      ('<pre>\n', '\n</code>'),
      ('<!--\n[quote]\n', '\n[/quote]\n-->'),
      ('    ', ''),
      ('\t', ''),
      ('> ', ''),
    ]) {
      final excluded = '$before$_event$after';
      expect(parseEventBlocks(excluded), isEmpty, reason: excluded);
      expect(hasEventMarkup(excluded), isFalse, reason: excluded);
      final source = '$excluded\n$_event';
      expect(parseEventBlocks(source), hasLength(1), reason: source);
      expect(parseEventBlocks(source).single.start, excluded.length + 1);
      expect(hasEventMarkup(source), isTrue);
    }
  });

  test('unfinished exclusion delimiters preserve current recognition', () {
    for (final opener in ['[quote]', '[code]', '[quote=', '```\n', '~~~\n']) {
      final source = '$opener\n$_event';
      expect(parseEventBlocks(source), isEmpty, reason: opener);
      expect(hasEventMarkup(source), isFalse, reason: opener);
    }
    for (final opener in ['<!--', '<pre>', '<code>', '`']) {
      final source = '$opener\n$_event';
      expect(parseEventBlocks(source).single.start, opener.length + 1);
      expect(hasEventMarkup(source), isTrue, reason: opener);
    }
  });

  test('inline code requires complete matching runs within a paragraph', () {
    const legacy = '[event start = "2026-09-08 12:00"]\nAgenda\n[/event]';
    for (var first = 1; first <= 8; first++) {
      for (var second = 1; second <= 8; second++) {
        final source = 'text ${'`' * first}\n$legacy\n${'`' * second}';
        final isCode = first == second;
        expect(parseEventBlocks(source).isEmpty, isCode, reason: source);
        expect(hasEventMarkup(source), !isCode, reason: source);
      }
    }
  });

  test('inline exclusions match the application cooker', () async {
    final service = OfflineCookingService();
    addTearDown(service.dispose);
    const legacy = '[event start = "2026-09-08 12:00"]\nAgenda\n[/event]';
    const dotted = '[event start=x future.Flag=abc]\nAgenda\n[/event]';
    final cases = <({String source, bool event, bool code, bool editable})>[
      for (final newline in ['\n', '\r\n', '\r'])
        for (final indent in ['', '   '])
          for (final closer in ['`', '``'])
            (
              source:
                  '`before$newline$indent${_event.replaceAll('\n', newline)}$newline$closer',
              event: true,
              code: false,
              editable: true,
            ),
      (
        source: '`before\n\n$legacy\n\n`after',
        event: false,
        code: false,
        editable: true,
      ),
      (
        source:
            '`before\n[event start="2026-09-08 12:00"\u0085name="Call"]\nAgenda\n[/event]\n`after',
        event: false,
        code: true,
        editable: false,
      ),
      (
        source:
            '`before\n[event start=x\u0085future.Flag=y]\nAgenda\n[/event]\n`after',
        event: true,
        code: false,
        editable: true,
      ),
      for (final separator in ['\u2028', '\u2029'])
        (
          source:
              '`before\n[event start="2026-09-08 12:00" name="a${separator}b"]\nAgenda\n[/event]\n`after',
          event: true,
          code: false,
          editable: true,
        ),
      for (final space in ['\u00a0', '\u2003', '\u2028', '\u2029'])
        (
          source: '`before\n$space\n$legacy\n`after',
          event: false,
          code: true,
          editable: false,
        ),
      for (final event in [legacy, dotted])
        (
          source: '`before\n$event\n`after',
          event: false,
          code: true,
          editable: false,
        ),
      for (final (before, after, code) in [
        ('``', '``', true),
        ('```', '``', false),
        ('`````', '```', false),
        ('``', '``` then ``', true),
        (r'\`', '`', false),
        (r'\``', '`', true),
        (r'\\`', '`', true),
        ('`', r'\`', true),
      ])
        (
          source: 'text $before\n$legacy\ntext $after',
          event: false,
          code: code,
          editable: !code,
        ),
      for (final (before, after) in [
        ('```\n', '\n```'),
        ('[code]\n', '\n[/code]'),
        ('<!--\n', '\n-->'),
      ])
        (
          source: '$before$_event$after',
          event: false,
          code: before != '<!--\n',
          editable: false,
        ),
    ];
    for (final fixture in cases) {
      final result = await service.cook(
        CookingRequest(
          raw: fixture.source,
          snapshot: CookingSnapshot(
            siteId: 'event-test',
            accountId: 'event-test',
            pluginContext: const {
              'discourse-events': {
                'settings': {'discourse_post_event_enabled': true},
              },
            },
          ),
          configuration: CookingConfiguration(
            modules: [
              CookingModule(
                id: 'post-event',
                owner: 'discourse-events',
                version: '1',
              ),
            ],
          ),
        ),
      );
      expect(result.failure, isNull, reason: fixture.source);
      expect(
        result.html.contains('class="discourse-post-event"'),
        fixture.event,
        reason: fixture.source,
      );
      expect(
        result.html.contains('<code'),
        fixture.code,
        reason: fixture.source,
      );
      final blocks = parseEventBlocks(fixture.source);
      expect(
        blocks,
        hasLength(fixture.editable ? 1 : 0),
        reason: fixture.source,
      );
      expect(
        hasEventMarkup(fixture.source),
        fixture.editable,
        reason: fixture.source,
      );
      for (final block in blocks) {
        expect(fixture.source.substring(block.start, block.end), block.source);
        expect(block.replace({}), block.source);
      }
    }
  });

  test('unfinished openers and nested rejections scale with the draft', () {
    for (final suffix in ['', '$_event\nTrailing']) {
      final smallSource = '${_unfinished * 256}$suffix';
      final largeSource = '${_unfinished * 2048}$suffix';
      final expected = suffix.isEmpty ? 0 : 1;
      expect(parseEventBlocks(smallSource), hasLength(expected));
      expect(parseEventBlocks(largeSource), hasLength(expected));
      final (:small, :large) = measureScaling(
        () => parseEventBlocks(smallSource).length,
        () => parseEventBlocks(largeSource).length,
      );
      expect(
        large,
        lessThan(small * 25),
        reason:
            '8x unfinished openers with suffix "$suffix": ${large / small}x',
      );
    }
  });

  test('unclosed asymmetric quote values scale within one opening line', () {
    String draft(int count) =>
        '`before\n[event start=“word ${'key=“word ' * count}]\nAgenda\n[/event]\n`after\n$_event';
    final smallSource = draft(256);
    final largeSource = draft(2048);
    for (final source in [smallSource, largeSource]) {
      expect(parseEventBlocks(source).map((block) => block.source), [_event]);
      expect(hasEventMarkup(source), isTrue);
    }
    final (:small, :large) = measureScaling(
      () =>
          parseEventBlocks(smallSource).length +
          (hasEventMarkup(smallSource) ? 1 : 0),
      () =>
          parseEventBlocks(largeSource).length +
          (hasEventMarkup(largeSource) ? 1 : 0),
    );
    expect(large, lessThan(small * 25));
  });

  test('exclusion scans and multiple blocks scale with the draft', () {
    // Exercise both public entry points, including unmatched delimiters whose
    // former regexes retried the remaining draft at every opening delimiter.
    for (final unit in [
      '$_event\n',
      '> quoted line\n$_event\n',
      '[quote]\n',
      '[quote=unfinished\n',
      '<pre>\n',
      '<pre unfinished\n',
      '<!--\n',
      'a ````````````````',
      '`',
    ]) {
      final smallSource = '${unit * 256}\n$_event';
      final largeSource = '${unit * 2048}\n$_event';
      final (:small, :large) = measureScaling(
        () =>
            parseEventBlocks(smallSource).length +
            (hasEventMarkup(smallSource) ? 1 : 0),
        () =>
            parseEventBlocks(largeSource).length +
            (hasEventMarkup(largeSource) ? 1 : 0),
      );
      expect(
        large,
        lessThan(small * 25),
        reason: '8x "$unit": ${large / small}x',
      );
    }
  });
}

/// Cooks a BBCode key as the `[event]` markdown rule in the plugin's markup
/// snapshot does: `data-${dasherize(key)}`.
String _cooked(String key) =>
    'data-${key.replaceAllMapped(RegExp('[A-Z]'), (match) => '${match.start == 0 ? '' : '-'}${match[0]!.toLowerCase()}')}';
