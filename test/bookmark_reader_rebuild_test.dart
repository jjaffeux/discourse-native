import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(id: 7, username: 'reader');
const _topicId = 7;
const _bookmarkedPostId = 2;

final List<Post> _posts = [
  for (var id = 1; id <= 30; id++)
    Post(
      id: id,
      postNumber: id,
      username: 'sam',
      userId: 9,
      createdAt: DateTime.utc(2026, 9, 1, 0, id),
      cooked: '<p>Short reply $id</p>',
      canLike: true,
    ),
];

TopicPayload _payload(
  List<Post> posts, {
  List<Bookmark> bookmarks = const [],
}) => topicPayload(
  id: _topicId,
  title: 'A topic',
  posts: posts,
  canCreatePost: true,
  bookmarks: bookmarks,
);

/// Reports a created bookmark on the next topic read, as a forum does, so the
/// reconcile that follows a write agrees with what the client already applied.
final class _BookmarkingApi extends FakeDiscourseApi {
  _BookmarkingApi({super.user, super.topics, super.postsById});

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async {
    final id = await super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    final saved = Bookmark(
      id: id,
      bookmarkableId: targetId,
      bookmarkableType: targetType.wireName,
      postNumber: targetId,
      autoDeletePreference: autoDeletePreference!,
    );
    topics[_topicId] = _payload(
      [
        for (final post in _posts)
          if (post.id == targetId) post.withBookmark(saved) else post,
      ],
      bookmarks: [saved],
    );
    return id;
  }
}

Future<ShellController> _openTopic(
  WidgetTester tester,
  Size size,
  TargetPlatform platform, {
  required bool mobile,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = _BookmarkingApi(
    user: _reader,
    topics: {_topicId: _payload(_posts)},
    postsById: {for (final post in _posts) post.id: post},
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    mobileNavigationEnabled: mobile,
    plugins: PluginInstaller.install(bundledWidgetTestManifest),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: const AdaptiveShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.pushContent(
    ContentRoute.topic(topicId: _topicId, slug: 'a-topic', title: 'A topic'),
  );
  await controller.loadTopic(_topicId, 'a-topic');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return controller;
}

Bookmark? _renderedBookmark(WidgetTester tester) => tester
    .widget<PostActions>(
      find.byWidgetPredicate(
        (widget) =>
            widget is PostActions && widget.post.id == _bookmarkedPostId,
      ),
    )
    .post
    .bookmark;

void main() {
  for (final (name, size, platform, mobile, budget) in [
    ('macos', const Size(1440, 844), TargetPlatform.macOS, false, 1039),
    ('ios', const Size(390, 844), TargetPlatform.iOS, true, 919),
  ]) {
    testWidgets('$name: a bookmark write redraws only the post it changed', (
      tester,
    ) async {
      final controller = await _openTopic(
        tester,
        size,
        platform,
        mobile: mobile,
      );
      expect(_renderedBookmark(tester), isNull);
      final rebuilt = <String>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        rebuilt.add(element.widget.runtimeType.toString());
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      final result = await controller.createBookmark(
        siteUrl: _site,
        topicId: _topicId,
        targetType: BookmarkTargetType.post,
        targetId: _bookmarkedPostId,
      );
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = previous;

      final elements = rebuilt.length;
      final tiles = rebuilt.where((type) => type == '_PostTile').length;
      // ignore: avoid_print
      print('PERF_PROOF bookmark-store ${name}_elements=$elements');
      // ignore: avoid_print
      print('PERF_PROOF bookmark-store ${name}_tiles=$tiles');

      expect(result.bookmark, isNotNull);
      expect(_renderedBookmark(tester), result.bookmark);
      expect(tiles, 1);
      expect(elements, lessThanOrEqualTo(budget));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
