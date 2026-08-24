import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('post bookmark lifecycle updates every cached representation', () async {
    final api = _BookmarkFakeApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final created = await shell.createBookmark(
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
      topicId: 0,
      targetType: BookmarkTargetType.chatMessage,
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
    expect(
      api.createdBookmarks.single.targetType,
      BookmarkTargetType.chatMessage,
    );
    expect(api.bookmarksRequested, isNotEmpty);

    final updated = await shell.updateBookmark(
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
      topicId: 0,
      bookmark: updated.bookmark!,
    );
    await pumpEventQueue();

    expect(deleted.saved, isTrue);
    expect(shell.store.read<ChatMessage>(_site, 42)?.bookmark, isNull);
    expect(api.deletedBookmarks, [created.bookmark!.id]);
  });

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
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 12,
    );
    await api.started.future;
    final duplicate = await shell.createBookmark(
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
      topicId: 0,
      targetType: BookmarkTargetType.chatMessage,
      targetId: 42,
    );
    await api.started.future;
    final duplicate = await shell.createBookmark(
      topicId: 0,
      targetType: BookmarkTargetType.chatMessage,
      targetId: 42,
    );

    expect(duplicate.saved, isFalse);
    expect(duplicate.message, contains('still finishing'));
    expect(api.calls, 1);

    api.response.complete(88);
    expect((await first).saved, isTrue);
  });

  test('a pre-write topic response cannot erase a saved bookmark', () async {
    final api = _StaleTopicBookmarkApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final stale = shell.loadTopic(7, 'topic', force: true);
    await api.staleStarted.future;
    final created = await shell.createBookmark(
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
