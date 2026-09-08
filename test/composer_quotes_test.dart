import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

void main() {
  group('parseComposerQuotes', () {
    test('a line of openers costs its length, not its square', () {
      // `_startsBlock` searched backwards for the line start at every `[`,
      // which on a line that has none walks to the top of the document. The
      // composer rescans on every keystroke, so that is felt as a freeze.
      const unit = '[quote="s, post:1, topic:2"] ';
      final smallSource = unit * 800;
      final largeSource = unit * 6400;
      final smallCode = CodeRanges.of(scanMarkdown(smallSource));
      final largeCode = CodeRanges.of(scanMarkdown(largeSource));
      final (:small, :large) = measureScaling(
        () =>
            parseComposerQuotes(smallSource, knownCodeRanges: smallCode).length,
        () =>
            parseComposerQuotes(largeSource, knownCodeRanges: largeCode).length,
      );

      expect(
        large,
        lessThan(small * 25),
        reason: 'eight times the openers took ${large / small} times as long',
      );
    });

    test('reads the metadata emitted by core buildQuote', () {
      const source =
          'Before\n\n'
          '[quote="Last, First, post:5, topic:650, full:true, '
          'username:zogstrip"]\n'
          'Quoted words.\n'
          '[/quote]\n\n'
          'After';

      final quote = parseComposerQuotes(source).single;

      expect(quote.source, startsWith('[quote="Last, First'));
      expect(quote.contents, 'Quoted words.');
      expect(quote.username, 'zogstrip');
      expect(quote.displayName, 'Last, First');
      expect(quote.title, 'Last, First');
      expect(quote.postNumber, 5);
      expect(quote.topicId, 650);
      expect(quote.full, isTrue);
      expect(source.substring(quote.start, quote.end), quote.source);
    });

    test('keeps a nested quote in one immutable outer block', () {
      const source =
          '[quote="sam, post:1, topic:2"]\n'
          'Outer\n\n'
          '[quote]\nInner\n[/quote]\n'
          '[/quote]';

      final quotes = parseComposerQuotes(source);

      expect(quotes, hasLength(1));
      expect(quotes.single.start, 0);
      expect(quotes.single.end, source.length);
      expect(quotes.single.contents, contains('[quote]\nInner\n[/quote]'));
    });

    test('supports core quotation marks and legacy unquoted values', () {
      const source =
          '[quote=“sam, post: 3, topic: 9”]\nCurly\n[/quote]\n\n'
          '[quote=pat, post:4, topic:9]\nLegacy\n[/quote]';

      final quotes = parseComposerQuotes(source);

      expect(quotes.map((quote) => quote.username), ['sam', 'pat']);
      expect(quotes.map((quote) => quote.postNumber), [3, 4]);
    });

    test('leaves code and incomplete quote source editable', () {
      const source =
          '```\n[quote="sam"]\ncode\n[/quote]\n```\n\n'
          '[quote="pat"]\nincomplete';

      expect(parseComposerQuotes(source), isEmpty);
    });
  });

  test('quoteSafeSelection treats a quote as one atomic range', () {
    const source = '[quote="sam"]\nwords\n[/quote]\n\nafter';
    final quote = parseComposerQuotes(source).single;

    expect(
      quoteSafeSelection(
        [quote],
        TextSelection.collapsed(offset: quote.start + 1),
        TextSelection.collapsed(offset: quote.start),
      ),
      TextSelection.collapsed(offset: quote.end),
    );
    expect(
      quoteSafeSelection(
        [quote],
        TextSelection.collapsed(offset: quote.end - 1),
        TextSelection.collapsed(offset: quote.end),
      ),
      TextSelection.collapsed(offset: quote.start),
    );
    expect(
      quoteSafeSelection(
        [quote],
        TextSelection(baseOffset: quote.start + 2, extentOffset: source.length),
        const TextSelection.collapsed(offset: 0),
      ),
      TextSelection(baseOffset: quote.start, extentOffset: source.length),
    );
  });

  test('text input can remove a whole quote but cannot rewrite its body', () {
    const source = 'Before\n[quote="sam"]\nwords\n[/quote]\nafter';
    final quote = parseComposerQuotes(source).single;
    const formatter = ComposerQuoteInputFormatter();
    final old = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: quote.start),
    );
    final bodyEdit = TextEditingValue(
      text: source.replaceRange(quote.start + 10, quote.start + 11, 'X'),
      selection: TextSelection.collapsed(offset: quote.start + 11),
    );

    expect(formatter.formatEditUpdate(old, bodyEdit), old);

    final removed = TextEditingValue(
      text: source.replaceRange(quote.start, quote.end, ''),
      selection: TextSelection.collapsed(offset: quote.start),
    );
    expect(formatter.formatEditUpdate(old, removed), removed);
  });

  group('selected quote replacement', () {
    const formatter = ComposerQuoteInputFormatter();
    const source = 'Before\n[quote="sam"]\nwords\n[/quote]\nAfter';
    final quote = parseComposerQuotes(source).single;

    for (final reversed in [false, true]) {
      for (final (label, replacement) in [
        ('opening bracket', '['),
        ('closing delimiter', '[/quote]\n'),
        ('another quote', '[quote="new"]\nReplacement\n[/quote]\n'),
        ('empty text', ''),
      ]) {
        test('${reversed ? 'reversed' : 'forward'} selection: $label', () {
          final old = TextEditingValue(
            text: source,
            selection: TextSelection(
              baseOffset: reversed ? quote.end : quote.start,
              extentOffset: reversed ? quote.start : quote.end,
              isDirectional: true,
            ),
          );
          final proposed = TextEditingValue(
            text: source.replaceRange(quote.start, quote.end, replacement),
            selection: TextSelection.collapsed(
              offset: quote.start + replacement.length,
              affinity: TextAffinity.upstream,
            ),
          );

          expect(formatter.formatEditUpdate(old, proposed), proposed);
        });
      }
    }

    test('replaces multiple quotes and selected surrounding text', () {
      const source =
          'Before\n[quote="sam"]\nFirst\n[/quote]\n\n'
          'Between\n[quote="pat"]\nSecond\n[/quote]\n\nAfter';
      final quotes = parseComposerQuotes(source);
      for (final selection in [
        TextSelection(
          baseOffset: quotes.first.start,
          extentOffset: quotes.last.end,
        ),
        const TextSelection(baseOffset: source.length, extentOffset: 0),
      ]) {
        final old = TextEditingValue(text: source, selection: selection);
        final replacement = source
            .substring(selection.start, selection.end)
            .replaceFirst('First', 'Changed first')
            .replaceFirst('Second', 'Changed second');
        final proposed = TextEditingValue(
          text: source.replaceRange(
            selection.start,
            selection.end,
            replacement,
          ),
          selection: TextSelection.collapsed(
            offset: selection.start + replacement.length,
          ),
        );

        expect(formatter.formatEditUpdate(old, proposed), proposed);
      }
    });

    test('rejects partial, collapsed and invalid quote selections', () {
      final bodyStart = source.indexOf('words');
      final proposed = TextEditingValue(
        text: source.replaceFirst('words', 'rewritten'),
        selection: TextSelection.collapsed(offset: bodyStart + 9),
      );
      for (final selection in [
        TextSelection(baseOffset: bodyStart, extentOffset: bodyStart + 5),
        TextSelection(baseOffset: quote.start + 1, extentOffset: quote.end),
        TextSelection(baseOffset: quote.end - 1, extentOffset: quote.start),
        TextSelection.collapsed(offset: quote.start),
        TextSelection.collapsed(offset: bodyStart),
        const TextSelection.collapsed(offset: -1),
        TextSelection(baseOffset: -1, extentOffset: quote.end),
        TextSelection(baseOffset: quote.start, extentOffset: source.length + 1),
        const TextSelection(baseOffset: source.length + 1, extentOffset: 0),
      ]) {
        final old = TextEditingValue(text: source, selection: selection);

        expect(
          formatter.formatEditUpdate(old, proposed),
          old,
          reason: '$selection',
        );
      }
    });

    test('a whole quote selection does not authorize edits outside it', () {
      final old = TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: quote.start,
          extentOffset: quote.end,
        ),
      );
      for (final text in [
        source
            .replaceFirst('words', 'rewritten')
            .replaceFirst('Before', 'Edit'),
        source.replaceFirst('words', 'rewritten').replaceFirst('After', 'Edit'),
      ]) {
        final proposed = TextEditingValue(
          text: text,
          selection: const TextSelection.collapsed(offset: 0),
        );

        expect(formatter.formatEditUpdate(old, proposed), old);
      }
    });

    test('unchanged text outside the selection cannot overlap', () {
      const source = 'a\n[quote]\nwords\n[/quote]\na\n[\n';
      final quote = parseComposerQuotes(source).single;
      final old = TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: quote.start,
          extentOffset: quote.end,
        ),
      );
      // Both outside fragments match, but the proposal is too short to hold
      // both of them. Its shared `[` must not authorize a quote body edit.
      const proposed = TextEditingValue(
        text: 'a\n[\n',
        selection: TextSelection.collapsed(offset: 3),
      );

      expect(formatter.formatEditUpdate(old, proposed), old);
    });

    test('selecting one quote cannot authorize rewriting another', () {
      const source =
          '[quote="sam"]\nFirst\n[/quote]\n\n'
          '[quote="pat"]\nSecond\n[/quote]';
      final quote = parseComposerQuotes(source).first;
      final old = TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: quote.start,
          extentOffset: quote.end,
        ),
      );
      final proposed = TextEditingValue(
        text: source.replaceFirst('Second', 'Rewritten'),
        selection: TextSelection.collapsed(offset: quote.start),
      );

      expect(formatter.formatEditUpdate(old, proposed), old);
    });

    test('rejects a replacement that only partly selects another quote', () {
      const source =
          '[quote="sam"]\nFirst\n[/quote]\n\n'
          '[quote="pat"]\nSecond\n[/quote]';
      final quotes = parseComposerQuotes(source);
      final selection = TextSelection(
        baseOffset: quotes.first.start,
        extentOffset: quotes.last.end - 1,
      );
      final old = TextEditingValue(text: source, selection: selection);
      final proposed = TextEditingValue(
        text: source.replaceRange(selection.start, selection.end, '['),
        selection: const TextSelection.collapsed(offset: 1),
      );

      expect(formatter.formatEditUpdate(old, proposed), old);
    });

    test('preserves composition when replacing a whole selected quote', () {
      final old = TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: quote.start,
          extentOffset: quote.end,
        ),
      );
      final proposed = TextEditingValue(
        text: source.replaceRange(quote.start, quote.end, '['),
        selection: TextSelection.collapsed(offset: quote.start + 1),
        composing: TextRange(start: quote.start, end: quote.start + 1),
      );

      expect(formatter.formatEditUpdate(old, proposed), proposed);
    });

    test('composition cannot mutate a hidden quote body', () {
      final bodyStart = source.indexOf('words');
      final old = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: bodyStart + 5),
        composing: TextRange(start: bodyStart, end: bodyStart + 5),
      );
      final proposed = TextEditingValue(
        text: source.replaceFirst('words', 'rewritten'),
        selection: TextSelection.collapsed(offset: bodyStart + 9),
        composing: TextRange(start: bodyStart, end: bodyStart + 9),
      );

      expect(formatter.formatEditUpdate(old, proposed), old);
    });

    test('preserves composing edits beside an unselected quote', () {
      final old = TextEditingValue(
        text: source,
        selection: const TextSelection.collapsed(offset: source.length),
        composing: TextRange(start: quote.end, end: source.length),
      );
      final proposed = TextEditingValue(
        text: '${source}word',
        selection: const TextSelection.collapsed(offset: source.length + 4),
        composing: TextRange(start: quote.end, end: source.length + 4),
      );

      expect(formatter.formatEditUpdate(old, proposed), proposed);
    });
  });
}
