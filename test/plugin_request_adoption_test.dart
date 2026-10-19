import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker_controller.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api_client.dart';
import 'package:discourse_native/src/plugins/solved/solved_change_result.dart';
import 'package:discourse_native/src/plugins/solved/solved_controller.dart';
import 'package:discourse_native/src/plugins/solved/solved_post.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'GIF helper preserves the request capability through a queued read',
    () async {
      final fixture = _Fixture((_) async => http.Response('{"tags":[]}', 200));
      addTearDown(fixture.close);
      final blocker = fixture.occupy();
      final picker = GifPickerController(
        siteUrl: _site,
        api: GifsApiClient(fixture.api),
        requests: fixture.requests,
        fileDetail: 'gif',
      );
      addTearDown(picker.dispose);
      final pending = picker.loadCategories();
      await fixture.api.entered.future;
      await pumpEventQueue();
      expect(fixture.sent, isEmpty);

      fixture.requests.lifecycle.invalidate(_site);
      await pending.timeout(const Duration(seconds: 2));
      blocker.complete(http.Response('{}', 200));
      await pumpEventQueue();

      expect(fixture.sent, isEmpty);
      expect(picker.categories, isEmpty);
      expect(picker.isCurrent, isFalse);
      expect(fixture.requests.reader.clientReads, 1);
    },
  );

  test('GIF requests send both values from the retained snapshot', () async {
    final fixture = _Fixture((_) async => http.Response('{"tags":[]}', 200));
    addTearDown(fixture.close);
    final picker = GifPickerController(
      siteUrl: _site,
      api: GifsApiClient(fixture.api),
      requests: fixture.requests,
      fileDetail: 'gif',
    );
    addTearDown(picker.dispose);
    await picker.loadCategories();
    final request = fixture.sent.single;
    expect(request.headers['User-Api-Key'], 'key');
    expect(request.headers['User-Api-Client-Id'], 'client');
    expect(fixture.api.readFailures, isEmpty);
  });

  test(
    'queued Solved writes retire as not sent without reading a client id',
    () async {
      final fixture = _Fixture((_) async => http.Response('{}', 200));
      addTearDown(fixture.close);
      final blocker = fixture.occupy();
      final pending = fixture.acceptSolution();
      await fixture.api.entered.future;
      await pumpEventQueue();
      expect(fixture.sent, isEmpty);

      fixture.requests.lifecycle.invalidate(_site);
      final result = await pending.timeout(const Duration(seconds: 2));
      expect(result.kind, SolvedChangeKind.notSent);
      expect(result.isCurrent, isFalse);
      blocker.complete(http.Response('{}', 200));
      await pumpEventQueue();

      expect(fixture.api.writeFailures.single.notSent, isTrue);
      expect(fixture.sent, isEmpty);
      expect(fixture.requests.reader.clientReads, 0);
      expect(fixture.posts.refreshes, 0);
      expect(fixture.reloads, 0);
    },
  );

  for (final responseLost in [false, true]) {
    test(
      'dispatched Solved write ${responseLost ? 'keeps an unknown outcome' : 'settles'} after retirement',
      () async {
        final response = Completer<http.Response>();
        final dispatched = Completer<void>();
        final fixture = _Fixture((_) {
          dispatched.complete();
          return response.future;
        });
        addTearDown(fixture.close);
        var settled = false;
        final pending = fixture.acceptSolution().whenComplete(
          () => settled = true,
        );
        await dispatched.future;
        fixture.requests.lifecycle.invalidate(_site);
        await pumpEventQueue();
        expect(settled, isFalse);
        expect(fixture.sent.single.headers['User-Api-Client-Id'], isNull);
        if (responseLost) {
          response.completeError(http.ClientException('response lost'));
        } else {
          response.complete(http.Response('{}', 200));
        }
        final result = await pending;
        expect(
          result.kind,
          responseLost
              ? SolvedChangeKind.uncertain
              : SolvedChangeKind.acceptedRetired,
        );
        expect(result.isCurrent, isFalse);
        await pumpEventQueue();

        expect(fixture.sent, hasLength(1));
        if (responseLost) {
          expect(fixture.api.writeFailures.single.notSent, isFalse);
        } else {
          expect(fixture.api.writeFailures, isEmpty);
        }
        expect(fixture.requests.reader.clientReads, 0);
        expect(fixture.posts.refreshes, 0);
        expect(fixture.reloads, 0);
      },
    );
  }
}

