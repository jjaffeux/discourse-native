import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _inbox = '/topics/private-messages/reader.json';
const _unread = '/topics/private-messages-unread/reader.json';
const _sent = '/topics/private-messages-sent/reader.json';
const _archive = '/topics/private-messages-archive/reader.json';
const _groupInbox = '/topics/private-messages-group/reader/team.json';
const _groupUnread = '/topics/private-messages-group/reader/team/unread.json';
const _groupArchive = '/topics/private-messages-group/reader/team/archive.json';

void main() {
  for (final (platform, width, textScale) in [
    (TargetPlatform.macOS, 1440.0, 1.0),
    (TargetPlatform.iOS, 360.0, 1.0),
    (TargetPlatform.linux, 640.0, 2.0),
  ]) {
    testWidgets(
      'keeps the inbox beside Messages at $width on ${platform.name} with ${textScale}x text',
      (tester) async {
        final setup = await _pumpInbox(
          tester,
          width: width,
          textScale: textScale,
        );
        setup.controller.selectMessageInbox(
          'engineering-infrastructure-platform-team',
        );
        await tester.pumpAndSettle();

        final title = find.text('Messages');
        final picker = find.byKey(const ValueKey('message-inbox-selector'));
        final navigation = find.byKey(
          const ValueKey('message-list-navigation'),
        );
        expect(title, findsOneWidget);
        expect(
          find.text('engineering-infrastructure-platform-team'),
          findsOneWidget,
        );
        expect(
          tester.getCenter(title).dy,
          closeTo(tester.getCenter(picker).dy, 1),
        );
        expect(
          tester.getRect(picker).left,
          greaterThan(tester.getRect(title).right),
        );
        expect(tester.getRect(picker).right, lessThanOrEqualTo(width));
        expect(
          tester.getRect(navigation).top,
          greaterThan(tester.getRect(picker).bottom),
        );
        expect(
          find.byType(ForumSearch),
          platform == TargetPlatform.macOS ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Personal'));
        await tester.pumpAndSettle();
        expect(setup.controller.currentContent, ContentRoute.messages());
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'switches message folders and inboxes using their own cached feeds',
    (tester) async {
      final setup = await _pumpInbox(tester);
      final shell = setup.controller;

      Future<void> folder(String mode) async {
        await tester.tap(find.byKey(ValueKey('message-list-$mode')));
        await tester.pumpAndSettle();
      }

      Future<void> inbox(String label) async {
        await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await folder('unread');
      expect(find.text('Unread personal message'), findsOneWidget);
      await inbox('team');
      expect(find.text('Unread group message'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-list-sent')), findsNothing);
      await folder('archive');
      expect(find.text('Archived group message'), findsOneWidget);
      await inbox('Personal');
      expect(find.text('Archived personal message'), findsOneWidget);
      await folder('sent');
      expect(find.text('Sent personal message'), findsOneWidget);
      await inbox('team');
      expect(shell.currentContent?.messageListMode, MessageListMode.inbox);
      expect(find.text('Group inbox message'), findsOneWidget);
      await inbox('Personal');
      expect(find.text('Personal inbox message'), findsOneWidget);
      expect(setup.api.feedPaths, [
        '/latest.json',
        _inbox,
        _unread,
        _groupUnread,
        _groupArchive,
        _archive,
        _sent,
        _groupInbox,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new personal message validates recipients and opens the native composer',
    (tester) async {
      final setup = await _pumpInbox(tester);
      await tester.tap(find.byKey(const ValueKey('new-message-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Choose at least one recipient.'), findsOneWidget);
      expect(setup.controller.visibleComposer, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('new-message-recipients')),
        'alex, sam',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      final target = setup.controller.visibleComposer!.target;
      expect(target.mode, ComposerMode.privateMessage);
      expect(target.targetRecipients, 'alex,sam');
      expect(target.originFeedId, 'messages');
      expect(setup.api.topicsCreated, isEmpty);
    },
  );

  testWidgets('new group message addresses the selected group', (tester) async {
    final setup = await _pumpInbox(tester);
    setup.controller.selectMessageInbox('team');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-message-button')));
    await tester.pumpAndSettle();
    expect(setup.controller.visibleComposer?.target.targetRecipients, 'team');
    expect(find.byKey(const ValueKey('new-message-recipients')), findsNothing);
    expect(setup.api.topicsCreated, isEmpty);
  });

  testWidgets(
    'keeps Personal visible without groups and hides unauthorized compose',
    (tester) async {
      await _pumpInbox(
        tester,
        user: const DiscourseUser(id: 1, username: 'reader'),
      );
      expect(find.text('Personal'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-message-button')), findsNothing);
      expect(find.byKey(const ValueKey('message-list-sent')), findsOneWidget);
    },
  );
}

Future<({ShellController controller, FakeDiscourseApi api})> _pumpInbox(
  WidgetTester tester, {
  double width = 1440,
  double textScale = 1,
  DiscourseUser user = const DiscourseUser(
    id: 1,
    username: 'reader',
    canSendPrivateMessages: true,
    messageGroupNames: ['team', 'engineering-infrastructure-platform-team'],
  ),
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final feeds = {
    _inbox: 'Personal inbox message',
    _unread: 'Unread personal message',
    _sent: 'Sent personal message',
    _archive: 'Archived personal message',
    _groupInbox: 'Group inbox message',
    _groupUnread: 'Unread group message',
    _groupArchive: 'Archived group message',
  };
  final api = FakeDiscourseApi(
    user: user,
    feeds: {
      '/latest.json': const [],
      for (final (index, entry) in feeds.entries.indexed)
        entry.key: [
          Topic(id: index + 1, title: entry.value, slug: 'message-$index'),
        ],
    },
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.selectDestination(
    const SidebarDestination(
      id: 'messages',
      label: 'Messages',
      icon: DIcons.inbox,
    ),
  );
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: MainContent(
            layout: width < 600 ? ShellLayout.compact : ShellLayout.expanded,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller: controller, api: api);
}
