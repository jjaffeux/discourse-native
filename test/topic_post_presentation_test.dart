import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/plugin_api/topic_reader.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/post_footer.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://presentation.example';
const _post = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>The canonical post body.</p>',
  isStaff: true,
  likeCount: 3,
  postActions: [PostActionSummary(id: 4, acted: true)],
);

void main() {
  for (final layout in [TopicPostLayout.headerOnly, TopicPostLayout.compact]) {
    testWidgets('$layout paints one navigation outline and clears it', (
      tester,
    ) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          controller,
          TopicPostPresentation(
            siteUrl: _site,
            topicId: 7,
            postId: 1,
            layout: layout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final post = find.byKey(const ValueKey('topic-post-highlight-1'));
      final outlineColor = DTokens.of(tester.element(post)).primary;
      final outline = find.descendant(
        of: post,
        matching: find.byWidgetPredicate((widget) {
          if (widget is! DecoratedBox) return false;
          final decoration = widget.decoration;
          if (decoration is! BoxDecoration) return false;
          final border = decoration.border;
          return border is Border &&
              border.top.color.a > 0 &&
              border.top.color.withValues(alpha: 1) == outlineColor;
        }),
      );
      expect(outline, findsNothing);
      if (layout == TopicPostLayout.headerOnly) {
        expect(tester.getSize(post).height, 48);
      }

      controller.openTopicPost(
        siteUrl: _site,
        topicId: 7,
        postNumber: 1,
        highlight: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(outline, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pumpAndSettle();
      expect(outline, findsNothing);
      if (layout == TopicPostLayout.headerOnly) {
        expect(tester.getSize(post).height, 48);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'stacked layout keeps body and footer beneath the avatar and updates its body action',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      var first = 0;
      var replacement = 0;
      Widget presentation(VoidCallback activate) => TopicPostPresentation(
        siteUrl: _site,
        topicId: 7,
        postId: 1,
        layout: TopicPostLayout.stacked,
        onBodyPressed: activate,
        bodyActionLabel: 'Activate the post body',
      );
      await tester.pumpWidget(_host(controller, presentation(() => first++)));
      await tester.pumpAndSettle();
      final avatar = tester.getRect(find.byType(DAvatar));
      final body = tester.getRect(find.byType(CookedHtml));
      expect(body.left, avatar.left);
      expect(body.top, greaterThanOrEqualTo(avatar.bottom));
      expect(tester.getRect(find.byType(PostFooter)).left, avatar.left);
      await tester.tap(find.byType(CookedHtml));
      await tester.pumpAndSettle();
      expect(first, 1);
      await tester.pumpWidget(
        _host(controller, presentation(() => replacement++)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CookedHtml));
      await tester.pumpAndSettle();
      expect(first, 1);
      expect(replacement, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact and header-only reuse the author and update cached slots',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      Widget presentation(TopicPostLayout layout, {Widget? leading}) =>
          TopicPostPresentation(
            siteUrl: _site,
            topicId: 7,
            postId: 1,
            layout: layout,
            leading: leading,
            bodyLeading: const SizedBox.expand(key: ValueKey('body-leading')),
            footerLeading: const SizedBox(
              key: ValueKey('footer-leading'),
              height: 28,
            ),
          );
      Future<void> pump(Widget child) async {
        await tester.pumpWidget(_host(controller, child));
        await tester.pumpAndSettle();
      }

      await pump(presentation(TopicPostLayout.standard));
      expect(find.byKey(const ValueKey('topic-map')), findsOneWidget);
      expect(find.byType(CookedHtml), findsOneWidget);

      await pump(presentation(TopicPostLayout.compact));
      expect(find.text('author'), findsOneWidget);
      expect(find.byType(CookedHtml), findsOneWidget);
      expect(find.byType(DSticky), findsNothing);
      expect(find.byKey(const ValueKey('topic-map')), findsNothing);
      final tile = find.byKey(const ValueKey('topic-post-highlight-1'));
      expect(
        tester.getCenter(find.byType(DAvatar)).dy - tester.getTopLeft(tile).dy,
        24,
      );
      expect(
        tester.getTopLeft(find.byType(CookedHtml)).dx -
            tester.getTopLeft(tile).dx,
        56,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('body-leading'))).width,
        32,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('body-leading'))).height,
        greaterThan(8),
      );

      await pump(
        presentation(
          TopicPostLayout.headerOnly,
          leading: const Text('Expand', key: ValueKey('first-leading')),
        ),
      );
      expect(find.text('author'), findsOneWidget);
      expect(find.byKey(const ValueKey('first-leading')), findsOneWidget);
      expect(find.byType(DAvatar), findsNothing);
      expect(find.byType(CookedHtml), findsNothing);
      expect(find.byType(PostFooter), findsNothing);
      expect(find.byType(PostActions), findsNothing);
      expect(find.byKey(const ValueKey('topic-map')), findsNothing);
      expect(tester.getSize(tile).height, 48);

      await pump(
        presentation(
          TopicPostLayout.headerOnly,
          leading: const Text('Open', key: ValueKey('next-leading')),
        ),
      );
      expect(find.byKey(const ValueKey('first-leading')), findsNothing);
      expect(find.byKey(const ValueKey('next-leading')), findsOneWidget);
      await pump(presentation(TopicPostLayout.compact));
      expect(find.byType(CookedHtml), findsOneWidget);
      expect(find.byKey(const ValueKey('footer-leading')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact news keeps the author above notices and flags', (
    tester,
  ) async {
    final controller = await _controller(
      _post.copyWith(
        bookmark: const Bookmark(id: 17, name: 'Read this again'),
        notice: const PostNotice(type: 'custom', raw: 'A canonical notice.'),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller,
        const TopicPostPresentation(
          siteUrl: _site,
          topicId: 7,
          postId: 1,
          layout: TopicPostLayout.compact,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frame = find.byKey(const ValueKey('topic-post-highlight-1'));
    final avatar = find.byType(DAvatar);
    expect(tester.getCenter(avatar).dy - tester.getTopLeft(frame).dy, 24);
    expect(find.text('A canonical notice.'), findsOneWidget);
    expect(
      find.text('You bookmarked this post · Read this again'),
      findsOneWidget,
    );
    expect(find.text('You flagged this post'), findsOneWidget);
    expect(find.byType(CookedHtml), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('A canonical notice.')).dy,
      greaterThan(tester.getBottomLeft(avatar).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'footer leading follows flags and aligns with engagement controls',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          controller,
          PostFooter(
            siteUrl: _site,
            post: _post,
            contentIndent: 40,
            leading: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: DToggle.iconOnly(
                  key: const ValueKey('footer-control'),
                  pressed: false,
                  onPressedChanged: (_) {},
                  semanticLabel: 'Toggle',
                  icon: const DIcon(DIcons.circleMinus),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.byKey(const ValueKey('footer-control'));
      final engagement = find.byType(DToggle).last;
      expect(tester.getCenter(control).dy, tester.getCenter(engagement).dy);
      expect(
        tester.getTopLeft(control).dy,
        greaterThan(
          tester.getBottomLeft(find.text('You flagged this post')).dy,
        ),
      );
      expect(tester.getCenter(control).dx, 16);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('footer leading remains visible without engagement or actions', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller,
        PostFooter(
          siteUrl: _site,
          post: const Post(id: 2, postNumber: 2, username: 'other', cooked: ''),
          contentIndent: 40,
          leading: SizedBox(
            height: 28,
            child: DButton(label: const Text('Collapse'), onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Collapse'), findsOneWidget);
    expect(tester.getSize(find.byType(PostFooter)).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}

Widget _host(ShellController controller, Widget child) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: TargetPlatform.linux),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Future<ShellController> _controller([Post post = _post]) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('presentation.example')]),
    api: FakeDiscourseApi(
      topics: {
        7: topicPayload(id: 7, title: 'Presentation', posts: [post]),
      },
    ),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'presentation', title: 'Presentation'),
  );
  await controller.loadTopic(7, 'presentation');
  return controller;
}
