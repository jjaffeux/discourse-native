import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_icons.dart';
import 'package:discourse_native/src/plugins/assign/assign_notifications.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/assign/assign_user_menu.dart';
import 'package:discourse_native/src/plugins/assign/assignment_actions.dart';
import 'package:discourse_native/src/plugins/assign/assignment_sheet.dart';
import 'package:discourse_native/src/shell/person_picker.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

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

        const reply = Post(
          id: 22,
          postNumber: 2,
          username: 'author',
          cooked: '',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    ..._plugin.postHeaders(context, _siteUrl, topic, post),
                    ..._plugin.postDecorations(context, _siteUrl, topic, post),
                    ..._plugin.postHeaders(context, _siteUrl, topic, reply),
                    ..._plugin.postDecorations(context, _siteUrl, topic, reply),
                  ],
                ),
              ),
            ),
          ),
        );

        // The first post is the topic: its news says the topic's assignment,
        // with the group's mark where a face would be.
        final news = find.byKey(const Key('assign-topic-news'));
        expect(
          find.descendant(
            of: news,
            matching: find.text('Topic assigned to support'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: news, matching: find.byType(GroupFace)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: news, matching: find.text('New · Topic note')),
          findsOneWidget,
        );
        // A post's own assignment is in its note box, not the first post's.
        final note = find.byKey(const Key('assign-post-22-assignment'));
        expect(
          find.descendant(
            of: note,
            matching: find.text('Post #2 assigned to Sam'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: note, matching: find.text('@sam')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: note, matching: find.text('Waiting · Post note')),
          findsOneWidget,
        );
        expect(find.byType(PostAssignmentNote), findsOneWidget);
        expect(find.byTooltip('Change assignment'), findsNothing);
      },
    );

    testWidgets('a post note box is the quiet fill reaching past the column', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final topic = TopicDetail(
        id: 10,
        title: 'Assigned topic',
        stream: const [11, 22],
        plugins: registry.readTopic(const {
          'can_assign': true,
          'indirectly_assigned_to': {
            '22': {
              'assigned_to': {'id': 7, 'username': 'sam', 'name': 'Sam'},
              'post_number': 2,
            },
          },
        }, _siteUrl),
      );
      final reply = Post(
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

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: Builder(
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _plugin.postDecorations(
                      context,
                      _siteUrl,
                      topic,
                      reply,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final column = tester.getRect(
        find.byKey(const Key('assign-post-22-assignment')),
      );
      final box = tester.getRect(find.byType(DItem));
      expect(box.left, column.left - 8);
      expect(box.right, column.right + 8);
      expect(box.top, column.top + 12);
      final face = tester.getRect(
        find.descendant(
          of: find.byType(DItem),
          matching: find.byType(AssignmentAssigneeAvatar),
        ),
      );
      expect(face.size, const Size.square(36));
      expect(face.left, box.left + 8);
      expect(
        tester
            .widget<Text>(find.text('Post #2 assigned to Sam'))
            .style
            ?.fontSize,
        13,
      );
      expect(tester.widget<Text>(find.text('@sam')).style?.fontSize, 12.5);
      final pencil = find.byTooltip('Change assignment');
      expect(pencil, findsOneWidget);
      expect(box.contains(tester.getCenter(pencil)), isTrue);

      await tester.tap(pencil);
      await tester.pumpAndSettle();
      expect(find.text('Reassign post'), findsOneWidget);
      expect(find.text('Unassign Sam from post'), findsOneWidget);
      expect(find.text('Add a note'), findsOneWidget);
    });

    testWidgets('the first post assigns the topic from its menu', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      const post = Post(id: 11, postNumber: 1, username: 'author', cooked: '');
      final labels = <String>[];
      for (final assigned in [false, true]) {
        final topic = TopicDetail(
          id: 10,
          title: 'Topic',
          stream: const [11],
          plugins: registry.readTopic({
            'can_assign': true,
            if (assigned) 'assigned_to_user': {'username': 'sam'},
          }, _siteUrl),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) {
                labels
                  ..clear()
                  ..addAll(
                    _plugin
                        .postMenu(
                          PostMenuContext(
                            buildContext: context,
                            siteUrl: _siteUrl,
                            post: post,
                            topic: topic,
                            currentUser: null,
                          ),
                        )
                        .entries
                        .map((entry) => entry.label),
                  );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(
          labels,
          assigned
              ? ['Reassign topic', 'Unassign from topic']
              : ['Assign topic'],
        );
      }
    });

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
    testWidgets('both list presentations show assignments', (tester) async {
      final shell = ShellController(
        plugins: installedPlugins,
        instanceStore: FakeInstanceStore([]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(() async {
        shell.dispose();
        await shell.pluginTeardown;
      });
      final registry = installedPlugins.registry;
      final topic = Topic(
        id: 10,
        title: 'Assigned topic',
        slug: 'assigned-topic',
        plugins: registry.readTopic(const {
          'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
        }, _siteUrl),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PluginScope(
            session: shell.pluginSession,
            registry: registry,
            child: Builder(
              builder: (context) {
                expect(
                  registry.topicListMetadata(context, _siteUrl, topic),
                  isNotEmpty,
                );
                expect(
                  registry.compactTopicListMetadata(
                    context,
                    _siteUrl,
                    topic,
                    ({property}) {},
                  ),
                  isNotEmpty,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets(
      'labels direct and post assignments separately from last-poster identity',
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
              '23': {
                'assigned_to': {'name': 'support'},
                'post_number': 3,
              },
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

          expect(find.text('Assigned to'), findsOneWidget);
          expect(find.text('#3, #2'), findsOneWidget);
          expect(find.byType(AssignmentAssigneeAvatar), findsNWidgets(2));
          expect(find.text('Sam'), findsOneWidget);
          expect(find.text('support'), findsOneWidget);
          expect(find.textContaining('Topic'), findsNothing);
          expect(find.text('· group'), findsOneWidget);
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
              'Post #3 assigned to support, group @support; Post #2 assigned to support, group @support, status Waiting',
            ),
            findsOneWidget,
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    for (final canAssign in [true, false]) {
      testWidgets(
        'one header dropdown exposes assignments with canAssign=$canAssign',
        (tester) async {
          const registry = PluginRegistry([AssignPlugin()]);
          final topic = TopicDetail(
            id: 10,
            title: 'Assigned topic',
            stream: const [11],
            plugins: registry.readTopic({
              'can_assign': canAssign,
              'assigned_to_user': {
                'username': 'sam',
                'name': 'Sam With A Long Display Name',
              },
            }, _siteUrl),
          );
          var showingDetails = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, setState) {
                      final section = _plugin
                          .topicProperties(context, _siteUrl, topic)
                          .single;
                      if (showingDetails) {
                        return Column(children: section.values);
                      }
                      return Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 220,
                          child: section.header!(
                            context,
                            () => setState(() => showingDetails = true),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          final header = find.byKey(const Key('assign-topic-header'));
          expect(header, findsOneWidget);
          expect(
            find.byKey(const Key('assign-topic-header-details')),
            findsNothing,
          );
          expect(find.byType(DButton), findsOneWidget);
          final avatar = find.descendant(
            of: header,
            matching: find.byType(DAvatar),
          );
          expect(tester.getSize(avatar), const Size.square(24));
          expect(tester.getSize(header).width, lessThanOrEqualTo(220));
          expect(tester.takeException(), isNull);
          await tester.tap(header);
          await tester.pumpAndSettle();
          expect(showingDetails, isTrue);
          expect(
            find.byKey(const Key('assign-topic-property')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('assign-topic-change')),
            canAssign ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('assign-topic-remove')),
            canAssign ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('post-only assignments remain accessible from the header', (
      tester,
    ) async {
      const registry = PluginRegistry([AssignPlugin()]);
      final topic = TopicDetail(
        id: 10,
        title: 'Post assignment',
        stream: const [11, 22],
        plugins: registry.readTopic(const {
          'can_assign': false,
          'indirectly_assigned_to': {
            '22': {
              'assigned_to': {'username': 'sam'},
              'post_number': 2,
            },
          },
        }, _siteUrl),
      );
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => _plugin
                  .topicProperties(context, _siteUrl, topic)
                  .single
                  .header!(context, () => opened = true),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('assign-topic-header')), findsNothing);
      await tester.tap(find.text('1 assigned post'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });

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
      expect(section.actions, isEmpty);
      expect(section.values, hasLength(1));
      final row = find.byKey(const Key('assign-topic-button'));
      expect(
        find.descendant(of: row, matching: find.text('Assign topic')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.userPlus,
          ),
        ),
        findsOneWidget,
      );
      // With nothing assigned, the foot's shortcut picks who at once.
      expect(section.compactAction?.label, 'Assign topic');
      expect(section.compactAction?.onSelected, isNotNull);
    });

    testWidgets('the foot shortcut says what the topic holds', (tester) async {
      const registry = PluginRegistry([AssignPlugin()]);
      Future<TopicPropertySection> sectionFor(Map<String, Object?> json) async {
        late TopicPropertySection section;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) {
                section = _plugin
                    .topicProperties(
                      context,
                      _siteUrl,
                      TopicDetail(
                        id: 10,
                        title: 'Topic',
                        stream: const [11, 22, 23],
                        plugins: registry.readTopic(json, _siteUrl),
                      ),
                    )
                    .single;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return section;
      }

      const post = {
        '22': {
          'assigned_to': {'username': 'zoe', 'name': 'Zoe'},
          'post_number': 2,
        },
      };
      final one = await sectionFor(const {
        'can_assign': true,
        'indirectly_assigned_to': post,
      });
      expect(one.compactAction?.label, 'Assigned to Zoe');
      expect(one.compactAction?.onSelected, isNull);
      expect(one.actions, isEmpty);
      // Only posts are given out, so the topic can still be.
      expect(one.values.last, isA<Builder>());

      final two = await sectionFor(const {
        'can_assign': true,
        'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
        'indirectly_assigned_to': post,
      });
      expect(two.compactAction?.label, '2 assignments');
      expect(two.compactAction?.onSelected, isNull);
      expect(two.actions, isEmpty);
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
          matching: find.text('Assigned post #2 to'),
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

    final assignmentLayouts = ValueVariant<(TextDirection, double)>({
      (TextDirection.ltr, 1),
      (TextDirection.rtl, 2),
    });

    testWidgets('gives an assigned topic icon-only change and remove actions', (
      tester,
    ) async {
      final (direction, textScale) = assignmentLayouts.currentValue!;
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Scaffold(
            body: SizedBox(
              width: 228,
              child: Builder(
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

      final row = find.byKey(const Key('assign-topic-property'));
      final change = find.byKey(const Key('assign-topic-change'));
      final remove = find.byKey(const Key('assign-topic-remove'));
      expect(
        find.descendant(of: row, matching: find.text('Assigned topic to')),
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
      expect(tester.getSemantics(change).label, 'Reassign topic');
      expect(tester.getSemantics(remove).label, 'Unassign Sam from topic');
      expect(tester.getRect(row).contains(tester.getCenter(change)), isTrue);
      expect(tester.getRect(row).contains(tester.getCenter(remove)), isTrue);
      expect(tester.takeException(), isNull);
    }, variant: assignmentLayouts);

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
          find.descendant(
            of: topicRow,
            matching: find.text('Assigned topic to'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: topicRow, matching: find.text('@sam')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: supportRow,
            matching: find.text('Assigned post #2 to'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: supportRow, matching: find.text('support')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: terryRow,
            matching: find.text('Assigned post #2 to'),
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
            matching: find.text('Assigned post #3 to'),
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
            matching: find.text('Assigned post to'),
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
            matching: find.text('Assigned post to'),
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
