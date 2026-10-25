import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'package:html/dom.dart' as dom;

import 'support/fakes.dart';

const _site = 'https://forum.example/community';
const _id = 'heading--destination';

String _document({String href = '#$_id', bool block = false, int count = 60}) =>
    '${block ? '<a href="$href"><div>Jump to section</div></a>' : '<p><a href="$href">Jump to section</a></p>'}'
    '${List.filled(count, '<p>Paragraph before destination.</p>').join()}'
    '<h2 id="$_id">Destination heading</h2><p>Last paragraph.</p>';

Widget _host(
  Widget child, {
  ScrollController? scroll,
  bool ownsScroll = true,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: ownsScroll
        ? SingleChildScrollView(controller: scroll, child: child)
        : child,
  ),
);

Future<void> _clickLink(
  WidgetTester tester, {
  Finder? within,
  int buttons = kPrimaryMouseButton,
}) async {
  final links = find.text('Jump to section', findRichText: true);
  final link = within == null
      ? links
      : find.descendant(of: within, matching: links);
  final paragraph = tester.renderObject<RenderParagraph>(link.first);
  final start = paragraph.text.toPlainText().indexOf('Jump to section');
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + 4),
  );
  expect(boxes, isNotEmpty);
  await tester.tapAt(
    paragraph.localToGlobal(boxes.first.toRect().center),
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await tester.pumpAndSettle();
}

class _HiddenProgressiveContent implements SitePlugin, CookedElementPlugin {
  @override
  String get name => 'hidden-progressive-content';

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      element.classes.contains('hidden-progressive')
      ? Offstage(
          child: TickerMode(
            enabled: false,
            child: CookedHtml(
              html: _document(count: 500),
              siteUrl: siteUrl,
              buildAsync: false,
              renderMode: const ProgressiveHtmlMode(),
            ),
          ),
        )
      : null;
}

