import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ComposerController composer;

  ComposerController open(String raw) {
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-real-topic',
        topicTitle: 'A real topic',
      ),
    );
    composer.text.text = raw;
    return composer;
  }

  tearDown(() {
    composer.dispose();
  });

  group('ComposerController.toggleMark', () {
    test('wraps the current selection in the requested mark', () {
      open('say hello');
      composer.text.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );

      composer.toggleMark(ComposerMark.bold);

      expect(composer.text.text, 'say **hello**');
    });

    test('composes multiple marks around the same selection', () {
      open('say hello');
      composer.text.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );

      composer.toggleMark(ComposerMark.bold);
      composer.toggleMark(ComposerMark.italic);

      expect(composer.text.text, 'say ***hello***');
    });

    test('removes an existing mark when toggled again', () {
      open('**say hello**');
      composer.text.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 13,
      );

      composer.toggleMark(ComposerMark.bold);

      expect(composer.text.text, 'say hello');
    });

    test('only toggles inline code around selected text', () {
      open('say hello');
      composer.text.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );

      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say `hello`');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 5, extentOffset: 10),
      );

      composer.text.selection = const TextSelection.collapsed(offset: 11);
      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say `hello`');
    });

    test('leaves a selected quote unchanged', () {
      const quote = '[quote="sam"]\nQuoted words.\n[/quote]';
      open(quote);
      composer.text.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: quote.length,
      );

      composer.toggleMark(ComposerMark.bold);
      composer.toggleMark(ComposerMark.italic);

      expect(composer.text.text, quote);
    });

    test('leaves a quote opening boundary unchanged', () {
      const quote = '[quote="sam"]\nQuoted words.\n[/quote]';
      const source = 'Before\n\n$quote';
      open(source);
      final quoteStart = source.indexOf('[quote');
      composer.text.selection = TextSelection.collapsed(offset: quoteStart);

      composer.toggleMark(ComposerMark.bold);
      expect(composer.text.text, source);

      composer.text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: quoteStart,
      );
      composer.toggleMark(ComposerMark.italic);

      expect(composer.text.text, source);
    });
  });

  group('composerLinkValue', () {
    test('replaces the captured selection with a markdown link', () {
      open('visit Discourse today');
      const selection = TextSelection(
        baseOffset: 6,
        extentOffset: 15,
      );

      final value = composerLinkValue(
        current: composer.text.value,
        expectedText: composer.text.text,
        selection: selection,
        url: 'https://discourse.org',
        anchor: 'Discourse',
      );

      expect(value, isNotNull);
      expect(
        value!.text,
        'visit [Discourse](https://discourse.org) today',
      );
      expect(value.selection.isCollapsed, isTrue);
      expect(value.selection.extentOffset, 40);
    });

    test('uses the URL as the anchor when no text is supplied', () {
      open('visit ');

      final value = composerLinkValue(
        current: composer.text.value,
        expectedText: composer.text.text,
        selection: const TextSelection.collapsed(offset: 6),
        url: 'https://discourse.org',
        anchor: '',
      );

      expect(
        value!.text,
        'visit [https://discourse.org](https://discourse.org)',
      );
    });

    test('does not apply a link to a stale editor value', () {
      open('selected');
      composer.text.text = 'changed';

      final value = composerLinkValue(
        current: composer.text.value,
        expectedText: 'selected',
        selection: const TextSelection(baseOffset: 0, extentOffset: 8),
        url: 'https://discourse.org',
        anchor: 'selected',
      );

      expect(value, isNull);
      expect(composer.text.text, 'changed');
    });
  });

  group('parseComposerLinks', () {
    test('finds prose links without treating images as links', () {
      open('');
      const source =
          'See [Discourse](https://discourse.org) and '
          '![logo](https://example.com/logo.png).';

      final links = parseComposerLinks(source);

      expect(links, hasLength(1));
      expect(links.single.anchor, 'Discourse');
      expect(links.single.url, 'https://discourse.org');
    });

    test('leaves escaped links and links in code as raw source', () {
      open('');
      const source = r'\[escaped](https://example.com) '
          '`[inline](https://example.com)`\n\n'
          '```\n[block](https://example.com)\n```';

      expect(parseComposerLinks(source), isEmpty);
    });
  });
}
