import 'dart:async';

import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_notifications.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  for (final activity in _Activity.values) {
    group(activity.label, () {
      testWidgets('loads again when the shell controller changes', (
        tester,
      ) async {
        final firstApi = _RecordingActivityApi();
        final secondApi = _RecordingActivityApi();
        final first = await _controller(firstApi);
        final second = await _controller(
          secondApi,
          load: activity == _Activity.chat,
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);

        await tester.pumpWidget(
          _section(first, activity.section(first, _siteUrl)),
        );
        await tester.pumpAndSettle();
        expect(activity.requests(firstApi), [_siteUrl]);

        await tester.pumpWidget(
          _section(second, activity.section(second, _siteUrl)),
        );
        await tester.pumpAndSettle();

        expect(activity.requests(firstApi), [_siteUrl]);
        expect(activity.requests(secondApi), [_siteUrl]);
      });

      testWidgets('loads again when the section site changes', (tester) async {
        final sites = [
          _connected('meta.example', 'meta-reader'),
          _connected('other.example', 'other-reader'),
        ];
        final api = _RecordingActivityApi();
        final controller = await _controller(api, sites: sites);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _section(controller, activity.section(controller, sites.first.url)),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _section(controller, activity.section(controller, sites.last.url)),
        );
        await tester.pumpAndSettle();

        expect(activity.requests(api), [sites.first.url, sites.last.url]);
      });

      if (activity != _Activity.chat) {
        testWidgets(
          'a stale controller load cannot dispatch an activity request',
          (tester) async {
            final site = _connected('meta.example', 'reader');
            final firstStore = _GatedInstanceStore([site]);
            final firstApi = _RecordingActivityApi();
            final secondApi = _RecordingActivityApi();
            final first = await _controller(
              firstApi,
              sites: [site],
              store: firstStore,
              load: false,
            );
            final second = await _controller(
              secondApi,
              sites: [site],
              load: false,
            );
            addTearDown(first.dispose);
            addTearDown(second.dispose);

            await tester.pumpWidget(
              _section(first, activity.section(first, site.url)),
            );
            await firstStore.loadStarted.future;
            expect(activity.requests(firstApi), isEmpty);

            await tester.pumpWidget(
              _section(second, activity.section(second, site.url)),
            );
            await tester.pumpAndSettle();
            expect(activity.requests(secondApi), [site.url]);

            firstStore.complete();
            await tester.pumpAndSettle();

            expect(activity.requests(firstApi), isEmpty);
            expect(activity.requests(secondApi), [site.url]);
          },
        );

        testWidgets('a stale site load cannot dispatch an activity request', (
          tester,
        ) async {
          final sites = [
            _connected('meta.example', 'meta-reader'),
            _connected('other.example', 'other-reader'),
          ];
          final store = _GatedInstanceStore(sites);
          final api = _RecordingActivityApi();
          final controller = await _controller(
            api,
            sites: sites,
            store: store,
            load: false,
          );
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            _section(controller, activity.section(controller, sites.first.url)),
          );
          await store.loadStarted.future;

          await tester.pumpWidget(
            _section(controller, activity.section(controller, sites.last.url)),
          );
          expect(activity.requests(api), isEmpty);

          store.complete();
          await tester.pumpAndSettle();

          expect(activity.requests(api), [sites.last.url]);
        });
      }
    });
  }
}

enum _Activity {
  notifications,
  replies,
  chat,
  bookmarks,
  userActivity;

  String get label => switch (this) {
    notifications => 'notifications',
    replies => 'replies',
    chat => 'chat notifications',
    bookmarks => 'bookmarks',
    userActivity => 'user activity',
  };

  Widget section(ShellController controller, String siteUrl) => switch (this) {
    notifications => NotificationSection(siteUrl: siteUrl, onOpened: _ignore),
    replies => RepliesSection(siteUrl: siteUrl, onOpened: _ignore),
    chat => PluginNotificationsSection(
      siteUrl: siteUrl,
      onOpened: _ignore,
      host: controller,
      source: chatNotificationFeed,
    ),
    bookmarks => BookmarkSection(siteUrl: siteUrl, onOpened: _ignore),
    userActivity => UserActivityView(siteUrl: siteUrl),
  };

