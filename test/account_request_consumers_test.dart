import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
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
}

class _ConsumerApi extends FakeDiscourseApi {
  _ConsumerApi(this.network) : super(feeds: const {'/latest.json': []});
  final DiscourseApi network;
  int topicCalls = 0;
  int pluginCalls = 0;

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
