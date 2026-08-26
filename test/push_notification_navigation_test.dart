import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/notification_opens.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      await Future<void>.delayed(Duration.zero);

      expect(opened, isTrue);
      expect(controller.currentInstance?.url, 'https://two.example');
      expect(controller.currentContent?.topicId, 42);
      expect(controller.currentContent?.postNumber, 3);
      expect(api.topicPostNumbersOpened, contains(3));
    },
  );

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
    expect(api.topicPostNumbersOpened, contains(7));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

DiscourseInstance _connected(String host) => instance(
  host,
).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));

final class _GatedInstanceStore implements InstanceStore {
  const _GatedInstanceStore(this.instances);

  final Future<List<DiscourseInstance>> instances;

  @override
  Future<List<DiscourseInstance>> load() => instances;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}
