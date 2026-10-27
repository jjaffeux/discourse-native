import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/users_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'AlignmentReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });

  for (final width in [390.0, 1440.0]) {
    for (final limited in [false, true]) {
      testWidgets('route edges match Topics at $width, limited $limited', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final site = instance(
          'meta.example',
        ).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));
        const topic = Topic(id: 1, title: 'A topic', slug: 'a-topic');
        final api = FakeDiscourseApi(
          user: site.user,
          feeds: const {
            '/latest.json': [topic],
          },
          categoryList: const [
            TopicCategory(id: 1, name: 'Support', color: '0088CC'),
            TopicCategory(id: 2, name: 'General', color: '0088CC'),
            TopicCategory(id: 3, name: 'Development', color: '0088CC'),
            TopicCategory(id: 4, name: 'Feedback', color: '0088CC'),
            TopicCategory(id: 5, name: 'Announcements', color: '0088CC'),
          ],
          userDraftList: const [
            UserDraft(
              key: 'new_topic',
              sequence: 1,
              data: ComposerDraft(title: 'A draft', reply: 'Work in progress'),
            ),
          ],
          bookmarkList: const [
            Bookmark(
              id: 1,
              bookmarkableType: 'Topic',
              title: 'A bookmark',
              path: '/t/a-topic/1',
            ),
          ],
        );
        final shell = ShellController(
          instanceStore: FakeInstanceStore([site]),
          api: api,
          authenticator: FakeAuthenticator()..keys[site.url] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        await shell.appSettings.setLimitContentSize(limited);
        await shell.loadCategories(site.url);
        await shell.draftList.load(site);
        final capture = GlobalKey();

        Future<void> pump(String name, Widget page) async {
          await tester.pumpWidget(
            ContentSettingsScope(
              controller: shell.appSettings,
              child: ShellScope(
                controller: shell,
                child: MaterialApp(
                  theme: AppTheme.dark.copyWith(
                    platform: width < 600
                        ? TargetPlatform.iOS
                        : TargetPlatform.macOS,
                    textTheme: AppTheme.dark.textTheme.apply(
                      fontFamily: 'AlignmentReview',
                    ),
                  ),
                  home: Scaffold(
                    body: RepaintBoundary(
                      key: capture,
                      child: DPageSurface(
                        framed: false,
                        limitContentSize: limited,
                        child: page,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          final dir = Platform.environment['ROUTE_ALIGNMENT_EXPORT_DIR'];
          if (dir != null && width == 1440 && limited) {
            await tester.runAsync(() async {
              final boundary =
                  capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$dir/$name.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }

        await pump(
          'Topics',
          TopicListNavigation(
            headingBuilder: (_, _) => const Text('Topics'),
            child: const TopicListView(
              feed: TopicFeed(topicIds: [1], loaded: true),
            ),
          ),
        );
        final reference = tester.getRect(
          find.byKey(const ValueKey('topic-card-1')),
        );
        final headingLeft = tester.getTopLeft(find.text('Topics')).dx;
        expect(reference.left, headingLeft);

        for (final (name, page, edges) in <(String, Widget, Finder)>[
          (
            'Drafts',
            DraftListView(siteUrl: site.url),
            find.byKey(const ValueKey('new_topic')),
          ),
          (
            'Users',
            UsersPage(
              siteUrl: site.url,
              data: const UsersPageData(
                loaded: true,
                items: [
                  UserDirectoryItem(
                    id: 1,
                    user: UserDirectoryUser(id: 1, username: 'sam'),
                  ),
                ],
              ),
            ),
            find.byKey(const ValueKey('users-table')),
          ),
          (
            'Categories',
            CategoriesPage(
              siteUrl: site.url,
              feed: shell.categoryFeedFor(site.url),
            ),
            find.byType(DPlaceCardGrid),
          ),
          (
            'Groups',
            GroupsPage(
              siteUrl: site.url,
              data: const GroupsPageData(
                loaded: true,
                groups: [Group(id: 1, name: 'support')],
              ),
            ),
            find.byKey(const ValueKey('group-row-support')),
          ),
          (
            'Bookmarks',
            BookmarkSection(siteUrl: site.url, page: true, onOpened: () {}),
            find.byKey(const ValueKey('bookmark-row-1')),
          ),
        ]) {
          await pump(name, page);
          final bounds = name == 'Categories'
              ? [1, 2, 3, 4, 5]
                    .map(
                      (id) => tester.getRect(
                        find.byKey(ValueKey('category-row-$id')),
                      ),
                    )
                    .reduce((a, b) => a.expandToInclude(b))
              : tester.getRect(edges);
          expect(
            tester.getTopLeft(find.text(name).first).dx,
            closeTo(headingLeft, .001),
            reason: '$name title',
          );
          expect(
            bounds.left,
            closeTo(reference.left, .001),
            reason: '$name left edge',
          );
          expect(
            bounds.right,
            closeTo(reference.right, .001),
            reason: '$name right edge',
          );
        }
      });
    }
  }
}
