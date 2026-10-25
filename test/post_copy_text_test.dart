import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final cases = <({String name, String cooked, String text})>[
    (
      name: 'paragraph and BR boundaries',
      cooked: '<p>Alpha</p><p>Beta<br>Gamma</p>',
      text: 'Alpha\n\nBeta\nGamma',
    ),
    (
      name: 'list item boundaries',
      cooked: '<ul><li>First</li><li>Second</li></ul>',
      text: 'First\n\nSecond',
    ),
    (
      name: 'code boundaries and indentation',
      cooked:
          '<p>Before</p><pre><code>  first\n\n\tsecond\n</code></pre><p>After</p>',
      text: 'Before\n\n  first\n\n\tsecond\n\nAfter',
    ),
    (
      name: 'code-only whitespace',
      cooked: '<pre><code>  first\n\n\tsecond\n</code></pre>',
      text: '  first\n\n\tsecond\n',
    ),
    (
      name: 'inline text without quote escapes',
      cooked:
          '<p>Literal *stars* &amp; <strong>bold</strong> <a href="https://example.com">link</a> <code>a`b</code>.</p>',
      text: 'Literal *stars* & bold link a`b.',
    ),
    (
      name: 'empty content',
      cooked: '<p></p><script>ignored</script>',
      text: '',
    ),
  ];
  for (final fixture in cases) {
    testWidgets('Copy text preserves ${fixture.name}', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const site = 'https://meta.example';
      final post = Post(
        id: 22,
        postNumber: 2,
        username: 'sam',
        cooked: fixture.cooked,
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.example',
            user: const DiscourseUser(username: 'reader'),
          ),
        ]),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.store.put(
        site,
        const TopicDetail(
          id: 7,
          title: 'Topic',
          stream: [22],
          canCreatePost: true,
        ),
      );
      shell.store.put(site, post);
      shell.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
      );
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: PluginScope(
            session: shell.pluginSession,
            registry: shell.plugins.registry,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: Scaffold(
                body: PostActions(
                  siteUrl: site,
                  post: post,
                  persistent: true,
                  child: const PostActionsFooter(child: Text('Post body')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-more-actions-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy text'));
      await tester.pumpAndSettle();
      expect(clipboard, fixture.text);
    });
  }
}
