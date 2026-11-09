import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/assign/assign_shell_service.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fromLink in [false, true]) {
    test(
      'Assign opens its typed group over a same-key feed ($fromLink)',
      () async {
        final route = ContentRoute.group(
          GroupRoute.plugin(
            groupName: 'support',
            owner: 'discourse-assign',
            section: 'assigned',
            subsection: 'support',
          ),
          title: 'support',
        );
        final host = _RecordingRouteHost()
          ..currentContent = ContentRoute(
            destination: FeedDestination(key: route.id),
            title: 'A feed',
            icon: DIcons.list,
          );
        final navigation = AssignShellService(
          host: host,
          canOpenGroupAssignments: (_) => true,
          openingPostFor: (_, _) => null,
        );

        if (fromLink) {
          expect(
            await navigation.openPluginUrl('/g/support/assigned/support'),
            isTrue,
          );
        } else {
          navigation.selectGroupFilter(
            'support',
            const AssignedGroupFilter.directGroup(),
          );
        }

        expect(host.currentContent!.sameDestinationAs(route), isTrue);
      },
    );
  }

  test('Assign marks only its direct post navigation for highlighting', () {
    final host = _RecordingRouteHost();
    final navigation = AssignShellService(
      host: host,
      canOpenGroupAssignments: (_) => true,
      openingPostFor: (_, _) => null,
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
    await prepareNativeUiEvidence(tester);
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
      Post(
        id: 13,
        postNumber: 3,
        username: 'sam',
        postType: Post.smallActionPostType,
        actionCode: 'closed.enabled',
        cooked: '',
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
          builder: nativeUiEvidenceBuilder,
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
    expect(find.byKey(const ValueKey('post-news-card-12')), findsNothing);

    controller.openTopicPost(
      siteUrl: site.url,
      topicId: 7,
      postNumber: 2,
      highlight: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
    expect(controller.isTopicPostHighlighted(site.url, 7, 2), isTrue);
    final card = find.byKey(const ValueKey('post-news-card-12'));
    expect(card, findsOneWidget);
    expect(tester.widget<DCard>(card).borderColor!.a, greaterThan(0));
    final paintedAncestors = tester
        .widgetList<AnimatedContainer>(
          find.ancestor(of: card, matching: find.byType(AnimatedContainer)),
        )
        .where((widget) {
          final decoration = widget.decoration;
          if (decoration is! BoxDecoration) return false;
          final border = decoration.border;
          return border is Border && border.top.color.a > 0;
        });
    expect(
      paintedAncestors,
      isEmpty,
      reason: 'the post card owns the sole navigation outline',
    );

    await captureNativeUi(tester, 'search-target-post');

    controller.openTopicPost(
      siteUrl: site.url,
      topicId: 7,
      postNumber: 1,
      highlight: true,
    );
    await tester.pump();
    final openingCard = find.byKey(const ValueKey('post-news-card-11'));
    expect(openingCard, findsOneWidget);
    expect(
      find.descendant(
        of: openingCard,
        matching: find.byKey(const ValueKey('topic-map')),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('topic-map')), findsOneWidget);
    await captureNativeUi(tester, 'search-opening-post');

    await tester.pump(const Duration(milliseconds: 2200));

    expect(controller.isTopicPostHighlighted(site.url, 7, 1), isFalse);
    expect(find.byKey(const ValueKey('post-news-card-11')), findsNothing);
    expect(find.byKey(const ValueKey('post-news-card-12')), findsNothing);

    controller.openTopicPost(
      siteUrl: site.url,
      topicId: 7,
      postNumber: 3,
      highlight: true,
    );
    await tester.pump();
    final smallCard = find.descendant(
      of: find.byKey(const ValueKey('topic-post-highlight-13')),
      matching: find.byType(DCard),
    );
    expect(smallCard, findsOneWidget);
    expect(tester.widget<DCard>(smallCard).borderColor!.a, greaterThan(0));
    await captureNativeUi(tester, 'search-small-action');
    await tester.pump(const Duration(milliseconds: 2200));
    expect(controller.isTopicPostHighlighted(site.url, 7, 3), isFalse);
    expect(tester.widget<DCard>(smallCard).borderColor, Colors.transparent);
  });
}

final class _RecordingRouteHost implements PluginRouteNavigationHost {
  @override
  String? get activeTabId => null;

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
  bool pushContent(
    ContentRoute route, {
    String? siteUrl,
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
    void Function(String tabId)? onOpened,
  }) {
    if (siteUrl != null && currentSite?.url != siteUrl) {
      final index = sites.indexWhere((site) => site.url == siteUrl);
      if (index < 0) return false;
      selectInstance(index);
    }
    currentContent = route;
    if (currentContent?.sameDestinationAs(route) == true) onNavigated?.call();
    return true;
  }

  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;

  @override
  void selectInstance(int index) {}
}
