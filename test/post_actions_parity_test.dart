import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart' show PluginData;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/solved/solved_post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_news_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment['POST_PARITY_RENDER_DIR'] == null) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final dark in [false, true]) {
    testWidgets('production post cards render in ${dark ? 'dark' : 'light'} mode', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(1000, 2100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final posts = [
        const Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>A shared place to plan the next release.</p>',
        ),
        const Post(
          id: 2,
          postNumber: 2,
          username: 'alex',
          cooked: '<p>Please keep the discussion focused on the proposal.</p>',
          notice: PostNotice(
            type: 'custom',
            cooked:
                '<p>Staff notice: keep personal information out of public replies.</p>',
          ),
        ),
        const Post(
          id: 3,
          postNumber: 3,
          username: 'sam',
          postType: 4,
          cooked:
              '<p>This whisper keeps <strong>the author’s emphasis</strong> without making the entire post italic.</p>',
        ),
        const Post(
          id: 4,
          postNumber: 4,
          username: 'alex',
          hidden: true,
          hiddenReasonId: 1,
          cooked:
              '<p>Hidden content remains server-filtered and is subdued for staff.</p>',
        ),
        const Post(
          id: 5,
          postNumber: 5,
          username: 'sam',
          locked: true,
          cooked:
              '<p>The details are settled. This post is locked against further edits.</p>',
        ),
        const Post(
          id: 6,
          postNumber: 6,
          username: 'alex',
          cooked: '<p>Keep this release checklist for later.</p>',
          bookmark: Bookmark(
            id: 90,
            bookmarkableId: 6,
            bookmarkableType: 'Post',
            name: 'Release checklist',
          ),
        ),
        Post(
          id: 7,
          postNumber: 7,
          username: 'sam',
          cooked: '<p>This post was removed.</p>',
          deletedAt: DateTime.utc(2026, 10, 8),
          canRecover: true,
        ),
        Post(
          id: 8,
          postNumber: 8,
          username: 'alex',
          cooked: '<p>This resolves the release question.</p>',
          plugins: PluginData.none.withValue(
            solvedPostKey,
            const SolvedPost(
              accepted: true,
              canAccept: false,
              canUnaccept: true,
            ),
          ),
        ),
      ];
      final controller = ShellController(
        plugins: installedPlugins,
        instanceStore: FakeInstanceStore([
          instance('meta.example').copyWith(
            user: const DiscourseUser(username: 'reader', staff: true),
          ),
        ]),
        api: FakeDiscourseApi(
          user: const DiscourseUser(username: 'reader', staff: true),
          topics: {
            7: topicPayload(
              id: 7,
              title: 'Planning the next release',
              posts: posts,
              canCreatePost: true,
              canEditStaffNotes: true,
            ),
          },
        ),
        authenticator: FakeAuthenticator()
          ..keys['https://meta.example'] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'release',
          title: 'Planning the next release',
        ),
      );
      await controller.loadTopic(7, 'release');
      final key = GlobalKey();
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: PluginScope(
            session: controller.pluginSession,
            registry: pluginRegistry,
            child: MaterialApp(
              theme: AppTheme.forBrightness(
                dark ? Brightness.dark : Brightness.light,
                fontFamily: 'Lato',
                readingFontFamily: 'Lato',
              ).copyWith(platform: TargetPlatform.macOS),
              home: RepaintBoundary(
                key: key,
                child: const Scaffold(body: TopicView()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PostNewsCard), findsNWidgets(8));
      expect(find.byKey(const ValueKey('post-news-card-1')), findsNothing);
      final whisper = tester.widget<DCard>(
        find.byKey(const ValueKey('post-news-card-3')),
      );
      expect(whisper.dashedBorder, isTrue);
      final body = tester
          .widgetList<CookedHtml>(find.byType(CookedHtml))
          .firstWhere((w) => w.post?.id == 3);
      expect(body.textStyle?.fontStyle, isNot(FontStyle.italic));
      expect(
        find.text('Hidden after flags from the community'),
        findsOneWidget,
      );
      expect(find.text('Unhide post'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'posts-${dark ? 'dark' : 'light'}');
      expect(find.text('Change post notice'), findsOneWidget);
      final solution = tester.widget<DCard>(
        find.byKey(const ValueKey('post-news-card-8')),
      );
      expect(
        solution.backgroundColor,
        DTokens.of(
          tester.element(find.byType(TopicView)),
        ).success.withValues(alpha: .08),
      );
      await tester.tap(find.byKey(const ValueKey('post-more-actions-6')));
      await tester.pumpAndSettle();
      final menuLabels = tester
          .widgetList<DDropdownMenuItem>(find.byType(DDropdownMenuItem))
          .map((item) => (item.child as Text).data)
          .toList();
      expect(menuLabels.take(4), ['Copy link', 'Copy text', 'Share', 'Quote']);
      expect(menuLabels, isNot(contains('Like')));
      await _capture(tester, 'post-menu-${dark ? 'dark' : 'light'}');
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Bookmarked'));
      await tester.pumpAndSettle();
      expect(find.text('In 2 hours'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);
      await _capture(tester, 'bookmark-menu-${dark ? 'dark' : 'light'}');
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      final tomorrow = find.widgetWithText(DToggle, 'Tomorrow');
      await tester.ensureVisible(tomorrow);
      await tester.tap(tomorrow);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tomorrow ·'), findsOneWidget);
      await _capture(tester, 'bookmark-editor-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(const Size(320, 1300));
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.forBrightness(
              dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Lato',
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final post in [posts[3], posts[5], posts[6]])
                        PostNewsCard(
                          siteUrl: 'https://meta.example',
                          topicId: 7,
                          post: post,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(post.username),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'post-headers-large-${dark ? 'dark' : 'light'}');
    });
  }

  for (final dark in [false, true]) {
    for (final material in DAppearanceMaterial.values) {
      for (final touch in [false, true]) {
        testWidgets(
          'opening post follows topic bookmark in ${dark ? 'dark' : 'light'} '
          '${material.name} on ${touch ? 'mobile' : 'desktop'}',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.binding.setSurfaceSize(Size(touch ? 390 : 1000, 1000));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            const site = 'https://meta.example';
            const posts = [
              Post(
                id: 11,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>The opening post has no special treatment.</p>',
              ),
              Post(
                id: 12,
                postNumber: 2,
                username: 'alex',
                cooked: '<p>A reply can be saved independently.</p>',
              ),
            ];
            const topicBookmark = Bookmark(
              id: 90,
              bookmarkableId: 7,
              bookmarkableType: 'Topic',
              name: 'Saved topic',
            );
            const replyBookmark = Bookmark(
              id: 91,
              bookmarkableId: 12,
              bookmarkableType: 'Post',
              name: 'Saved reply',
            );
            final api = FakeDiscourseApi(
              topics: {
                7: topicPayload(id: 7, title: 'Topic bookmarks', posts: posts),
              },
            );
            final controller = ShellController(
              instanceStore: FakeInstanceStore([instance('meta.example')]),
              api: api,
              authenticator: FakeAuthenticator()..keys[site] = 'key',
              drafts: FakeDraftStore(),
              trackers: FakeSiteTracker.reset(),
              updateStore: FakeUpdateStore(),
            );
            addTearDown(controller.dispose);
            await controller.load();
            controller.pushContent(
              ContentRoute.topic(
                topicId: 7,
                slug: 'bookmarks',
                title: 'Topic bookmarks',
              ),
            );
            await controller.loadTopic(7, 'bookmarks');
            await tester.pumpWidget(
              ShellScope(
                controller: controller,
                child: MaterialApp(
                  theme: DMaterialTheme.apply(
                    AppTheme.forBrightness(
                      dark ? Brightness.dark : Brightness.light,
                      fontFamily: 'Lato',
                      readingFontFamily: 'Lato',
                    ).copyWith(
                      platform: touch
                          ? TargetPlatform.iOS
                          : TargetPlatform.macOS,
                    ),
                    material,
                  ),
                  home: const Scaffold(body: TopicView()),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final opening = find.byKey(const ValueKey('post-news-card-11'));
            final reply = find.byKey(const ValueKey('post-news-card-12'));
            expect(opening, findsNothing);
            expect(reply, findsNothing);
            await _capture(
              tester,
              'ordinary-${dark ? 'dark' : 'light'}-${material.name}-$touch',
            );

            Future<void> refresh({required bool savedTopic}) async {
              api.topics[7] = topicPayload(
                id: 7,
                title: 'Topic bookmarks',
                posts: [posts.first, posts.last.withBookmark(replyBookmark)],
                bookmarks: [if (savedTopic) topicBookmark, replyBookmark],
              );
              await controller.loadTopic(7, 'bookmarks', force: true);
              await tester.pumpAndSettle();
            }

            // Saving a reply must not decorate the opening post.
            await refresh(savedTopic: false);
            expect(opening, findsNothing);
            expect(reply, findsOneWidget);

            await refresh(savedTopic: true);
            expect(opening, findsOneWidget);
            expect(reply, findsOneWidget);
            expect(
              find.text('You bookmarked this topic · Saved topic'),
              findsOneWidget,
            );
            expect(
              find.text('You bookmarked this post · Saved reply'),
              findsOneWidget,
            );
            final topicBounds = tester.getRect(find.byType(DPageSurface));
            for (final card in [opening, reply]) {
              final bounds = tester.getRect(card);
              // Both 1px strokes are inside their bounds, leaving 1px clear.
              expect(bounds.left - topicBounds.left, 2);
              expect(topicBounds.right - bounds.right, 2);
            }
            final openingCard = tester.widget<DCard>(opening);
            final primary = Theme.of(
              tester.element(opening),
            ).colorScheme.primary;
            expect(openingCard.backgroundColor, primary.withValues(alpha: .08));
            expect(openingCard.borderColor, primary.withValues(alpha: .26));
            expect(tester.takeException(), isNull);
            await _capture(
              tester,
              'bookmarked-${dark ? 'dark' : 'light'}-${material.name}-$touch',
            );

            await tester.tap(
              find.descendant(
                of: opening,
                matching: find.widgetWithText(DButton, 'Edit bookmark'),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Saved topic'), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();

            await refresh(savedTopic: false);
            expect(opening, findsNothing);
            expect(reply, findsOneWidget);
            expect(
              find.textContaining('You bookmarked this topic'),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['POST_PARITY_RENDER_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
