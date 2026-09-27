import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';
import 'support/shell_test_harness.dart';

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

    test('opens the pages the app links to under its subfolder', () async {
      final shell = await loadShell(FakeDiscourseApi());
      addTearDown(shell.dispose);

      expect(shell.siteLink('/latest'), '$_siteUrl/latest');
      expect(shell.siteLink('/u/alice'), '$_siteUrl/u/alice');
      expect(shell.openCorePageUrl(shell.siteLink('/latest')), isTrue);
      expect(shell.currentContent?.id, 'latest');
    });

    testWidgets('shows the card of a user found by search in the app', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final api = GlobalSearchFixtureApi();
      await pumpShell(
        tester,
        desktop,
        instances: [
          DiscourseInstance(
            url: _siteUrl,
            title: 'Subfolder',
            user: globalSearchFixtureUser,
          ),
        ],
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      );

      await tester.tap(find.byKey(ForumSearch.inputKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ForumSearch.inputKey), 'design');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('global-search-result-users:101')),
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(api.cardsRequested, ['mira']);
      expect(find.byKey(const ValueKey('user-card-surface')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