final class _Fixture {
  _Fixture(Future<http.Response> Function(http.Request) respond) {
    transport = DiscourseTransport(
      SafeHttpClient.owned(
        MockClient((request) {
          sent.add(request);
          return respond(request);
        }),
      ),
      const Duration(seconds: 5),
      4096,
      maxConcurrentPerOrigin: 1,
    );
    network = DiscourseApi(transport: transport);
    api = _Api(network);
    solved = SolvedController(
      transport: api,
      requests: requests,
      posts: posts,
      topics: PluginTopicRefreshHost(reloadTopic: (_, _) async => reloads++),
    );
  }

  final requests = _Requests();
  final posts = _Posts();
  final sent = <http.Request>[];
  final blockers = <Completer<http.Response>>[];
  late final DiscourseTransport transport;
  late final DiscourseApi network;
  late final _Api api;
  late final SolvedController solved;
  int reloads = 0;

  Completer<http.Response> occupy() {
    final blocker = Completer<http.Response>();
    blockers.add(blocker);
    unawaited(
      transport.coordinator.run(Uri.parse(_site), () => blocker.future),
    );
    return blocker;
  }

  Future<SolvedChangeResult> acceptSolution() => solved.change(
    siteUrl: _site,
    topic: const TopicDetail(id: 7, title: 'Question', stream: [2]),
    postId: 2,
    accepted: true,
    lease: requests.capture(_site),
  );

  void close() {
    for (final blocker in blockers) {
      if (!blocker.isCompleted) blocker.complete(http.Response('{}', 200));
    }
    solved.close();
    network.close();
  }
}

final class _Reader implements ApiCredentialReader {
  int clientReads = 0;
  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'key';
  @override
  Future<String> clientId() async {
    clientReads++;
    return 'client';
  }
}

final class _Requests implements PluginRequestHost {
  final lifecycle = SiteLifecycle();
  final reader = _Reader();

  @override
  PluginSiteLease capture(String siteUrl) => _Lease(lifecycle.capture(siteUrl));

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    final snapshot = await AccountRequestSession(
      siteUrl,
      lifecycle.capture(siteUrl),
    ).credentials(reader);
    return PluginRequestCredentials(
      apiKey: snapshot.apiKey,
      clientId: snapshot.clientId,
      execute: snapshot.run,
    );
  }

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    final snapshot = await AccountRequestSession(
      siteUrl,
      lifecycle.capture(siteUrl),
    ).keyCredentials(reader);
    return (
      credentials: PluginRequestCredentials(
        apiKey: snapshot.apiKey,
        clientId: snapshot.clientId,
        execute: snapshot.run,
      ),
      failure: null,
    );
  }
}

final class _Lease implements PluginSiteLease {
  const _Lease(this.lease);
  final SiteLease lease;
  @override
  bool get isCurrent => lease.isCurrent;
  @override
  bool commit(void Function() mutation) => lease.commit(mutation);
}

final class _Api extends FakeDiscourseApi {
  _Api(this.network);
  final DiscourseApi network;
  final entered = Completer<void>();
  final writeFailures = <WriteException>[];
  final readFailures = <Object>[];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (!entered.isCompleted) entered.complete();
    try {
      return await network.pluginGetJson(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    } catch (error) {
      readFailures.add(error);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (!entered.isCompleted) entered.complete();
    try {
      return await network.pluginWriteJson(
        siteUrl: siteUrl,
        path: path,
        method: method,
        apiKey: apiKey,
        body: body,
        clientId: clientId,
      );
    } on WriteException catch (error) {
      writeFailures.add(error);
      rethrow;
    }
  }
}

final class _Posts implements PluginPostHost {
  int refreshes = 0;
  final post = Post(
    id: 2,
    postNumber: 2,
    username: 'sam',
    cooked: '<p>Answer</p>',
    plugins: PluginData.none.withValue(
      solvedPostKey,
      const SolvedPost(accepted: false, canAccept: true, canUnaccept: true),
    ),
  );
  @override
  Post? readPost(String siteUrl, int postId) => post;
  @override
  bool beginWrite(String siteUrl, int postId) => true;
  @override
  void endWrite(String siteUrl, int postId) {}
  @override
  bool writeInFlight(String siteUrl, int postId) => false;
  @override
  bool topicArchived(String siteUrl, int topicId) => false;
  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T?) update,
  ) {}
  @override
  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) async {
    refreshes++;
  }
}
