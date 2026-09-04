import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_data.dart';
import 'package:discourse_native/src/plugins/assign/assign_notifications.dart';
import 'package:discourse_native/src/plugins/assign/assign_services.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

DiscourseUser _assignUser({
  String username = 'reader',
  bool canAssign = true,
  bool? canAssignGlobally,
}) => DiscourseUser(
  username: username,
  plugins: PluginData.none.withValue(
    assignCurrentUserDataKey,
    AssignCurrentUser(
      canAssign: canAssign,
      canAssignGlobally: canAssignGlobally,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Assign routes', () {
    test('binds an owner-scoped notification feed host', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(canAssignGlobally: true),
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
      final shell = await _loadListShell(
        api,
        user: _assignUser(canAssignGlobally: true),
      );
      addTearDown(shell.dispose);

      final host = shell.pluginSession.require(assignNotificationHostService);

      expect(host, isNot(same(shell)));
      expect(
        host.notificationFeedListenable(assignNotificationFeed.id),
        isNotNull,
      );
    });

    test('open a group tab natively when globally permitted', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(canAssignGlobally: true),
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
      final shell = await _loadListShell(
        api,
        user: _assignUser(canAssignGlobally: true),
      );
      addTearDown(shell.dispose);

      expect(await shell.openPluginUrl('/g/support/assigned/support'), isTrue);
      await pumpEventQueue();

      expect(shell.currentContent?.groupRoute?.groupName, 'support');
      expect(shell.currentContent?.groupRoute?.pluginOwner, 'discourse-assign');
      expect(shell.currentContent?.groupRoute?.section, 'assigned');
      expect(shell.currentContent?.groupRoute?.subsection, 'support');
      expect(shell.currentContent?.feedPath, isNull);
    });

    test('reject group tabs without global permission', () async {
      const assignedPath =
          '/topics/group-topics-assigned/support.json?direct=true';
      final api = FakeDiscourseApi(
        user: _assignUser(canAssign: true, canAssignGlobally: false),
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
      final shell = await _loadListShell(
        api,
        user: _assignUser(canAssign: true, canAssignGlobally: false),
      );
      addTearDown(shell.dispose);

      expect(await shell.openPluginUrl('/g/support/assigned/support'), isFalse);
      expect(api.feedPaths, isNot(contains(assignedPath)));
    });

    test('loads a topic selected from the assigned group', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(canAssignGlobally: true),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: topicPayload(id: 7, title: 'Assigned topic')},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
      final shell = await _loadListShell(
        api,
        user: _assignUser(canAssignGlobally: true),
      );
      addTearDown(shell.dispose);

      final navigation = shell.pluginSession.require(
        assignGroupNavigationService,
      );
      navigation.openTopic(
        const Topic(id: 7, title: 'Assigned topic', slug: 'assigned-topic'),
      );
      await pumpEventQueue();

      expect(shell.currentContent?.topicId, 7);
      expect(shell.currentContent?.slug, 'assigned-topic');
      expect(api.topicsOpened, [7]);
      expect(shell.currentTopic?.id, 7);
    });
  });

  group('assignment writes', () {
    test('send only an exact assignable target and reload its topic', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentGroup(name: 'triage'),
        note: 'Please investigate',
        status: 'New',
      );

      expect(error, isNull);
      expect(api.pluginWrites.single.body, {
        'target_id': 12,
        'target_type': 'Post',
        'group_name': 'triage',
        'note': 'Please investigate',
        'status': 'New',
      });
      expect(api.topicsOpened, [7, 7]);
    });

    testWidgets('manage a known assigned post outside the loaded window', (
      tester,
    ) async {
      const assignment = Assignment(
        assignee: AssignmentUser(username: 'sam'),
        postId: 12,
        postNumber: 2,
      );
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {
          7: _payload(
            canAssignTopic: true,
            canAssignPost: false,
            postAssignment: assignment,
            loadAssignedPost: false,
          ),
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/unassign.json': {'success': 'OK'},
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);
      const target = AssignmentTarget.post(12, topicId: 7);

      expect(_assignments(shell).canAssign(_site, target), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    for (final section
                        in PluginScope.of(context).registry.topicProperties(
                          context,
                          _site,
                          shell.currentTopic!,
                        ))
                      ...section.values,
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('assign-post-12-change')), findsOneWidget);
      expect(find.byKey(const Key('assign-post-12-remove')), findsOneWidget);
      await tester.tap(find.byKey(const Key('assign-post-12-remove')));
      await tester.pumpAndSettle();

      api.topics[7] = _payload(
        canAssignTopic: true,
        canAssignPost: false,
        loadAssignedPost: false,
      );
      await tester.runAsync(() => shell.loadTopic(7, 'topic', force: true));
      await tester.pump();
      expect(_assignments(shell).canAssign(_site, target), isFalse);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(api.pluginWrites.map((write) => write.body), [
        {'target_id': 12, 'target_type': 'Post'},
        {
          'target_id': 12,
          'target_type': 'Post',
          'username': 'sam',
          'should_notify': 'false',
        },
      ]);
    });

    test('reject post #1 even when its serializer says assignable', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(11, topicId: 7),
        const AssignmentUser(username: 'sam'),
      );

      expect(error, contains("can't post"));
      expect(api.pluginWrites, isEmpty);
      expect(api.topicsOpened, [7]);
    });

    test('respect per-target denial over a global capability', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(canAssignGlobally: true),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: false)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentUser(username: 'sam'),
      );

      expect(error, contains("can't post"));
      expect(api.pluginWrites, isEmpty);
    });
  });

  group('legacy capability fallback', () {
    test('uses a fresh session capability for older target payloads', () async {
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: null)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentUser(username: 'sam'),
      );

      expect(error, isNull);
      expect(api.pluginWrites, hasLength(1));
    });

    test(
      'does not reuse a persisted capability when the fresh session omits it',
      () async {
        final api = FakeDiscourseApi(
          user: const DiscourseUser(username: 'reader'),
          feeds: const {'/latest.json': <Topic>[]},
          topics: {7: _payload(canAssignPost: null)},
          siteConfigs: const {_site: SiteConfig.unknown()},
          pluginResponses: const {
            'PUT /assign/assign.json': {'success': 'OK'},
          },
        );
        final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
        final shell = ShellController(
          plugins: installedPlugins,
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(user: _assignUser()),
          ]),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await pumpEventQueue();
        shell.pushContent(
          ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
        );
        await shell.loadTopic(7, 'topic');

        final error = await _assignments(shell).assign(
          _site,
          const AssignmentTarget.post(12, topicId: 7),
          const AssignmentUser(username: 'sam'),
        );

        expect(error, isNotNull);
        expect(api.pluginWrites, isEmpty);
      },
    );

    test(
      'disables only the legacy fallback after a plugin-route 404',
      () async {
        final api = FakeDiscourseApi(
          user: _assignUser(),
          feeds: const {'/latest.json': <Topic>[]},
          topics: {7: _payload(canAssignPost: null)},
          siteConfigs: const {_site: SiteConfig.unknown()},
          pluginResponses: const {
            'PUT /assign/assign.json': {'success': 'OK'},
          },
          pluginWriteFailures: {
            'PUT /assign/assign.json': const WriteException(
              WriteFailure.unreachable,
              statusCode: 404,
            ),
          },
        );
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        final assignments = shell.pluginSession.require(
          assignmentControllerService,
        );
        const legacyTarget = AssignmentTarget.post(12, topicId: 7);
        expect(assignments.canAssign(_site, legacyTarget), isTrue);

        final error = await _assignments(shell).assign(
          _site,
          const AssignmentTarget.post(12, topicId: 7),
          const AssignmentUser(username: 'sam'),
        );

        expect(error, 'This assignment target is no longer available.');
        expect(assignments.canAssign(_site, legacyTarget), isFalse);
        expect(
          assignments.canAssign(_site, const AssignmentTarget.topic(7)),
          isTrue,
        );
      },
    );
  });

  group('plugin contributions', () {
    testWidgets('omit the topic header when Assign is unavailable', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignTopic: false, canAssignPost: false)},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);
      final assignments = shell.pluginSession.require(
        assignmentControllerService,
      );
      expect(
        assignments.canAssign(_site, const AssignmentTarget.topic(7)),
        isFalse,
      );
      late List<TopicPropertySection> contribution;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  contribution = PluginScope.of(context).registry
                      .topicProperties(context, _site, shell.currentTopic!);
                  return Row(
                    children: [
                      for (final section in contribution) ...section.values,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(contribution, isEmpty);
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
    });

    testWidgets('open a sidebar assignment around its exact post', (
      tester,
    ) async {
      const assignment = Assignment(
        assignee: AssignmentUser(username: 'sam', name: 'Sam'),
        postId: 12,
        postNumber: 2,
      );
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {
          7: _payload(
            canAssignTopic: false,
            canAssignPost: false,
            postAssignment: assignment,
          ),
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    for (final section
                        in PluginScope.of(context).registry.topicProperties(
                          context,
                          _site,
                          shell.currentTopic!,
                        ))
                      ...section.values,
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final postTarget = find.byKey(const Key('assign-post-12-target'));
      expect(tester.getSize(postTarget).height, greaterThanOrEqualTo(40));
      expect(
        tester.getSemantics(postTarget),
        isSemantics(
          label: 'Open Post #2',
          isButton: false,
          isLink: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(postTarget);
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 7]);
      expect(api.topicPostNumbersOpened, [null, 2]);
      expect(shell.currentContent?.postNumber, 2);
      expect(shell.isTopicPostHighlighted(_site, 7, 2), isTrue);

      await tester.pump(const Duration(milliseconds: 2200));
      expect(shell.isTopicPostHighlighted(_site, 7, 2), isFalse);
    });

    testWidgets(
      'open separate Change editors for exact topic and post targets',
      (tester) async {
        const topicAssignment = Assignment(
          assignee: AssignmentUser(username: 'lead', name: 'Topic lead'),
          note: 'Own the topic',
        );
        const postAssignment = Assignment(
          assignee: AssignmentUser(username: 'sam', name: 'Sam'),
          postId: 12,
          postNumber: 2,
        );
        final api = FakeDiscourseApi(
          user: _assignUser(),
          feeds: const {'/latest.json': <Topic>[]},
          topics: {
            7: _payload(
              canAssignTopic: true,
              canAssignPost: true,
              topicAssignment: topicAssignment,
              postAssignment: postAssignment,
            ),
          },
          siteConfigs: const {_site: SiteConfig.unknown()},
          pluginResponses: const {
            'GET /assign/suggestions.json?target_id=7&target_type=Topic': {},
            'GET /assign/suggestions.json?target_id=12&target_type=Post': {},
          },
        );
        final shell = (await tester.runAsync(() => _loadShell(api)))!;
        addTearDown(shell.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ShellScope(
              controller: shell,
              child: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      for (final section
                          in PluginScope.of(context).registry.topicProperties(
                            context,
                            _site,
                            shell.currentTopic!,
                          ))
                        ...section.values,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('assign-topic-change')));
        await tester.pumpAndSettle();

        expect(find.text('Edit topic assignment'), findsOneWidget);
        expect(api.pluginReadPaths, [
          '/assign/suggestions.json?target_id=7&target_type=Topic',
        ]);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-post-12-change')));
        await tester.pumpAndSettle();

        expect(find.text('Edit post assignment'), findsOneWidget);
        expect(api.pluginReadPaths, [
          '/assign/suggestions.json?target_id=7&target_type=Topic',
          '/assign/suggestions.json?target_id=12&target_type=Post',
        ]);
      },
    );

    testWidgets('remove topic and post assignments through exact controls', (
      tester,
    ) async {
      const topicAssignment = Assignment(
        assignee: AssignmentUser(username: 'lead', name: 'Topic lead'),
      );
      const postAssignment = Assignment(
        assignee: AssignmentUser(username: 'sam', name: 'Sam'),
        postId: 12,
        postNumber: 2,
      );
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {
          7: _payload(
            canAssignTopic: true,
            canAssignPost: true,
            topicAssignment: topicAssignment,
            postAssignment: postAssignment,
          ),
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/unassign.json': {'success': 'OK'},
        },
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    for (final section
                        in PluginScope.of(context).registry.topicProperties(
                          context,
                          _site,
                          shell.currentTopic!,
                        ))
                      ...section.values,
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('assign-topic-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Topic assignment removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-post-12-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Post #2 assignment removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      expect(api.pluginWrites.map((write) => write.body), [
        {'target_id': 7, 'target_type': 'Topic'},
        {'target_id': 12, 'target_type': 'Post'},
      ]);
      expect(api.pluginWrites.map((write) => '${write.method} ${write.path}'), [
        'PUT /assign/unassign.json',
        'PUT /assign/unassign.json',
      ]);
      expect(api.topicPostNumbersOpened, everyElement(isNull));
    });

    testWidgets('Undo restores the exact assignment and its details', (
      tester,
    ) async {
      const topicAssignment = Assignment(
        assignee: AssignmentUser(username: 'lead', name: 'Topic lead'),
        note: 'Own the topic',
        status: 'New',
      );
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {
          7: _payload(
            canAssignTopic: true,
            canAssignPost: false,
            topicAssignment: topicAssignment,
          ),
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/unassign.json': {'success': 'OK'},
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    for (final section
                        in PluginScope.of(context).registry.topicProperties(
                          context,
                          _site,
                          shell.currentTopic!,
                        ))
                      ...section.values,
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('assign-topic-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(api.pluginWrites, hasLength(2));
      expect(api.pluginWrites.first.body, {
        'target_id': 7,
        'target_type': 'Topic',
      });
      expect(api.pluginWrites.last.body, {
        'target_id': 7,
        'target_type': 'Topic',
        'username': 'lead',
        'note': 'Own the topic',
        'status': 'New',
        'should_notify': 'false',
      });
    });

    testWidgets('announces a Remove error after its action is rebuilt away', (
      tester,
    ) async {
      const topicAssignment = Assignment(
        assignee: AssignmentUser(username: 'lead', name: 'Topic lead'),
      );
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {
          7: _payload(
            canAssignTopic: null,
            canAssignPost: false,
            topicAssignment: topicAssignment,
          ),
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginWriteFailures: {
          'PUT /assign/unassign.json': const WriteException(
            WriteFailure.unreachable,
            statusCode: 404,
          ),
        },
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final registry = PluginScope.of(context).registry;
                  final assignments = shell.pluginSession.require(
                    assignmentControllerService,
                  );
                  return ListenableBuilder(
                    listenable: assignments,
                    builder: (context, _) => Column(
                      children: [
                        for (final section in registry.topicProperties(
                          context,
                          _site,
                          shell.currentTopic!,
                        ))
                          ...section.values,
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('assign-topic-remove')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assign-topic-remove')), findsNothing);
      expect(
        find.text('This assignment target is no longer available.'),
        findsOneWidget,
      );
    });

    testWidgets('remove topic and post-menu actions after a legacy 404', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignTopic: null, canAssignPost: null)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginWriteFailures: {
          'PUT /assign/assign.json': const WriteException(
            WriteFailure.unreachable,
            statusCode: 404,
          ),
        },
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);
      final assignments = shell.pluginSession.require(
        assignmentControllerService,
      );
      late PostMenuContribution postMenu;
      late Listenable topicPropertiesRebuildOn;
      late Listenable postMenuRebuildOn;
      var topicPropertiesBuilds = 0;
      var postMenuBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final registry = PluginScope.of(context).registry;
                  final topic = shell.currentTopic!;
                  final post = shell.store.read<Post>(_site, 12)!;
                  topicPropertiesRebuildOn = registry.topicPropertiesRebuildOn(
                    context,
                    _site,
                    topic,
                  )!;
                  postMenu = registry.postMenu(
                    context,
                    _site,
                    post,
                    topic: topic,
                    currentUser: shell.currentInstance?.user,
                  );
                  postMenuRebuildOn = postMenu.rebuildOn!;
                  return Column(
                    children: [
                      ListenableBuilder(
                        listenable: topicPropertiesRebuildOn,
                        builder: (context, _) {
                          topicPropertiesBuilds++;
                          final properties = registry.topicProperties(
                            context,
                            _site,
                            topic,
                          );
                          return SizedBox(
                            width: 320,
                            child: Column(
                              children: [
                                for (final section in properties)
                                  ...section.values,
                              ],
                            ),
                          );
                        },
                      ),
                      ListenableBuilder(
                        listenable: postMenuRebuildOn,
                        builder: (context, _) {
                          postMenuBuilds++;
                          postMenu = registry.postMenu(
                            context,
                            _site,
                            post,
                            topic: topic,
                            currentUser: shell.currentInstance?.user,
                          );
                          return Text(
                            postMenu.entries.map((entry) => entry.label).join(),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('assign-topic-property')), findsOneWidget);
      expect(postMenu.entries.map((entry) => entry.label), ['Assign post']);
      expect(identical(topicPropertiesRebuildOn, assignments), isTrue);
      expect(identical(postMenuRebuildOn, assignments), isTrue);
      final initialTopicPropertiesBuilds = topicPropertiesBuilds;
      final initialPostMenuBuilds = postMenuBuilds;

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentUser(username: 'sam'),
      );
      await tester.pumpAndSettle();

      expect(error, 'This assignment target is no longer available.');
      expect(topicPropertiesBuilds, greaterThan(initialTopicPropertiesBuilds));
      expect(postMenuBuilds, greaterThan(initialPostMenuBuilds));
      expect(find.byKey(const Key('assign-topic-property')), findsNothing);
      expect(postMenu.entries, isEmpty);
      expect(identical(postMenu.rebuildOn, assignments), isTrue);
    });

    testWidgets('keep an assigned post read-only after a legacy 404', (
      tester,
    ) async {
      const assignment = Assignment(
        assignee: AssignmentUser(username: 'sam', name: 'Sam'),
        status: 'New',
        postId: 12,
        postNumber: 2,
      );
      final api = FakeDiscourseApi(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {
          7: _payload(
            canAssignTopic: null,
            canAssignPost: null,
            postAssignment: assignment,
          ),
        },
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginWriteFailures: {
          'PUT /assign/assign.json': const WriteException(
            WriteFailure.unreachable,
            statusCode: 404,
          ),
        },
      );
      final shell = (await tester.runAsync(() => _loadShell(api)))!;
      addTearDown(shell.dispose);
      final assignments = shell.pluginSession.require(
        assignmentControllerService,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final registry = PluginScope.of(context).registry;
                  return ListenableBuilder(
                    listenable: assignments,
                    builder: (context, _) {
                      final topic = shell.currentTopic!;
                      final post = shell.store.read<Post>(_site, 12)!;
                      return Column(
                        children: [
                          for (final section in registry.topicProperties(
                            context,
                            _site,
                            topic,
                          ))
                            ...section.values,
                          ...registry.postDecorations(
                            context,
                            _site,
                            topic,
                            post,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      final sidebarRow = find.byKey(const Key('assign-topic-property-post-12'));
      final assignmentRow = find.byKey(const Key('assign-post-12-assignment'));
      Finder editIcon() => find.descendant(
        of: assignmentRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.pencil,
        ),
      );
      expect(sidebarRow, findsOneWidget);
      expect(find.byKey(const Key('assign-post-12-change')), findsOneWidget);
      expect(find.byKey(const Key('assign-post-12-remove')), findsOneWidget);
      expect(assignmentRow, findsOneWidget);
      expect(editIcon(), findsOneWidget);

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentUser(username: 'other'),
      );
      await tester.pumpAndSettle();

      expect(error, 'This assignment target is no longer available.');
      expect(sidebarRow, findsOneWidget);
      expect(find.byKey(const Key('assign-post-12-change')), findsNothing);
      expect(find.byKey(const Key('assign-post-12-remove')), findsNothing);
      expect(assignmentRow, findsOneWidget);
      expect(find.text('Post #2 assigned to Sam'), findsOneWidget);
      expect(editIcon(), findsNothing);
    });
  });

  group('assignment reconciliation', () {
    test('retries an ordinary open after a failed forced refresh', () async {
      final api = _OneFailedRefreshApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentUser(username: 'sam'),
      );

      expect(error, isNull);
      expect(api.topicsOpened, [7, 7]);

      await shell.loadTopic(7, 'topic');
      expect(api.topicsOpened, [7, 7, 7]);
    });
  });
}

AssignmentController _assignments(ShellController shell) =>
    shell.pluginSession.require(assignmentControllerService);

Future<ShellController> _loadListShell(
  FakeDiscourseApi api, {
  required DiscourseUser user,
}) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

Future<ShellController> _loadShell(FakeDiscourseApi api) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await pumpEventQueue();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await shell.loadTopic(7, 'topic');
  return shell;
}

TopicPayload _payload({
  required bool? canAssignPost,
  bool? canAssignTopic = true,
  Assignment? topicAssignment,
  Assignment? postAssignment,
  bool loadAssignedPost = true,
}) {
  PluginData assignmentData(
    bool? canAssign, {
    Assignment? direct,
    Map<int, Assignment> postAssignments = const {},
  }) => PluginData.none.withValue(
    assignmentsDataKey,
    Assignments(
      canAssign: canAssign,
      direct: direct,
      postAssignments: postAssignments,
    ),
  );

  final first = Post(
    id: 11,
    postNumber: 1,
    username: 'author',
    cooked: '<p>Topic</p>',
    plugins: assignmentData(true),
  );
  final reply = Post(
    id: 12,
    postNumber: 2,
    username: 'sam',
    cooked: '<p>Reply</p>',
    plugins: assignmentData(canAssignPost, direct: postAssignment),
  );
  return (
    detail: TopicDetail(
      id: 7,
      title: 'Topic',
      stream: const [11, 12],
      postsCount: 2,
      plugins: assignmentData(
        canAssignTopic,
        direct: topicAssignment,
        postAssignments: postAssignment == null
            ? const {}
            : {12: postAssignment},
      ),
    ),
    posts: [first, if (loadAssignedPost) reply],
  );
}

class _OneFailedRefreshApi extends FakeDiscourseApi {
  _OneFailedRefreshApi()
    : super(
        user: _assignUser(),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) {
    if (topicsOpened.length == 1) {
      topicsOpened.add(id);
      topicPostNumbersOpened.add(postNumber);
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
