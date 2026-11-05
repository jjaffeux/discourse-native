import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/invite_fixtures.dart';

const _siteA = 'https://a.example';
const _inviter = DiscourseUser(
  id: 1,
  username: 'reader',
  canInviteToForum: true,
);
const _inviteKey = ValueKey('topic-share-invite');
const _sheetTitle = 'Invite to this topic';

void main() {
  group('canInviteToTopic', () {
    Future<ShellController> shellFor(DiscourseUser user) async {
      final shell = await _createShell(_ShareApi(user), user);
      addTearDown(shell.dispose);
      return shell;
    }

    test(
      'needs the forum invite right and the topic right, on a live topic',
      () async {
        final shell = await shellFor(_inviter);
        expect(shell.canInviteToTopic(_topic()), isTrue);
        expect(shell.canInviteToTopic(_topic(canInviteTo: false)), isFalse);
        expect(shell.canInviteToTopic(_topic(closed: true)), isFalse);
        expect(shell.canInviteToTopic(_topic(archived: true)), isFalse);
        expect(
          shell.canInviteToTopic(_topic(deletedAt: DateTime.utc(2026))),
          isFalse,
        );
      },
    );

    test('is withheld from a user who cannot invite to the forum', () async {
      final shell = await shellFor(
        const DiscourseUser(id: 1, username: 'reader'),
      );
      expect(shell.canInviteToTopic(_topic()), isFalse);
    });
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    final surface = platform == TargetPlatform.macOS ? 'menu' : 'sheet';

    testWidgets('$surface: invites to the shared topic through the editor', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, platform: platform);
      await harness.openShare(tester);
      expect(find.text('Invite people'), findsOneWidget);

      await tester.tap(find.byKey(_inviteKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_inviteKey), findsNothing);
      expect(find.text(_sheetTitle), findsOneWidget);
      expect(find.text('Create invite'), findsNothing);
      await tester.ensureVisible(find.text('Create invite link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create invite link'));
      await tester.pumpAndSettle();

      final write = harness.api.pluginWrites.single;
      expect((write.method, write.path), ('POST', '/invites.json'));
      expect(write.body['topic_id'], 7);
      expect(write.body, isNot(contains('invite_to_topic')));
      expect(find.text('Invite link created.'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsNothing);
    });
  }

  testWidgets('offers no invite for a closed topic or one without the right', (
    tester,
  ) async {
    for (final detail in [
      _topic(closed: true),
      _topic(canInviteTo: false),
      _topic(archived: true),
      _topic(deletedAt: DateTime.utc(2026)),
    ]) {
      final harness = await _Harness.create(tester, detail: detail);
      await harness.openShare(tester);
      expect(find.byKey(_inviteKey), findsNothing);
      expect(find.text('Invite people'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final replacement in ['topic', 'account']) {
    testWidgets('a share surface outliving a $replacement change opens no '
        'editor', (tester) async {
      final harness = await _Harness.create(tester);
      final shell = harness.shell;
      await harness.openShare(tester);
      if (replacement == 'topic') {
        _openTopic(shell, topicId: 8);
      } else {
        await shell.disconnectCurrentInstance();
        harness.api.account = const DiscourseUser(
          id: 2,
          username: 'replacement',
          canInviteToForum: true,
        );
        await shell.connectCurrentInstance();
        _openTopic(shell);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_inviteKey), findsOneWidget);

      await tester.tap(find.byKey(_inviteKey));
      await tester.pumpAndSettle();

      expect(find.text(_sheetTitle), findsNothing);
      expect(find.byKey(_inviteKey), findsNothing);
      expect(harness.api.pluginWrites, isEmpty);
    });
  }
}

final class _Harness {
  _Harness(this.shell, this.api);

  final ShellController shell;
  final _ShareApi api;

  static Future<_Harness> create(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.macOS,
    TopicDetail? detail,
  }) async {
    tester.view.physicalSize = platform == TargetPlatform.iOS
        ? const Size(390, 844)
        : const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ShareApi(_inviter);
    final shell = await _createShell(api, _inviter, detail: detail);
    addTearDown(() {
      if (!shell.accountSessionDisposed) shell.dispose();
    });
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final controller = ShellScope.of(context);
                final topic = controller.currentTopic;
                if (topic == null) return const SizedBox();
                return Center(
                  child: TopicShareButton(
                    siteUrl: controller.currentInstance!.url,
                    topic: topic,
                    route: controller.currentContent,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Harness(shell, api);
  }

  Future<void> openShare(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('topic-share-button')));
    await tester.pumpAndSettle();
  }
}

TopicDetail _topic({
  int id = 7,
  bool canInviteTo = true,
  bool closed = false,
  bool archived = false,
  DateTime? deletedAt,
}) => TopicDetail(
  id: id,
  title: id == 7 ? 'A real topic' : 'Another topic',
  stream: const [1],
  categoryId: 5,
  canInviteTo: canInviteTo,
  closed: closed,
  archived: archived,
  deletedAt: deletedAt,
);

Future<ShellController> _createShell(
  _ShareApi api,
  DiscourseUser user, {
  TopicDetail? detail,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('a.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteA] = 'a-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  _openTopic(shell, detail: detail);
  return shell;
}

void _openTopic(ShellController shell, {int topicId = 7, TopicDetail? detail}) {
  final siteUrl = shell.currentInstance!.url;
  shell.store.put(siteUrl, detail ?? _topic(id: topicId));
  shell.store.put(
    siteUrl,
    const Post(id: 1, postNumber: 1, username: 'author', cooked: '<p>Post</p>'),
  );
  shell.pushContent(
    ContentRoute.topic(
      topicId: topicId,
      slug: topicId == 7 ? 'a-real-topic' : 'another-topic',
      title: topicId == 7 ? 'A real topic' : 'Another topic',
    ),
  );
}

class _ShareApi extends FakeDiscourseApi {
  _ShareApi(this.account)
    : super(
        feeds: const {'/latest.json': []},
        pluginResponses: {'POST /invites.json': inviteRow(9)},
      );

  DiscourseUser account;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => account;
}
