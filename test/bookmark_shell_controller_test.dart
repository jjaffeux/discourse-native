import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_bookmark.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.example';
const _otherSite = 'https://other.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('post bookmark lifecycle updates every cached representation', () async {
    final api = _BookmarkFakeApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final created = await shell.createBookmark(
      siteUrl: _site,
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 12,
      name: 'Read this',
      reminderAt: DateTime.now().add(const Duration(days: 1)),
      autoDeletePreference: BookmarkAutoDeletePreference.whenReminderSent,
    );
    await pumpEventQueue();

    expect(created.saved, isTrue);
    expect(shell.store.read<Post>(_site, 12)?.bookmark?.name, 'Read this');
    expect(
      shell.store.read<TopicDetail>(_site, 7)?.postBookmarks,
      hasLength(1),
    );
    expect(shell.store.read<Topic>(_site, 7)?.bookmarked, isTrue);
    expect(api.createdBookmarks, hasLength(1));
    expect(api.bookmarksRequested, isNotEmpty);

    final updated = await shell.updateBookmark(
      siteUrl: _site,
      topicId: 7,
      bookmark: created.bookmark!,
      name: 'Keep this',
      autoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
    );
    await pumpEventQueue();

    expect(updated.saved, isTrue);
    expect(shell.store.read<Post>(_site, 12)?.bookmark?.name, 'Keep this');
    expect(shell.store.read<Post>(_site, 12)?.bookmark?.reminderAt, isNull);

    final deleted = await shell.deleteBookmark(
      siteUrl: _site,
      topicId: 7,
      bookmark: updated.bookmark!,
    );
    await pumpEventQueue();

    expect(deleted.saved, isTrue);
    expect(shell.store.read<Post>(_site, 12)?.bookmark, isNull);
    expect(shell.store.read<TopicDetail>(_site, 7)?.bookmarks, isEmpty);
    expect(shell.store.read<Topic>(_site, 7)?.bookmarked, isFalse);
  });

  test('chat message bookmark lifecycle updates the live message', () async {
    final api = _ChatBookmarkFakeApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    _putChatFixture(shell);

    final created = await shell.createBookmark(
      siteUrl: _site,
      topicId: 0,
      targetType: chatMessageBookmarkTarget,
      targetId: 42,
      name: 'Follow up',
      reminderAt: DateTime.now().add(const Duration(days: 1)),
      autoDeletePreference: BookmarkAutoDeletePreference.whenReminderSent,
    );
    await pumpEventQueue();

    expect(created.saved, isTrue);
    final heldBookmark = shell.store.read<ChatMessage>(_site, 42)?.bookmark;
    expect(heldBookmark?.id, created.bookmark?.id);
    expect(heldBookmark?.name, 'Follow up');
    expect(heldBookmark?.reminderAt, created.bookmark?.reminderAt?.toUtc());
    expect(api.createdBookmarks.single.targetType, chatMessageBookmarkTarget);
    expect(api.bookmarksRequested, isNotEmpty);

    final updated = await shell.updateBookmark(
      siteUrl: _site,
      topicId: 0,
      bookmark: created.bookmark!,
      name: 'Keep this',
      autoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
    );
    await pumpEventQueue();

    expect(updated.saved, isTrue);
    expect(
      shell.store.read<ChatMessage>(_site, 42)?.bookmark?.name,
      'Keep this',
    );
    expect(
      shell.store.read<ChatMessage>(_site, 42)?.bookmark?.reminderAt,
      isNull,
    );

    final deleted = await shell.deleteBookmark(
      siteUrl: _site,
      topicId: 0,
      bookmark: updated.bookmark!,
    );
    await pumpEventQueue();

    expect(deleted.saved, isTrue);
    expect(shell.store.read<ChatMessage>(_site, 42)?.bookmark, isNull);
    expect(api.deletedBookmarks, [created.bookmark!.id]);
  });

  test(
    'chat bookmark actions stay target- and site-bound after a site switch',
    () async {
      final api = _ChatBookmarkFakeApi();
      final authenticator = FakeAuthenticator()
        ..keys[_site] = 'meta-key'
        ..keys[_otherSite] = 'other-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.example',
          ).copyWith(user: const DiscourseUser(username: 'reader')),
          instance(
            'other.example',
          ).copyWith(user: const DiscourseUser(username: 'reader')),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);
      await shell.load();
      _putChatFixture(shell);

      final host = shell.pluginSession.require(chatBookmarkHostService);
      expect(host, isA<PluginBookmarkHost>());
      expect(host, isNot(isA<BookmarkHost>()));

      shell.selectInstance(1);
      expect(shell.currentInstance?.url, _otherSite);

      final foreign = await host.updateBookmark(
        siteUrl: _site,
        topicId: 7,
        bookmark: const Bookmark(
          id: 91,
          bookmarkableId: 12,
          bookmarkableType: 'Post',
        ),
        autoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
      );
      expect(foreign.saved, isFalse);
      expect(foreign.message, contains('does not belong'));
      expect(api.updatedBookmarks, isEmpty);

      final created = await host.createBookmark(
        siteUrl: _site,
        topicId: 0,
        targetId: 42,
        name: 'First forum',
      );
      await pumpEventQueue();

      expect(created.saved, isTrue);
      expect(api.createdAtSites, [_site]);
      expect(shell.currentInstance?.url, _otherSite);
      expect(
        shell.store.read<ChatMessage>(_site, 42)?.bookmark?.name,
        'First forum',
      );
      expect(shell.store.read<ChatMessage>(_otherSite, 42), isNull);
    },
  );

  test(
    'a plugin bookmark target fails closed when its plugin is absent',
    () async {
      final api = _ChatBookmarkFakeApi();
      final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.example',
          ).copyWith(user: const DiscourseUser(username: 'reader')),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();

      final result = await shell.createBookmark(
        siteUrl: _site,
        topicId: 0,
        targetType: chatMessageBookmarkTarget,
        targetId: 42,
      );

      expect(result.saved, isFalse);
      expect(result.message, contains('not available'));
      expect(api.createdBookmarks, isEmpty);
    },
  );

  test(
    'plugin bookmark factory cannot grant core or foreign target authority',
    () async {
      final probe = _BookmarkAuthorityProbeModule();
      final plugins = PluginInstaller.install(PluginManifest([probe]));
      final api = _ChatBookmarkFakeApi();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.example',
          ).copyWith(user: const DiscourseUser(username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: plugins,
      );
      addTearDown(shell.dispose);

      // Opening the session materializes the bookmark factory for `probe`.
      final _ = shell.pluginSession;

      expect(probe.deniedTargets, {
        BookmarkTargetType.post.id,
        _foreignBookmarkTarget.id,
      });

      // A caller can describe a new target in its own namespace, but that
      // facade remains inert until the exact target is contributed and
      // validated. Matching only core's wire name must not confer authority.
      final spoofed = await probe.spoofedCoreWireHost!.updateBookmark(
        siteUrl: _site,
        topicId: 7,
        bookmark: const Bookmark(
          id: 91,
          bookmarkableId: 12,
          bookmarkableType: 'Post',
        ),
        autoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
      );

      expect(spoofed.saved, isFalse);
      expect(spoofed.message, contains('does not belong'));
      expect(api.updatedBookmarks, isEmpty);
    },
  );

  test('an ambiguous create is reconciled and never posted twice', () async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(username: 'reader'),
      feeds: const {
        '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
      },
      topics: {7: _payload()},
      siteConfigs: const {_site: SiteConfig.unknown()},
      bookmarkList: const [],
      writeFailure: const WriteException(WriteFailure.unreachable),
    );
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final result = await shell.createBookmark(
      siteUrl: _site,
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 12,
    );
    await pumpEventQueue();

    expect(result.reconciled, isTrue);
    expect(api.createdBookmarks, isEmpty);
    expect(api.topicsOpened, [7, 7]);
  });

  test('repeated taps share the post write lock', () async {
    final api = _GatedCreateBookmarkApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final first = shell.createBookmark(
      siteUrl: _site,
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 12,
    );
    await api.started.future;
    final duplicate = await shell.createBookmark(
      siteUrl: _site,
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 12,
    );

    expect(duplicate.saved, isFalse);
    expect(duplicate.message, contains('still finishing'));
    expect(api.calls, 1);

    api.response.complete(88);
    expect((await first).saved, isTrue);
  });

  test('repeated taps share the chat message write lock', () async {
    final api = _GatedCreateBookmarkApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    _putChatFixture(shell);

    final first = shell.createBookmark(
      siteUrl: _site,
      topicId: 0,
      targetType: chatMessageBookmarkTarget,
      targetId: 42,
    );
    await api.started.future;
    final duplicate = await shell.createBookmark(
      siteUrl: _site,
      topicId: 0,
      targetType: chatMessageBookmarkTarget,
      targetId: 42,
    );

    expect(duplicate.saved, isFalse);
    expect(duplicate.message, contains('still finishing'));
    expect(api.calls, 1);

    api.response.complete(88);
    expect((await first).saved, isTrue);
  });

  test(
    'plugin bookmark busy listenable filters unrelated shell changes',
    () async {
      final api = _GatedCreateBookmarkApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      _putChatFixture(shell);
      final host = shell.pluginSession.require(chatBookmarkHostService);
      final busy = host.bookmarkWriteInFlightListenable(
        siteUrl: _site,
        topicId: 0,
        targetId: 42,
      );
      expect(busy, isNot(isA<ShellController>()));
      expect(
        host.bookmarkWriteInFlightListenable(
          siteUrl: _site,
          topicId: 0,
          targetId: 42,
        ),
        same(busy),
      );
      var notifications = 0;
      void notified() => notifications++;
      busy.addListener(notified);
      addTearDown(() => busy.removeListener(notified));

      shell.pushContent(
        ContentRoute.topic(topicId: 8, slug: 'other', title: 'Other'),
      );
      expect(notifications, 0);

      final write = host.createBookmark(
        siteUrl: _site,
        topicId: 0,
        targetId: 42,
      );
      await api.started.future;
      await pumpEventQueue();
      expect(busy.value, isTrue);
      expect(notifications, 1);

      api.response.complete(88);
      expect((await write).saved, isTrue);
      await pumpEventQueue();
      expect(busy.value, isFalse);
      expect(notifications, 2);
    },
  );

  test('a pre-write topic response cannot erase a saved bookmark', () async {
    final api = _StaleTopicBookmarkApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final stale = shell.loadTopic(7, 'topic', force: true);
    await api.staleStarted.future;
    final created = await shell.createBookmark(
      siteUrl: _site,
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 12,
    );
    expect(created.saved, isTrue);
    expect(shell.store.read<Post>(_site, 12)?.bookmark?.id, 91);

    api.staleResponse.complete(_payload());
    await stale;
    await pumpEventQueue();

    expect(shell.store.read<Post>(_site, 12)?.bookmark?.id, 91);
    expect(shell.store.read<TopicDetail>(_site, 7)?.bookmarks, hasLength(1));
    expect(api.topicCalls, 3);
  });

  test('a same-topic bookmark jump replays behind an active load', () async {
    final api = _GatedTopicApi();
    final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.example',
        ).copyWith(user: const DiscourseUser(username: 'reader')),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    await shell.load();
    addTearDown(shell.dispose);
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );

    final first = shell.loadTopic(7, 'topic');
    await pumpEventQueue();
    expect(api.postNumbers, [null]);

    shell.openCurrentTopicPost(42);
    api.responses.first.complete(_payload());
    await first;
    await pumpEventQueue();

    expect(api.postNumbers, [null, 42]);
    api.responses[1].complete(_payloadWithTarget());
    await pumpEventQueue();

    expect(shell.currentContent?.postNumber, 42);
    expect(shell.store.read<Post>(_site, 99)?.postNumber, 42);
  });
}

