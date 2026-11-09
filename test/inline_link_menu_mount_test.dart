// ignore_for_file: avoid_print

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

/// A paragraph's inline link menu answers secondary presses only, so a reader
/// who never right-clicks a paragraph must not pay for a closed menu under
/// every one of them.
void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    final name = platform.name.toLowerCase();
    testWidgets('$name: linked paragraphs mount within the topic budget', (
      tester,
    ) async {
      await _openTopic(tester, platform);
      final bodies = find
          .byType(CookedHtml, skipOffstage: false)
          .evaluate()
          .length;
      expect(bodies, greaterThan(3));

      final (:renderObjects, :elements) = _count(
        find.byType(TopicView, skipOffstage: false).evaluate().single,
      );
      print(
        'PERF_PROOF link-context-menu '
        '${name}_render_objects=$renderObjects '
        '${name}_elements=$elements '
        '${name}_bodies=$bodies',
      );

      expect(renderObjects, lessThanOrEqualTo(_renderObjectBudget[platform]!));
      expect(elements, lessThanOrEqualTo(_elementBudget[platform]!));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('the first right-click on a link opens its menu at the pointer', (
    tester,
  ) async {
    final controller = await _openTopic(tester, TargetPlatform.macOS);
    controller.desktopTopicTabs = true;
    await tester.pumpAndSettle();

    final point = _linkPoint(tester, 'first topic');
    await tester.tapAt(
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(DContextMenuContent), findsOneWidget);
    final popup = tester.getRect(find.byType(DContextMenuContent));
    expect(popup.left, greaterThanOrEqualTo(point.dx - 2));
    expect(popup.top, greaterThanOrEqualTo(point.dy));

    await tester.tap(find.text('Open in main panel'));
    await tester.pumpAndSettle();
    expect(controller.currentContent?.topicId, 42);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a second right-click moves the menu to the other link', (
    tester,
  ) async {
    await _openTopic(tester, TargetPlatform.macOS);

    for (final text in ['first topic', 'second topic']) {
      final point = _linkPoint(tester, text);
      await tester.tapAt(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DContextMenuContent), findsOneWidget);
      final popup = tester.getRect(find.byType(DContextMenuContent));
      expect(popup.left, greaterThanOrEqualTo(point.dx - 2));
      expect(popup.top, greaterThanOrEqualTo(point.dy));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DContextMenuContent), findsNothing);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a right-click beside a link opens nothing', (tester) async {
    await _openTopic(tester, TargetPlatform.macOS);

    final paragraph = _paragraph(tester, 'first topic');
    final plain = paragraph.text.toPlainText().indexOf('Read');
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: plain, extentOffset: plain + 4),
        )
        .first;
    await tester.tapAt(
      paragraph.localToGlobal(box.toRect().center),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(DContextMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'a right-click on the right half of a link glyph opens its menu',
    (tester) async {
      final controller = await _openTopic(tester, TargetPlatform.macOS);
      controller.desktopTopicTabs = true;
      await tester.pumpAndSettle();

      final paragraph = _paragraph(tester, 'first topic');
      final glyph = _glyph(paragraph, _linkEnd(paragraph, 'first topic') - 1);
      await tester.tapAt(
        paragraph.localToGlobal(
          Offset(glyph.right - glyph.width / 4, glyph.center.dy),
        ),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.byType(DContextMenuContent), findsOneWidget);
      await tester.tap(find.text('Open in main panel'));
      await tester.pumpAndSettle();
      expect(controller.currentContent?.topicId, 42);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a right-click past a link that ends its line opens nothing', (
    tester,
  ) async {
    await _openTopic(tester, TargetPlatform.macOS);

    final paragraph = _paragraph(tester, 'second topic');
    final end = _linkEnd(paragraph, 'second topic');
    expect(end, paragraph.text.toPlainText().length);
    final glyph = _glyph(paragraph, end - 1);
    final past = Offset(glyph.right + glyph.width, glyph.center.dy);
    expect(paragraph.size.contains(past), isTrue);
    await tester.tapAt(
      paragraph.localToGlobal(past),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(DContextMenuContent), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

/// The after-numbers of the proof, so a regression fails here.
const _renderObjectBudget = {
  TargetPlatform.macOS: 1098,
  TargetPlatform.iOS: 1201,
};
const _elementBudget = {TargetPlatform.macOS: 2841, TargetPlatform.iOS: 3143};

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(id: 7, username: 'reader');
const _posts = 24;

String _paragraphHtml(int post, int index) =>
    '<p>Post $post paragraph $index with a '
    '<a href="https://example.com/$post/$index">regular link</a>, some '
    '<strong>bold</strong> and <em>italic</em> text, an '
    '<code>inline_code()</code> span, and enough prose to wrap over two or '
    'three lines in the reading lane.</p>';

Post _post(int id) => Post(
  id: id,
  postNumber: id,
  username: 'sam',
  userId: 9,
  createdAt: DateTime.utc(2026, 9, 1, 0, id),
  cooked: id == 1
      ? '<p>Read <a href="/t/first/42">first topic</a> or '
            '<a href="/t/second/43">second topic</a></p>'
            '${_paragraphHtml(id, 1)}'
      : [
          for (var index = 0; index < 4; index++) _paragraphHtml(id, index),
        ].join(),
);

({int renderObjects, int elements}) _count(Element root) {
  var renderObjects = 0;
  var elements = 0;
  void visit(Element element) {
    elements++;
    if (element is RenderObjectElement) renderObjects++;
    element.visitChildren(visit);
  }

  visit(root);
  return (renderObjects: renderObjects, elements: elements);
}

RenderParagraph _paragraph(
  WidgetTester tester,
  String linkText,
) => tester.renderObject<RenderParagraph>(
  find
      .byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(linkText),
      )
      .first,
);

Rect _glyph(RenderParagraph paragraph, int offset) => paragraph
    .getBoxesForSelection(
      TextSelection(baseOffset: offset, extentOffset: offset + 1),
    )
    .first
    .toRect();

int _linkEnd(RenderParagraph paragraph, String linkText) =>
    paragraph.text.toPlainText().indexOf(linkText) + linkText.length;

Offset _linkPoint(WidgetTester tester, String linkText) {
  final paragraph = _paragraph(tester, linkText);
  final start = paragraph.text.toPlainText().indexOf(linkText);
  return paragraph.localToGlobal(_glyph(paragraph, start).center);
}

Future<ShellController> _openTopic(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final mobile = platform == TargetPlatform.iOS;
  final size = mobile ? const Size(390, 3000) : const Size(1440, 3000);
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final byId = <int, Post>{for (var id = 1; id <= _posts; id++) id: _post(id)};
  final api = FakeDiscourseApi(
    user: _reader,
    feeds: {
      '/latest.json': [
        Topic(
          id: 7,
          title: 'A topic',
          slug: 'a-topic',
          bumpedAt: DateTime.utc(2026, 9, 1),
        ),
      ],
    },
    topics: {
      7: topicPayload(
        id: 7,
        title: 'A topic',
        posts: byId.values.toList(),
        canCreatePost: true,
      ),
      42: topicPayload(id: 42, title: 'First', posts: [_post(1)]),
    },
    postsById: byId,
  );
  final installed = PluginInstaller.install(bundledWidgetTestManifest);
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    mobileNavigationEnabled: mobile,
    plugins: installed,
  );
  addTearDown(() async {
    controller.dispose();
    await installed.close();
  });
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: const AdaptiveShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  await controller.loadTopic(7, 'a-topic');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  return controller;
}
