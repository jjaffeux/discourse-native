import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
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

void _ignoreMember(BuildContext context, GroupMember member) {}

void main() {
  for (final (width, contentWidth) in [
    (1400.0, 825.0),
    (700.0, 668.0),
    (390.0, 358.0),
  ]) {
    testWidgets(
      'group header, tabs, and member controls share the content lane at width $width',
      (tester) async {
        final settings = AppSettingsController(
          store: AppSettingsStore(persistence: MemoryAppSettingsPersistence()),
        );
        addTearDown(settings.dispose);
        var route = GroupRoute.detail('support');
        late StateSetter update;
        await _pump(
          tester,
          ContentAlignmentScope(
            controller: settings,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return GroupPage(
                  siteUrl: 'https://meta.discourse.org',
                  route: route,
                  registry: PluginRegistry.empty,
                  data: const GroupPageData(
                    detail: _detail,
                    members: GroupMembersPage(members: [_member], total: 1),
                    activity: GroupActivityPage(),
                    canInviteToForum: true,
                    loaded: true,
                  ),
                  onOpenMember: _ignoreMember,
                );
              },
            ),
          ),
          size: Size(width, 900),
        );

        for (final alignment in ContentAlignment.values) {
          await settings.setContentAlignment(alignment);
          update(() => route = GroupRoute.detail('support'));
          await tester.pump();
          final left = switch (alignment) {
            ContentAlignment.left => 16.0,
            ContentAlignment.center => (width - contentWidth) / 2,
            ContentAlignment.right => width - 16 - contentWidth,
          };
          final right = left + contentWidth;
          expect(tester.getTopLeft(find.text('Support Team')).dx, left);
          final primaryTabs = tester.getRect(
            find.byKey(const ValueKey('group-primary-tabs')),
          );
          expect(primaryTabs.left, left);
          expect(primaryTabs.width, contentWidth);
          final search = tester.getRect(
            find.byKey(const ValueKey('group-member-search')),
          );
          final invite = tester.getRect(
            find.byKey(const ValueKey('invite-group-members')),
          );
          expect(search.left, left);
          if (contentWidth >= 600) {
            expect(invite.right, right);
            expect(invite.center.dy, search.center.dy);
          } else {
            expect(search.width, contentWidth);
            expect(invite.right, lessThanOrEqualTo(right));
          }
          expect(
            tester
                .getSize(
                  find.byKey(const PageStorageKey('group-members-scroll')),
                )
                .width,
            width,
          );
          if (width >= 760) {
            final divider = tester.getRect(find.byType(Divider).first);
            expect(divider.left, left);
            expect(divider.width, contentWidth);
          }

          update(
            () => route = GroupRoute.detail(
              'support',
              section: GroupRoute.activity,
              subsection: GroupRoute.posts,
            ),
          );
          await tester.pump();
          final secondaryTabs = tester.getRect(
            find.byKey(const ValueKey('group-secondary-tabs')),
          );
          expect(secondaryTabs.left, left);
          expect(secondaryTabs.width, contentWidth);
          expect(tester.takeException(), isNull);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('header actions and capability-gated primary tabs are native', (
    tester,
  ) async {
    GroupMembershipAction? membership;
    GroupMember? openedMember;
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
        onOpenMember: (_, member) => openedMember = member,
        onSelectRoute: (route) => selected = route,
      ),
    );

    expect(find.text('Support Team'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-flair')), findsNothing);
    expect(find.text('Sam Example'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-join')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-requests')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-messages')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-manage')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-tab-permissions')), findsOneWidget);
    expect(find.text('2 members'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('group-tab-members')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('group-join')));
    await tester.pump();
    expect(membership, GroupMembershipAction.join);

    await tester.tap(find.byKey(const ValueKey('group-message')));
    expect(messaged, isTrue);

    await tester.tap(find.text('Sam Example'));
    expect(openedMember, _member);

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
        onOpenMember: _ignoreMember,
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
        onOpenMember: _ignoreMember,
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
        onOpenMember: _ignoreMember,
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

  testWidgets('member parity tools expose metadata and management actions', (
    tester,
  ) async {
    String? filtered;
    GroupMemberAction? memberAction;
    List<String>? addedUsernames;
    final member = GroupMember(
      id: 3,
      username: 'sam',
      name: 'Sam Example',
      owner: true,
      addedAt: DateTime(2023, 2, 16),
      lastPostedAt: DateTime.now().subtract(const Duration(days: 3)),
      lastSeenAt: DateTime.now().subtract(const Duration(hours: 13)),
    );

    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail('support'),
        registry: PluginRegistry.empty,
        data: GroupPageData(
          detail: const GroupDetail(
            group: _group,
            visibleGroupNames: ['support', 'design'],
          ),
          members: GroupMembersPage(members: [member], total: 1),
          canInviteToForum: true,
          currentUserStaff: true,
          loaded: true,
        ),
        onMemberFilterChanged: (value) => filtered = value,
        onMemberSortChanged: (_, _) {},
        onSearchUsers: (_) async => const [
          FoundUser(username: 'lee', name: 'Lee Example'),
        ],
        onAddMembers: (usernames, emails) async {
          addedUsernames = usernames;
          return GroupMembershipMutationResult(usernames: usernames);
        },
        onCreateInvite: ({email, customMessage}) async =>
            const GroupInvite(id: 8, link: '/invites/native'),
        onMemberAction: (_, action) async {
          memberAction = action;
          return true;
        },
        onOpenMember: _ignoreMember,
      ),
      size: const Size(1180, 900),
    );

    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Last post'), findsOneWidget);
    expect(find.text('Last seen'), findsOneWidget);
    expect(find.textContaining('Feb 16'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-group-members')), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-group-members')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-switcher')), findsNothing);
    expect(find.text('Members (1)'), findsNothing);
    final search = tester.getRect(
      find.byKey(const ValueKey('group-member-search')),
    );
    for (final key in ['add-group-members', 'invite-group-members']) {
      final action = tester.getRect(find.byKey(ValueKey(key)));
      expect(action.center.dy, closeTo(search.center.dy, 1));
      expect(action.left, greaterThan(search.right));
    }

    await tester.enterText(
      find.byKey(const ValueKey('group-member-search')),
      'sam',
    );
    await tester.pump(const Duration(milliseconds: 310));
    expect(filtered, 'sam');

    await tester.tap(find.byKey(const ValueKey('add-group-members')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-members-search')),
      'lee',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-user-lee')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-add-members')));
    await tester.pumpAndSettle();
    expect(addedUsernames, ['lee']);

    await tester.tap(find.byKey(const ValueKey('invite-group-members')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-group-invite')));
    await tester.pumpAndSettle();
    expect(
      find.text('https://meta.discourse.org/invites/native'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manage-member-sam')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make primary group'));
    await tester.pumpAndSettle();
    expect(memberAction, GroupMemberAction.makePrimary);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1180.0, 390.0]) {
    testWidgets('member headers sort and reverse each column at width $width', (
      tester,
    ) async {
      var order = 'last_seen_at';
      var ascending = false;
      final changes = <(String, bool)>[];
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => GroupPage(
            siteUrl: 'https://meta.discourse.org',
            route: GroupRoute.detail('support'),
            registry: PluginRegistry.empty,
            data: GroupPageData(
              detail: _detail,
              members: const GroupMembersPage(members: [_member], total: 1),
              memberOrder: order,
              memberAscending: ascending,
              canInviteToForum: true,
              loaded: true,
            ),
            onMemberSortChanged: (value, direction) => setState(() {
              changes.add((value, direction));
              order = value;
              ascending = direction;
            }),
            onOpenMember: _ignoreMember,
          ),
        ),
        size: Size(width, 900),
      );

      expect(find.byKey(const ValueKey('group-member-sort')), findsNothing);
      expect(
        find.byKey(const ValueKey('group-member-sort-direction')),
        findsNothing,
      );
      for (final (column, direction) in [
        ('last_seen_at', true),
        ('last_seen_at', false),
        ('username_lower', true),
        ('username_lower', false),
        ('added_at', false),
        ('added_at', true),
        ('last_posted_at', false),
        ('last_posted_at', true),
      ]) {
        final header = find.byKey(ValueKey('group-member-sort-$column'));
        await tester.tap(header);
        await tester.pump();
        expect(changes.removeLast(), (column, direction));
        expect(changes, isEmpty);
        expect(
          tester.getSemantics(header).value,
          direction ? 'Sorted ascending' : 'Sorted descending',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'header renders configured flair icons and site-relative images',
    (tester) async {
      for (final group in const [
        Group(id: 9, name: 'support', flairIcon: 'star', flairColor: 'ff0000'),
        Group(id: 9, name: 'support', flairUrl: 'star'),
        Group(id: 9, name: 'support', flairUrl: 'uploads/group.png'),
      ]) {
        await _pump(
          tester,
          GroupPage(
            siteUrl: 'https://meta.discourse.org/forum',
            route: GroupRoute.detail('support'),
            registry: PluginRegistry.empty,
            data: GroupPageData(
              detail: GroupDetail(group: group),
              loaded: true,
            ),
            onOpenMember: _ignoreMember,
          ),
        );
        final flair = find.byKey(const ValueKey('group-flair'));
        expect(flair, findsOneWidget);
        if (group.flairUrl == 'uploads/group.png') {
          final avatar = tester.widget<AvatarImage>(
            find.descendant(of: flair, matching: find.byType(AvatarImage)),
          );
          expect(
            avatar.url,
            'https://meta.discourse.org/forum/uploads/group.png',
          );
          expect(avatar.fit, BoxFit.contain);
        } else {
          final icon = tester.widget<DIcon>(
            find.descendant(of: flair, matching: find.byType(DIcon)),
          );
          expect(icon.icon, DIcons.star);
          if (group.flairColor != null) {
            expect(icon.color, const Color(0xFFFF0000));
          }
        }
        expect(find.text('S'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('admin deletion requires an exact group-name confirmation', (
    tester,
  ) async {
    var deleted = false;
    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail('support'),
        registry: PluginRegistry.empty,
        data: const GroupPageData(
          detail: _detail,
          members: GroupMembersPage(members: [_member], total: 1),
          isAdmin: true,
          loaded: true,
        ),
        onDeleteGroup: () async {
          deleted = true;
          return true;
        },
        onOpenMember: _ignoreMember,
      ),
    );

    expect(find.text('More'), findsNothing);
    expect(find.text('Group settings'), findsNothing);
    expect(find.text('Copy group link'), findsNothing);
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('confirm-delete-group')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('group-delete-confirmation')),
      'support',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-group')));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(tester.takeException(), isNull);
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
        onOpenMember: _ignoreMember,
        data: const GroupPageData(
          detail: _detail,
          smtpEnabled: true,
          taggingEnabled: true,
          loaded: true,
        ),
        onSaveManage: (update) async {
          saved = update;
          return true;
        },
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
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('save-group-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-group-tags')));
    await tester.pump();

    expect(saved?.subsection, GroupRoute.tags);
    expect(saved?.values['watching_tags'], ['flutter', 'native']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manage controls honor group and site capabilities', (
    tester,
  ) async {
    const automaticGroup = Group(
      id: 10,
      name: 'trust-level-1',
      automatic: true,
      canAdminGroup: true,
    );
    await _pump(
      tester,
      GroupPage(
        siteUrl: 'https://meta.discourse.org',
        route: GroupRoute.detail(
          'trust-level-1',
          section: GroupRoute.manage,
          subsection: GroupRoute.profile,
        ),
        registry: PluginRegistry.empty,
        onOpenMember: _ignoreMember,
        data: const GroupPageData(
          detail: GroupDetail(group: automaticGroup),
          smtpEnabled: true,
          taggingEnabled: false,
          loaded: true,
        ),
        onSaveManage: (_) async => true,
      ),
    );

    expect(find.text('Profile'), findsNWidgets(2));
    expect(find.text('Interaction'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('Membership'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Tags'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('group-field-name')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('save-group-profile')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'profile form keeps input focus and renders controller validation',
    (tester) async {
      var submissions = 0;
      await _pump(
        tester,
        GroupPage(
          siteUrl: 'https://meta.discourse.org',
          route: GroupRoute.detail(
            'support',
            section: GroupRoute.manage,
            subsection: GroupRoute.profile,
          ),
          registry: PluginRegistry.empty,
          onOpenMember: _ignoreMember,
          data: const GroupPageData(detail: _detail, loaded: true),
          onSaveManage: (_) async {
            submissions += 1;
            return true;
          },
        ),
      );
      final nameField = find.byKey(const ValueKey('group-field-name'));
      final saveButton = find.byKey(const ValueKey('save-group-profile'));
      final formList = find.byKey(
        const PageStorageKey('group-manage-profile-scroll'),
      );

      await tester.tap(nameField);
      await tester.enterText(nameField, '');
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: nameField,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.drag(formList, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pump();
      expect(find.text('Enter a group name.'), findsOneWidget);
      expect(submissions, 0);

      await tester.enterText(nameField, 'community-support');
      await tester.pump();
      expect(find.text('Enter a group name.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
        onOpenMember: _ignoreMember,
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
