import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/assign/assign_services.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_prefetch_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(id: 1, username: 'reader');
const _docsId = 7;
const _readDocs = Topic(
  id: 41,
  title: 'Read docs',
  slug: 'read-docs',
  categoryId: _docsId,
  highestPostNumber: 5,
  lastReadPostNumber: 5,
);

void _report(String metric, Object? value) {
  // ignore: avoid_print
  print('PERF_PROOF opening-post-owner $metric=$value');
}

final class _Api extends FakeDiscourseApi {
  _Api()
    : super(
        user: _reader,
        feeds: const {
          '/latest.json': [_readDocs],
        },
        feedCategoriesByPath: {
          '/latest.json': [
            TopicCategory.fromJson(const {
              'id': _docsId,
              'name': 'Docs',
              'color': '0088CC',
              'slug': 'docs',
              'navigate_to_first_post_after_read': true,
            }),
          ],
        },
        topics: {41: topicPayload(id: 41, title: 'Read docs')},
      );

  final requestedPosts = <int?>[];

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) {
    requestedPosts.add(postNumber);
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
  }
}

Future<(ShellController, _Api)> _shell() async {
  SharedPreferences.setMockInitialValues({});
  final api = _Api();
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.loadFeed('latest');
  return (shell, api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Assign opens a fully read first-post topic at post 1', () async {
    final (shell, _) = await _shell();

    shell.pluginSession
        .require(assignGroupNavigationService)
        .openTopic(_readDocs);

    final opened = shell.currentContent?.postNumber;
    _report('assign_post', opened);
    expect(opened, 1);
  });

  test('prefetch loads the post a tap will open', () async {
    final (shell, api) = await _shell();
    api.requestedPosts.clear();

    final release = shell.prefetchTopic(
      _site,
      _readDocs,
      intent: TopicPrefetchIntent.trajectory,
    );
    addTearDown(release);
    await pumpEventQueue();

    final prefetched = api.requestedPosts.singleOrNull;
    _report('prefetch_post', prefetched);
    expect(prefetched, 1);
  });

  testWidgets('a card links to the post a tap will open', (tester) async {
    late ShellController shell;
    await tester.runAsync(() async {
      (shell, _) = await _shell();
    });
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: TopicListView(feed: shell.currentFeed!)),
        ),
      ),
    );
    await tester.pump();

    final url = tester
        .widgetList<LinkTarget>(find.byType(LinkTarget))
        .map((target) => target.url)
        .whereType<String>()
        .singleWhere((url) => url.contains('/t/read-docs/41/'));
    _report('card_url_post', Uri.parse(url).pathSegments.last);
    expect(url, '$_site/t/read-docs/41/1');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
