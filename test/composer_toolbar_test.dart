import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/material.dart';
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

    for (final mark in [ComposerMark.bold, ComposerMark.italic]) {
      for (final (leading, trailing) in [
        (' ', ''),
        ('', ' '),
        (' ', ' '),
        ('\t', '\t'),
        ('\n', '\n'),
      ]) {
        test('${mark.name} leaves boundary ${jsonEncode([leading, trailing])} '
            'outside repeated toggles', () {
          final source = 'say ${leading}hello$trailing now';
          open(source);
          composer.text.selection = TextSelection(
            baseOffset: 4,
            extentOffset: source.length - 4,
          );

          composer.toggleMark(mark);

          expect(
            composer.text.text,
            'say $leading${mark.marker}hello${mark.marker}$trailing now',
          );
          final contentStart = 4 + leading.length + mark.marker.length;
          expect(
            composer.text.selection,
            TextSelection(
              baseOffset: contentStart,
              extentOffset: contentStart + 5,
            ),
          );

          composer.toggleMark(mark);

          expect(composer.text.text, source);
          expect(
            composer.text.selection,
            TextSelection(
              baseOffset: 4 + leading.length,
              extentOffset: 9 + leading.length,
            ),
          );
        });
      }
    }

    test('composes multiple marks inside selected boundary whitespace', () {
      open('say \thello \nnow');
      composer.text.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 12,
      );

      composer.toggleMark(ComposerMark.bold);
      composer.toggleMark(ComposerMark.italic);

      expect(composer.text.text, 'say \t***hello*** \nnow');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 8, extentOffset: 13),
      );
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

    test('keeps selected literal ticks intact through repeated Cmd+E', () {
      open('say a`b now');
      const selection = TextSelection(baseOffset: 4, extentOffset: 7);
      composer.text.selection = selection;

      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say ``a`b`` now');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 6, extentOffset: 9),
      );

      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say a`b now');
      expect(composer.text.selection, selection);
    });

    test('keeps boundary padding outside a reversed inline selection', () {
      open('say `hello now');
      const selection = TextSelection(baseOffset: 10, extentOffset: 4);
      composer.text.selection = selection;

      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say `` `hello `` now');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 13, extentOffset: 7),
      );

      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say `hello now');
      expect(composer.text.selection, selection);
    });

    test('unwraps an existing selected multi-backtick span', () {
      open('say ``` a``b` ``` now');
      composer.text.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 17,
      );

      composer.toggleSelectedInlineCode();

      expect(composer.text.text, 'say a``b` now');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 4, extentOffset: 9),
      );
    });

    test('ignores inline code when the field has no valid selection', () {
      open('say hello');
      final original = composer.text.value;

      composer.toggleSelectedInlineCode();

      expect(composer.text.value, original);
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
      composer.toggleSelectedInlineCode();

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
      composer.toggleSelectedInlineCode();

      expect(composer.text.text, source);
    });
  });

  group('composerLinkValue', () {
    test('replaces the captured selection with a markdown link', () {
      open('visit Discourse today');
      const selection = TextSelection(baseOffset: 6, extentOffset: 15);

      final value = composerLinkValue(
        current: composer.text.value,
        expectedText: composer.text.text,
        selection: selection,
        url: 'https://discourse.org',
        anchor: 'Discourse',
      );

      expect(value, isNotNull);
      expect(value!.text, 'visit [Discourse](https://discourse.org) today');
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

  testWidgets('editing a projected Wikipedia link replaces its full source', (
    tester,
  ) async {
    const url = 'https://en.wikipedia.org/wiki/Dart_(programming_language)';
    const source = 'Read [Dart]($url) now.';
    open(source);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final projection = const ComposerLinkSyntaxPolicy().parse(source).single;
    final editing = projection.edit(
      tester.element(find.byType(Scaffold)),
      composer,
    );
    await tester.pumpAndSettle();
    final urlField = find.byKey(const ValueKey('composer-link-url'));
    expect(tester.widget<DInput>(urlField).controller!.text, url);
    expect(
      tester
          .widget<DInput>(find.byKey(const ValueKey('composer-link-anchor')))
          .controller!
          .text,
      'Dart',
    );

    await tester.enterText(urlField, 'https://dart.dev');
    await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
    await tester.pumpAndSettle();
    await editing;

    const expected = 'Read [Dart](https://dart.dev) now.';
    expect(composer.raw, expected);
    expect(
      composer.text.selection,
      TextSelection.collapsed(offset: expected.indexOf(' now.')),
    );
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
      const source =
          r'\[escaped](https://example.com) '
          '`[inline](https://example.com)`\n\n'
          '```\n[block](https://example.com)\n```';

      expect(parseComposerLinks(source, enableLinkify: false), isEmpty);
    });

    test('linkifies fuzzy domains, protocol URLs, and email like core', () {
      open('');
      const source =
          'Try google.fr/path?q=one, https://example.test/a and '
          'team@discourse.org.';

      final links = parseComposerLinks(source);

      expect(links.map((link) => (link.source, link.url, link.kind)), [
        (
          'google.fr/path?q=one',
          'http://google.fr/path?q=one',
          ComposerLinkKind.linkify,
        ),
        (
          'https://example.test/a',
          'https://example.test/a',
          ComposerLinkKind.linkify,
        ),
        (
          'team@discourse.org',
          'mailto:team@discourse.org',
          ComposerLinkKind.linkify,
        ),
      ]);
    });

    test('uses the configured fuzzy TLDs but always links protocols', () {
      open('');
      const source =
          'www.cnn.com test.it http://test.com https://test.ab https://a';

      final links = parseComposerLinks(source, linkifyTlds: const ['it']);

      expect(links.map((link) => link.source), [
        'test.it',
        'http://test.com',
        'https://test.ab',
        'https://a',
      ]);
      expect(parseComposerLinks(source, enableLinkify: false), isEmpty);
    });

    test('keeps punctuation out and balanced URL parentheses in', () {
      open('');
      const source =
          '(google.fr), http://en.wikipedia.org/wiki/The_Dark_Knight_(film).';

      final links = parseComposerLinks(source);

      expect(links.map((link) => link.source), [
        'google.fr',
        'http://en.wikipedia.org/wiki/The_Dark_Knight_(film)',
      ]);
    });

    test(
      'does not linkify code, markdown links, images, references, or HTML',
      () {
        open('');
        const source =
            '`google.fr` [google.fr](https://google.fr) '
            '![google.fr](https://google.fr/logo.png)\n'
            '[ref]: https://google.fr\n'
            '<a href="https://google.fr">site</a>';

        final links = parseComposerLinks(source);

        expect(links, hasLength(1));
        expect(links.single.kind, ComposerLinkKind.markdown);
        expect(links.single.source, '[google.fr](https://google.fr)');
      },
    );
  });
}
