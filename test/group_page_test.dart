import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = Group(
  id: 9,
  name: 'support',
  fullName: 'Support Team',
  userCount: 2,
  bioCooked: '<p>Helpful people.</p>',
  publicAdmission: true,
  publicExit: true,
  allowMembershipRequests: true,
  canSeeMembers: true,
  canAdminGroup: true,
  hasMessages: true,
  messageCount: 3,
  messageable: true,
);

const _detail = GroupDetail(group: _group);

const _member = GroupMember(
  id: 3,
  username: 'sam',
  name: 'Sam Example',
  owner: true,
);

void main() {
  testWidgets('header actions and capability-gated primary tabs are native', (
    tester,
  ) async {
    GroupMembershipAction? membership;
    GroupRoute? selected;
    var messaged = false;

    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail('support'),
        registry: PluginRegistry.empty,
        data: const GroupPageData(
          detail: _detail,
          members: GroupMembersPage(members: [_member], total: 1),
          canSendPrivateMessages: true,
          isAdmin: true,
          loaded: true,
        ),
        onMembershipAction: (action) async => membership = action,
        onMessageGroup: () => messaged = true,
        onSelectRoute: (route) => selected = route,
      ),
    );

    expect(find.text('Support Team'), findsOneWidget);
    expect(find.text('Sam Example'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-join')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-requests')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-messages')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-manage')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-permissions')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('group-join')));
    await tester.pump();
    expect(membership, GroupMembershipAction.join);

    await tester.tap(find.byKey(const ValueKey('group-message')));
    expect(messaged, isTrue);

    await tester.tap(find.byKey(const ValueKey('group-tab-activity')));
    expect(selected?.section, GroupRoute.activity);
    expect(selected?.subsection, GroupRoute.posts);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity, messages and requests expose their native subtabs', (
    tester,
  ) async {
    GroupRoute? selected;
    GroupRequestAction? requestAction;

    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail(
          'support',
          section: GroupRoute.activity,
          subsection: GroupRoute.posts,
        ),
        registry: PluginRegistry.empty,
        data: const GroupPageData(
          detail: _detail,
          activity: GroupActivityPage(
            posts: [
              GroupActivityPost(
                id: 8,
                topicId: 4,
                postNumber: 2,
                topicTitle: 'Native groups',
                topicSlug: 'native-groups',
                excerpt: '<p>A helpful update</p>',
                username: 'sam',
              ),
            ],
          ),
          canSendPrivateMessages: true,
          loaded: true,
        ),
        topicFeed: const Text('Topic feed slot'),
        onSelectRoute: (route) => selected = route,
      ),
    );

    expect(find.text('Native groups'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-subtab-topics')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-subtab-mentions')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-subtab-topics')));
    expect(selected?.subsection, GroupRoute.topics);

    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail('support', section: GroupRoute.requests),
        registry: PluginRegistry.empty,
        data: const GroupPageData(
          detail: _detail,
          requesters: GroupRequestersPage(
            requesters: [
              GroupRequester(id: 12, username: 'lee', reason: 'I can help'),
            ],
            total: 1,
          ),
          loaded: true,
        ),
        onRequestAction: (requester, action) async => requestAction = action,
      ),
    );
    expect(find.text('I can help'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-lee')));
    await tester.pump();
    expect(requestAction, GroupRequestAction.accept);

    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail(
          'support',
          section: GroupRoute.messages,
          subsection: GroupRoute.archive,
        ),
        registry: PluginRegistry.empty,
        data: const GroupPageData(
          detail: _detail,
          canSendPrivateMessages: true,
          loaded: true,
        ),
        messageFeed: const Text('Message feed slot'),
      ),
    );
    expect(find.text('Message feed slot'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('group-subtab-archive')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('all manage subtabs are present and tag changes are submitted', (
    tester,
  ) async {
    GroupManageUpdate? saved;
    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail(
          'support',
          section: GroupRoute.manage,
          subsection: GroupRoute.tags,
        ),
        registry: PluginRegistry.empty,
        data: const GroupPageData(
          detail: _detail,
          smtpEnabled: true,
          taggingEnabled: true,
          loaded: true,
        ),
        onSaveManage: (update) async => saved = update,
      ),
    );

    for (final label in [
      'Profile',
      'Membership',
      'Interaction',
      'Email',
      'Categories',
      'Tags',
      'Logs',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.enterText(
      find.byKey(const ValueKey('group-field-watching_tags')),
      'flutter, native',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('save-group-tags')));
    await tester.tap(find.byKey(const ValueKey('save-group-tags')));
    await tester.pump();

    expect(saved?.subsection, GroupRoute.tags);
    expect(saved?.values['watching_tags'], ['flutter', 'native']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin tabs and plugin-owned content render through registry', (
    tester,
  ) async {
    final registry = PluginRegistry.validated(const [_ExampleGroupPlugin()]);
    GroupRoute? selected;
    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.plugin(
          groupName: 'support',
          owner: 'example',
          section: 'insights',
        ),
        registry: registry,
        data: const GroupPageData(detail: _detail, loaded: true),
        onSelectRoute: (route) => selected = route,
      ),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Plugin group content'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-tab-members')));
    expect(selected?.section, GroupRoute.members);
  });
}

final class _ExampleGroupPlugin implements SitePlugin, GroupTabPlugin {
  const _ExampleGroupPlugin();

  @override
  String get name => 'example';

  @override
  PluginGroupTab? groupTab(PluginGroupContext group) => const PluginGroupTab(
    section: 'insights',
    label: 'Insights',
    icon: DIcons.star,
    count: 2,
  );

  @override
  Widget? groupContent(BuildContext context, PluginGroupContext group) =>
      const Center(child: Text('Plugin group content'));

  @override
  Listenable? groupListenable(BuildContext context, PluginGroupContext group) =>
      null;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1000, 820),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
