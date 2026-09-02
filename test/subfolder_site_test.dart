import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://example.com/forum';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ShellController> loadShell(FakeDiscourseApi api) async {
    final credentials = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('example.com/forum', title: 'Subfolder'),
      ]),
      api: api,
      authenticator: credentials,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    await shell.load();
    await pumpEventQueue();
    return shell;
  }

  group('a forum served from a subfolder', () {
    test('is stored and addressed under its subfolder', () async {
      final shell = await loadShell(FakeDiscourseApi());
      addTearDown(shell.dispose);

      expect(shell.currentInstance?.url, _siteUrl);
      expect(shell.currentInstance?.host, 'example.com');
      expect(shell.absoluteUrl('/forum/t/a-topic/7'), '$_siteUrl/t/a-topic/7');
    });

    test(
      'opens its own topic links and leaves the rest of the host alone',
      () async {
        final api = FakeDiscourseApi(
          feeds: const {
            '/latest.json': [Topic(id: 7, title: 'A topic', slug: 'a-topic')],
          },
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A topic',
              posts: const [
                Post(
                  id: 1,
                  postNumber: 1,
                  username: 'author',
                  cooked: '<p>x</p>',
                ),
              ],
            ),
          },
        );
        final shell = await loadShell(api);
        addTearDown(shell.dispose);

        expect(shell.openTopicUrl('https://example.com/t/a-topic/7'), isFalse);
        expect(
          shell.openTopicUrl('https://example.com/other/t/a-topic/7'),
          isFalse,
        );
        expect(shell.openTopicUrl('$_siteUrl/t/a-topic/7'), isTrue);
        expect(shell.currentContent?.topicId, 7);
      },
    );
  });
}
