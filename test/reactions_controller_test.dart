import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _SequencedReactorsApi implements ReactionsApi {
  _SequencedReactorsApi(this.gates);

  final List<Completer<void>> gates;
  int requests = 0;

  @override
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  }) async {
    final request = requests++;
    await gates[request].future;
    return PostReactors(
      postId: postId,
      filter: reaction,
      total: 1,
      reactors: [
        PostReactor(
          id: request + 1,
          username: request == 0 ? 'account-a' : 'account-b',
          reaction: reaction ?? 'heart',
        ),
      ],
    );
  }
}

final class _GatedCredentials implements ApiCredentialReader {
  final Completer<void> apiKeyStarted = Completer();
  final Completer<String?> apiKeyResult = Completer();
  final Completer<void> clientIdStarted = Completer();
  final Completer<String> clientIdResult = Completer();

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    apiKeyStarted.complete();
    return apiKeyResult.future;
  }

  @override
  Future<String> clientId() {
    clientIdStarted.complete();
    return clientIdResult.future;
  }
}

final class _SequencedApiKeys implements ApiCredentialReader {
  _SequencedApiKeys(this.results);

  final List<Completer<String?>> results;
  int apiKeyCalls = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) => results[apiKeyCalls++].future;

  @override
  Future<String> clientId() async => 'client';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an old finalizer cannot release a new session request', () async {
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    final api = _SequencedReactorsApi([oldGate, newGate]);
    final lifecycle = SiteLifecycle();
    final store = Store();
    final controller = ReactionsController(
      api: api,
      credentials: FakeApiCredentialReader(),
      store: store,
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);

    final oldLoad = controller.load(siteUrl: _siteUrl, postId: 7);
    await Future<void>.delayed(Duration.zero);
    lifecycle.invalidate(_siteUrl);
    controller.forget(_siteUrl);

    final newLoad = controller.load(siteUrl: _siteUrl, postId: 7);
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, 2);

    oldGate.complete();
    await oldLoad;
    await controller.load(siteUrl: _siteUrl, postId: 7);

    // The old request's `finally` did not remove the new request's loading
    // guard, so opening the same list again did not start a third request.
    expect(api.requests, 2);
    expect(controller.reactors(_siteUrl, 7), isNull);

    newGate.complete();
    await newLoad;

    expect(api.requests, 2);
    expect(
      controller.reactors(_siteUrl, 7)?.reactors.single.username,
      'account-b',
    );
  });

  test('forget notifies direct consumers when request state disappears', () {
    final controller = ReactionsController(
      api: _SequencedReactorsApi([Completer<void>()]),
      credentials: FakeApiCredentialReader(),
      store: Store(),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    unawaited(controller.load(siteUrl: _siteUrl, postId: 7));
    expect(notifications, 1);

    controller.forget(_siteUrl);
    expect(notifications, 2);
  });

  test('forget while the API key is pending sends no stale request', () async {
    final credentials = _GatedCredentials();
    final api = _SequencedReactorsApi([]);
    final controller = ReactionsController(
      api: api,
      credentials: credentials,
      store: Store(),
    );
    addTearDown(controller.dispose);

    final load = controller.load(siteUrl: _siteUrl, postId: 7);
    await credentials.apiKeyStarted.future;
    controller.forget(_siteUrl);
    credentials.apiKeyResult.complete('stale-key');
    await load;

    expect(api.requests, 0);
    expect(credentials.clientIdStarted.isCompleted, isFalse);
  });

  test(
    'account invalidation during client id lookup sends no request',
    () async {
      final credentials = _GatedCredentials();
      final api = _SequencedReactorsApi([]);
      final lifecycle = SiteLifecycle();
      final controller = ReactionsController(
        api: api,
        credentials: credentials,
        store: Store(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);

      final load = controller.load(siteUrl: _siteUrl, postId: 7);
      await credentials.apiKeyStarted.future;
      credentials.apiKeyResult.complete('stale-key');
      await credentials.clientIdStarted.future;
      lifecycle.invalidate(_siteUrl);
      credentials.clientIdResult.complete('stale-client');
      await load;

      expect(api.requests, 0);
    },
  );

  test(
    'a replacement request supersedes a pending credential lookup',
    () async {
      final oldKey = Completer<String?>();
      final replacementKey = Completer<String?>();
      final credentials = _SequencedApiKeys([oldKey, replacementKey]);
      final response = Completer<void>();
      final api = _SequencedReactorsApi([response]);
      final controller = ReactionsController(
        api: api,
        credentials: credentials,
        store: Store(),
      );
      addTearDown(controller.dispose);

      final oldLoad = controller.load(siteUrl: _siteUrl, postId: 7);
      await pumpEventQueue();
      controller.forget(_siteUrl);
      final replacementLoad = controller.load(siteUrl: _siteUrl, postId: 7);
      await pumpEventQueue();

      replacementKey.complete('replacement-key');
      await pumpEventQueue();
      expect(api.requests, 1);

      oldKey.complete('stale-key');
      await oldLoad;
      expect(api.requests, 1);

      response.complete();
      await replacementLoad;
    },
  );

  test('forget matches site identities rather than string prefixes', () async {
    const forgottenSite = 'https://meta.discourse.org/';
    const retainedSite = 'https://meta.discourse.org/~tenant';
    final key = Completer<String?>();
    final unexpectedKey = Completer<String?>();
    final credentials = _SequencedApiKeys([key, unexpectedKey]);
    final response = Completer<void>();
    final api = _SequencedReactorsApi([response]);
    final controller = ReactionsController(
      api: api,
      credentials: credentials,
      store: Store(),
    );
    addTearDown(controller.dispose);

    final load = controller.load(siteUrl: retainedSite, postId: 7);
    await pumpEventQueue();
    controller.forget(forgottenSite);
    await controller.load(siteUrl: retainedSite, postId: 7);

    expect(credentials.apiKeyCalls, 1);

    key.complete('retained-key');
    await pumpEventQueue();
    expect(api.requests, 1);
    response.complete();
    await load;
  });

  test('dispose during client id lookup sends no request', () async {
    final credentials = _GatedCredentials();
    final api = _SequencedReactorsApi([]);
    final controller = ReactionsController(
      api: api,
      credentials: credentials,
      store: Store(),
    );

    final load = controller.load(siteUrl: _siteUrl, postId: 7);
    await credentials.apiKeyStarted.future;
    credentials.apiKeyResult.complete('stale-key');
    await credentials.clientIdStarted.future;
    controller.dispose();
    credentials.clientIdResult.complete('stale-client');
    await load;

    expect(api.requests, 0);
  });
}
