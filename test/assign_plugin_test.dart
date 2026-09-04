import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_icons.dart';
import 'package:discourse_native/src/plugins/assign/assign_notifications.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/assign/assign_user_menu.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/pill.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://forum.example.com';
const _plugin = AssignPlugin();

void main() {
  test('registers its group-plus artwork as a plugin-owned icon', () {
    final registry = PluginRegistry.validated(const [_plugin]);

    expect(
      registry.iconNamed('group-plus', fallback: DIcons.users),
      AssignIcons.groupPlus,
    );
    expect(
      PluginRegistry.empty.iconNamed('group-plus', fallback: DIcons.users),
      DIcons.users,
    );
  });

  group('user menu', () {
    DiscourseUser user({
      required bool canAssign,
      required bool canAssignGlobally,
      int storedUnread = 0,
    }) => DiscourseUser(
      username: 'reader',
      groupedUnreadNotifications: NotificationTypeCounts.fromWire({
        '34': storedUnread,
      }),
      plugins: PluginData.none.withValue(
        assignCurrentUserDataKey,
        AssignCurrentUser(
          canAssign: canAssign,
          canAssignGlobally: canAssignGlobally,
        ),
      ),
    );

    PluginUserMenuContext context(
      DiscourseUser user, {
      NotificationTotals? totals,
    }) => PluginUserMenuContext(siteUrl: _siteUrl, user: user, totals: totals);

    test('fails closed unless both core Assign permissions are true', () {
      expect(
        _plugin.userMenuSections(
          context(user(canAssign: false, canAssignGlobally: true)),
        ),
        isEmpty,
      );
      expect(
        _plugin.userMenuSections(
          context(user(canAssign: true, canAssignGlobally: false)),
        ),
        isEmpty,
      );
      expect(
        _plugin.userMenuSections(
          context(user(canAssign: true, canAssignGlobally: true)),
        ),
        hasLength(1),
      );
    });

    test('contributes its feed-backed tab with the assigned unread count', () {
      final storedSections = _plugin.userMenuSections(
        context(
          user(canAssign: true, canAssignGlobally: true, storedUnread: 3),
        ),
      );
      final sections = _plugin.userMenuSections(
        context(
          user(canAssign: true, canAssignGlobally: true, storedUnread: 3),
          totals: NotificationTotals.fromJson(const {
            'grouped_unread_notifications': {'34': 8},
          }),
        ),
      );

      expect(storedSections.single.badge, 3);
      expect(sections.single.id, AssignPlugin.notificationsSection);
      expect(sections.single.icon, DIcons.userPlus);
      expect(sections.single.label, 'Assign list');
      expect(sections.single.badge, 8);
      expect(sections.single.linkWhenActive, '/u/reader/activity/assigned');
      expect(_plugin.notificationFeeds, [assignNotificationFeed]);
    });

    testWidgets('forwards the assigned count to feed dismissal', (
      tester,
    ) async {
      final section = _plugin
          .userMenuSections(
            context(
              user(canAssign: true, canAssignGlobally: true, storedUnread: 3),
            ),
          )
          .single;
      late Widget built;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              built = section.builder(
                context,
                PluginUserMenuRenderContext(onDismiss: () {}),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(built, isA<AssignUserMenuNotifications>());
      final widget = built as AssignUserMenuNotifications;
      expect(widget.unreadCount, 3);
      expect(widget.viewAllPath, '/u/reader/activity/assigned');
    });
  });

  group('serializer projection', () {
    test('keeps Assign absent when its block is absent', () {
      expect(_plugin.readTopic(const {}, _siteUrl), isNull);
      expect(_plugin.readPost(const {'id': 1}, _siteUrl), isNull);
    });

    test('parses public assignments independently of write permission', () {
      final assignments = _plugin.readTopic(const {
        'can_assign': false,
        'assigned_to_user': {'id': 7, 'username': 'sam', 'name': 'Sam Example'},
        'assignment_status': 'In progress',
        'assignment_note': 'Follow up tomorrow',
      }, _siteUrl);

      expect(assignments, isNotNull);
      expect(assignments!.canAssign, isFalse);
      expect(assignments.direct?.assignee.displayName, 'Sam Example');
      expect(assignments.direct?.status, 'In progress');
      expect(assignments.direct?.note, 'Follow up tomorrow');
    });
  });

  group('capability and invalidation', () {
    test('requires every server-authored guardian for the group tab', () {
      const registry = PluginRegistry([AssignPlugin()]);
      final route = GroupRoute.plugin(
        groupName: 'support',
        owner: _plugin.name,
        section: 'assigned',
      );

      PluginGroupTab? tab({
        Map<String, dynamic> group = const {
          'assignable_level': 1,
          'can_show_assigned_tab': true,
          'assignment_count': 4,
        },
        Map<String, dynamic> user = const {'can_assign_globally': true},
        bool canSeeMembers = true,
      }) => _plugin.groupTab(
        PluginGroupContext(
          siteUrl: _siteUrl,
          route: route,
          groupName: 'support',
          canSeeMembers: canSeeMembers,
          groupData: registry.readGroup(group, _siteUrl),
          currentUserData: registry.readCurrentUser(user, _siteUrl),
        ),
      );

      expect(tab()?.count, 4);
      expect(tab(group: const {}), isNull);
      expect(
        tab(
          group: const {'assignable_level': 0, 'can_show_assigned_tab': true},
        ),
        isNull,
      );
      expect(
        tab(
          group: const {'assignable_level': 1, 'can_show_assigned_tab': false},
        ),
        isNull,
      );
      expect(tab(canSeeMembers: false), isNull);
      expect(tab(user: const {'can_assign_globally': false}), isNull);
      expect(tab(user: const {}), isNull);
    });

    test(
      'invalidates the open topic only for matching assignment messages',
      () {
        expect(_plugin.topicChannels(42), ['/staff/topic-assignment']);
        expect(
          _plugin.staleTopic(42, '/staff/topic-assignment', const {
            'topic_id': 42,
            'post_id': 9,
          }),
          isTrue,
        );
        expect(
          _plugin.staleTopic(42, '/staff/topic-assignment', const {
            'topic_id': '41',
          }),
          isFalse,
        );
        expect(
          _plugin.staleTopic(42, '/topic/42/reactions', const {'topic_id': 42}),
          isFalse,
        );
        expect(
          _plugin.stalePosts('/staff/topic-assignment', const {}),
          isEmpty,
        );
      },
    );
  });

  group('small-action projection', () {
    test('recognises every Assign family and nothing else', () {
      const userAssigned = Post(
        id: 1,
        postNumber: 2,
        username: 'mod',
        cooked: '',
        actionCode: 'assigned_to_post',
        actionCodeWho: 'sam',
      );
      const groupUnassigned = Post(
        id: 2,
        postNumber: 3,
        username: 'mod',
        cooked: '',
        actionCode: 'unassigned_group_from_post',
        actionCodeWho: 'support',
      );
      const detailChange = Post(
        id: 3,
        postNumber: 4,
        username: 'mod',
        cooked: '',
        actionCode: 'status_change',
        actionCodeWho: 'sam',
      );
      const unrelated = Post(
        id: 4,
        postNumber: 5,
        username: 'mod',
        cooked: '',
        actionCode: 'closed.enabled',
      );

      expect(_plugin.smallAction(userAssigned)?.icon, DIcons.userPlus);
      expect(
        _plugin.smallAction(userAssigned)?.phrase,
        'assigned sam to a post',
      );
      expect(_plugin.smallAction(groupUnassigned)?.icon, DIcons.circleMinus);
      expect(_plugin.smallAction(detailChange)?.icon, DIcons.pencil);
      expect(_plugin.smallAction(unrelated), isNull);
    });
  });

  group('post and topic decorations', () {
    testWidgets(
      'show topic and indirect assignments on the first post without controls',
      (tester) async {
        const registry = PluginRegistry([AssignPlugin()]);
        final topicPlugins = registry.readTopic(const {
          'can_assign': false,
          'assigned_to_group': {'id': 4, 'name': 'support'},
          'assignment_status': 'New',
          'assignment_note': 'Topic note',
          'indirectly_assigned_to': {
            '22': {
              'assigned_to': {'id': 7, 'username': 'sam', 'name': 'Sam'},
              'post_number': 2,
              'assignment_status': 'Waiting',
              'assignment_note': 'Post note',
            },
          },
        }, _siteUrl);
        final topic = TopicDetail(
          id: 10,
          title: 'Assigned topic',
          stream: const [11, 22],
          plugins: topicPlugins,
        );
        const post = Post(
          id: 11,
          postNumber: 1,
          username: 'author',
          cooked: '',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: _plugin.postDecorations(
                    context,
                    _siteUrl,
                    topic,
                    post,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Topic assigned to support'), findsOneWidget);
        expect(find.text('Post #2 assigned to Sam'), findsOneWidget);
        expect(find.textContaining('Status: New'), findsOneWidget);
        expect(find.textContaining('Note: Post note'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.pencil,
          ),
          findsNothing,
        );
      },
    );

    testWidgets('omit post assignment actions from the first-post menu', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final plugins = registry.readPost(const {
        'id': 11,
        'post_number': 1,
        'can_assign': true,
      }, _siteUrl);
      final post = Post(
        id: 11,
        postNumber: 1,
        username: 'author',
        cooked: '',
        plugins: plugins,
      );
      PostMenuContribution? contribution;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              contribution = _plugin.postMenu(
                PostMenuContext(
                  buildContext: context,
                  siteUrl: _siteUrl,
                  post: post,
                  topic: null,
                  currentUser: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(contribution?.entries, isEmpty);
    });

    testWidgets('expose a pointer anchor callback for post assignment', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final post = Post(
        id: 22,
        postNumber: 2,
        username: 'author',
        cooked: '',
        plugins: registry.readPost(const {
          'id': 22,
          'post_number': 2,
          'can_assign': true,
        }, _siteUrl),
      );
      final topic = TopicDetail(
        id: 10,
        title: 'Assignable topic',
        stream: const [11, 22],
        plugins: registry.readTopic(const {'can_assign': false}, _siteUrl),
      );
      PostMenuContribution? contribution;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              contribution = _plugin.postMenu(
                PostMenuContext(
                  buildContext: context,
                  siteUrl: _siteUrl,
                  post: post,
                  topic: topic,
                  currentUser: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(contribution?.entries, hasLength(1));
      expect(contribution?.entries.single.onInvokeAnchored, isNotNull);
    });
  });

  group('topic assignment presentation', () {
    testWidgets(
      'renders one neutral avatar-and-name token for every list assignment',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          const registry = PluginRegistry([AssignPlugin()]);
          final plugins = registry.readTopic(const {
            'can_assign': false,
            'assigned_to_user': {
              'username': 'sam',
              'name': 'Sam',
              'avatar_template':
                  '/user_avatar/forum.example.com/sam/{size}/1.png',
            },
            'assignment_status': 'In progress',
            'assignment_note': 'Hidden from the compact token',
            'indirectly_assigned_to': {
              '22': {
                'assigned_to': {'name': 'support'},
                'post_number': 2,
                'assignment_status': 'Waiting',
              },
            },
          }, _siteUrl);
          final topic = Topic(
            id: 10,
            title: 'Assigned topic',
            slug: 'assigned-topic',
            plugins: plugins,
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Wrap(
                    children: _plugin.topicListMetadata(
                      context,
                      _siteUrl,
                      topic,
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(find.byType(Pill), findsNWidgets(2));
          expect(find.byType(AssignmentAssigneeAvatar), findsNWidgets(2));
          expect(find.text('Sam'), findsOneWidget);
          expect(find.text('support'), findsOneWidget);
          expect(find.textContaining('Topic'), findsNothing);
          expect(find.textContaining('Post'), findsNothing);
          expect(find.textContaining('In progress'), findsNothing);
          expect(find.textContaining('Waiting'), findsNothing);
          expect(find.textContaining('Hidden from'), findsNothing);
          expect(
            find.bySemanticsLabel(
              'Topic assigned to Sam, user @sam, status In progress, '
              'note Hidden from the compact token',
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              'Post #2 assigned to support, group @support, status Waiting',
            ),
            findsOneWidget,
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets('uses a full-width primary CTA for an unassigned topic', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final plugins = registry.readTopic(const {'can_assign': true}, _siteUrl);
      final topic = TopicDetail(
        id: 10,
        title: 'Unassigned topic',
        stream: const [11],
        plugins: plugins,
      );
      late TopicPropertySection section;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                section = _plugin
                    .topicProperties(context, _siteUrl, topic)
                    .single;
                return Column(children: section.values);
              },
            ),
          ),
        ),
      );

      expect(section.layout, TopicPropertySectionLayout.standalone);
      expect(section.showHeader, isFalse);
      expect(section.values, hasLength(1));
      expect(find.text('Topic · Unassigned'), findsNothing);
      expect(find.text('Assign topic'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('assign-topic-property')),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.userPlus,
          ),
        ),
        findsOneWidget,
      );
      final action = find.byKey(const Key('assign-topic-property'));
      final button = find.byKey(const Key('assign-topic-button'));
      final dButton = tester.widget<DButton>(button);
      expect(dButton.variant, DButtonVariant.primary);
      expect(tester.getSize(button).height, 46);
      expect(tester.getSize(button).width, tester.getSize(action).width);
      expect(
        tester.getSemantics(button),
        isSemantics(
          label: 'Topic unassigned. Assign topic',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('lets the Assign topic CTA grow with large text', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final plugins = registry.readTopic(const {'can_assign': true}, _siteUrl);
      final topic = TopicDetail(
        id: 10,
        title: 'Unassigned topic',
        stream: const [11],
        plugins: plugins,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: _plugin
                      .topicProperties(context, _siteUrl, topic)
                      .single
                      .values,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('assign-topic-button'))).height,
        greaterThan(46),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('only shows real post assignments in post-only sections', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final plugins = registry.readTopic(const {
        'can_assign': false,
        'indirectly_assigned_to': {
          '22': {
            'assigned_to': {'username': 'sam', 'name': 'Sam'},
            'post_number': 2,
          },
        },
      }, _siteUrl);
      final topic = TopicDetail(
        id: 10,
        title: 'Post-only assignment',
        stream: const [11, 22],
        plugins: plugins,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: _plugin
                    .topicProperties(context, _siteUrl, topic)
                    .single
                    .values,
              ),
            ),
          ),
        ),
      );

      final topicRow = find.byKey(const Key('assign-topic-property'));
      final postRow = find.byKey(const Key('assign-topic-property-post-22'));
      expect(topicRow, findsNothing);
      expect(postRow, findsOneWidget);
      expect(
        find.descendant(
          of: postRow,
          matching: find.text('Assigned to · Post #2', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: postRow, matching: find.text('@sam')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assign-post-22-target')), findsNothing);
      expect(find.byKey(const Key('assign-post-22-change')), findsNothing);
      expect(find.byKey(const Key('assign-post-22-remove')), findsNothing);
      expect(
        find.descendant(
          of: postRow,
          matching: find.byType(AssignmentAssigneeAvatar),
        ),
        findsOneWidget,
      );
    });

    testWidgets('gives an assigned topic icon-only change and remove actions', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final plugins = registry.readTopic(const {
        'can_assign': true,
        'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
      }, _siteUrl);
      final topic = TopicDetail(
        id: 10,
        title: 'Assigned topic',
        stream: const [11],
        plugins: plugins,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: _plugin
                    .topicProperties(context, _siteUrl, topic)
                    .single
                    .values,
              ),
            ),
          ),
        ),
      );

      final row = find.byKey(const Key('assign-topic-property'));
      final change = find.byKey(const Key('assign-topic-change'));
      final remove = find.byKey(const Key('assign-topic-remove'));
      expect(
        find.descendant(of: row, matching: find.text('Assigned to')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('@sam')),
        findsOneWidget,
      );
      expect(change, findsOneWidget);
      expect(remove, findsOneWidget);
      expect(
        find.descendant(of: change, matching: find.text('Change')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: change,
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.pencil,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(row)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(tester.getSemantics(change).label, 'Change topic assignment');
      expect(tester.getSemantics(remove).label, 'Remove topic assignment');
    });

    testWidgets('orders rows and exposes hidden details through semantics', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        const registry = PluginRegistry([AssignPlugin()]);
        final plugins = registry.readTopic(const {
          'can_assign': false,
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
          'assignment_note': 'A deliberately long topic note',
          'indirectly_assigned_to': {
            '30': {
              'assigned_to': {'username': 'zoe', 'name': 'Zoe'},
              'post_number': 3,
            },
            '32': {
              'assigned_to': {'username': 'missing', 'name': 'Missing number'},
            },
            '31': {
              'assigned_to': {'username': 'invalid', 'name': 'Invalid number'},
              'post_number': 0,
            },
            '23': {
              'assigned_to': {'username': 'terry', 'name': 'Terry'},
              'post_number': 2,
            },
            '22': {
              'assigned_to': {'name': 'support'},
              'post_number': 2,
              'assignment_note': 'Another deliberately long post note',
            },
          },
        }, _siteUrl);
        final topic = TopicDetail(
          id: 10,
          title: 'Assigned topic',
          stream: const [11, 22, 23, 30, 31, 32],
          plugins: plugins,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: _plugin
                      .topicProperties(context, _siteUrl, topic)
                      .single
                      .values,
                ),
              ),
            ),
          ),
        );

        final topicRow = find.byKey(const Key('assign-topic-property'));
        final supportRow = find.byKey(
          const Key('assign-topic-property-post-22'),
        );
        final terryRow = find.byKey(const Key('assign-topic-property-post-23'));
        final zoeRow = find.byKey(const Key('assign-topic-property-post-30'));
        final invalidRow = find.byKey(
          const Key('assign-topic-property-post-31'),
        );
        final missingRow = find.byKey(
          const Key('assign-topic-property-post-32'),
        );
        expect(
          find.descendant(of: topicRow, matching: find.text('Assigned to')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: topicRow, matching: find.text('@sam')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: supportRow,
            matching: find.text('Assigned to · Post #2', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: supportRow, matching: find.text('@support')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: terryRow,
            matching: find.text('Assigned to · Post #2', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: terryRow, matching: find.text('@terry')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: zoeRow,
            matching: find.text('Assigned to · Post #3', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: zoeRow, matching: find.text('@zoe')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: invalidRow,
            matching: find.text('Assigned to · Post', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: invalidRow, matching: find.text('@invalid')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: missingRow,
            matching: find.text('Assigned to · Post', findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: missingRow, matching: find.text('@missing')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(topicRow).dy,
          lessThan(tester.getTopLeft(supportRow).dy),
        );
        expect(
          tester.getTopLeft(supportRow).dy,
          lessThan(tester.getTopLeft(terryRow).dy),
        );
        expect(
          tester.getTopLeft(terryRow).dy,
          lessThan(tester.getTopLeft(zoeRow).dy),
        );
        expect(
          tester.getTopLeft(zoeRow).dy,
          lessThan(tester.getTopLeft(invalidRow).dy),
        );
        expect(
          tester.getTopLeft(invalidRow).dy,
          lessThan(tester.getTopLeft(missingRow).dy),
        );
        expect(find.textContaining('deliberately long'), findsNothing);
        expect(
          tester.getSemantics(topicRow).label,
          'Topic assigned to Sam, user @sam, '
          'note A deliberately long topic note',
        );
        expect(
          tester.getSemantics(supportRow).label,
          'Post #2 assigned to support, group @support, '
          'note Another deliberately long post note',
        );
      } finally {
        semanticsHandle.dispose();
      }
    });
  });
}