Future<ShellController> _loadShell(FakeDiscourseApi api) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.example',
      ).copyWith(user: const DiscourseUser(username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  await pumpEventQueue();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await shell.loadTopic(7, 'topic');
  return shell;
}

TopicPayload _payload({Bookmark? bookmark}) {
  final post = Post(
    id: 12,
    postNumber: 2,
    username: 'sam',
    cooked: '<p>Reply</p>',
    bookmark: bookmark,
  );
  return (
    detail: TopicDetail(
      id: 7,
      title: 'Topic',
      stream: const [12],
      postsCount: 1,
      bookmarks: bookmark == null ? const [] : [bookmark],
    ),
    posts: [post],
  );
}

ChatMessage _chatMessage([Bookmark? bookmark]) => ChatMessage(
  id: 42,
  channelId: 9,
  cooked: '<p>Chat reply</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  bookmark: bookmark,
);

void _putChatFixture(ShellController shell) {
  shell.store.put(
    _site,
    const ChatChannel(
      id: 9,
      title: 'Support',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
    ),
  );
  shell.store.put(_site, _chatMessage());
}

TopicPayload _payloadWithTarget() {
  final initial = _payload();
  return (
    detail: initial.detail.copyWith(stream: const [12, 99]),
    posts: [
      ...initial.posts,
      const Post(
        id: 99,
        postNumber: 42,
        username: 'alex',
        cooked: '<p>Bookmarked target</p>',
      ),
    ],
  );
}

final class _GatedTopicApi extends FakeDiscourseApi {
  _GatedTopicApi()
    : super(
        user: const DiscourseUser(username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
      );

  final List<int?> postNumbers = [];
  final List<Completer<TopicPayload>> responses = [];

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    String? apiKey,
    String? clientId,
    bool summary = false,
  }) {
    postNumbers.add(postNumber);
    final response = Completer<TopicPayload>();
    responses.add(response);
    return response.future;
  }
}

