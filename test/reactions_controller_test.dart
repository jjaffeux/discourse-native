import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/emoji_preferences.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api.dart';
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

final class _UnusedPostHost implements PluginPostHost {
  @override
  bool beginWrite(String siteUrl, int postId) => false;

  @override
  void endWrite(String siteUrl, int postId) {}

  @override
  Post? readPost(String siteUrl, int postId) => null;

  @override
  bool topicArchived(String siteUrl, int topicId) => false;

  @override
  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) async {}

  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T? held) update,
  ) {}

  @override
  bool writeInFlight(String siteUrl, int postId) => false;
}

final class _UnusedEmojiPreferences implements EmojiPreferenceStore {
  @override
  Future<void> clearHistory({
    required String siteUrl,
    required EmojiUsageContext context,
  }) async {}

  @override
  Future<List<String>> favoriteEmojiCodes({
    required String siteUrl,
    required EmojiUsageContext context,
    required SiteEmojiCatalog catalog,
  }) async => const [];

  @override
  Future<EmojiSkinTone> readSkinTone({required String siteUrl}) async =>
      EmojiSkinTone.neutral;

  @override
  Future<void> trackEmoji({
    required String siteUrl,
    required EmojiUsageContext context,
    required String emoji,
  }) async {}

  @override
  Future<void> writeSkinTone({
    required String siteUrl,
    required EmojiSkinTone tone,
  }) async {}
}

