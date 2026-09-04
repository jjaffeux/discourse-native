import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/assign/assign_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Assign marks only its direct post navigation for highlighting', () {
    final host = _RecordingRouteHost();
    final navigation = AssignShellService(
      host: host,
      canOpenGroupAssignments: (_) => true,
    );

    navigation.openTopicPost(
      siteUrl: host.currentSite!.url,
      topicId: 7,
      postNumber: 2,
    );

    expect(host.opened, (
      siteUrl: host.currentSite!.url,
      topicId: 7,
      postNumber: 2,
      highlight: true,
    ));

    navigation.openTopic(
      const Topic(
        id: 8,
        title: 'Assigned topic',
        slug: 'assigned-topic',
        highestPostNumber: 3,
      ),
    );

    expect(host.opened?.highlight, isFalse);
  });

  testWidgets('briefly highlights the post surface and then clears it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final site = instance('meta.example');
    const posts = [
      Post(
        id: 11,
        postNumber: 1,
        username: 'author',
        cooked: '<p>First post</p>',
      ),
      Post(
        id: 12,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Target post</p>',
      ),
    ];
    final payload = topicPayload(
      id: 7,
      title: 'Topic',
      posts: posts,
      postsCount: posts.length,
    );
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': <Topic>[]},
      topics: {7: payload},
    );
    final authenticator = FakeAuthenticator()..keys[site.url] = 'api-key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    await controller.loadTopic(7, 'topic');

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TopicView(showSidebar: true)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Show topic sidebar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);

    final surface = find.byKey(const ValueKey('topic-post-highlight-12'));
    expect(surface, findsOneWidget);
    expect(_surfaceDecoration(tester, surface).color, Colors.transparent);

    controller.openTopicPost(
      siteUrl: site.url,
      topicId: 7,
      postNumber: 2,
      highlight: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
    expect(controller.isTopicPostHighlighted(site.url, 7, 2), isTrue);
    expect(
      _surfaceDecoration(tester, surface).color,
      isNot(Colors.transparent),
    );

    await tester.pump(const Duration(milliseconds: 2200));

    expect(controller.isTopicPostHighlighted(site.url, 7, 2), isFalse);
    expect(_surfaceDecoration(tester, surface).color, Colors.transparent);
  });
}

BoxDecoration _surfaceDecoration(WidgetTester tester, Finder surface) =>
    tester.widget<AnimatedContainer>(surface).decoration! as BoxDecoration;

final class _RecordingRouteHost implements PluginRouteNavigationHost {
  @override
  final List<PluginRouteSite> sites = const [
    PluginRouteSite(
      url: 'https://meta.example',
      title: 'Meta',
      isConnected: true,
    ),
  ];

  @override
  PluginRouteSite? get currentSite => sites.first;

  @override
  ContentRoute? currentContent;

  ({String siteUrl, int topicId, int postNumber, bool highlight})? opened;

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {
    opened = (
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      highlight: highlight,
    );
  }

  @override
  void pushContent(ContentRoute route) => currentContent = route;

  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;

  @override
  void selectInstance(int index) {}
}
