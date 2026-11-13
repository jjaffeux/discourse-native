import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/src/data/category_load_result.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_conversation.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
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
const _topic = Topic(id: 23, title: 'Topic', slug: 'topic', categoryId: 7);
const _post = Post(
  id: 123,
  postNumber: 1,
  username: 'reader',
  cooked: '<p>Text</p>',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    stdout.writeln(
      jsonEncode({
        'follow_cold_chat_thread_link': await _followLink(),
        'open_topic_with_unloaded_category': await _openTopic(),
        'refresh_topic_and_retained_feed_after_plugin_mutation':
            await _reconcile(),
        'load_embedded_thread_with_uncached_channel': await _conversation(),
      }),
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

Future<double> _followLink() async {
  final api = _Api();
  final fixture = await _shell(api);
  final chat = _chat(api);
  final navigation = ChatShellService(
    chat: chat,
    host: fixture.module.navigation,
    routeNavigation: fixture.module.routes,
    openNewTopic: (_) async => OpenComposerResult.unavailable,
    store: Store(),
    postFlagCatalog: (_) => const [],
  );
  try {
    final watch = Stopwatch()..start();
    final opened = await navigation.openPluginUrl('$_url/chat/c/-/9/t/3');
    watch.stop();
    _check(
      opened &&
          fixture.shell.currentContent?.id ==
              ChatRoute.thread(channelId: 9, threadId: 3).routeId,
      'navigated to thread',
    );
    _check(
      api.chatDirectoryReads == 1 &&
          api.threadReads == 1 &&
          api.channelReads == 0,
      'thread and directory requests',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    navigation.dispose();
    chat.dispose();
    fixture.shell.dispose();
  }
}

Future<double> _openTopic() async {
  final api = _Api();
  final fixture = await _shell(api);
  final shell = fixture.shell;
  try {
    shell.store.put(_url, _topic);
    final watch = Stopwatch()..start();
    await shell.loadTopic(23, 'topic');
    watch.stop();
    _check(
      shell.store.read<Post>(_url, 123)?.cooked == '<p>Text</p>' &&
          shell.store.read<TopicCategory>(_url, 7)?.name == 'News',
      'topic and category publication',
    );
    _check(
      api.topicReads == 1 && api.categoryReads == 1,
      'one topic and supplement request',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

Future<double> _reconcile() async {
  final api = _Api();
  final fixture = await _shell(api);
  final shell = fixture.shell;
  try {
    const destinationId = 'benchmark-retained-feed';
    await shell.topicFeeds.load(
      instance: shell.currentInstance!,
      destinationId: destinationId,
      path: '/latest.json?benchmark=retained',
      incoming: null,
    );
    _check(
      shell.topicFeeds.feedFor(_url, destinationId)?.topicIds.contains(23) ==
          true,
      'retained feed ready',
    );
    api.feedReads = 0;
    api.repair = true;
    final watch = Stopwatch()..start();
    final result = await fixture.module.refresh.refreshAfterMutation!(
      siteUrl: _url,
      topicId: 23,
      lease: fixture.module.requests.capture(_url),
    );
    watch.stop();
    _check(
      result == PluginTopicRefreshResult.refreshed &&
          shell.store.read<TopicDetail>(_url, 23)?.title == 'Updated' &&
          shell.topicFeeds
                  .feedFor(_url, destinationId)
                  ?.topicIds
                  .contains(23) ==
              true,
      'refreshed topic and feed',
    );
    _check(
      api.topicReads == 1 && api.repairFeedReads == 1,
      'both repair reads',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    shell.dispose();
  }
}

Future<double> _conversation() async {
  final api = _Api();
  final chat = _chat(api);
  final conversation = ChatControllerConversationCapability(
    chat,
  ).openThread(siteUrl: _url, channelId: 9, threadId: 3);
  try {
    final watch = Stopwatch()..start();
    await conversation.refresh();
    watch.stop();
    _check(
      conversation.value.messages.single.id == 14 &&
          !conversation.value.loading &&
          conversation.value.error == null,
      'ready conversation',
    );
    _check(
      api.threadReads == 1 &&
          api.threadWindowReads == 1 &&
          api.channelReads == 1,
      'three conversation reads',
    );
    return watch.elapsedMicroseconds.toDouble();
  } finally {
    conversation.close();
    chat.dispose();
  }
}

ChatController _chat(_Api api) => ChatController(
  api: api,
  requests: FakePluginRequestHost(
    credentials: FakeApiCredentialReader()..keys[_url] = 'key',
  ),
  store: Store(),
  currentUserFor: (_) => _user,
);

Future<({ShellController shell, _Module module})> _shell(_Api api) async {
  final module = _Module();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('forum.example', user: _user)]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    plugins: PluginInstaller.install(PluginManifest([module])),
  );
  await shell.load();
  await shell.loadFeed(shell.currentContent!.id);
  return (shell: shell, module: module);
}

void _check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

final class _Module implements PluginModule {
  late PluginNavigationHost navigation;
  late PluginRouteNavigationHost routes;
  late PluginTopicRefreshHost refresh;
  late PluginRequestHost requests;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('benchmark'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (bindings, _) {
        navigation = bindings.require(corePluginNavigationPort);
        routes = bindings.require(corePluginRouteNavigationPort);
        refresh = bindings.require(corePluginTopicRefreshPort);
        requests = bindings.require(corePluginRequestPort);
        return PluginSessionContribution(lifecycle: _Lifecycle());
      },
      requires: const [
        corePluginNavigationPort,
        corePluginRouteNavigationPort,
        corePluginTopicRefreshPort,
        corePluginRequestPort,
      ],
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {}

final class _Api extends FakeDiscourseApi {
  _Api() : super(user: _user);
  var chatDirectoryReads = 0;
  var threadReads = 0;
  var threadWindowReads = 0;
  var channelReads = 0;
  var topicReads = 0;
  var categoryReads = 0;
  var feedReads = 0;
  var repairFeedReads = 0;
  var repair = false;

  @override
  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    chatDirectoryReads++;
    await Future<void>.delayed(_latency);
    return const ChatChannels(public: [_channel]);
  }

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) async {
    threadReads++;
    await Future<void>.delayed(_latency);
    return const ChatThread(id: 3, channelId: 9, status: 'open', replyCount: 1);
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
    threadWindowReads++;
    await Future<void>.delayed(_latency);
    return (
      messages: const <ChatMessage>[_message],
      canLoadMorePast: false,
      canLoadMoreFuture: false,
      targetMessageId: null,
    );
  }

  @override
  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    channelReads++;
    await Future<void>.delayed(_latency);
    return _channel;
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(const []);

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    categoryReads++;
    await Future<void>.delayed(_latency);
    return const [TopicCategory(id: 7, name: 'News', color: 'ffff00')];
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    feedReads++;
    final retained = path == '/latest.json?benchmark=retained';
    if (repair && retained) {
      repairFeedReads++;
      await Future<void>.delayed(_latency);
    }
    return TopicList(
      topics: [
        if (repair && retained)
          _topic.copyWith(title: 'Updated')
        else if (retained)
          _topic,
      ],
    );
  }

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
  }) async {
    topicReads++;
    await Future<void>.delayed(_latency);
    return (
      detail: TopicDetail(
        id: id,
        title: repair ? 'Updated' : 'Topic',
        categoryId: repair ? null : 7,
        stream: const [123],
      ),
      posts: const <Post>[_post],
    );
  }
}
