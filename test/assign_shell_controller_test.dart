import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/assign/assign_data.dart';
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

  test('Assign group URL opens its direct assignment feed natively', () async {
    const assignedPath =
        '/topics/group-topics-assigned/support.json?direct=true';
    final api = FakeDiscourseApi(
      user: _assignUser(),
      feeds: const {
        '/latest.json': <Topic>[],
        assignedPath: [
          Topic(id: 42, title: 'Assigned topic', slug: 'assigned-topic'),
        ],
      },
      siteConfigs: const {_site: SiteConfig.unknown()},
    );
    final shell = await _loadListShell(api, user: _assignUser());
    addTearDown(shell.dispose);

    expect(await shell.openPluginUrl('/g/support/assigned/support'), isTrue);
    await pumpEventQueue();

    expect(shell.currentContent?.id, 'assign-group-support');
    expect(shell.currentContent?.title, 'Assigned to support');
    expect(shell.currentContent?.feedPath, assignedPath);
    expect(api.feedPaths, contains(assignedPath));
    expect(shell.currentFeed?.topicIds, [42]);
  });

  test('Assign group URL stays external without Assign permission', () async {
    const assignedPath =
        '/topics/group-topics-assigned/support.json?direct=true';
    final api = FakeDiscourseApi(
      user: _assignUser(canAssign: false),
      feeds: const {'/latest.json': <Topic>[]},
      siteConfigs: const {_site: SiteConfig.unknown()},
    );
    final shell = await _loadListShell(
      api,
      user: _assignUser(canAssign: false),
    );
    addTearDown(shell.dispose);

    expect(await shell.openPluginUrl('/g/support/assigned/support'), isFalse);
    expect(api.feedPaths, isNot(contains(assignedPath)));
  });

  test(
    'Shell writes only an exact assignable target and reloads its topic',
    () async {
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
    },
  );

  test(
    'Shell rejects post #1 even if its post serializer says assignable',
    () async {
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
    },
  );

  test(
    'Shell never substitutes a global capability for target denial',
    () async {
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
    },
  );

  test('a fresh session capability supports older target payloads', () async {
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
    'a persisted capability never substitutes for a fresh absence',
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

  test('a plugin-route 404 disables only the legacy fallback', () async {
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
    // Explicit modern per-target capabilities stay authoritative.
    expect(
      assignments.canAssign(_site, const AssignmentTarget.topic(7)),
      isTrue,
    );
  });

  testWidgets(
    'controller-backed unavailable Assign contributes no topic header',
    (tester) async {
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
      late List<Widget> contribution;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  contribution = PluginScope.of(
                    context,
                  ).registry.topicHeader(context, _site, shell.currentTopic!);
                  return Row(children: contribution);
                },
              ),
            ),
          ),
        ),
      );

      expect(contribution, isEmpty);
      expect(find.byKey(const Key('assign-topic-header')), findsNothing);
    },
  );

  testWidgets(
    'a legacy 404 rebuilds away topic-header and post-menu contributions',
    (tester) async {
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
      late Listenable topicHeaderRebuildOn;
      late Listenable postMenuRebuildOn;
      var topicHeaderBuilds = 0;
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
                  topicHeaderRebuildOn = registry.topicHeaderRebuildOn(
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
                        listenable: topicHeaderRebuildOn,
                        builder: (context, _) {
                          topicHeaderBuilds++;
                          return Row(
                            children: registry.topicHeader(
                              context,
                              _site,
                              topic,
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

      expect(find.byKey(const Key('assign-topic-header')), findsOneWidget);
      expect(postMenu.entries.map((entry) => entry.label), ['Assign post']);
      expect(identical(topicHeaderRebuildOn, assignments), isTrue);
      expect(identical(postMenuRebuildOn, assignments), isTrue);
      final initialTopicHeaderBuilds = topicHeaderBuilds;
      final initialPostMenuBuilds = postMenuBuilds;

      final error = await _assignments(shell).assign(
        _site,
        const AssignmentTarget.post(12, topicId: 7),
        const AssignmentUser(username: 'sam'),
      );
      await tester.pumpAndSettle();

      expect(error, 'This assignment target is no longer available.');
      expect(topicHeaderBuilds, greaterThan(initialTopicHeaderBuilds));
      expect(postMenuBuilds, greaterThan(initialPostMenuBuilds));
      expect(find.byKey(const Key('assign-topic-header')), findsNothing);
      expect(postMenu.entries, isEmpty);
      expect(identical(postMenu.rebuildOn, assignments), isTrue);
    },
  );

  testWidgets('a legacy 404 rebuilds an assigned post as read-only', (
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

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                final topic = shell.currentTopic!;
                final post = shell.store.read<Post>(_site, 12)!;
                return Column(
                  children: PluginScope.of(
                    context,
                  ).registry.postDecorations(context, _site, topic, post),
                );
              },
            ),
          ),
        ),
      ),
    );

    final assignmentRow = find.byKey(const Key('assign-post-12-assignment'));
    Finder editIcon() => find.descendant(
      of: assignmentRow,
      matching: find.byWidgetPredicate(
        (widget) => widget is DIcon && widget.icon == DIcons.pencil,
      ),
    );
    expect(assignmentRow, findsOneWidget);
    expect(editIcon(), findsOneWidget);

    final error = await _assignments(shell).assign(
      _site,
      const AssignmentTarget.post(12, topicId: 7),
      const AssignmentUser(username: 'other'),
    );
    await tester.pumpAndSettle();

    expect(error, 'This assignment target is no longer available.');
    expect(assignmentRow, findsOneWidget);
    expect(find.text('Post #2 assigned to Sam'), findsOneWidget);
    expect(editIcon(), findsNothing);
  });

  test('a failed reconciliation makes the next ordinary open retry', () async {
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

    // The topic is still held, but the failed forced reconciliation prevents
    // it from becoming a permanent cache hit.
    await shell.loadTopic(7, 'topic');
    expect(api.topicsOpened, [7, 7, 7]);
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
  Assignment? postAssignment,
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
        postAssignments: postAssignment == null
            ? const {}
            : {12: postAssignment},
      ),
    ),
    posts: [first, reply],
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
