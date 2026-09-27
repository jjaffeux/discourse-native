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
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_controller.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

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

/// Holds the post write lane and the post records the way the shell does,
/// without a shell.
final class _LanePostHost implements PluginPostHost {
  _LanePostHost(Iterable<Post> posts)
    : posts = {for (final post in posts) post.id: post};

  final Map<int, Post> posts;
  final Set<(String, int)> writes = {};

  @override
  bool beginWrite(String siteUrl, int postId) => writes.add((siteUrl, postId));

  @override
  void endWrite(String siteUrl, int postId) => writes.remove((siteUrl, postId));

  @override
  Post? readPost(String siteUrl, int postId) => posts[postId];

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
  ) {
    final post = posts[postId];
    if (post == null) return;
    posts[postId] = post.withPlugins(
      post.plugins.withValue(key, update(post.plugins.get(key))),
    );
  }

  @override
  bool writeInFlight(String siteUrl, int postId) =>
      writes.contains((siteUrl, postId));
}

final class _AcceptedWrites implements ReactionsWriteApi {
  final List<(int, String)> toggled = [];

  @override
  Future<Post?> toggleReaction({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String reaction,
    String? clientId,
  }) async {
    toggled.add((postId, reaction));
    return null;
  }
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

PluginEmojiHost _emojiHost({required PluginEmojiCatalogLoader loadCatalog}) =>
    PluginEmojiHost(
      preferences: _UnusedEmojiPreferences(),
      siteConfigFor: (_) => const SiteConfig.unknown(),
      loadCatalog: loadCatalog,
      loadSearchAliases: (_, {refresh = false}) async => null,
      resolveUrl: (siteUrl, name) => '$siteUrl/$name',
    );

/// Answers the way the shell's presentation controller does once a site's
/// catalog request has failed: immediately, with nothing, until a refresh.
final class _MissingEmojiCatalog {
  int loads = 0;