  List<String> requests(_RecordingActivityApi api) => switch (this) {
    notifications => api.notificationSites,
    replies => api.replySites,
    chat => api.chatSites,
    bookmarks => api.bookmarkSites,
    userActivity => api.userActivitySites,
  };
}

final class _RecordingActivityApi extends FakeDiscourseApi {
  _RecordingActivityApi()
    : super(
        notificationList: const [],
        replyNotificationList: const [],
        chatNotificationList: const [],
        bookmarkList: const [],
        user: const DiscourseUser(username: 'reader'),
      );

  final List<String> notificationSites = [];
  final List<String> replySites = [];
  final List<String> chatSites = [];
  final List<String> bookmarkSites = [];
  final List<String> userActivitySites = [];
  final Map<String, DiscourseUser> currentUsers = {};

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    final user = currentUsers[siteUrl];
    if (user != null) return Future.value(user);
    return super.currentUser(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) {
    if (filterByTypes.isEmpty) {
      notificationSites.add(siteUrl);
    } else if (_sameKinds(filterByTypes, userMenuReplyNotificationTypes)) {
      replySites.add(siteUrl);
    } else if (_sameKinds(filterByTypes, chatNotificationFeed.filterByTypes)) {
      chatSites.add(siteUrl);
    } else {
      throw StateError('Unexpected notification filter: $filterByTypes');
    }
    return super.notifications(
      siteUrl: siteUrl,
      apiKey: apiKey,
      limit: limit,
      filterByTypes: filterByTypes,
      clientId: clientId,
    );
  }

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) {
    bookmarkSites.add(siteUrl);
    return super.bookmarks(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      clientId: clientId,
    );
  }

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) {
    userActivitySites.add(siteUrl);
    return super.userActivity(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
  }
}

bool _sameKinds(
  List<NotificationTypeName> first,
  List<NotificationTypeName> second,
) =>
    first.length == second.length &&
    Iterable<int>.generate(
      first.length,
    ).every((index) => first[index] == second[index]);

final class _GatedInstanceStore implements InstanceStore {
  _GatedInstanceStore(this.instances);

  final List<DiscourseInstance> instances;
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> _loadGate = Completer<void>();

  @override
  Future<List<DiscourseInstance>> load() async {
    if (!loadStarted.isCompleted) loadStarted.complete();
    await _loadGate.future;
    return instances;
  }

  void complete() => _loadGate.complete();

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}

void _ignore() {}

DiscourseInstance _connected(String host, String username) =>
    instance(host).copyWith(user: DiscourseUser(username: username));

Widget _section(ShellController controller, Widget child) => ShellScope(
  controller: controller,
  child: MaterialApp(home: Scaffold(body: child)),
);

Future<ShellController> _controller(
  _RecordingActivityApi api, {
  List<DiscourseInstance>? sites,
  InstanceStore? store,
  bool load = true,
}) async {
  final resolvedSites = sites ?? [_connected('meta.example', 'reader')];
  for (final site in resolvedSites) {
    if (site.user case final user?) api.currentUsers[site.url] = user;
  }
  final authenticator = FakeAuthenticator();
  for (final site in resolvedSites) {
    authenticator.keys[site.url] = 'api-key';
  }
  final plugins = PluginInstaller.install(
    const PluginManifest([_ChatNotificationFeedModule()]),
  );
  addTearDown(plugins.close);
  final controller = ShellController(
    instanceStore: store ?? FakeInstanceStore(resolvedSites),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    plugins: plugins,
  );
  if (load) await controller.load();
  return controller;
}

final class _ChatNotificationFeedModule implements PluginModule {
  const _ChatNotificationFeedModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('chat'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _ChatNotificationFeedPlugin());
  }
}

final class _ChatNotificationFeedPlugin
    implements SitePlugin, NotificationFeedPlugin, NotificationTypePlugin {
  const _ChatNotificationFeedPlugin();

  @override
  String get name => 'chat';

  @override
  List<PluginNotificationType> get notificationTypes => chatNotificationTypes;

  @override
  List<PluginNotificationFeedSource> get notificationFeeds => const [
    chatNotificationFeed,
  ];
}
