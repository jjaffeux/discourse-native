import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/category_load_result.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_mutation_outcome.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart';

const _url = 'https://forum.example';
const _latency = Duration(milliseconds: 30);
const _user = DiscourseUser(id: 1, username: 'reader');
const _channel = ChatChannel(
  id: 9,
  title: 'Chat',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
  threadingEnabled: true,
);
const _message = ChatMessage(
  id: 14,
  channelId: 9,
  threadId: 3,
  cooked: '<p>Text</p>',
  author: ChatMessageAuthor(id: 1, username: 'reader'),
);
const _target = ChatThreadTarget(channelId: 9, threadId: 3);
const _page = (
  messages: [_message],
  canLoadMorePast: false,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln(
      jsonEncode({
        'load_cold_category_directory': await _directory(),
        'resolve_cold_chat_bookmark': await _bookmark(),
        'open_cold_chat_thread': await _thread(),
        'repair_selected_posts_across_three_pages': await _repairSelected(),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<double> _directory() async {
  final api = _Api();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('other.example'),
      instance('forum.example'),
    ]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  try {
    await shell.load();
    final watch = Stopwatch()..start();
    await shell.loadCategories(_url);
    watch.stop();
    final feed = shell.categoryFeedFor(_url);
    _check(
      feed.loaded && feed.error == null && feed.categoryIds.single == 7,
      'directory publication',
    );
    _check(
      api.categoryReads == 1 && api.configReads == 1,
      'directory requests',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

ChatController _chat(_Api api) => ChatController(
  api: api,
  requests: FakePluginRequestHost(
    credentials: FakeApiCredentialReader()..keys[_url] = 'key',
  ),
  store: Store(),
  currentUserFor: (_) => _user,
  siteConfigFor: (_) => SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(),
    ),
  ),
);

Future<double> _bookmark() async {
  final api = _Api();
  final chat = _chat(api);
  try {
    final watch = Stopwatch()..start();
    final message = await chat.resolveBookmarkMessage(
      _url,
      ChatLink(route: ChatRoute.channel(9), messageId: 14),
    );
    watch.stop();
    _check(
      message?.id == 14 && chat.message(_url, 14) == message,
      'bookmark target',
    );
    _check(api.channelReads == 1 && api.messageReads == 1, 'bookmark requests');
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    chat.dispose();
  }
}

Future<double> _thread() async {
  final api = _Api();
  final chat = _chat(api);
  try {
    final watch = Stopwatch()..start();
    await chat.openThread(_url, _target);
    watch.stop();
    final stream = chat.streamFor(_url, _target);
    _check(
      stream.messageIds.single == 14 &&
          stream.lastReadOnOpen == 14 &&
          stream.anchorMessageId == 14 &&
          !stream.loading &&
          stream.error == null,
      'thread publication and anchor',
    );
    _check(
      api.threadReads == 1 && api.threadWindowReads == 1,
      'thread requests',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    chat.dispose();
  }
}

Future<double> _repairSelected() async {
  final api = _Api();
  final store = Store();
  final owner = TopicDataOwner(
    content: api,
    feeds: api,
    models: const DiscourseModelCodec.core(),
    store: store,
    credentials: FakeApiCredentialReader(),
    lifecycle: SiteLifecycle(),
    changed: () {},
    liveChanged: (_) {},
    published: (_, _) => true,
    prepareCategories: (_, _) async {},
    loadTimeout: const Duration(seconds: 5),
    bookmarkReads: (_, _) => const _Bookmarks(),
  );
  try {
    final ids = [for (var id = 1; id <= 41; id++) id];
    store.put(_url, TopicDetail(id: 23, title: 'Topic', stream: ids));
    store.putAll(_url, [
      for (final id in ids)
        Post(id: id, postNumber: id, username: 'reader', cooked: '<p>Old</p>'),
    ]);
    final session = owner.forSite(_url);
    final watch = Stopwatch()..start();
    final freshness = await session.repairSelectedPosts(
      23,
      ids,
      'key',
      session.lease,
    );
    watch.stop();
    _check(
      freshness == PostProjectionFreshness.fresh && api.repairPages.length == 3,
      'three completed repair batches',
    );
    _check(
      api.repairPages.expand((page) => page).toList().join(',') ==
          ids.join(','),
      'complete requested coverage',
    );
    for (final id in ids) {
      _check(
        store.read<Post>(_url, id)?.cooked == '<p>Updated $id</p>',
        'repaired post $id',
      );
    }
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    owner.dispose();
  }
}

void _check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

final class _Api extends FakeDiscourseApi {
  var categoryReads = 0;
  var configReads = 0;
  var channelReads = 0;
  var messageReads = 0;
  var threadReads = 0;
  var threadWindowReads = 0;
  final repairPages = <List<int>>[];

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    if (siteUrl != _url) {
      return super.loadCategories(siteUrl: siteUrl, page: page);
    }
    categoryReads++;
    await Future<void>.delayed(_latency);
    return CategoryLoadResult(const [
      TopicCategory(id: 7, name: 'News', color: 'ffff00'),
    ]);
  }

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    if (siteUrl == _url) {
      configReads++;
      await Future<void>.delayed(_latency);
    }
    return const SiteConfig();
  }

  @override
  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    _check(channelId == 9, 'channel ID');
    channelReads++;
    await Future<void>.delayed(_latency);
    return _channel;
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
  }) async {
    _check(channelId == 9 && targetMessageId == 14, 'bookmark IDs');
    messageReads++;
    await Future<void>.delayed(_latency);
    return _page;
  }

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) async {
    _check(channelId == 9 && threadId == 3, 'thread detail IDs');
    threadReads++;
    await Future<void>.delayed(_latency);
    return const ChatThread(
      id: 3,
      channelId: 9,
      status: 'open',
      replyCount: 1,
      membership: ChatThreadMembership(threadId: 3, lastReadMessageId: 14),
    );
  }

  @override
  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    _check(channelId == 9 && threadId == 3, 'thread window IDs');
    threadWindowReads++;
    await Future<void>.delayed(_latency);
    return _page;
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    _check(
      topicId == 23 && apiKey == 'key',
      'captured moderation key and topic',
    );
    repairPages.add(ids);
    await Future<void>.delayed(_latency);
    return [
      for (final id in ids)
        Post(
          id: id,
          postNumber: id,
          username: 'reader',
          cooked: '<p>Updated $id</p>',
        ),
    ];
  }
}

final class _Bookmarks implements BookmarkReadProjection {
  const _Bookmarks();
  @override
  int get epoch => 0;
  @override
  int revision(int topicId) => 0;
  @override
  bool Function() guard(int topicId) =>
      () => true;
  @override
  Post postFromRead(int topicId, int version, Post incoming) => incoming;
  @override
  Post preservePost(Post incoming) => incoming;
  @override
  TopicDetail detailFromRead(int version, TopicDetail incoming) => incoming;
  @override
  Topic prepareRow(Topic incoming, int? versionAtDispatch) => incoming;
  @override
  Topic projectTopicRow(Topic incoming) => incoming;
}
