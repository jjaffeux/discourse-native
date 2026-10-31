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
import 'package:flutter/rendering.dart';
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

  for (final platform in [TargetPlatform.linux, TargetPlatform.iOS]) {
    testWidgets('compact author headers keep one smaller style on $platform', (
      tester,
    ) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      Future<void> pump(TopicPostLayout layout) async {
        await tester.pumpWidget(
          _host(
            controller,
            TopicPostPresentation(
              siteUrl: _site,
              topicId: 7,
              postId: 1,
              layout: layout,
            ),
            platform: platform,
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(TopicPostLayout.standard);
      expect(tester.getSize(find.byType(DAvatar)), const Size(32, 32));
      final ordinaryName = tester.widget<Text>(find.text('author')).style!;
      final ordinaryBadge = tester.renderObject<RenderParagraph>(
        find.text('staff'),
      );
      final ordinaryBadgeFont = ordinaryBadge.text.style!.fontSize!;
      final ordinaryBadgeHeight = ordinaryBadge.size.height;
      expect(ordinaryName.fontWeight, FontWeight.w700);
      for (final layout in [
        TopicPostLayout.compact,
        TopicPostLayout.stacked,
        TopicPostLayout.headerOnly,
      ]) {
        await pump(layout);
        expect(tester.getSize(find.byType(DAvatar)), const Size(28, 28));
        final name = tester.widget<Text>(find.text('author')).style!;
        expect(name.fontWeight, FontWeight.w400);
        expect(name.fontSize, lessThan(ordinaryName.fontSize!));
        final badge = tester.renderObject<RenderParagraph>(find.text('staff'));
        expect(badge.text.style!.fontSize, lessThan(ordinaryBadgeFont));
        expect(
          tester.getSize(find.byType(DBadge)).height,
          lessThan(ordinaryBadgeHeight),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'author badges stay beside long names and update cached content',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const name = 'A very long author name that must truncate in the header';
      final controller = await _controller(
        const Post(
          id: 1,
          postNumber: 1,
          username: 'author',
          name: name,
          cooked: '<p>Body</p>',
          isStaff: true,
        ),
      );
      addTearDown(controller.dispose);
      Future<void> pump(List<Widget> badges) async {
        await tester.pumpWidget(
          _host(
            controller,
            TopicPostPresentation(
              siteUrl: _site,
              topicId: 7,
              postId: 1,
              layout: TopicPostLayout.stacked,
              contentExpanded: false,
              authorBadges: badges,
            ),
            platform: TargetPlatform.iOS,
            textScaler: const TextScaler.linear(1.4),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(const [DBadge.inline(child: Text('First'))]);
      final author = find.text(name);
      final badge = find.text('First');
      final staff = find.text('staff');
      final authorRect = tester.getRect(author);
      final badgeRect = tester.getRect(badge);
      expect(badgeRect.left, greaterThan(authorRect.right));
      expect(badgeRect.right, lessThan(tester.getRect(staff).left));
      expect(authorRect.overlaps(badgeRect), isFalse);
      expect(badgeRect.center.dy, closeTo(authorRect.center.dy, 1));
      expect(badgeRect.right, lessThan(390));
      final paragraph = tester.renderObject<RenderParagraph>(author);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(find.byType(CookedHtml), findsNothing);
      await pump(const [DBadge.inline(child: Text('Replacement'))]);
      expect(find.text('First'), findsNothing);
      expect(find.text('Replacement'), findsOneWidget);
      await pump(const []);
      expect(find.text('Replacement'), findsNothing);
      expect(find.text('staff'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'compact content disclosure honors reduced motion $reducedMotion',
      (tester) async {
        final controller = await _controller(
          _post.copyWith(
            notice: const PostNotice(type: 'custom', raw: 'A notice.'),
          ),
        );
        addTearDown(controller.dispose);
        Future<void> pump(bool expanded) async {
          await tester.pumpWidget(
            _host(
              controller,
              TopicPostPresentation(
                siteUrl: _site,
                topicId: 7,
                postId: 1,
                layout: TopicPostLayout.stacked,
                contentExpanded: expanded,
              ),
              disableAnimations: reducedMotion,
            ),
          );
        }

        final post = find.byKey(const ValueKey('topic-post-highlight-1'));
        await pump(true);
        await tester.pumpAndSettle();
        final openHeight = tester.getSize(post).height;
        final authorTop = tester.getTopLeft(find.text('author'));
        await pump(false);
        expect(tester.getTopLeft(find.text('author')), authorTop);
        if (!reducedMotion) {
          expect(find.byType(CookedHtml), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 90));
          expect(tester.getSize(post).height, greaterThan(48));
          expect(tester.getSize(post).height, lessThan(openHeight));
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(post).height, 48);
        expect(find.byType(CookedHtml), findsNothing);
        expect(find.byType(PostFooter), findsNothing);
        expect(find.text('A notice.'), findsNothing);
        expect(find.text('author'), findsOneWidget);
        await pump(true);
        if (!reducedMotion) {
          await tester.pump(const Duration(milliseconds: 90));
          final openingHeight = tester.getSize(post).height;
          expect(openingHeight, greaterThan(48));
          expect(openingHeight, lessThan(openHeight));
          await pump(false);
          await tester.pump(const Duration(milliseconds: 45));
          expect(tester.getSize(post).height, lessThan(openingHeight));
          await pump(true);
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(post).height, openHeight);
        expect(find.text('A notice.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
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

Widget _host(
  ShellController controller,
  Widget child, {
  TargetPlatform platform = TargetPlatform.linux,
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
}) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations, textScaler: textScaler),
      child: child!,
    ),
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
