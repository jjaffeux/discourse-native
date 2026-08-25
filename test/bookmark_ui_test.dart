import 'dart:async';

import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/bookmark_ui.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _post = Post(
  id: 12,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Post body</p>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TimezoneEnvironment.instance.ensureDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop quick-create opens the full editor and saves once', (
    tester,
  ) async {
    final (controller, api) = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _postActionsHost(controller, platform: TargetPlatform.macOS, post: _post),
    );
    await tester.pumpAndSettle();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('Post body')));
    await tester.pump();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bookmark this post'));
    await tester.pumpAndSettle();

    expect(api.createdBookmarks, hasLength(1));
    expect(find.text('Bookmarked!'), findsOneWidget);
    expect(find.text('In 2 hours'), findsOneWidget);
    expect(find.text('More options'), findsOneWidget);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Times use Europe/Paris.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Follow up');
    await tester.tap(find.text('Tomorrow').last);
    await _scrollEditorToEnd(tester, 'Save');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.updatedBookmarks, hasLength(1));
    expect(api.updatedBookmarks.single.name, 'Follow up');
    expect(api.updatedBookmarks.single.reminderAt, isNotNull);
  });

  testWidgets('touch long-press exposes the same bookmark action', (
    tester,
  ) async {
    final (controller, api) = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _postActionsHost(
        controller,
        platform: TargetPlatform.android,
        post: _post,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Post body'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmark'), findsOneWidget);

    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();

    expect(api.createdBookmarks, hasLength(1));
    expect(find.text('Bookmarked!'), findsOneWidget);
  });

  testWidgets('an existing bookmark stays outside More actions like Core', (
    tester,
  ) async {
    final (controller, _) = await _controller();
    addTearDown(controller.dispose);
    const bookmarkedPost = Post(
      id: 12,
      postNumber: 2,
      username: 'sam',
      cooked: '<p>Post body</p>',
      bookmark: Bookmark(
        id: 81,
        bookmarkableId: 12,
        bookmarkableType: 'Post',
        postNumber: 2,
      ),
    );
    await tester.pumpWidget(
      _postActionsHost(
        controller,
        platform: TargetPlatform.macOS,
        post: bookmarkedPost,
      ),
    );
    await tester.pumpAndSettle();

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('Post body')));
    await tester.pump();

    expect(find.byTooltip('Edit this post bookmark'), findsOneWidget);
  });

  testWidgets('editor prefill is local and cancel discards it', (tester) async {
    final (controller, api) = await _controller();
    addTearDown(controller.dispose);
    const bookmark = Bookmark(
      id: 81,
      bookmarkableId: 12,
      bookmarkableType: 'Post',
      postNumber: 2,
      name: 'Original note',
    );
    await tester.pumpWidget(
      _host(
        controller,
        TargetPlatform.macOS,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showBookmarkEditor(
                context: context,
                controller: controller,
                siteUrl: _site,
                topicId: 7,
                bookmark: bookmark,
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.text('Original note'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Changed locally');
    await _scrollEditorToEnd(tester, 'Cancel');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(api.updatedBookmarks, isEmpty);
  });

  testWidgets('grouped topic bookmarks are ordered by post number', (
    tester,
  ) async {
    const later = Bookmark(
      id: 83,
      bookmarkableId: 14,
      bookmarkableType: 'Post',
      postNumber: 4,
      name: 'Later',
    );
    const earlier = Bookmark(
      id: 82,
      bookmarkableId: 13,
      bookmarkableType: 'Post',
      postNumber: 3,
      name: 'Earlier',
    );
    final topic = _topic(bookmarks: const [later, earlier]).detail;
    final (controller, _) = await _controller(topic: topic);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller,
        TargetPlatform.macOS,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showTopicBookmarkMenu(
                context: context,
                controller: controller,
                siteUrl: _site,
                topic: topic,
              ),
            ),
            child: const Text('Manage bookmarks'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Manage bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Post #3'), findsOneWidget);
    expect(find.text('Post #4'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Post #3')).dy,
      lessThan(tester.getTopLeft(find.text('Post #4')).dy),
    );
    expect(find.text('Delete all bookmarks'), findsOneWidget);
  });
}

Future<(ShellController, FakeDiscourseApi)> _controller({
  TopicDetail? topic,
}) async {
  final payload = topic == null
      ? _topic()
      : (detail: topic, posts: const [_post]);
  final api = FakeDiscourseApi(
    user: const DiscourseUser(username: 'reader', timezone: 'Europe/Paris'),
    feeds: const {
      '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
    },
    topics: {7: payload},
    siteConfigs: const {_site: SiteConfig.unknown()},
    bookmarkList: const [],
  );
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(
        user: const DiscourseUser(username: 'reader', timezone: 'Europe/Paris'),
      ),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await controller.loadTopic(7, 'topic');
  return (controller, api);
}

TopicPayload _topic({List<Bookmark> bookmarks = const []}) => (
  detail: TopicDetail(
    id: 7,
    title: 'Topic',
    stream: const [12],
    postsCount: 1,
    bookmarks: bookmarks,
  ),
  posts: const [_post],
);

Widget _postActionsHost(
  ShellController controller, {
  required TargetPlatform platform,
  required Post post,
}) => _host(
  controller,
  platform,
  SizedBox(
    width: 240,
    height: 100,
    child: PostActions(
      siteUrl: _site,
      post: post,
      child: const Center(child: Text('Post body')),
    ),
  ),
);

Widget _host(
  ShellController controller,
  TargetPlatform platform,
  Widget child,
) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    home: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _scrollEditorToEnd(WidgetTester tester, String action) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final scrollable = find.ancestor(
    of: find.text(action),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.maxScrollExtent, greaterThan(0));
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
}
