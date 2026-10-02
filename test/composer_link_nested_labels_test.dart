import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  final cooking = OfflineCookingService();
  tearDownAll(cooking.dispose);

  for (final anchor in [
    'outer [inner]',
    'outer [middle [inner]]',
    'café [中文]',
    for (final depth in [32, 33]) '${'[' * depth}deep${']' * depth}',
  ]) {
    test('nested label agrees with cooked link text: $anchor', () async {
      final markdown = '[$anchor](https://example.test)';
      final source = '😀 Read $markdown now';
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
      final cooked = html.parseFragment(result.html).querySelectorAll('a');
      expect(cooked, hasLength(1), reason: result.html);
      expect(cooked.single.text, anchor);
      expect(cooked.single.attributes['href'], 'https://example.test');

      final link = parseComposerLinks(source).single;
      expect(link.kind, ComposerLinkKind.markdown);
      expect(link.anchor, anchor);
      expect(link.source, markdown);
      expect(link.start, source.indexOf(markdown));
      expect(link.end, source.indexOf(markdown) + markdown.length);
    });
  }

  testWidgets('a nested label projects one pill spanning the entire link', (
    tester,
  ) async {
    const markdown = '[outer [inner]](https://example.test)';
    const source = 'Read $markdown now';
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: source.length);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DInput(
            borderless: true,
            controller: controller,
            maxLines: null,
          ),
        ),
      ),
    );
    final pill = tester.widget<ComposerLinkPill>(find.byType(ComposerLinkPill));
    expect(pill.anchor, 'outer [inner]');
    expect(pill.url, 'https://example.test');
    final projection = const ComposerLinkSyntaxPolicy().parse(source).single;
    expect(projection.source, markdown);
    expect(projection.start, source.indexOf(markdown));
    expect(projection.end, source.indexOf(markdown) + markdown.length);
    expect(controller.text, source);
    expect(tester.takeException(), isNull);
  });
}