void main() {
  late List<String> launched;
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  setUp(() {
    launched = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.startsWith('launch')) {
            launched.add((call.arguments as Map)['url'] as String);
          }
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final native in [false, true]) {
    for (final block in [false, true]) {
      testWidgets(
        '${native ? 'CookedHtml' : 'package control'} ${block ? 'block' : 'inline'} fragment scrolls locally',
        (tester) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final html = _document(block: block);
          await tester.pumpWidget(
            _host(
              native
                  ? CookedHtml(html: html, siteUrl: _site, buildAsync: false)
                  : HtmlWidget(
                      html,
                      baseUrl: Uri.parse(_site),
                      buildAsync: false,
                    ),
              scroll: scroll,
            ),
          );
          await tester.pumpAndSettle();
          expect(scroll.offset, 0);
          await _clickLink(tester);
          expect(launched, isEmpty);
          expect(scroll.offset, greaterThan(0));
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final href in [
    '#heading--missing',
    '$_site#$_id',
    '/t/other/42#$_id',
    'https://elsewhere.example/#$_id',
  ]) {
    testWidgets('unhandled or nonlocal $href keeps normal navigation', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          CookedHtml(
            html: _document(href: href),
            siteUrl: _site,
            buildAsync: false,
          ),
          scroll: scroll,
        ),
      );
      await tester.pumpAndSettle();
      await _clickLink(tester);
      expect(scroll.offset, 0);
      expect(launched, [Uri.parse(_site).resolve(href).toString()]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('percent-encoded fragment identifies the local heading', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        CookedHtml(
          html: _document(href: '#heading--%64estination'),
          siteUrl: _site,
          buildAsync: false,
        ),
        scroll: scroll,
      ),
    );
    await tester.pumpAndSettle();
    await _clickLink(tester);
    expect(launched, isEmpty);
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('two cooked documents keep duplicate anchor IDs scoped', (
    tester,
  ) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    const secondKey = ValueKey('second-document');
    await tester.pumpWidget(
      _host(
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: first,
                child: CookedHtml(
                  html: _document(),
                  siteUrl: _site,
                  buildAsync: false,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: second,
                child: CookedHtml(
                  key: secondKey,
                  html: _document(),
                  siteUrl: _site,
                  buildAsync: false,
                ),
              ),
            ),
          ],
        ),
        ownsScroll: false,
      ),
    );
    await tester.pumpAndSettle();
    await _clickLink(tester, within: find.byKey(secondKey));
    expect(launched, isEmpty);
    expect(first.offset, 0);
    expect(second.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lazy list reveals an initially unmounted local heading', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookedHtml(
          html: _document(count: 150),
          siteUrl: _site,
          buildAsync: false,
          renderMode: RenderMode.listView,
        ),
        ownsScroll: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Destination heading', findRichText: true), findsNothing);
    await _clickLink(tester);
    expect(launched, isEmpty);
    expect(
      tester
          .getRect(find.text('Destination heading', findRichText: true))
          .overlaps(const Rect.fromLTWH(0, 0, 800, 600)),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'progressively mounted document retains local anchor navigation',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          CookedHtml(
            html: _document(count: 150),
            siteUrl: _site,
            buildAsync: false,
            renderMode: const ProgressiveHtmlMode(),
          ),
          scroll: scroll,
        ),
      );
      await tester.pumpAndSettle();
      await _clickLink(tester);
      expect(launched, isEmpty);
      expect(scroll.offset, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an early progressive click waits for its unmounted heading', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        CookedHtml(
          html: _document(count: 500),
          siteUrl: _site,
          buildAsync: false,
          renderMode: const ProgressiveHtmlMode(),
        ),
        scroll: scroll,
      ),
    );
    expect(find.text('Destination heading', findRichText: true), findsNothing);
    await _clickLink(tester);
    expect(launched, isEmpty);
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final block in [false, true]) {
    testWidgets(
      '${block ? 'block' : 'inline'} fragment middle click retains navigation intent',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _host(
            CookedHtml(
              html: _document(block: block),
              siteUrl: _site,
              buildAsync: false,
            ),
            scroll: scroll,
          ),
        );
        await tester.pumpAndSettle();
        await _clickLink(tester, buttons: kMiddleMouseButton);
        expect(scroll.offset, 0);
        expect(launched, ['$_site#$_id']);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('a hidden nested document cannot delay its parent anchor', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        CookedHtml(
          html:
              '<div class="hidden-progressive"></div>${_document(count: 150)}',
          siteUrl: _site,
          registry: PluginRegistry([_HiddenProgressiveContent()]),
          buildAsync: false,
          renderMode: const ProgressiveHtmlMode(),
        ),
        scroll: scroll,
      ),
    );
    await tester.pumpAndSettle();
    await _clickLink(tester);
    expect(launched, isEmpty);
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dispose in [false, true]) {
    testWidgets(
      'pending progressive click is discarded on ${dispose ? 'dispose' : 'replacement'}',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _host(
            CookedHtml(
              html: _document(count: 500),
              siteUrl: _site,
              buildAsync: false,
              renderMode: const ProgressiveHtmlMode(),
            ),
            scroll: scroll,
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Jump to section', findRichText: true),
        );
        final box = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .first;
        await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
        await tester.pumpWidget(
          dispose
              ? const SizedBox.shrink()
              : _host(
                  CookedHtml(
                    html: _document().replaceFirst(
                      'Jump to section',
                      'New link',
                    ),
                    siteUrl: _site,
                    buildAsync: false,
                    renderMode: const ProgressiveHtmlMode(),
                  ),
                  scroll: scroll,
                ),
        );
        await tester.pumpAndSettle();
        expect(launched, isEmpty);
        if (!dispose) expect(scroll.offset, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final key in [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('modified fragment click with $key retains navigation intent', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _host(
          CookedHtml(html: _document(), siteUrl: _site, buildAsync: false),
          scroll: scroll,
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(key);
      await _clickLink(tester);
      await tester.sendKeyUpEvent(key);
      expect(scroll.offset, 0);
      expect(launched, ['$_site#$_id']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final block in [false, true]) {
    testWidgets(
      '${block ? 'block' : 'inline'} fragment context menu retains navigation intent',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          _host(
            CookedHtml(
              html: _document(block: block),
              siteUrl: _site,
              buildAsync: false,
            ),
            scroll: scroll,
          ),
        );
        await tester.pumpAndSettle();
        await _clickLink(tester, buttons: kSecondaryMouseButton);
        expect(launched, isEmpty);
        expect(scroll.offset, 0);
        await tester.tap(find.text('Open in new main tab'));
        await tester.pumpAndSettle();
        expect(launched, ['$_site#$_id']);
        expect(scroll.offset, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final wrapper in ['quote', 'details']) {
    testWidgets('nested $wrapper uses its own local anchor registry', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final body = _document();
      final html = wrapper == 'quote'
          ? '<blockquote>$body</blockquote>'
          : '<details open><summary>Sections</summary>$body</details>';
      await tester.pumpWidget(
        _host(
          CookedHtml(html: html, siteUrl: _site, buildAsync: false),
          scroll: scroll,
        ),
      );
      await tester.pumpAndSettle();
      await _clickLink(tester);
      expect(launched, isEmpty);
      expect(scroll.offset, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('actual shell keeps heading clicks in the current document', (
    tester,
  ) async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('forum.example')]),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: _host(
          CookedHtml(html: _document(), siteUrl: _site, buildAsync: false),
          scroll: scroll,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final original = controller.currentContent;
    await _clickLink(tester);
    expect(launched, isEmpty);
    expect(scroll.offset, greaterThan(0));
    expect(controller.currentContent, same(original));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
