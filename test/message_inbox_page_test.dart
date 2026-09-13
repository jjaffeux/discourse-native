import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('restored inbox keeps its label and a route back to Personal', (
    tester,
  ) async {
    final setup = await _pumpInbox(tester);
    setup.controller.replaceCurrentContent(
      ContentRoute.messages(groupName: 'former-team'),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Choose inbox: former-team'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
    await tester.pumpAndSettle();
    final menu = find.byType(DComboboxContent);
    expect(
      find.descendant(of: menu, matching: find.text('former-team')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: menu, matching: find.text('Personal')),
    );
    await tester.pumpAndSettle();
    expect(setup.controller.currentContent, ContentRoute.messages());
    expect(menu, findsNothing);
  });

  for (final change in ['session', 'folder', 'site']) {
    testWidgets('open inbox menu rejects $change changes before rebuilding', (
      tester,
    ) async {
      final setup = await _pumpInbox(tester, secondSite: true);
      final shell = setup.controller;
      await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
      await tester.pumpAndSettle();
      switch (change) {
        case 'session':
          shell.lifecycle.invalidate(_site);
        case 'folder':
          shell.selectMessageListMode(MessageListMode.unread);
        case 'site':
          shell.selectInstance(1);
          shell.selectDestination(
            const SidebarDestination(
              id: 'messages',
              label: 'Messages',
              icon: DIcons.inbox,
            ),
          );
      }
      final route = shell.currentContent;
      // Activate the still-mounted old menu before its next frame.
      await tester.tap(
        find.descendant(
          of: find.byType(DComboboxContent),
          matching: find.text('team'),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent, route);
      expect(shell.currentContent?.messageGroupName, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('navigation retires an open inbox menu', (tester) async {
    final setup = await _pumpInbox(tester);
    await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
    await tester.pumpAndSettle();
    setup.controller.pushContent(ContentRoute.userActivity());
    await tester.pumpAndSettle();
    expect(find.byType(DComboboxContent), findsNothing);
    expect(find.byTooltip('Choose inbox: Personal'), findsNothing);
  });

  testWidgets('keyboard inbox switching keeps the trigger focused', (
    tester,
  ) async {
    final setup = await _pumpInbox(tester);
    setup.controller.selectMessageListMode(MessageListMode.sent);
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('message-inbox-selector'));
    await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DComboboxContent),
        matching: find.byType(TextField),
      ),
      'tEaM',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      setup.controller.currentContent,
      ContentRoute.messages(groupName: 'team'),
    );
    expect(tester.widget<DButton>(picker).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(DComboboxContent), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(DComboboxContent),
        matching: find.byType(TextField),
      ),
      'personal',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(setup.controller.currentContent, ContentRoute.messages());
    expect(tester.widget<DButton>(picker).focusNode!.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final group in [null, 'team']) {
    testWidgets(
      'activates ${group ?? 'Personal'} folders ahead of the selected message at 200% text',
      (tester) async {
        final setup = await _pumpInbox(tester, width: 360, textScale: 2);
        setup.controller.selectMessageInbox(group);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('message-list-inbox')));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(
          setup.controller.currentContent?.messageListMode,
          MessageListMode.inbox,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.text(
            group == null ? 'Unread personal message' : 'Unread group message',
          ),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        final archive = find.byKey(const ValueKey('message-list-archive'));
        expect(archive.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(archive).bottom,
          lessThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('new-message-button')))
                .top,
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(
          find.text(
            group == null
                ? 'Archived personal message'
                : 'Archived group message',
          ),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.text(
            group == null ? 'Sent personal message' : 'Unread group message',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

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

  testWidgets('message reader keeps its list, footer and collapse control', (
    tester,
  ) async {
    final setup = await _pumpInbox(tester, inboxCount: 20);
    final shell = setup.controller;
    final list = find.byType(TopicListView);
    final listElement = tester.element(list);
    final scroll = tester
        .widget<Scrollable>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .controller!;
    scroll.jumpTo(350);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('topic-card-14'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 14);
    expect(shell.topicListContent, ContentRoute.messages());
    expect(shell.currentFeedId, 'messages');
    expect(tester.element(list), same(listElement));
    expect(tester.widget<DItem>(row).selected, isTrue);
    final listPane = find.byKey(const ValueKey('inbox-topic-list-pane'));
    final readerPane = find.byKey(const ValueKey('inbox-topic-reader-pane'));
    expect(tester.getRect(listPane).right, tester.getRect(readerPane).left);
    final listFooter = find.byKey(const ValueKey('topic-list-bottom-bar'));
    final readerFooter = find.byKey(const ValueKey('topic-bottom-bar'));
    expect(
      tester.getRect(listFooter).bottom,
      tester.getRect(readerFooter).bottom,
    );
    expect(
      find.descendant(of: listFooter, matching: find.byTooltip('New message')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('topic-reply-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-bookmark-button')), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse message'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicView), findsNothing);
    expect(tester.element(list), same(listElement));
    expect(scroll.offset, greaterThan(0));
    expect(row.hitTestable(), findsOneWidget);
    expect(shell.currentContent, ContentRoute.messages());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'message arrows and gj/gk navigate the source feed and paginate',
    (tester) async {
      final setup = await _pumpInbox(tester, inboxCount: 2, paginate: true);
      final shell = setup.controller;
      await tester.tap(find.byKey(const ValueKey('topic-card-1')));
      await tester.pumpAndSettle();
      final previous = find.byKey(const ValueKey('inbox-previous-topic'));
      final next = find.byKey(const ValueKey('inbox-next-topic'));
      expect(tester.widget<DButton>(previous).onPressed, isNull);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 10);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 1);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      for (final id in [10, 100]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, id);
        expect(shell.contentStack, hasLength(2));
      }
      expect(setup.api.feedPaths, contains('$_inbox?page=1'));
      expect(tester.widget<DButton>(next).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 10);

      await tester.tap(find.byKey(const ValueKey('new-message-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-message-recipients')),
        'alex',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 10);
      await tester.enterText(
        find.byKey(const ValueKey('new-message-recipients')),
        'alex',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(shell.visibleComposer?.target.targetRecipients, 'alex');
      expect(shell.visibleComposer?.target.originFeedId, 'messages');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'folders and group inboxes retain the reader and compose context',
    (tester) async {
      final setup = await _pumpInbox(tester);
      final shell = setup.controller;
      await tester.tap(find.byKey(const ValueKey('topic-card-1')));
      await tester.pumpAndSettle();
      final reader = tester.element(find.byType(TopicView));
      await tester.tap(find.byKey(const ValueKey('message-list-sent')));
      await tester.pumpAndSettle();
      expect(
        shell.topicListContent,
        ContentRoute.messages(mode: MessageListMode.sent),
      );
      expect(tester.element(find.byType(TopicView)), same(reader));
      expect(find.text('Sent personal message'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('team'));
      await tester.pumpAndSettle();
      expect(shell.topicListContent, ContentRoute.messages(groupName: 'team'));
      expect(shell.activeTab?.rootDestinationId, 'messages');
      expect(tester.element(find.byType(TopicView)), same(reader));
      expect(find.byKey(const ValueKey('message-list-sent')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new-message-button')));
      await tester.pumpAndSettle();
      expect(shell.visibleComposer?.target.targetRecipients, 'team');
      expect(
        shell.visibleComposer?.target.originFeedId,
        ContentRoute.messages(groupName: 'team').id,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('narrow message reader collapses back to its retained list', (
    tester,
  ) async {
    final setup = await _pumpInbox(tester, width: 390);
    await tester.tap(find.byKey(const ValueKey('topic-card-1')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicListView), findsNothing);
    expect(find.byType(TopicListView, skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-bottom-bar')), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse message'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicListView), findsOneWidget);
    expect(setup.controller.currentContent, ContentRoute.messages());
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('open inbox menu rejects folder changes beside the same reader', (
    tester,
  ) async {
    final setup = await _pumpInbox(tester);
    final shell = setup.controller;
    await tester.tap(find.byKey(const ValueKey('topic-card-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
    await tester.pumpAndSettle();
    shell.selectMessageListMode(MessageListMode.unread, keepTopicOpen: true);
    await tester.tap(
      find.descendant(
        of: find.byType(DComboboxContent),
        matching: find.text('team'),
      ),
    );
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 1);
    expect(
      shell.topicListContent,
      ContentRoute.messages(mode: MessageListMode.unread),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<({ShellController controller, FakeDiscourseApi api})> _pumpInbox(
  WidgetTester tester, {
  double width = 1440,
  double textScale = 1,
  bool secondSite = false,
  int inboxCount = 1,
  bool paginate = false,
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
  final rows = <String, List<Topic>>{
    '/latest.json': const [],
    for (final (index, entry) in feeds.entries.indexed)
      entry.key: [
        Topic(
          id: index + 1,
          title: entry.value,
          slug: 'message-$index',
          privateMessage: true,
        ),
        if (entry.key == _inbox)
          for (var i = 1; i < inboxCount; i++)
            Topic(
              id: i + 9,
              title: 'Personal message $i',
              slug: 'personal-$i',
              privateMessage: true,
            ),
      ],
    if (paginate)
      '$_inbox?page=1': const [
        Topic(
          id: 100,
          title: 'Next page message',
          slug: 'next-page',
          privateMessage: true,
        ),
      ],
  };
  final api = FakeDiscourseApi(
    user: user,
    feeds: rows,
    nextPages: {if (paginate) _inbox: '$_inbox?page=1'},
    topics: {
      for (final row in rows.values.expand((rows) => rows))
        row.id: (
          detail: TopicDetail(
            id: row.id,
            title: row.title,
            stream: [row.id * 100],
            postsCount: 1,
            privateMessage: true,
            canCreatePost: true,
          ),
          posts: [
            Post(
              id: row.id * 100,
              postNumber: 1,
              username: 'alex',
              userId: 2,
              cooked: '<p>Message body ${row.id}</p>',
            ),
          ],
        ),
    },
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
      if (secondSite) instance('team.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys[_site] = 'api-key'
      ..keys['https://team.example'] = 'other-key',
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
