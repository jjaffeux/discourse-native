import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opens a new-topic composer with an opaque seed unchanged', () async {
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance(
          'meta.discourse.org',
        ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
      ]),
      api: FakeDiscourseApi(
        feeds: const {'/latest.json': <Topic>[]},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpEventQueue();

    final routeId = shell.currentContent!.id;
    const seed = 'opaque-extension-payload:\n  <keep this exactly>';

    expect(
      await shell.openNewTopicFromPlugin(
        const OpenNewTopicComposerRequest(
          siteUrl: _siteUrl,
          sourceRouteId: 'stale-route',
          seed: ComposerSeed(raw: seed),
        ),
      ),
      OpenComposerResult.sourceChanged,
    );
    expect(shell.visibleComposer, isNull);

    expect(
      await shell.openNewTopicFromPlugin(
        OpenNewTopicComposerRequest(
          siteUrl: _siteUrl,
          sourceRouteId: routeId,
          seed: const ComposerSeed(raw: seed),
        ),
      ),
      OpenComposerResult.opened,
    );
    expect(shell.visibleComposer!.target.isNewTopic, isTrue);
    expect(shell.visibleComposer!.raw, seed);
  });

  test(
    'Aggregate cancels a pending seed without replacing its composer',
    () async {
      final api = _GatedComposerApi();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();

      shell.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
      );
      shell.store.put(
        _siteUrl,
        const TopicDetail(
          id: 7,
          title: 'Topic',
          stream: [],
          canCreatePost: true,
        ),
      );
      shell.openReply();
      final retained = shell.visibleComposer!;
      retained.text.text = 'Keep this reply';

      final opening = shell.openNewTopicFromPlugin(
        const OpenNewTopicComposerRequest(
          siteUrl: _siteUrl,
          sourceRouteId: 'topic-7',
          seed: ComposerSeed(raw: 'A new topic seed'),
        ),
      );
      await api.capabilityStarted.future;

      shell.selectAggregate();
      api.capabilityGate.complete();

      expect(await opening, OpenComposerResult.sourceChanged);
      expect(shell.visibleComposer, isNull);

      shell.selectInstance(0);

      expect(shell.visibleComposer, same(retained));
      expect(shell.visibleComposer?.raw, 'Keep this reply');
    },
  );
}

final class _GatedComposerApi extends FakeDiscourseApi {
  _GatedComposerApi()
    : super(
        feeds: const {'/latest.json': <Topic>[]},
        creatableFeedPaths: const {'/latest.json'},
      );

  final capabilityStarted = Completer<void>();
  final capabilityGate = Completer<void>();

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    capabilityStarted.complete();
    await capabilityGate.future;
    return super.topicComposerCapabilities(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
