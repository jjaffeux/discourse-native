import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://first.example';
const _reader = DiscourseUser(id: 7, username: 'reader');
const _next = DiscourseUser(id: 8, username: 'next-reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a current-user refresh that answers with another account', () {
    late _ReplacementUserApi api;
    late ShellController shell;
    late List<String> pluginForgets;

    setUp(() async {
      api = _ReplacementUserApi();
      pluginForgets = [];
      shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('first.example').copyWith(user: _reader),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: PluginInstaller.install(
          PluginManifest([_RecordingModule(pluginForgets)]),
        ),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      addTearDown(() {
        if (!api.response.isCompleted) api.response.complete(_reader);
      });
      await shell.load();
      await api.started.future;
      await pumpEventQueue();
    });

    Future<void> replaceAccount() async {
      api.response.complete(_next);
      await pumpEventQueue();
      expect(shell.currentInstance?.user?.id, _next.id);
    }

    test('keeps the lease and drops the former account\'s records', () async {
      final lease = shell.lifecycle.capture(_site);
      shell.store.put(
        _site,
        const Topic(
          id: 99,
          title: 'Private',
          slug: 'private',
          bookmarked: true,
        ),
      );

      await replaceAccount();

      expect(lease.isCurrent, isTrue);
      expect(shell.store.read<Topic>(_site, 99), isNull);
    });

    test('drops the former account\'s topic lists', () async {
      final route = ContentRoute.topicList(TopicListMode.newTopics);
      api.rows = const [Topic(id: 30, title: 'Theirs', slug: 'theirs')];
      shell.pushContent(route);
      await shell.loadFeed(route.id);
      expect(shell.topicFeeds.feedFor(_site, route.id), isNotNull);

      await replaceAccount();

      expect(shell.topicFeeds.feedFor(_site, route.id), isNull);
    });

    test('opens a workspace that belongs to the accepted account', () async {
      shell.pushContent(ContentRoute.topicList(TopicListMode.newTopics));
      expect(
        shell.currentWorkspace?.accountIdentity,
        shell.currentAccountIdentity,
      );

      await replaceAccount();

      expect(
        shell.currentWorkspace?.accountIdentity,
        shell.currentAccountIdentity,
      );
    });

    test('tells plugins to forget the former account', () async {
      expect(pluginForgets, isEmpty);

      await replaceAccount();

      expect(pluginForgets, [_site]);
    });
  });
}

final class _ReplacementUserApi extends FakeDiscourseApi {
  _ReplacementUserApi() : super(user: _reader);
  final started = Completer<void>();
  final response = Completer<DiscourseUser>();
  List<Topic> rows = const [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async => TopicList(topics: rows);

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    currentUserRequests.add(siteUrl);
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

final class _RecordingModule implements PluginModule {
  const _RecordingModule(this.forgets);
  final List<String> forgets;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('forget-recorder'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(lifecycle: _Recorder(forgets)),
    );
  }
}

final class _Recorder extends PluginSessionLifecycle {
  _Recorder(this.forgets);
  final List<String> forgets;

  @override
  Future<void> forget(String siteUrl) async => forgets.add(siteUrl);
}
