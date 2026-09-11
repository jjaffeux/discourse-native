import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/notification_opens.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported platforms expose no native notification opens', () async {
    final opens = PlatformNotificationOpens(platform: TargetPlatform.linux);

    expect(await opens.urls.toList(), isEmpty);
  });

  test(
    'a notification switches forums and opens its exact topic post',
    () async {
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        topics: {42: topicPayload(id: 42, title: 'Native push')},
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([
          _connected('one.example'),
          _connected('two.example'),
        ]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final opened = await controller.openNotificationUrl(
        'https://two.example/t/native-push/42/3',
      );
      await _waitForTopic(controller);

      expect(opened, isTrue);
      expect(controller.currentInstance?.url, 'https://two.example');
      expect(controller.currentContent?.topicId, 42);
      expect(controller.currentContent?.postNumber, 3);
      expect(api.topicPostNumbersOpened, [3]);
      expect(controller.topicListContent?.id, 'latest');
    },
  );

  test('a reaction notification refreshes its cached target post', () async {
    final topics = <int, TopicPayload>{42: _reactionTopic()};
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      topics: topics,
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([_connected('one.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    addTearDown(controller.dispose);
    await controller.load();

    const target = 'https://one.example/t/reactions/42/1';
    expect(await controller.openNotificationUrl(target), isTrue);
    await _waitForTopic(controller);
    expect(
      controller.store.read<Post>('https://one.example', 1)?.reactions?.entries,
      isEmpty,
    );

    topics[42] = _reactionTopic(
      reactions: const [Reaction(id: 'clap', count: 1)],
    );
    expect(await controller.openNotificationUrl(target), isTrue);
    await _waitForTopic(controller);

    expect(api.topicsOpened, [42, 42]);
    expect(
      controller.store.read<Post>('https://one.example', 1)?.reactions?.entries,
      const [Reaction(id: 'clap', count: 1)],
    );
  });

  for (final cached in [false, true]) {
    for (final existingInbox in [false, true]) {
      test('PM notification selects its list (cached: $cached, '
          'existing inbox: $existingInbox)', () async {
        final payload = topicPayload(id: 42, title: 'Private conversation');
        final message = (
          detail: payload.detail.copyWith(privateMessage: true),
          posts: payload.posts,
        );
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          topics: {42: message},
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([_connected('one.example')]),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        final inbox = ContentRoute.messages(
          groupName: 'team',
          mode: MessageListMode.archive,
        );
        if (existingInbox) controller.pushContent(inbox);
        if (cached) controller.store.put('https://one.example', message.detail);

        expect(
          await controller.openNotificationUrl(
            'https://one.example/t/private-conversation/42/3',
          ),
          isTrue,
        );
        await _waitForTopic(controller);

        expect(controller.currentContent?.topicId, 42);
        expect(controller.currentContent?.postNumber, 3);
        expect(
          controller.contentStack[controller.contentStack.length - 2].id,
          existingInbox ? inbox.id : 'messages',
        );
        if (!existingInbox) {
          expect(
            api.feedPaths,
            contains('/topics/private-messages/reader.json'),
          );
        }
        controller.handleBack();
        expect(controller.currentContent?.isMessages, isTrue);
      });
    }
  }

  test('notification navigation rejects unsafe and unowned URLs', () async {
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        _connected('one.example'),
        instance('signed-out.example'),
      ]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();

    for (final url in const [
      'https://elsewhere.example/t/topic/1',
      'https://signed-out.example/t/topic/1',
      'http://one.example/t/topic/1',
      'https://user:secret@one.example/t/topic/1',
      'https://one.example/u/reader',
    ]) {
      expect(await controller.openNotificationUrl(url), isFalse, reason: url);
    }
    expect(controller.currentInstance?.url, 'https://one.example');
    expect(controller.currentContent?.topicId, isNull);
  });

  test(
    'a notification cannot navigate after its account lease expires',
    () async {
      final started = Completer<void>();
      final pluginResult = Completer<bool>();
      final plugins = PluginInstaller.install(
        PluginManifest([
          _NotificationLinkModule((_) {
            started.complete();
            return pluginResult.future;
          }),
        ]),
      );
      addTearDown(plugins.close);
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        topics: {42: topicPayload(id: 42, title: 'Expired notification')},
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([_connected('one.example')]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: plugins,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final opening = controller.openNotificationUrl(
        'https://one.example/t/expired/42/1',
      );
      await started.future;
      controller.lifecycle.invalidate('https://one.example');
      pluginResult.complete(false);

      expect(await opening, isFalse);
      expect(controller.currentContent?.topicId, isNull);
      expect(api.topicsOpened, isEmpty);
    },
  );

  testWidgets('a cold-start tap waits for stored forums before navigating', (
    tester,
  ) async {
    final stored = Completer<List<DiscourseInstance>>();
    final opens = StreamController<String>.broadcast(sync: true);
    addTearDown(opens.close);
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      topics: {42: topicPayload(id: 42, title: 'Cold start')},
    );

    await tester.pumpWidget(
      DiscourseApp(
        store: _GatedInstanceStore(stored.future),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
        notificationOpenUrls: opens.stream,
      ),
    );

    opens.add('https://one.example/t/cold-start/42/7');
    stored.complete([_connected('one.example')]);
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ShellScope>(find.byType(ShellScope))
        .notifier!;
    expect(controller.currentContent?.topicId, 42);
    expect(controller.currentContent?.postNumber, 7);
    expect(api.topicPostNumbersOpened, [7]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a burst of taps preserves the newest pending destinations', (
    tester,
  ) async {
    final opens = StreamController<String>.broadcast(sync: true);
    addTearDown(opens.close);
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      topics: {42: topicPayload(id: 42, title: 'Notification queue')},
    );
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore([_connected('one.example')]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
        notificationOpenUrls: opens.stream,
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ShellScope>(find.byType(ShellScope))
        .notifier!;
    final openedPosts = <int>[];
    controller.addListener(() {
      final post = controller.currentContent?.postNumber;
      if (post != null && openedPosts.lastOrNull != post) {
        openedPosts.add(post);
      }
    });
    for (var post = 1; post <= 20; post++) {
      opens.add('https://one.example/t/notification-queue/42/$post');
    }
    await tester.pumpAndSettle();

    expect(openedPosts, [1, for (var post = 5; post <= 20; post++) post]);
    expect(controller.currentContent?.postNumber, 20);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

DiscourseInstance _connected(String host) => instance(
  host,
).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));

TopicPayload _reactionTopic({List<Reaction> reactions = const []}) =>
    topicPayload(
      id: 42,
      title: 'Reactions',
      posts: [
        Post(
          id: 1,
          postNumber: 1,
          username: 'author',
          cooked: '<p>Post body</p>',
          plugins: PluginData.none.withValue(
            reactionsDataKey,
            Reactions(entries: reactions, userCount: reactions.length),
          ),
        ),
      ],
    );

Future<void> _waitForTopic(ShellController controller) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(Duration.zero);
    if (!controller.currentTopicLoading) return;
  }
  fail('Topic did not finish loading');
}

final class _GatedInstanceStore implements InstanceStore {
  const _GatedInstanceStore(this.instances);

  final Future<List<DiscourseInstance>> instances;

  @override
  Future<List<DiscourseInstance>> load() => instances;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}

final class _NotificationLinkModule implements PluginModule {
  const _NotificationLinkModule(this.open);

  final Future<bool> Function(String url) open;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('notification-link-test'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _NotificationLinkLifecycle(),
        capabilities: [_NotificationLinkHandler(open)],
      ),
    );
  }
}

final class _NotificationLinkLifecycle extends PluginSessionLifecycle {}

final class _NotificationLinkHandler implements PluginLinkHandler {
  const _NotificationLinkHandler(this.open);

  final Future<bool> Function(String url) open;

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) => open(url);
}
