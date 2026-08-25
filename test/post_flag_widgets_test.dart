import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/anonymous_flag_dialog.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/post_footer.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _offTopic = PostFlagType(
  id: 3,
  nameKey: 'off_topic',
  name: 'Off-Topic',
  description: '<p>This post is not relevant.</p>',
  appliesTo: ['Post'],
  system: true,
);
const _catalog = SitePostActionCatalog(postFlags: [_offTopic]);
const _custom = PostFlagType(
  id: 1001,
  nameKey: 'custom_copyright_concern',
  name: 'Copyright concern',
  description: '<p>A custom site reason.</p>',
  appliesTo: ['Post'],
);
const _customCatalog = SitePostActionCatalog(postFlags: [_custom]);
const _availablePost = Post(
  id: 42,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Hello</p>',
  postActions: [PostActionSummary(id: 3, canAct: true)],
);
const _actedPost = Post(
  id: 42,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Hello</p>',
  likeCount: 2,
  postActions: [PostActionSummary(id: 3, acted: true)],
);

Future<({ShellController shell, FakeDiscourseApi api})> _connectedShell({
  SitePostActionCatalog catalog = _catalog,
  Post flagResponse = _actedPost,
}) async {
  final feedGate = Completer<void>();
  final api = FakeDiscourseApi(
    feeds: const {'/latest.json': []},
    gate: feedGate,
    categoryPostActionCatalog: catalog,
    flagResponses: {42: flagResponse},
  );
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.loadCategories(_siteUrl);
  feedGate.complete();
  expect(shell.postFlagTypesFor(_siteUrl), catalog.postFlags);
  shell.store.put(_siteUrl, _availablePost);
  return (shell: shell, api: api);
}

Widget _postHost(ShellController shell) => ShellScope(
  controller: shell,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: ValueListenableBuilder<Post?>(
            valueListenable: shell.store.ref<Post>(_siteUrl, 42),
            builder: (context, post, child) {
              if (post == null) return const SizedBox.shrink();
              return PostActions(
                siteUrl: _siteUrl,
                post: post,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Post body'),
                    PostFooter(siteUrl: _siteUrl, post: post),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  ),
);

Widget _plainActionsHost(ShellController shell, Post post) => ShellScope(
  controller: shell,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: PostActions(
            siteUrl: _siteUrl,
            post: post,
            child: const Text('Post body'),
          ),
        ),
      ),
    ),
  ),
);

Future<TestGesture> _hoverPost(WidgetTester tester) async {
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: Offset.zero);
  await pointer.moveTo(tester.getCenter(find.text('Post body')));
  await tester.pump();
  return pointer;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the menu submits a flag and the authoritative post confirms it',
    (tester) async {
      final (:shell, :api) = await _connectedShell();
      addTearDown(shell.dispose);
      await tester.pumpWidget(_postHost(shell));
      await _pumpFrames(tester);

      final pointer = await _hoverPost(tester);
      addTearDown(pointer.removePointer);
      expect(
        find.byTooltip('Privately flag this post for attention'),
        findsOneWidget,
      );
      expect(find.byTooltip('More actions'), findsNothing);

      await tester.tap(
        find.byTooltip('Privately flag this post for attention'),
      );
      await _pumpFrames(tester);
      expect(
        find.text('Thanks for keeping our community civil!'),
        findsOneWidget,
      );
      expect(
        tester.widget<CookedHtml>(find.byType(CookedHtml)).html,
        '<p>This post is not relevant.</p>',
      );

      await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
      await _pumpFrames(tester);

      expect(api.flagsCreated, hasLength(1));
      expect(
        find.text('Thanks for keeping our community civil!'),
        findsNothing,
      );
      expect(find.text('You flagged this as off-topic'), findsOneWidget);
      expect(find.byType(PostLikes), findsOneWidget);

      await pointer.moveTo(Offset.zero);
      await pointer.moveTo(tester.getCenter(find.text('Post body')));
      await tester.pump();
      expect(
        find.byTooltip('Privately flag this post for attention'),
        findsNothing,
      );
    },
  );

  testWidgets('anonymous readers get the explanatory email path only', (
    tester,
  ) async {
    const config = SiteConfig(
      allowAllUsersToFlagIllegalContent: true,
      illegalContentReportEmail: 'legal@example.com',
    );
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      siteConfigs: const {_siteUrl: config},
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(config: config),
      ]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'civil-topic', title: 'Civil Topic'),
    );
    shell.store.put(
      _siteUrl,
      const TopicDetail(id: 7, title: 'Civil Topic', stream: [42]),
    );

    await tester.pumpWidget(_plainActionsHost(shell, _availablePost));
    await _pumpFrames(tester);
    final pointer = await _hoverPost(tester);
    addTearDown(pointer.removePointer);

    expect(find.byTooltip('Report illegal content by email'), findsNothing);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(
      find.byTooltip('Privately flag this post for attention'),
      findsNothing,
    );
    await tester.tap(find.byTooltip('More actions'));
    await _pumpFrames(tester);
    expect(find.byTooltip('Report illegal content by email'), findsOneWidget);
    await tester.tap(find.byTooltip('Report illegal content by email'));
    await _pumpFrames(tester);
    expect(find.text('Report illegal content'), findsOneWidget);
    expect(find.text('Open email'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _pumpFrames(tester);
    await tester.pumpWidget(
      _plainActionsHost(shell, _availablePost.copyWith(hidden: true)),
    );
    await _pumpFrames(tester);
    await pointer.moveTo(Offset.zero);
    await pointer.moveTo(tester.getCenter(find.text('Post body')));
    await tester.pump();
    expect(find.byTooltip('Report illegal content by email'), findsNothing);
  });

  testWidgets('custom acted status remains independent of likes', (
    tester,
  ) async {
    const customActed = Post(
      id: 42,
      postNumber: 2,
      username: 'sam',
      cooked: '<p>Hello</p>',
      likeCount: 3,
      postActions: [PostActionSummary(id: 1001, acted: true)],
    );
    final (:shell, :api) = await _connectedShell(
      catalog: _customCatalog,
      flagResponse: customActed,
    );
    addTearDown(shell.dispose);

    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: PostFooter(siteUrl: _siteUrl, post: customActed),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('You flagged this as Copyright concern.'), findsOneWidget);
    expect(find.byType(PostLikes), findsOneWidget);
    expect(api.flagsCreated, isEmpty);
  });

  testWidgets('acted status has a neutral fallback without catalog metadata', (
    tester,
  ) async {
    final feedGate = Completer<void>();
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}, gate: feedGate),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();

    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: PostFooter(
              siteUrl: _siteUrl,
              post: Post(
                id: 42,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>Hello</p>',
                postActions: [PostActionSummary(id: 1001, acted: true)],
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('You flagged this post'), findsOneWidget);
    expect(find.byType(PostLikes), findsOneWidget);
    feedGate.complete();
  });

  test('anonymous illegal-content mailto is canonically encoded', () {
    final uri = illegalContentMailtoUri(
      email: 'legal@example.com',
      topicTitle: 'Civil & Safe',
      postUrl: 'https://meta.discourse.org/t/civil-topic/7/2',
    );

    expect(uri.scheme, 'mailto');
    expect(uri.path, 'legal@example.com');
    expect(uri.queryParameters, {
      'subject': 'Illegal content: Civil & Safe',
      'body':
          'This post https://meta.discourse.org/t/civil-topic/7/2 '
          'contains illegal content.',
    });
    expect(uri.toString(), contains('Civil+%26+Safe'));
  });
}
