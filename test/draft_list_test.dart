import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _draft = UserDraft(
  key: 'new_topic',
  sequence: 4,
  data: ComposerDraft(
    reply: 'A draft from another device',
    action: ComposerDraft.createTopicAction,
    title: 'Native drafts page',
    categoryId: 5,
  ),
);

void main() {
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
    expect(find.text('Native drafts page'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('A draft from another device'), findsOneWidget);
    expect(find.byTooltip('Edit draft'), findsOneWidget);
    expect(find.byTooltip('Remove draft'), findsOneWidget);
    expect(fixture.api.userDraftRequests, [
      (siteUrl: _siteUrl, offset: 0, limit: 30),
    ]);
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
    expect(find.text('Native drafts page'), findsOneWidget);
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
    expect(shell.visibleComposer?.title.text, 'Native drafts page');
    expect(shell.visibleComposer?.text.text, 'A draft from another device');
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

Future<_Fixture> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final site = instance('meta.discourse.org').copyWith(
    user: const DiscourseUser(id: 7, username: 'reader', draftCount: 1),
  );
  final api = FakeDiscourseApi(
    user: site.user,
    totals: const NotificationTotals(),
    userDraftList: const [_draft],
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
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api);
}
