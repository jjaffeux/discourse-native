import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _reply = {'reply': 'half-written on the website', 'action': 'reply'};

Map<String, Object?> _wirePost(int id) => {
  'id': id,
  'post_number': id,
  'username': 'author',
  'cooked': '<p>Post $id</p>',
};

/// Answers `/t/7.json` by the parameters TopicsController#show reads.
///
/// Only `filter` reaches TopicView (topics_controller.rb:96-105), which keeps
/// the top replies when it is "summary" (topic_view.rb:1151).
http.Response _showTopic(http.Request request) {
  final query = request.url.queryParameters;
  final ids = query['filter'] == 'summary' ? [1, 3] : [1, 2, 3];
  return http.Response(
    jsonEncode({
      'id': 7,
      'title': 'A topic',
      'fancy_title': 'A topic',
      'posts_count': 3,
      'highest_post_number': 3,
      'has_summary': true,
      'draft_sequence': 4,
      'post_stream': {
        'posts': [for (final id in ids) _wirePost(id)],
        'stream': ids,
      },
      'details': {'can_create_post': true},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

/// The real request path for topic reads, with everything else faked.
final class _SiteApi extends FakeDiscourseApi {
  _SiteApi() {
    addTearDown(_real.close);
  }

  late final _real = DiscourseApi(
    client: MockClient((request) async {
      requests.add(request.url);
      return _showTopic(request);
    }),
  );

  final requests = <Uri>[];

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
  }) => _real.topic(
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

Future<ShellController> _openedTopic(_SiteApi api) async {
  final plugins = PluginInstaller.install(const PluginManifest([]));
  addTearDown(plugins.close);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'forum.example',
      ).copyWith(user: const DiscourseUser(username: 'reader')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  await shell.loadTopic(7, 'a-topic');
  await pumpEventQueue();
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Top replies shows only the replies the site picked', () async {
    final shell = await _openedTopic(_SiteApi());
    expect(shell.currentPostIds, [1, 2, 3]);

    expect(await shell.toggleTopicSummary(), isNull);

    expect(shell.currentPostIds, [1, 3]);
  });
}