  late final PluginEmojiHost host = _emojiHost(
    loadCatalog: (_, {refresh = false}) {
      loads++;
      return Future.value(null);
    },
  );
}

ReactionsController _controller({
  required ReactionsApi api,
  required PluginRequestHost requests,
  PluginEmojiHost? emoji,
  PluginPostHost? posts,
  ReactionsWriteApi? writes,
}) => ReactionsController(
  api: api,
  writes: writes,
  requests: requests,
  posts: posts ?? _UnusedPostHost(),
  siteState: PluginSiteStateHost(
    currentUserFor: (_) => null,
    siteConfigFor: (_) => const SiteConfig.unknown(),
  ),
  resolveSiteConfig: (_) async => null,
  emoji: emoji ?? _emojiHost(loadCatalog: (_, {refresh = false}) async => null),
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

  group('emoji catalog', () {
    test('a read that finds no catalog does not wake its readers', () async {
      final catalog = _MissingEmojiCatalog();
      final controller = _controller(
        api: _SequencedReactorsApi([]),
        requests: FakePluginRequestHost(),
        emoji: catalog.host,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      // A notification marks a ListenableBuilder dirty; its builder reads the
      // URL again on the next frame, which the timer queue stands in for.
      controller.addListener(() {
        notifications++;
        Timer.run(() => controller.emojiUrlFor(_siteUrl, 'clap'));
      });

      expect(
        controller.emojiUrlFor(_siteUrl, 'clap'),
        const SiteConfig.unknown().emojiUrl('clap', siteUrl: _siteUrl),
      );
      await pumpEventQueue();

      expect(catalog.loads, 1);
      expect(notifications, 0);
    });

    test('a catalog found after a miss is adopted by the next read', () async {
      final answers = <SiteEmojiCatalog?>[
        null,
        SiteEmojiCatalog(
          groups: [
            SiteEmojiGroup(
              id: 'default',
              emojis: const [
                SiteEmoji(name: 'clap', url: '$_siteUrl/custom/clap.png'),
              ],
            ),
          ],
        ),
      ];
      var loads = 0;
      final controller = _controller(
        api: _SequencedReactorsApi([]),
        requests: FakePluginRequestHost(),
        emoji: _emojiHost(
          loadCatalog: (_, {refresh = false}) => Future.value(answers[loads++]),
        ),
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.emojiUrlFor(_siteUrl, 'clap');
      await pumpEventQueue();
      expect(notifications, 0);

      controller.emojiUrlFor(_siteUrl, 'clap');
      await pumpEventQueue();

      expect(loads, 2);
      expect(notifications, 1);
      expect(
        controller.emojiUrlFor(_siteUrl, 'clap'),
        '$_siteUrl/custom/clap.png',
      );
      expect(loads, 2);
    });

    testWidgets('a held reaction settles while its site has no catalog', (
      tester,
    ) async {
      installTestMediaPipeline(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final catalog = _MissingEmojiCatalog();
      final controller = _controller(
        api: _SequencedReactorsApi([]),
        requests: FakePluginRequestHost(),
        emoji: catalog.host,
      );
      addTearDown(controller.dispose);
      final post = Post(
        id: 7,
        postNumber: 1,
        username: 'author',
        cooked: '<p>Post</p>',
        plugins: PluginData.none.withValue(
          reactionsDataKey,
          const Reactions(
            entries: [Reaction(id: 'clap', count: 1)],
            mine: Reaction(id: 'clap', count: 1, canUndo: true),
            userCount: 1,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: PostReactionButton(
                controller: controller,
                emoji: catalog.host,
                siteUrl: _siteUrl,
                post: post,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Remove your clap reaction'), findsOne);
      // Settling only proves something if the held emoji asked for a catalog.
      expect(catalog.loads, isPositive);
    });

    testWidgets(
      'a held reaction redraws from its site catalog when it arrives',
      (tester) async {
        installTestMediaPipeline(
          client: MockClient((_) async => http.Response('', 404)),
        );
        final catalog = Completer<SiteEmojiCatalog?>();
        final emoji = _emojiHost(
          loadCatalog: (_, {refresh = false}) => catalog.future,
        );
        final controller = _controller(
          api: _SequencedReactorsApi([]),
          requests: FakePluginRequestHost(),
          emoji: emoji,
        );
        addTearDown(controller.dispose);
        final post = Post(
          id: 7,
          postNumber: 1,
          username: 'author',
          cooked: '<p>Post</p>',
          plugins: PluginData.none.withValue(
            reactionsDataKey,
            const Reactions(
              entries: [Reaction(id: 'clap', count: 1)],
              mine: Reaction(id: 'clap', count: 1, canUndo: true),
              userCount: 1,
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Center(
                child: PostReactionButton(
                  controller: controller,
                  emoji: emoji,
                  siteUrl: _siteUrl,
                  post: post,
                ),
              ),
            ),
          ),
        );
        // Settled first, so the button's own settings read cannot be what
        // redraws it once the catalog arrives.
        await tester.pumpAndSettle();
        String drawn() =>
            tester.widget<EmojiImage>(find.byType(EmojiImage)).url;
        expect(
          drawn(),
          const SiteConfig.unknown().emojiUrl('clap', siteUrl: _siteUrl),
        );

        catalog.complete(
          SiteEmojiCatalog(
            groups: [
              SiteEmojiGroup(
                id: 'default',
                emojis: const [
                  SiteEmoji(name: 'clap', url: '$_siteUrl/custom/clap.png'),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(drawn(), '$_siteUrl/custom/clap.png');
      },
    );
  });

  group('per-post notifications', () {
    const other = 'https://other.example';

    test(
      'a post hears its own loads and writes, and its site hears the catalog and forget',
      () async {
        final post = Post(
          id: 7,
          postNumber: 1,
          username: 'author',
          cooked: '<p>Post</p>',
          canLike: true,
          plugins: PluginData.none.withValue(
            reactionsDataKey,
            const Reactions(entries: [Reaction(id: 'clap', count: 1)]),
          ),
        );
        final writes = _AcceptedWrites();
        final controller = _controller(
          api: _SequencedReactorsApi([
            for (var request = 0; request < 2; request++)
              Completer<void>()..complete(),
          ]),
          requests: FakePluginRequestHost(
            credentials: FakeApiCredentialReader()..keys[_siteUrl] = 'key',
          ),
          posts: _LanePostHost([post]),
          writes: writes,
          emoji: _emojiHost(
            loadCatalog: (_, {refresh = false}) async =>
                SiteEmojiCatalog(groups: const []),
          ),
        );
        addTearDown(controller.dispose);
        final changed = <Object>[];
        for (final (site, id) in const [
          (_siteUrl, 7),
          (_siteUrl, 8),
          (other, 7),
        ]) {
          controller
              .postChanges(site, id)
              .addListener(() => changed.add((site, id)));
        }
        for (final site in const [_siteUrl, other]) {
          controller
              .emojiCatalogChanges(site)
              .addListener(() => changed.add(site));
        }
        var controllerChanges = 0;
        controller.addListener(() => controllerChanges++);

        await controller.load(siteUrl: _siteUrl, postId: 7, filter: 'clap');
        expect(changed, [(_siteUrl, 7), (_siteUrl, 7)]);
        expect(controllerChanges, 2);

        changed.clear();
        expect(
          await controller.toggle(post, 'clap', siteUrl: _siteUrl),
          isNull,
        );
        expect(writes.toggled, [(7, 'clap')]);
        expect(changed, [(_siteUrl, 7), (_siteUrl, 7)]);
        expect(controllerChanges, 4);

        changed.clear();
        controller.emojiUrlFor(_siteUrl, 'clap');
        await pumpEventQueue();
        expect(changed, [_siteUrl]);
        expect(controllerChanges, 5);

        changed.clear();
        controller.forget(_siteUrl);
        expect(
          changed,
          unorderedEquals([(_siteUrl, 7), (_siteUrl, 8), _siteUrl]),
        );
        expect(controllerChanges, 6);

        // A row that outlives forget still hears its post's next load.
        changed.clear();
        await controller.load(siteUrl: _siteUrl, postId: 7);
        expect(changed, [(_siteUrl, 7), (_siteUrl, 7)]);
      },
    );

    test(
      'a post notifier is kept only while something listens to it',
      () async {
        final controller = _controller(
          api: _SequencedReactorsApi([]),
          requests: FakePluginRequestHost(),
        );
        addTearDown(controller.dispose);
        void listener() {}

        final held = controller.postChanges(_siteUrl, 7);
        held.addListener(listener);
        await pumpEventQueue();
        expect(controller.postChanges(_siteUrl, 7), same(held));

        // A builder handed a new listenable leaves the old one before joining
        // the next, and both may be this one.
        held.removeListener(listener);
        held.addListener(listener);
        await pumpEventQueue();
        expect(controller.postChanges(_siteUrl, 7), same(held));

        held.removeListener(listener);
        await pumpEventQueue();
        final next = controller.postChanges(_siteUrl, 7);
        expect(next, isNot(same(held)));

        // Asked for and never listened to, as by a build that was discarded.
        await pumpEventQueue();
        expect(controller.postChanges(_siteUrl, 7), isNot(same(next)));
      },
    );
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
