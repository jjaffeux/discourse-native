import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

const _event = '[event start="2026-09-08 12:00"]\nAgenda\n[/event]';
const _unfinished = '[event start="2026-09-08 12:00"]\n';

void main() {
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

  test('overlapping exclusions leave subsequent actual blocks detectable', () {
    for (final (before, after) in [
      ('```text\n', '\n```'),
      ('~~~~\n~~~\n', '\n~~~~'),
      ('[quote=x]\n[code]\n', '\n[/quote]\n[/code]'),
      ('[code foo]\n', '\n[/code]'),
      ('<pre>\n', '\n</code>'),
      ('<!--\n[quote]\n', '\n[/quote]\n-->'),
      ('`\n', '\n`'),
      ('``\n', '\na ```'),
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

  test(
    'inline backtick runs retain greedy opener and partial closer behavior',
    () {
      for (final (before, after, excluded) in [
        ('a ``', '``', true),
        ('a ```', '``', true),
        ('a ````', '``', false),
        ('a `````', '```', true),
        ('a `````', '``', true),
        ('a ``````', '``', false),
        ('a ``', '```\n$_event\n`', true),
      ]) {
        final source = '$before\n$_event\n$after';
        expect(parseEventBlocks(source).isEmpty, excluded, reason: source);
        expect(hasEventMarkup(source), !excluded, reason: source);
      }
    },
  );

  test('varying backtick runs preserve the previous exclusion pattern', () {
    final pattern = RegExp(r'(`+)[\s\S]*?\1');
    for (var first = 0; first <= 8; first++) {
      for (var second = 0; second <= 8; second++) {
        for (var third = 0; third <= 8; third++) {
          final source = [
            for (final width in [first, second, third])
              'text ${'`' * width}\n$_event\n',
          ].join();
          final excluded = pattern.allMatches(source).toList();
          final expected = [
            for (final match in RegExp(r'\[event').allMatches(source))
              if (!excluded.any(
                (range) =>
                    range.start <= match.start && match.start < range.end,
              ))
                match.start,
          ];
          expect(
            parseEventBlocks(source).map((block) => block.start),
            expected,
            reason: 'backtick widths: $first, $second, $third',
          );
          expect(hasEventMarkup(source), expected.isNotEmpty);
        }
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
