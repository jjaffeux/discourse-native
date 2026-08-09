import 'dart:async';

import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
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
        final second = await _controller(secondApi, load: false);
        addTearDown(first.dispose);
        addTearDown(second.dispose);

        await tester.pumpWidget(_section(first, activity.section(_siteUrl)));
        await tester.pumpAndSettle();
        expect(activity.requests(firstApi), [_siteUrl]);

        await tester.pumpWidget(_section(second, activity.section(_siteUrl)));
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
          _section(controller, activity.section(sites.first.url)),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _section(controller, activity.section(sites.last.url)),
        );
        await tester.pumpAndSettle();

        expect(activity.requests(api), [sites.first.url, sites.last.url]);
      });

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

          await tester.pumpWidget(_section(first, activity.section(site.url)));
          await firstStore.loadStarted.future;
          expect(activity.requests(firstApi), isEmpty);

          await tester.pumpWidget(_section(second, activity.section(site.url)));
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
          _section(controller, activity.section(sites.first.url)),
        );
        await store.loadStarted.future;

        await tester.pumpWidget(
          _section(controller, activity.section(sites.last.url)),
        );
        expect(activity.requests(api), isEmpty);

        store.complete();
        await tester.pumpAndSettle();

        expect(activity.requests(api), [sites.last.url]);
      });
    });
  }
}

enum _Activity {
  notifications,
  replies,
  chat,
  bookmarks;

  String get label => switch (this) {
    notifications => 'notifications',
    replies => 'replies',
    chat => 'chat notifications',
    bookmarks => 'bookmarks',
  };

  Widget section(String siteUrl) => switch (this) {
    notifications => NotificationSection(siteUrl: siteUrl, onOpened: _ignore),
    replies => RepliesSection(siteUrl: siteUrl, onOpened: _ignore),
    chat => ChatNotificationsSection(siteUrl: siteUrl, onOpened: _ignore),
    bookmarks => BookmarkSection(siteUrl: siteUrl, onOpened: _ignore),
  };

  List<String> requests(_RecordingActivityApi api) => switch (this) {
    notifications => api.notificationSites,
    replies => api.replySites,
    chat => api.chatSites,
    bookmarks => api.bookmarkSites,
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

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) {
    if (filterByTypes.isEmpty) {
      notificationSites.add(siteUrl);
    } else if (_sameKinds(filterByTypes, userMenuReplyNotificationKinds)) {
      replySites.add(siteUrl);
    } else if (_sameKinds(filterByTypes, userMenuChatNotificationKinds)) {
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
}

bool _sameKinds(List<NotificationKind> first, List<NotificationKind> second) =>
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
  final authenticator = FakeAuthenticator();
  for (final site in resolvedSites) {
    authenticator.keys[site.url] = 'api-key';
  }
  final controller = ShellController(
    instanceStore: store ?? FakeInstanceStore(resolvedSites),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  if (load) await controller.load();
  return controller;
}
