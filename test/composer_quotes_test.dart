import 'package:discourse_native/src/shell/composer_quotes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseComposerQuotes', () {
    test('a line of openers costs its length, not its square', () {
      // `_startsBlock` searched backwards for the line start at every `[`,
      // which on a line that has none walks to the top of the document. The
      // composer rescans on every keystroke, so that is felt as a freeze.
      const unit = '[quote="s, post:1, topic:2"] ';
      final small = _bestOf(() => parseComposerQuotes(unit * 800));
      final large = _bestOf(() => parseComposerQuotes(unit * 6400));

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
}

int _bestOf(void Function() body) {
  var best = -1;
  for (var run = 0; run < 3; run += 1) {
    final elapsed = Stopwatch()..start();
    body();
    elapsed.stop();
    if (best < 0 || elapsed.elapsedMicroseconds < best) {
      best = elapsed.elapsedMicroseconds;
    }
  }
  return best;
}
