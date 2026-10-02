import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final cooking = OfflineCookingService();
  tearDownAll(cooking.dispose);

  Future<void> expectCookedLink(
    String source, {
    required String anchor,
    required String url,
  }) async {
    final result = await cooking.cook(
      CookingRequest(
        raw: source,
        snapshot: CookingSnapshot(
          siteId: 'test-site',
          accountId: 'test-account',
        ),
      ),
    );
    expect(result.failure, isNull);
    final links = html.parseFragment(result.html).querySelectorAll('a');
    expect(links, hasLength(1), reason: result.html);
    expect(links.single.text, anchor);
    expect(links.single.attributes['href'], url);
  }

  Future<ComposerController> openDialog(
    WidgetTester tester,
    String source, {
    ComposerLinkBlock? link,
  }) async {
    final composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-real-topic',
        topicTitle: 'A real topic',
      ),
    );
    addTearDown(composer.dispose);
    composer.text.value = TextEditingValue(
      text: source,
      selection: TextSelection(baseOffset: 0, extentOffset: source.length),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    unawaited(
      showComposerLinkDialog(
        context: tester.element(find.byType(Scaffold)),
        composer: composer,
        link: link,
      ),
    );
    await tester.pumpAndSettle();
    return composer;
  }

  Future<void> insert(WidgetTester tester) async {
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
    await tester.pumpAndSettle();
  }

  for (final anchor in [r'the [guide]', 'A]B', r'path\name']) {
    testWidgets('link dialog preserves literal label $anchor and destination', (
      tester,
    ) async {
      final composer = await openDialog(tester, anchor);
      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://example.com/a)b',
      );
      await insert(tester);
      await tester.runAsync(
        () => expectCookedLink(
          composer.raw,
          anchor: anchor,
          url: 'https://example.com/a%29b',
        ),
      );
      final link = parseComposerLinks(
        composer.raw,
        enableLinkify: false,
      ).single;
      expect(link.source, composer.raw);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('link dialog escapes the URL used as a fallback label', (
    tester,
  ) async {
    final composer = await openDialog(tester, '');
    const url = 'https://example.com/a[b])';
    await tester.enterText(
      find.byKey(const ValueKey('composer-link-url')),
      url,
    );
    await insert(tester);
    await tester.runAsync(
      () => expectCookedLink(
        composer.raw,
        anchor: url,
        url: 'https://example.com/a%5Bb%5D%29',
      ),
    );
    expect(
      parseComposerLinks(composer.raw, enableLinkify: false).single.source,
      composer.raw,
    );
  });

  for (final source in const [
    r'[A\]B](https://example.com/a\)b)',
    r'[the \[guide\]](https://example.com/a%29b)',
    '[Dart](https://en.wikipedia.org/wiki/Dart_(programming_language))',
  ]) {
    testWidgets('unchanged link dialog preserves source $source', (
      tester,
    ) async {
      final block = parseComposerLinks(source, enableLinkify: false).single;
      final composer = await openDialog(tester, source, link: block);
      await insert(tester);
      expect(composer.raw, source);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editing a link label preserves its editable Markdown escapes', (
    tester,
  ) async {
    const source = r'[A\]B](https://example.com/a\)b)';
    final block = parseComposerLinks(source, enableLinkify: false).single;
    final composer = await openDialog(tester, source, link: block);
    final anchorField = find.byKey(const ValueKey('composer-link-anchor'));
    final urlField = find.byKey(const ValueKey('composer-link-url'));
    expect(tester.widget<DInput>(anchorField).controller!.text, r'A\]B');
    expect(
      tester.widget<DInput>(urlField).controller!.text,
      r'https://example.com/a\)b',
    );
    await tester.enterText(anchorField, r'A\]B [updated]');
    await insert(tester);
    expect(composer.raw, r'[A\]B \[updated\]](https://example.com/a\)b)');
    await tester.runAsync(
      () => expectCookedLink(
        composer.raw,
        anchor: 'A]B [updated]',
        url: 'https://example.com/a)b',
      ),
    );
  });

  testWidgets('editing a destination preserves the existing label source', (
    tester,
  ) async {
    const source = r'[A\]B](https://example.com/a\)b)';
    final block = parseComposerLinks(source, enableLinkify: false).single;
    final composer = await openDialog(tester, source, link: block);
    await tester.enterText(
      find.byKey(const ValueKey('composer-link-url')),
      r'https://example.com/a\)b/new)path',
    );
    await insert(tester);
    expect(composer.raw, r'[A\]B](https://example.com/a\)b/new%29path)');
    await tester.runAsync(
      () => expectCookedLink(
        composer.raw,
        anchor: 'A]B',
        url: 'https://example.com/a)b/new%29path',
      ),
    );
  });
}