final class _GatedCreateBookmarkApi extends FakeDiscourseApi {
  _GatedCreateBookmarkApi()
    : super(
        user: const DiscourseUser(username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        topics: {7: _payload()},
        siteConfigs: const {_site: SiteConfig.unknown()},
        bookmarkList: const [],
      );

  final Completer<void> started = Completer<void>();
  final Completer<int> response = Completer<int>();
  int calls = 0;

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) {
    calls++;
    started.complete();
    return response.future;
  }
}

final class _StaleTopicBookmarkApi extends FakeDiscourseApi {
  _StaleTopicBookmarkApi()
    : super(
        user: const DiscourseUser(username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
        bookmarkList: const [],
      );

  final Completer<void> staleStarted = Completer<void>();
  final Completer<TopicPayload> staleResponse = Completer<TopicPayload>();
  Bookmark? serverBookmark;
  int topicCalls = 0;

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    String? apiKey,
    String? clientId,
    bool summary = false,
  }) {
    topicCalls++;
    if (topicCalls == 2) {
      staleStarted.complete();
      return staleResponse.future;
    }
    return Future.value(_payload(bookmark: serverBookmark));
  }

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    serverBookmark = Bookmark(
      id: 91,
      bookmarkableId: targetId,
      bookmarkableType: targetType.wireName,
      postNumber: 2,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference:
          autoDeletePreference ?? BookmarkAutoDeletePreference.clearReminder,
    );
    return 91;
  }
}

