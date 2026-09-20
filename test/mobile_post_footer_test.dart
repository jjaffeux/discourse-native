import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/post_footer.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://meta.example';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact footer stays on one line at $width / $scale', (
        tester,
      ) async {
        final (controller, _) = await _pumpFooter(
          tester,
          width: width,
          scale: scale,
        );
        final summary = find.byKey(const ValueKey('post-reaction-summary-1'));
        final react = find.byKey(const ValueKey('post-reaction-button-1'));
        final reply = find.byKey(
          const ValueKey(('post-footer-action', 1, 'Reply')),
        );
        final more = find.byKey(const ValueKey('post-more-actions-1'));
        final y = tester.getCenter(summary).dy;
        for (final control in [react, reply, more]) {
          expect(tester.getCenter(control).dy, closeTo(y, .1));
          expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
        }
        expect(find.text('Reply'), findsNothing);
        expect(find.text('161'), findsOneWidget);
        expect(
          find.byKey(const ValueKey(('post-footer-action', 1, 'Edit'))),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(reply);
        await tester.pumpAndSettle();
        expect(controller.visibleComposer?.target.replyToPostNumber, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('summary opens individual counts and loads all reactors', (
    tester,
  ) async {
    final (_, api) = await _pumpFooter(tester);
    await tester.tap(find.byKey(const ValueKey('post-reaction-summary-1')));
    await tester.pumpAndSettle();
    expect(find.byType(DSheetContent), findsOneWidget);
    for (final count in ['124', '18', '8', '6', '3', '2']) {
      expect(find.text(count), findsOneWidget);
    }
    expect(api.reactorsRequested, contains((postId: 1, filter: null)));
    expect(find.text('Sam Example'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile overflow keeps Edit and Bookmark available', (
    tester,
  ) async {
    final (controller, _) = await _pumpFooter(tester);
    await tester.tap(find.byKey(const ValueKey('post-more-actions-1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DDropdownMenuItem, 'Bookmark'), findsOneWidget);
    await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Edit'));
    await tester.pumpAndSettle();
    expect(controller.visibleComposer?.target.editingPostId, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty reactions leave React and Reply accessible', (
    tester,
  ) async {
    await _pumpFooter(tester, entries: const []);
    expect(find.byKey(const ValueKey('post-reaction-summary-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('post-reaction-button-1')),
      findsOneWidget,
    );
    expect(find.byTooltip('Reply to this post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only reactions still open the summary', (tester) async {
    await _pumpFooter(tester, canReact: false);
    expect(find.byKey(const ValueKey('post-reaction-button-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('post-reaction-summary-1')));
    await tester.pumpAndSettle();
    expect(find.text('Sam Example'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop retains separate reactions and labeled Reply', (
    tester,
  ) async {
    await _pumpFooter(tester, width: 1000, platform: TargetPlatform.macOS);
    expect(find.byKey(const ValueKey('post-reaction-summary-1')), findsNothing);
    expect(find.text('124'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(
      find.byKey(const ValueKey(('post-footer-action', 1, 'Edit'))),
      findsOneWidget,
    );
    expect(find.byTooltip('Bookmark this post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<(ShellController, FakeDiscourseApi)> _pumpFooter(
  WidgetTester tester, {
  double width = 320,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.android,
  bool canReact = true,
  List<Reaction> entries = const [
    Reaction(id: 'heart', count: 124),
    Reaction(id: 'laughing', count: 18),
    Reaction(id: 'tada', count: 8),
    Reaction(id: '+1', count: 6),
    Reaction(id: 'bulb', count: 3),
    Reaction(id: 'pray', count: 2),
  ],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installTestMediaPipeline(
    client: MockClient((_) async => http.Response('', 404)),
  );
  final post = Post(
    id: 1,
    postNumber: 1,
    username: 'reader',
    cooked: '<p>Post body</p>',
    canEdit: true,
    canLike: canReact,
    plugins: PluginData.none.withValue(
      reactionsDataKey,
      Reactions(entries: entries),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      reactionsSettingsDataKey,
      const ReactionsSettings(
        mainReaction: 'heart',
        offeredReactions: ['heart', 'laughing'],
      ),
    ),
  );
  const user = DiscourseUser(username: 'reader');
  final api = FakeDiscourseApi(
    user: user,
    siteConfigs: {_site: config},
    feeds: const {
      '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
    },
    topics: {
      7: (
        detail: const TopicDetail(
          id: 7,
          title: 'Topic',
          stream: [1],
          postsCount: 1,
          canCreatePost: true,
        ),
        posts: [post],
      ),
    },
    reactorsById: {
      PostReactors.key(1, null): const PostReactors(
        postId: 1,
        total: 1,
        reactors: [
          PostReactor(
            id: 2,
            username: 'sam',
            name: 'Sam Example',
            reaction: 'heart',
          ),
        ],
      ),
    },
  );
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user, config: config),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await controller.loadTopic(7, 'topic');
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PostActions(
              siteUrl: _site,
              post: post,
              persistent: true,
              child: PostFooter(siteUrl: _site, post: post),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, api);
}
