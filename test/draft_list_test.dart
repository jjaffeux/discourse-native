import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart'
    show Focus, InkWell, MaterialApp, MouseRegion, Row, Size, ValueKey;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _draft = UserDraft(
  key: 'new_topic',
  sequence: 4,
  data: ComposerDraft(
    reply: 'A draft :smiley: from another device',
    action: ComposerDraft.createTopicAction,
    title: 'Native :sparkles: drafts page',
    categoryId: 5,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the wide New topic button has core text and icon', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('New topic'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(TopicCreateButton.buttonKey),
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.farPenToSquare,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the New topic text is hidden only below the small breakpoint', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('latest')));
    await tester.pumpAndSettle();

    expect(find.byKey(TopicCreateButton.buttonKey), findsOneWidget);
    expect(find.text('New topic'), findsNothing);
    expect(find.byTooltip('New topic'), findsOneWidget);
  });

  testWidgets('the attached menu loads and resumes a recent draft', (
    tester,
  ) async {
    final fixture = await _pump(tester);

    expect(fixture.api.userDraftRequests, isEmpty);
    await tester.tap(find.byKey(TopicCreateButton.draftsButtonKey));
    await tester.pumpAndSettle();

    expect(fixture.api.userDraftRequests, [
      (siteUrl: _siteUrl, offset: 0, limit: 30),
    ]);
    final row = find.byKey(const ValueKey('recent-draft-new_topic'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.layerGroup,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(ComposerPanel), findsOneWidget);
    final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));
    expect(shell.visibleComposer?.title.text, 'Native :sparkles: drafts page');
    expect(shell.visibleComposer?.draftSequence, 4);
  });

  testWidgets('the attached drafts chevron closes an open menu', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final button = find.byKey(TopicCreateButton.draftsButtonKey);
    final row = find.byKey(const ValueKey('recent-draft-new_topic'));

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(row, findsOneWidget);
    expect(fixture.api.userDraftRequests, hasLength(1));

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(row, findsNothing);
    expect(fixture.api.userDraftRequests, hasLength(1));
  });

  testWidgets('the recent menu matches core draft icons and four-row limit', (
    tester,
  ) async {
    final drafts = [
      _draft,
      const UserDraft(
        key: 'new_private_message_1',
        sequence: 5,
        data: ComposerDraft(reply: 'Private draft', title: 'A message'),
      ),
      for (var index = 1; index <= 4; index++)
        UserDraft(
          key: 'topic_$index',
          sequence: index,
          data: ComposerDraft(reply: 'Reply $index'),
          topicId: index,
          title: 'Reply draft $index',
          slug: 'reply-draft-$index',
        ),
    ];
    await _pump(tester, draftCount: drafts.length, userDrafts: drafts);

    await tester.tap(find.byKey(TopicCreateButton.draftsButtonKey));
    await tester.pumpAndSettle();

    final privateRow = find.byKey(
      const ValueKey('recent-draft-new_private_message_1'),
    );
    final replyRow = find.byKey(const ValueKey('recent-draft-topic_1'));
    expect(privateRow, findsOneWidget);
    expect(replyRow, findsOneWidget);
    expect(
      find.descendant(
        of: privateRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.envelope,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: replyRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.reply,
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('recent-draft-topic_3')), findsNothing);
    expect(find.text('+2 other drafts'), findsOneWidget);
    expect(find.text('view all drafts'), findsOneWidget);

    await tester.tap(find.text('view all drafts'));
    await tester.pumpAndSettle();

    expect(find.byType(DraftListView), findsOneWidget);
  });

  testWidgets('the sidebar shows the draft count as plain trailing text', (
    tester,
  ) async {
    await _pump(tester);

    final count = find.descendant(
      of: find.byType(InstanceSidebar),
      matching: find.text('1'),
    );

    expect(count, findsOneWidget);
    Object? parent;
    tester.element(count).visitAncestorElements((element) {
      parent = element.widget;
      return false;
    });
    expect(parent, isA<Row>());
  });

  testWidgets('the sidebar opens the account-backed drafts page', (
    tester,
  ) async {
    final fixture = await _pump(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.text('Drafts'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DraftListView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TopicTitle &&
            widget.title == 'Native :sparkles: drafts page',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(DraftListView),
        matching: find.text('Support'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TopicTitle &&
            widget.title == 'A draft :smiley: from another device',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
          .map((emoji) => emoji.name),
      ['sparkles', 'smiley'],
    );
    expect(find.byTooltip('Edit draft'), findsOneWidget);
    expect(find.byTooltip('Remove draft'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DraftListView),
        matching: find.byType(UserMenuAvatar),
      ),
      findsNothing,
    );
    expect(fixture.api.userDraftRequests, [
      (siteUrl: _siteUrl, offset: 0, limit: 30),
    ]);
  });

  testWidgets('the drafts page uses a draft-row skeleton while loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(tester, userDraftGate: gate);
    final semantics = tester.ensureSemantics();

    await tester.tap(
      find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.text('Drafts'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('draft-list-loading-skeleton')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('draft-list-loading-skeleton-content')),
          )
          .height,
      greaterThanOrEqualTo(
        tester
                .getSize(
                  find.byKey(const ValueKey('draft-list-loading-skeleton')),
                )
                .height -
            36,
      ),
    );
    expect(find.bySemanticsLabel('Loading drafts'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('draft-list-loading-skeleton')),
      findsNothing,
    );
    expect(find.byTooltip('Edit draft'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('compact draft actions are 44 pixel keyboard targets', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    final controller = ShellScope.read(
      tester.element(find.byType(MaterialApp)),
    );
    controller.openDrafts(_siteUrl);
    await tester.pumpAndSettle();

    final edit = find.byTooltip('Edit draft');
    final remove = find.byTooltip('Remove draft');
    expect(tester.getSize(edit), const Size.square(44));
    expect(tester.getSize(remove), const Size.square(44));

    await _focusDraftAction(tester, remove);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.text('Remove draft?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _focusDraftAction(tester, edit);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(ComposerPanel), findsOneWidget);
  });

  testWidgets('the profile Drafts row opens the same destination', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(UserMenuButton.avatarKey));
    await tester.pumpAndSettle();
    final profileTab = find.byTooltip('Profile');
    await tester.tap(
      profileTab.evaluate().isEmpty ? find.text('Profile').last : profileTab,
    );
    await tester.pumpAndSettle();
    final panelDrafts = find.descendant(
      of: find.byType(UserMenuPanel),
      matching: find.text('Drafts'),
    );
    await tester.tap(
      panelDrafts.evaluate().isEmpty ? find.text('Drafts').last : panelDrafts,
    );
    await tester.pumpAndSettle();

    expect(find.byType(UserMenuPanel), findsNothing);
    expect(find.byType(DraftListView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TopicTitle &&
            widget.title == 'Native :sparkles: drafts page',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a supported draft resumes in the composer', (tester) async {
    await _pump(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.text('Drafts'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit draft'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposerPanel), findsOneWidget);
    final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));
    expect(shell.visibleComposer?.title.text, 'Native :sparkles: drafts page');
    expect(
      shell.visibleComposer?.text.text,
      'A draft :smiley: from another device',
    );
    expect(shell.visibleComposer?.draftSequence, 4);
  });

  testWidgets('removing a draft updates the page and server count', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.text('Drafts'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('No drafts yet'), findsOneWidget);
    expect(fixture.api.userDraftsDeleted, [
      (siteUrl: _siteUrl, draftKey: 'new_topic', sequence: 4),
    ]);
  });
}

typedef _Fixture = ({FakeDiscourseApi api});

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  int draftCount = 1,
  List<UserDraft> userDrafts = const [_draft],
  Completer<void>? userDraftGate,
}) async {
  EmojiCache.instance = EmojiCache(
    client: MockClient((_) async => http.Response('', 404)),
  );
  addTearDown(EmojiCache.instance.clear);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final site = instance('meta.discourse.org').copyWith(
    user: DiscourseUser(id: 7, username: 'reader', draftCount: draftCount),
  );
  final api = FakeDiscourseApi(
    user: site.user,
    totals: const NotificationTotals(),
    userDraftList: userDrafts,
    userDraftGate: userDraftGate,
    categoryList: const [
      TopicCategory(id: 5, name: 'Support', color: '0088CC'),
    ],
    feeds: const {'/latest.json': []},
    creatableFeedPaths: const {'/latest.json'},
  );
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([site]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api);
}

Future<void> _focusDraftAction(WidgetTester tester, Finder action) async {
  final inkWell = find.descendant(of: action, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
}
