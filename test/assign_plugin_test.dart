import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://forum.example.com';
const _plugin = AssignPlugin();

void main() {
  test('an absent serializer block keeps Assign absent', () {
    expect(_plugin.readTopic(const {}, _siteUrl), isNull);
    expect(_plugin.readPost(const {'id': 1}, _siteUrl), isNull);
  });

  test('public assignment is parsed independently of write permission', () {
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

  test('the group tab requires every server-authored Assign guardian', () {
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
      tab(group: const {'assignable_level': 0, 'can_show_assigned_tab': true}),
      isNull,
    );
    expect(
      tab(group: const {'assignable_level': 1, 'can_show_assigned_tab': false}),
      isNull,
    );
    expect(tab(canSeeMembers: false), isNull);
    expect(tab(user: const {'can_assign_globally': false}), isNull);
    expect(tab(user: const {}), isNull);
  });

  test('only matching assignment messages invalidate the open topic', () {
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
    expect(_plugin.stalePosts('/staff/topic-assignment', const {}), isEmpty);
  });

  test('recognises every Assign small-action family and nothing else', () {
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
    expect(_plugin.smallAction(userAssigned)?.phrase, 'assigned sam to a post');
    expect(_plugin.smallAction(groupUnassigned)?.icon, DIcons.circleMinus);
    expect(_plugin.smallAction(detailChange)?.icon, DIcons.pencil);
    expect(_plugin.smallAction(unrelated), isNull);
  });

  testWidgets(
    'first post shows topic and indirect assignments without write controls',
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
      const post = Post(id: 11, postNumber: 1, username: 'author', cooked: '');

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

  testWidgets('first post never gets a post assignment menu action', (
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

  testWidgets('post assignment actions expose a pointer anchor callback', (
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

  testWidgets('unassigned topic uses the first row of a standalone section', (
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
    expect(section.values, hasLength(1));
    expect(find.text('Topic · Unassigned'), findsOneWidget);
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
    final icon = tester.widget<DIcon>(
      find.descendant(
        of: action,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.userPlus,
        ),
      ),
    );
    final label = tester.widget<Text>(
      find.descendant(of: action, matching: find.text('Topic · Unassigned')),
    );
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: action, matching: find.byType(InkWell)),
    );
    expect(icon.size, 14);
    expect(
      label.style?.fontSize,
      AppTheme.light.textTheme.labelMedium?.fontSize,
    );
    expect(inkWell.mouseCursor, SystemMouseCursors.click);
    expect(inkWell.hoverColor, Colors.transparent);
    expect(tester.getSize(action).height, lessThanOrEqualTo(30));
    expect(
      tester.getSemantics(action),
      isSemantics(
        label: 'Topic unassigned. Assign topic',
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('post-only sections retain a read-only topic row first', (
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
    expect(find.text('Topic · Unassigned'), findsOneWidget);
    expect(find.text('Post #2 · Sam'), findsOneWidget);
    expect(
      tester.getTopLeft(topicRow).dy,
      lessThan(tester.getTopLeft(postRow).dy),
    );
    final semantics = tester.widget<Semantics>(
      find.descendant(of: topicRow, matching: find.byType(Semantics)).first,
    );
    expect(semantics.properties.onTap, isNull);
  });

  testWidgets('rows are ordered and expose details only through semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
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
    final supportRow = find.byKey(const Key('assign-topic-property-post-22'));
    final terryRow = find.byKey(const Key('assign-topic-property-post-23'));
    final zoeRow = find.byKey(const Key('assign-topic-property-post-30'));
    final invalidRow = find.byKey(const Key('assign-topic-property-post-31'));
    final missingRow = find.byKey(const Key('assign-topic-property-post-32'));
    expect(find.text('Topic · Sam'), findsOneWidget);
    expect(find.text('Post #2 · support'), findsOneWidget);
    expect(find.text('Post #2 · Terry'), findsOneWidget);
    expect(find.text('Post #3 · Zoe'), findsOneWidget);
    expect(find.text('Post · Invalid number'), findsOneWidget);
    expect(find.text('Post · Missing number'), findsOneWidget);
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
      contains('note A deliberately long topic note'),
    );
    expect(
      tester.getSemantics(supportRow).label,
      contains('note Another deliberately long post note'),
    );
    semanticsHandle.dispose();
  });
}
