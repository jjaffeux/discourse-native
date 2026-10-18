import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/cooked_render_context.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _topic = PluginContainingTopic(id: 7, slug: 'topic', archived: false);

class _Probe implements SitePlugin, PostBodyPlugin, CookedInlinePlugin {
  _Probe([this.prefix = 'Prefix']);
  final String prefix;
  int calls = 0;
  final contexts = <PluginPostBodyContext>[];

  @override
  String get name => 'cooked-context-probe';

  @override
  Widget? postBodyElement(PluginPostBodyContext context, dom.Element element) {
    calls++;
    if (!element.classes.contains('probe')) return null;
    contexts.add(context);
    return Text(
      '${context.post.id}:${context.post.postNumber} '
      '${Localizations.localeOf(context.buildContext).toLanguageTag()}',
    );
  }

  @override
  CookedInlinePrefix? cookedInlinePrefix(dom.Element element) =>
      element.classes.contains('prefix')
      ? CookedInlinePrefix(child: Text(prefix))
      : null;
}

class _CountingElements implements SitePlugin, CookedElementPlugin {
  int calls = 0;
  @override
  String get name => 'counting-cooked-context';
  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    calls++;
    return null;
  }
}

class _ActionShell extends ShellController {
  _ActionShell()
    : super(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
        ]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );

  Post? toggledPost;
  PostChecklistTarget? toggledTarget;

  @override
  Future<String?> togglePostChecklist({
    required String siteUrl,
    required int topicId,
    required Post post,
    required PostChecklistTarget target,
    required bool checked,
  }) async {
    toggledPost = post;
    toggledTarget = target;
    return null;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Post post,
  required PluginRegistry registry,
  ShellController? shell,
  String site = _site,
  ThemeData? theme,
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  Widget body = SingleChildScrollView(
    child: CookedHtml(
      html: post.cooked,
      post: post,
      registry: registry,
      siteUrl: site,
      containingTopic: _topic,
      buildAsync: false,
    ),
  );
  if (shell != null) body = ShellScope(controller: shell, child: body);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Builder(
        builder: (context) => Localizations.override(
          context: context,
          locale: locale,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: body),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cached nested checkbox actions use the current post and source',
    (tester) async {
      final shell = _ActionShell();
      addTearDown(shell.dispose);
      await shell.load();
      const html =
          '<details open><summary>Tasks</summary><p>'
          '<span class="chcklst-box fa-square-o" data-chk-src="4:1"></span>'
          'Task</p></details>';
      const original = Post(
        id: 22,
        postNumber: 2,
        username: 'author',
        cooked: html,
        raw: '[ ] Task',
        canEdit: true,
      );
      final probe = _CountingElements();
      final registry = PluginRegistry([probe]);
      await _pump(tester, post: original, registry: registry, shell: shell);
      final calls = probe.calls;
      expect(shell.instanceFor(_site)?.isConnected, isTrue);
      final checkbox = tester.widget<DCheckbox>(find.byType(DCheckbox));
      final latest = original.copyWith(
        likeCount: 2,
        version: 3,
        raw: 'New raw',
      );
      await _pump(tester, post: latest, registry: registry, shell: shell);
      expect(probe.calls, calls);
      checkbox.onChanged!(true);
      await tester.pump();
      expect(shell.toggledPost, same(latest));
      expect(shell.toggledTarget?.toggle(true), {
        'checkbox_index': 0,
        'checkbox_source': '4:1',
        'checked': true,
      });
      final bodies = tester
          .widgetList<HtmlWidget>(find.byType(HtmlWidget))
          .map(
            (widget) =>
                (widget.rebuildTriggers.last as CookedRenderInputs).body,
          )
          .toList();
      expect(bodies.length, greaterThan(1));
      expect(bodies.skip(1), everyElement(same(bodies[1])));
      expect(bodies, everyElement(equals(bodies.first)));
    },
  );

  testWidgets(
    'nested plugin identity, locale and text metrics invalidate bodies',
    (tester) async {
      const html =
          '<details open><summary>Content</summary><div class="probe"></div>'
          '<p><code>code</code></p></details>';
      const original = Post(
        id: 1,
        postNumber: 1,
        username: 'author',
        cooked: html,
      );
      final probe = _Probe();
      final registry = PluginRegistry([probe]);
      await _pump(tester, post: original, registry: registry);
      expect(find.text('1:1 en'), findsOneWidget);
      final calls = probe.calls;
      const second = Post(
        id: 2,
        postNumber: 8,
        username: 'author',
        cooked: html,
      );
      await _pump(tester, post: second, registry: registry);
      expect(find.text('2:8 en'), findsOneWidget);
      expect(probe.calls, greaterThan(calls));
      expect(probe.contexts.last.siteUrl, _site);
      expect(probe.contexts.last.topic, _topic);
      await _pump(
        tester,
        post: second,
        registry: registry,
        locale: const Locale('en', 'GB'),
        scale: 1.5,
        theme: AppTheme.dark,
      );
      expect(find.text('2:8 en-GB'), findsOneWidget);
      final htmlWidgets = tester.widgetList<HtmlWidget>(
        find.byType(HtmlWidget),
      );
      expect(
        htmlWidgets.last.textStyle?.color,
        AppTheme.dark.textTheme.bodyLarge?.color,
      );
      expect(
        (htmlWidgets.last.rebuildTriggers.last as CookedRenderInputs).textScaler
            .scale(10),
        15,
      );
    },
  );

  testWidgets('factory context changes retain an expanded disclosure', (
    tester,
  ) async {
    const html =
        '<details><summary>Content</summary><p><span class="prefix">Text</span>'
        '<img src="/image.png" width="10" height="10"></p></details>';
    const post = Post(id: 1, postNumber: 1, username: 'author', cooked: html);
    await _pump(
      tester,
      post: post,
      registry: PluginRegistry([_Probe('First prefix')]),
    );
    await tester.tap(find.text('Content'));
    await tester.pumpAndSettle();
    expect(find.text('First prefix'), findsOneWidget);
    expect(tester.widget<SiteImage>(find.byType(SiteImage)).siteUrl, _site);
    final disclosure = tester.state(find.byType(DAccordion<int>));
    await _pump(
      tester,
      post: post,
      registry: PluginRegistry([_Probe('Second prefix')]),
      site: 'https://other.example',
    );
    expect(tester.state(find.byType(DAccordion<int>)), same(disclosure));
    expect(find.text('Second prefix'), findsOneWidget);
    expect(find.text('First prefix'), findsNothing);
    final image = tester.widget<SiteImage>(find.byType(SiteImage));
    expect(image.siteUrl, 'https://other.example');
    expect(image.url, 'https://other.example/image.png');
  });

  testWidgets('table captions preserve their inherited text metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CookedHtml(
            html:
                '<table><caption>Caption</caption><tr><th>Header</th></tr><tr><td>Cell</td></tr></table>',
            textStyle: TextStyle(fontSize: 31, color: Colors.red),
            buildAsync: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final caption = find.byType(DTableCaption);
    final inherited = DefaultTextStyle.of(tester.element(caption)).style;
    final rendered = tester.widget<HtmlWidget>(
      find.descendant(of: caption, matching: find.byType(HtmlWidget)),
    );
    expect(rendered.textStyle?.fontSize, inherited.fontSize);
    expect(rendered.textStyle?.color, inherited.color);
    expect(rendered.textStyle?.fontSize, isNot(31));
  });

  test(
    'document fragments preserve authority without reindexing their contents',
    () {
      const html =
          '<p><span class="chcklst-box fa-square-o" data-chk-src="0:0"></span>First</p>'
          '<p><span class="chcklst-box fa-square-o" data-chk-src="1:0"></span>Second</p>';
      final document = CookedDocument(html, savedHtml: html);
      final parsed = document.checklist;
      expect(CookedDocument(html, savedHtml: html).checklist, same(parsed));
      final fragment = document.fragment(
        '<span data-native-checklist-index="1"></span>',
      );
      expect(fragment.document, same(document));
      expect(document.fragment(fragment.html), fragment);
      final content = document.bind(
        (context, fragment, style) => const SizedBox.shrink(),
      );
      final checkbox = dom.Element.tag('span')
        ..attributes[PostChecklistDocument.indexAttribute] = '1';
      expect(content.targetFor(checkbox)?.source, '1:0');
      expect(
        CookedDocument(html, savedHtml: html, revisionDiff: true).checklist,
        isNull,
      );
    },
  );
}
