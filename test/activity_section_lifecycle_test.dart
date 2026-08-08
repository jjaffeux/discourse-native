import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('notifications load again when the shell controller changes', (
    tester,
  ) async {
    final firstApi = FakeDiscourseApi(notificationList: const []);
    final secondApi = FakeDiscourseApi(notificationList: const []);
    final first = await _controller(firstApi);
    final second = await _controller(secondApi, load: false);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _section(
        first,
        const NotificationSection(siteUrl: _siteUrl, onOpened: _ignore),
      ),
    );
    await tester.pumpAndSettle();
    expect(firstApi.notificationCalls, 1);

    await tester.pumpWidget(
      _section(
        second,
        const NotificationSection(siteUrl: _siteUrl, onOpened: _ignore),
      ),
    );
    await tester.pumpAndSettle();

    expect(firstApi.notificationCalls, 1);
    expect(secondApi.notificationCalls, 1);
  });

  testWidgets('bookmarks load again when the shell controller changes', (
    tester,
  ) async {
    const user = DiscourseUser(username: 'reader');
    final firstApi = FakeDiscourseApi(bookmarkList: const [], user: user);
    final secondApi = FakeDiscourseApi(bookmarkList: const [], user: user);
    final first = await _controller(firstApi);
    final second = await _controller(secondApi, load: false);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      _section(
        first,
        const BookmarkSection(siteUrl: _siteUrl, onOpened: _ignore),
      ),
    );
    await tester.pumpAndSettle();
    expect(firstApi.bookmarksRequested, ['reader']);

    await tester.pumpWidget(
      _section(
        second,
        const BookmarkSection(siteUrl: _siteUrl, onOpened: _ignore),
      ),
    );
    await tester.pumpAndSettle();

    expect(firstApi.bookmarksRequested, ['reader']);
    expect(secondApi.bookmarksRequested, ['reader']);
  });
}

void _ignore() {}

Widget _section(ShellController controller, Widget child) => ShellScope(
  controller: controller,
  child: MaterialApp(home: Scaffold(body: child)),
);

Future<ShellController> _controller(
  FakeDiscourseApi api, {
  bool load = true,
}) async {
  final site = instance(
    'meta.example',
  ).copyWith(user: const DiscourseUser(username: 'reader'));
  final authenticator = FakeAuthenticator()..keys[site.url] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  if (load) await controller.load();
  return controller;
}