final class _BookmarkFakeApi extends FakeDiscourseApi {
  _BookmarkFakeApi()
    : super(
        user: const DiscourseUser(username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        topics: {7: _payload()},
        siteConfigs: const {_site: SiteConfig.unknown()},
        bookmarkList: const [],
      );

  Bookmark? _bookmark;

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    final id = await super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    _bookmark = Bookmark(
      id: id,
      bookmarkableId: targetId,
      bookmarkableType: targetType.wireName,
      postNumber: 2,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference:
          autoDeletePreference ?? BookmarkAutoDeletePreference.clearReminder,
    );
    topics[7] = _payload(bookmark: _bookmark);
    return id;
  }

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async {
    await super.updateBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    _bookmark = _bookmark!.copyWith(
      name: name,
      clearName: name == null,
      reminderAt: reminderAt,
      clearReminder: reminderAt == null,
      autoDeletePreference: autoDeletePreference,
    );
    topics[7] = _payload(bookmark: _bookmark);
  }

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    await super.deleteBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      targetType: targetType,
      clientId: clientId,
    );
    _bookmark = null;
    topics[7] = _payload();
    return false;
  }
}

final class _ChatBookmarkFakeApi extends FakeDiscourseApi {
  _ChatBookmarkFakeApi()
    : super(
        user: const DiscourseUser(username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        topics: {7: _payload()},
        siteConfigs: const {_site: SiteConfig.unknown()},
        bookmarkList: const [],
      );

  Bookmark? _bookmark;
  final List<String> createdAtSites = [];

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    createdAtSites.add(siteUrl);
    final id = await super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    _bookmark = Bookmark(
      id: id,
      bookmarkableId: targetId,
      bookmarkableType: targetType.wireName,
      name: name,
      reminderAt: reminderAt?.toUtc(),
      autoDeletePreference:
          autoDeletePreference ?? BookmarkAutoDeletePreference.clearReminder,
    );
    return id;
  }

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async {
    await super.updateBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    _bookmark = _bookmark!.copyWith(
      name: name,
      clearName: name == null,
      reminderAt: reminderAt?.toUtc(),
      clearReminder: reminderAt == null,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    await super.deleteBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      targetType: targetType,
      clientId: clientId,
    );
    _bookmark = null;
    return null;
  }

  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async => (
    messages: [_chatMessage(_bookmark)],
    canLoadMorePast: false,
    canLoadMoreFuture: false,
    targetMessageId: targetMessageId,
  );
}

const _foreignBookmarkTarget = BookmarkTargetType(
  owner: PluginId('foreign'),
  name: 'record',
  wireName: 'Foreign::Record',
  refreshLabel: 'foreign record',
);

const _spoofedCoreWireTarget = BookmarkTargetType(
  owner: PluginId('probe'),
  name: 'spoofed-post',
  wireName: 'Post',
  refreshLabel: 'probe record',
);

final class _BookmarkAuthorityProbeModule implements PluginModule {
  final Set<String> deniedTargets = {};
  PluginBookmarkHost? spoofedCoreWireHost;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('probe'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession((bindings, _) {
      final factory = bindings.require(corePluginBookmarkPort);
      for (final target in const [
        BookmarkTargetType.post,
        _foreignBookmarkTarget,
      ]) {
        try {
          factory.forTarget(target);
        } on PluginInstallationException {
          deniedTargets.add(target.id);
        }
      }
      spoofedCoreWireHost = factory.forTarget(_spoofedCoreWireTarget);
      return PluginSessionContribution(lifecycle: _ProbeSessionLifecycle());
    }, requires: const [corePluginBookmarkPort]);
  }
}

final class _ProbeSessionLifecycle extends PluginSessionLifecycle {}