ReactionsController _controller({
  required ReactionsApi api,
  required PluginRequestHost requests,
}) => ReactionsController(
  api: api,
  requests: requests,
  posts: _UnusedPostHost(),
  siteState: PluginSiteStateHost(
    currentUserFor: (_) => null,
    siteConfigFor: (_) => const SiteConfig.unknown(),
  ),
  resolveSiteConfig: (_) async => null,
  emoji: PluginEmojiHost(
    preferences: _UnusedEmojiPreferences(),
    siteConfigFor: (_) => const SiteConfig.unknown(),
    loadCatalog: (_, {refresh = false}) async => null,
    loadSearchAliases: (_, {refresh = false}) async => null,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('request replacement and finalizers', () {
    test('an old finalizer cannot release a replacement request', () async {
      final oldGate = Completer<void>();
      final newGate = Completer<void>();
      final api = _SequencedReactorsApi([oldGate, newGate]);
      final lifecycle = SiteLifecycle();
      final requests = FakePluginRequestHost(lifecycle: lifecycle);
      final controller = _controller(api: api, requests: requests);
      addTearDown(controller.dispose);

      final oldLoad = controller.load(siteUrl: _siteUrl, postId: 7);
      await pumpEventQueue();
      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);

      final newLoad = controller.load(siteUrl: _siteUrl, postId: 7);
      await pumpEventQueue();
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
        controller.reactors(_siteUrl, 7),
        const PostReactors(
          postId: 7,
          total: 1,
          reactors: [
            PostReactor(id: 2, username: 'account-b', reaction: 'heart'),
          ],
        ),
      );
    });

    test('a replacement supersedes a pending credential lookup', () async {
      final oldKey = Completer<String?>();
      final replacementKey = Completer<String?>();
      final credentials = _SequencedApiKeys([oldKey, replacementKey]);
      final response = Completer<void>();
      final api = _SequencedReactorsApi([response]);
      final controller = _controller(
        api: api,
        requests: FakePluginRequestHost(credentials: credentials),
      );
      addTearDown(controller.dispose);

      final oldLoad = controller.load(siteUrl: _siteUrl, postId: 7);
      await pumpEventQueue();
      controller.forget(_siteUrl);
      final replacementLoad = controller.load(siteUrl: _siteUrl, postId: 7);
      await pumpEventQueue();

      replacementKey.complete('replacement-key');
      await pumpEventQueue();
      expect(credentials.apiKeyCalls, 2);
      expect(api.requests, 1);

      oldKey.complete('stale-key');
      await oldLoad;
      expect(api.requests, 1);

      response.complete();
      await replacementLoad;
      expect(
        controller.reactors(_siteUrl, 7),
        const PostReactors(
          postId: 7,
          total: 1,
          reactors: [
            PostReactor(id: 1, username: 'account-a', reaction: 'heart'),
          ],
        ),
      );
    });
  });

  group('forget and site identity', () {
    test('forget notifies when request state disappears', () async {
      final api = _SequencedReactorsApi([]);
      final controller = _controller(
        api: api,
        requests: FakePluginRequestHost(),
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final load = controller.load(siteUrl: _siteUrl, postId: 7);
      expect(notifications, 1);

      controller.forget(_siteUrl);
      expect(notifications, 2);
      await load;
      expect(api.requests, 0);
      expect(notifications, 2);
    });

    test('forget during credential lookup sends no stale request', () async {
      final credentials = _GatedCredentials();
      final api = _SequencedReactorsApi([]);
      final controller = _controller(
        api: api,
        requests: FakePluginRequestHost(credentials: credentials),
      );
      addTearDown(controller.dispose);

      final load = controller.load(siteUrl: _siteUrl, postId: 7);
      await credentials.apiKeyStarted.future;
      controller.forget(_siteUrl);
      credentials.apiKeyResult.complete('stale-key');
      await credentials.clientIdStarted.future;
      credentials.clientIdResult.complete('stale-client');
      await load;

      expect(api.requests, 0);
    });

    test(
      'forget matches site identities rather than string prefixes',
      () async {
        const forgottenSite = 'https://meta.discourse.org/';
        const retainedSite = 'https://meta.discourse.org/~tenant';
        final key = Completer<String?>();
        final unexpectedKey = Completer<String?>();
        final credentials = _SequencedApiKeys([key, unexpectedKey]);
        final response = Completer<void>();
        final api = _SequencedReactorsApi([response]);
        final controller = _controller(
          api: api,
          requests: FakePluginRequestHost(credentials: credentials),
        );
        addTearDown(controller.dispose);

        final load = controller.load(siteUrl: retainedSite, postId: 7);
        await pumpEventQueue();
        controller.forget(forgottenSite);
        final duplicateLoad = controller.load(siteUrl: retainedSite, postId: 7);
        await pumpEventQueue();

        expect(credentials.apiKeyCalls, 1);

        key.complete('retained-key');
        await pumpEventQueue();
        expect(api.requests, 1);
        response.complete();
        await Future.wait([load, duplicateLoad]);
        expect(
          controller.reactors(retainedSite, 7),
          const PostReactors(
            postId: 7,
            total: 1,
            reactors: [
              PostReactor(id: 1, username: 'account-a', reaction: 'heart'),
            ],
          ),
        );
      },
    );
  });

  group('account invalidation', () {
    test('during client ID lookup sends no request', () async {
      final credentials = _GatedCredentials();
      final api = _SequencedReactorsApi([]);
      final lifecycle = SiteLifecycle();
      final controller = _controller(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
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
    });
  });

  group('disposal', () {
    test('dispose during client ID lookup sends no request', () async {
      final credentials = _GatedCredentials();
      final api = _SequencedReactorsApi([]);
      final controller = _controller(
        api: api,
        requests: FakePluginRequestHost(credentials: credentials),
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

    test('load after dispose reads no credentials', () async {
      final credentials = _GatedCredentials();
      final api = _SequencedReactorsApi([]);
      final controller = _controller(
        api: api,
        requests: FakePluginRequestHost(credentials: credentials),
      );
      controller.dispose();

      await controller.load(siteUrl: _siteUrl, postId: 7);

      expect(credentials.apiKeyStarted.isCompleted, isFalse);
      expect(credentials.clientIdStarted.isCompleted, isFalse);
      expect(api.requests, 0);
    });
  });
}
