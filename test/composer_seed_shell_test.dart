import 'package:discourse_native/src/models/discourse_user.dart';
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
}
