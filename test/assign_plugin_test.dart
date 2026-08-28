import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
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
            contribution = _plugin.postMenu(context, _siteUrl, post);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(contribution?.entries, isEmpty);
  });

  testWidgets('unassigned topic header uses the Assign icon', (tester) async {
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
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                Row(children: _plugin.topicHeader(context, _siteUrl, topic)),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('assign-topic-header')),
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.userPlus,
        ),
      ),
      findsOneWidget,
    );
    final button = tester.widget<DButton>(
      find.byKey(const Key('assign-topic-header')),
    );
    expect(button.size, DButtonSize.small);
  });

  testWidgets('topic header has a concise actionable semantic label', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    const registry = PluginRegistry([AssignPlugin()]);
    final plugins = registry.readTopic(const {
      'can_assign': false,
      'assigned_to_user': {'username': 'sam', 'name': 'Sam'},
      'assignment_note': 'A deliberately long topic note',
      'indirectly_assigned_to': {
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
      stream: const [11, 22],
      plugins: plugins,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                Row(children: _plugin.topicHeader(context, _siteUrl, topic)),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byKey(const Key('assign-topic-header'))),
      isSemantics(
        label: 'View 2 assignments',
        isButton: true,
        hasTapAction: true,
      ),
    );
    final assignmentHeader = find.byKey(const Key('assign-topic-header'));
    expect(
      find.descendant(of: assignmentHeader, matching: find.byType(DButton)),
      findsNothing,
    );
    final icon = tester.widget<DIcon>(
      find.descendant(of: assignmentHeader, matching: find.byType(DIcon)),
    );
    expect(icon.size, 14);
    expect(
      icon.color,
      Theme.of(tester.element(assignmentHeader)).colorScheme.onSurfaceVariant,
    );
    expect(find.bySemanticsLabel(RegExp('long')), findsNothing);
    semanticsHandle.dispose();
  });
}
