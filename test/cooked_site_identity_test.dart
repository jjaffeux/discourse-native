import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_url.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'support/fakes.dart';

const sourceSite = 'https://source.example.com';
const selectedSite = 'https://selected.example.com';

List<String> watchBrowser(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launched;
}

Future<ShellController> pumpCookedFromSource(
  WidgetTester tester,
  String html, {
  FakeDiscourseApi? api,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('source.example.com'),
      instance('selected.example.com'),
    ]),
    api: api ?? FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CookedHtml(html: html, siteUrl: sourceSite),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

final class _RecordingUserCardApi extends FakeDiscourseApi {
  final List<String> sites = [];

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    sites.add(siteUrl);
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }
}

void main() {
  test('site URL resolution preserves the source origin', () {
    expect(resolveSiteUrl('/faq', sourceSite), '$sourceSite/faq');
    expect(
      resolveSiteUrl('//cdn.example.com/icon.png', 'http://localhost:3000'),
      'http://cdn.example.com/icon.png',
    );
    expect(
      resolveSiteUrl('mailto:team@example.com', sourceSite),
      'mailto:team@example.com',
    );
    expect(resolveSiteUrl('/faq', null), '/faq');
  });

  testWidgets('a persistent post keeps resolving links against its source', (
    tester,
  ) async {
    final launched = watchBrowser(tester);
    final controller = await pumpCookedFromSource(
      tester,
      '<p><a href="/faq">Source FAQ</a></p>',
    );

    controller.selectInstance(1);
    await tester.pump();
    expect(controller.currentInstance?.url, selectedSite);

    final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(renderer.baseUrl, Uri.parse(sourceSite));
    await renderer.onTapUrl!('/faq');

    expect(launched, ['$sourceSite/faq']);
    expect(controller.currentInstance?.url, selectedSite);
  });

  testWidgets('mention taps fetch the card from the post source site', (
    tester,
  ) async {
    final api = _RecordingUserCardApi();
    final controller = await pumpCookedFromSource(
      tester,
      '<p><a class="mention" href="/u/sam">@sam</a></p>',
      api: api,
    );

    controller.selectInstance(1);
    await tester.pump();
    expect(
      tester.widget<MentionPill>(find.byType(MentionPill)).siteUrl,
      sourceSite,
    );

    await tester.tap(find.text('@sam'));
    await tester.pump();

    expect(api.sites, [sourceSite]);
    expect(controller.currentInstance?.url, selectedSite);
  });

  testWidgets('category art and navigation use the source site', (
    tester,
  ) async {
    const html = '''
<p><a class="hashtag-cooked" href="/c/bug/5" data-type="category"
data-slug="bug" data-id="5" data-style-type="square">
<span class="hashtag-icon-placeholder"></span><span>bug</span></a></p>
''';
    final controller = await pumpCookedFromSource(tester, html);
    controller.store
      ..put(
        sourceSite,
        const TopicCategory(id: 5, name: 'Bug', color: '0088CC'),
      )
      ..put(
        selectedSite,
        const TopicCategory(id: 5, name: 'Bug', color: 'CC3300'),
      );
    controller.selectInstance(1);
    await tester.pump();

    final pill = tester.widget<HashtagPill>(find.byType(HashtagPill));
    final square = tester.widget<CategorySquare>(find.byType(CategorySquare));
    expect(pill.siteUrl, sourceSite);
    expect(square.color, const Color(0xFF0088CC));

    await tester.tap(find.text('bug'));
    await tester.pump();

    expect(controller.currentInstance?.url, sourceSite);
    expect(controller.currentContent?.feedPath, '/c/bug/5.json');
  });

  testWidgets('quotes and oneboxes retain the source through nested HTML', (
    tester,
  ) async {
    const html = '''
<aside class="quote" data-username="sam">
  <div class="title">sam:</div>
  <blockquote><p><a class="inline-onebox" href="/t/source-topic/42">
    Source topic</a></p></blockquote>
</aside>
<aside class="onebox" data-onebox-src="/about">
  <article class="onebox-body">
    <p><a class="mention" href="/u/alex">@alex</a></p>
  </article>
</aside>
''';
    await pumpCookedFromSource(tester, html);

    expect(
      tester.widget<QuoteBlock>(find.byType(QuoteBlock)).siteUrl,
      sourceSite,
    );
    expect(
      tester.widget<OneboxCard>(find.byType(OneboxCard)).siteUrl,
      sourceSite,
    );
    expect(
      tester.widget<MentionPill>(find.byType(MentionPill)).siteUrl,
      sourceSite,
    );
    expect(
      tester
          .widgetList<CookedHtml>(find.byType(CookedHtml))
          .map((w) => w.siteUrl),
      everyElement(sourceSite),
    );
    expect(
      tester
          .widgetList<HtmlWidget>(find.byType(HtmlWidget))
          .map((w) => w.baseUrl),
      everyElement(Uri.parse(sourceSite)),
    );
  });
}
