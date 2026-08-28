import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/assign/assignment_shell_extension.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Shell writes only an exact assignable target and reloads its topic',
    () async {
      final api = FakeDiscourseApi(
        user: const DiscourseUser(username: 'reader', canAssign: true),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await shell.assignTarget(
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
        user: const DiscourseUser(username: 'reader', canAssign: true),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await shell.assignTarget(
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
        user: const DiscourseUser(
          username: 'reader',
          canAssign: true,
          canAssignGlobally: true,
        ),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: _payload(canAssignPost: false)},
        siteConfigs: const {_site: SiteConfig.unknown()},
        pluginResponses: const {
          'PUT /assign/assign.json': {'success': 'OK'},
        },
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      final error = await shell.assignTarget(
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
      user: const DiscourseUser(username: 'reader', canAssign: true),
      feeds: const {'/latest.json': <Topic>[]},
      topics: {7: _payload(canAssignPost: null)},
      siteConfigs: const {_site: SiteConfig.unknown()},
      pluginResponses: const {
        'PUT /assign/assign.json': {'success': 'OK'},
      },
    );
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final error = await shell.assignTarget(
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
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(username: 'reader', canAssign: true),
          ),
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

      final error = await shell.assignTarget(
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
      user: const DiscourseUser(username: 'reader', canAssign: true),
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
    expect(shell.canAssignForTarget(_site, null), isTrue);

    final error = await shell.assignTarget(
      _site,
      const AssignmentTarget.post(12, topicId: 7),
      const AssignmentUser(username: 'sam'),
    );

    expect(error, 'This assignment target is no longer available.');
    expect(shell.canAssignForTarget(_site, null), isFalse);
    // Explicit modern per-target capabilities stay authoritative.
    expect(shell.canAssignForTarget(_site, true), isTrue);
  });

  test('a failed reconciliation makes the next ordinary open retry', () async {
    final api = _OneFailedRefreshApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);

    final error = await shell.assignTarget(
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

TopicPayload _payload({required bool? canAssignPost}) {
  PluginData assignmentData(bool? canAssign) => PluginData.none.withValue(
    assignmentsDataKey,
    Assignments(canAssign: canAssign),
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
    plugins: assignmentData(canAssignPost),
  );
  return (
    detail: TopicDetail(
      id: 7,
      title: 'Topic',
      stream: const [11, 12],
      postsCount: 2,
      plugins: assignmentData(true),
    ),
    posts: [first, reply],
  );
}

class _OneFailedRefreshApi extends FakeDiscourseApi {
  _OneFailedRefreshApi()
    : super(
        user: const DiscourseUser(username: 'reader', canAssign: true),
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
