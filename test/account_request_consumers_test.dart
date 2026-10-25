import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final categoryId in [null, 7]) {
    test(
      '${categoryId == null ? 'empty' : 'cached'} category IDs add no client-ID read to feed preparation',
      () async {
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': [],
            '/category-check.json': [
              Topic(
                id: 7,
                title: 'Topic',
                slug: 'topic',
                categoryId: categoryId,
              ),
            ],
          },
        );
        final plugins = PluginInstaller.install(const PluginManifest([]));
        addTearDown(plugins.close);
        final auth = _CountingAuthenticator()..keys[_site] = 'api-key';
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
          ]),
          api: api,
          plugins: plugins,
          authenticator: auth,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await pumpEventQueue();
        shell.store.put(
          _site,
          const TopicCategory(id: 7, name: 'Cached', color: '0088cc'),
        );
        final before = auth.clientReads;
        await shell.topicFeeds.load(
          instance: shell.currentInstance!,
          destinationId: 'category-check',
          path: '/category-check.json',
          incoming: null,
        );
        await pumpEventQueue();
        expect(shell.topicFeeds.feedFor(_site, 'category-check')?.topicIds, [
          7,
        ]);
        expect(
          auth.clientReads,
          before,
          reason:
              'The loaded category directory needs no credentials; empty or cached IDs must add no read.',
        );
      },
    );
  }

  for (final consumer in ['topic', 'cached summary', 'summary generation']) {
    test(
      'retirement withdraws the production $consumer request while queued',
      () async {
        final sent = <http.Request>[];
        final transport = DiscourseTransport(
          SafeHttpClient.owned(
            MockClient((request) async {
              sent.add(request);
              return http.Response('{}', 200);
            }),
          ),
          const Duration(seconds: 5),
          4096,
          maxConcurrentPerOrigin: 1,
        );
        final network = DiscourseApi(transport: transport);
        addTearDown(network.close);
        final api = _ConsumerApi(network);
        final plugins = PluginInstaller.install(
          const PluginManifest([discourseAiModule]),
        );
        addTearDown(plugins.close);
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
          ]),
          api: api,
          plugins: plugins,
          authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await pumpEventQueue();
        final blocker = Completer<http.Response>();
        final occupied = transport.coordinator.run(
          Uri.parse(_site),
          () => blocker.future,
        );
        late Future<void> settled;
        if (consumer == 'topic') {
          settled = shell.loadTopic(7, 'topic', force: true);
        } else {
          final summary = shell.pluginSession
              .require(aiSummaryControllerService)
              .load(
                siteUrl: _site,
                topicId: 7,
                hasCachedSummary: consumer == 'cached summary',
              );
          settled = expectLater(
            summary.result,
            throwsA(
              consumer == 'cached summary'
                  ? isA<SiteLookupException>()
                  : isA<WriteException>().having(
                      (error) => error.notSent,
                      'notSent',
                      isTrue,
                    ),
            ),
          );
        }
        await pumpEventQueue();
        expect(api.topicCalls + api.pluginCalls, 1);
        expect(sent, isEmpty);
        shell.lifecycle.invalidate(_site);
        await settled;
        blocker.complete(http.Response('{}', 200));
        await occupied;
        await pumpEventQueue();
        expect(sent, isEmpty);
        expect(shell.store.read<TopicDetail>(_site, 7), isNull);
      },
    );
  }

  for (final consumer in ['post page', 'tags']) {
    test(
      'retirement withdraws the production $consumer while queued',
      () async {
        final sent = <http.Request>[];
        final transport = DiscourseTransport(
          SafeHttpClient.owned(
            MockClient((request) async {
              sent.add(request);
              return http.Response('{}', 200);
            }),
          ),
          const Duration(seconds: 5),
          4096,
          maxConcurrentPerOrigin: 1,
        );
        final network = DiscourseApi(transport: transport);
        addTearDown(network.close);
        final api = _ConsumerApi(network);
        if (consumer == 'post page') {
          api.initialTopic = topicPayload(
            id: 7,
            posts: [
              for (var id = 1; id <= 20; id++)
                Post(id: id, postNumber: id, username: 'reader', cooked: '$id'),
            ],
            stream: [for (var id = 1; id <= 45; id++) id],
            postsCount: 45,
          );
        }
        final plugins = PluginInstaller.install(const PluginManifest([]));
        addTearDown(plugins.close);
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
          ]),
          api: api,
          plugins: plugins,
          authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await pumpEventQueue();
        if (consumer == 'post page') {
          shell.pushContent(
            ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
          );
          await shell.loadTopic(7, 'topic');
        }

        final blocker = Completer<http.Response>();
        final occupied = transport.coordinator.run(
          Uri.parse(_site),
          () => blocker.future,
        );
        final settled = consumer == 'post page'
            ? shell.loadMorePosts()
            : shell.loadTags(_site, force: true);
        await pumpEventQueue();
        expect(consumer == 'post page' ? api.postCalls : api.tagCalls, 1);
        expect(sent, isEmpty);
        shell.lifecycle.invalidate(_site);
        await settled;
        blocker.complete(http.Response('{}', 200));
        await occupied;
        await pumpEventQueue();
        expect(sent, isEmpty);
        if (consumer == 'post page') {
          expect(shell.store.read<Post>(_site, 21), isNull);
        } else {
          expect(shell.tagDirectoryFeedFor(_site).tags, isEmpty);
        }
      },
    );
  }

  for (final connected in [false, true]) {
    test(
      'tag directory uses ${connected ? 'full' : 'anonymous'} headers',
      () async {
        final sent = <http.Request>[];
        final transport = DiscourseTransport(
          SafeHttpClient.owned(
            MockClient((request) async {
              sent.add(request);
              return http.Response('{}', 200);
            }),
          ),
          const Duration(seconds: 5),
          4096,
        );
        final network = DiscourseApi(transport: transport);
        addTearDown(network.close);
        final api = _ConsumerApi(network);
        final plugins = PluginInstaller.install(const PluginManifest([]));
        addTearDown(plugins.close);
        final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
        if (!connected) {
          authenticator.apiKeyFailure = StateError(
            'anonymous tags read storage',
          );
        }
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(
              user: connected
                  ? const DiscourseUser(id: 7, username: 'reader')
                  : null,
            ),
          ]),
          api: api,
          plugins: plugins,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await pumpEventQueue();
        await shell.loadTags(_site, force: true);
        expect(sent, hasLength(1));
        expect(sent.single.url.path, '/tags.json');
        expect(
          sent.single.headers['User-Api-Key'],
          connected ? 'api-key' : isNull,
        );
        expect(
          sent.single.headers['User-Api-Client-Id'],
          connected ? 'test-client' : isNull,
        );
      },
    );
  }
}

class _ConsumerApi extends FakeDiscourseApi {
  _ConsumerApi(this.network) : super(feeds: const {'/latest.json': []});
  final DiscourseApi network;
  int topicCalls = 0;
  int pluginCalls = 0;
  int postCalls = 0;
  int tagCalls = 0;
  TopicPayload? initialTopic;

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
    topicCalls++;
    if (initialTopic case final topic?) return Future.value(topic);
    return network.topic(
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

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) {
    postCalls++;
    return network.posts(
      siteUrl: siteUrl,
      topicId: topicId,
      ids: ids,
      includeRaw: includeRaw,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    tagCalls++;
    return network.tags(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    pluginCalls++;
    return network.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) {
    pluginCalls++;
    return network.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }
}

final class _CountingAuthenticator extends FakeAuthenticator {
  int clientReads = 0;

  @override
  Future<String> clientId() async {
    clientReads++;
    return super.clientId();
  }
}
