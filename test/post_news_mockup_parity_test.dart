import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

const _renderDir = 'POST_NEWS_RENDER_DIR';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment[_renderDir] == null) return;
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final (name, width, dark) in [
    ('phone-light', 390.0, false),
    ('phone-dark', 390.0, true),
    ('desktop-light', 900.0, false),
  ]) {
    testWidgets('a whisper is said first as news, under a fading tint, and '
        'ruled off from its post on $name', (tester) async {
      await _pumpTopic(tester, width: width, dark: dark);
      await _capture(tester, 'whisper-locked-$name');

      final card = find.byKey(const ValueKey('post-news-card-2'));
      final whisper = find.byKey(const ValueKey('post-whisper-2'));
      final line = find.descendant(
        of: whisper,
        matching: find.text('Whisper, only staff can see this'),
      );
      expect(line, findsOneWidget);
      final tokens = DTokens.of(tester.element(line));
      final secondary = Color.lerp(tokens.background, tokens.foreground, .62);
      final style = DefaultTextStyle.of(tester.element(line)).style;
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, secondary);

      // The mark is its icon alone, 15 points in a face's 30-point room.
      final mark = find.descendant(
        of: whisper,
        matching: find.dIcon(DIcons.farEyeSlash),
      );
      expect(tester.getSize(mark), const Size.square(15));
      expect(tester.getRect(line).left - tester.getCenter(mark).dx, 15 + 9);
      expect(
        find.descendant(of: card, matching: find.byType(DAvatar)),
        findsOneWidget,
        reason: 'only the author has a face; the mark draws no disc',
      );

      // Said before the lock, the lines are bare and 12 apart.
      final locked = find.byKey(const ValueKey('post-locked-2'));
      expect(
        tester.getTopLeft(locked).dy - tester.getBottomLeft(whisper).dy,
        12,
      );
      final lockMark = find.descendant(
        of: locked,
        matching: find.dIcon(DIcons.lock),
      );
      expect(IconTheme.of(tester.element(lockMark)).color, secondary);

      // The whisper card takes the head tint in the text colour, with its
      // dashed edge.
      final head = tester.widget<DCardTint>(
        find.byKey(const ValueKey('post-news-head-2')),
      );
      expect(
        head.color,
        Theme.of(
          tester.element(card),
        ).colorScheme.onSurface.withValues(alpha: .08),
      );
      final cardWidget = tester.widget<DCard>(card);
      expect(cardWidget.dashedBorder, isTrue);
      expect(cardWidget.backgroundColor, Colors.transparent);

      // The byline is ruled off 12 under the news; the old corner icon is
      // gone.
      final rule = find.byKey(const ValueKey('post-news-rule-2'));
      final headRect = tester.getRect(
        find.byKey(const ValueKey('post-news-head-2')),
      );
      expect(tester.getRect(rule).top, headRect.bottom);
      expect(headRect.bottom - tester.getBottomLeft(locked).dy, 12);
      final author = find.descendant(of: card, matching: find.text('staffer'));
      expect(author, findsOneWidget);
      expect(
        tester.getTopLeft(author).dy,
        greaterThanOrEqualTo(tester.getRect(rule).bottom + 12),
      );
      expect(
        find.byType(DTooltip).evaluate().where((e) {
          final tooltip = e.widget as DTooltip;
          return tooltip.message == 'This post is a private whisper';
        }),
        isEmpty,
      );

      // A post with no news draws no rule.
      expect(find.byKey(const ValueKey('post-news-rule-3')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the head tint fades out by the rule; the post keeps the '
      'page ground', (tester) async {
    await _pumpTopic(tester, width: 390, dark: false);
    final pixels = await _pixels(tester);
    final head = tester.getRect(find.byKey(const ValueKey('post-news-head-2')));
    final view = tester.view.physicalSize.width.round();
    int at(double x, double y) {
      final offset = (y.round() * view + x.round()) * 4;
      return pixels.getUint32(offset);
    }

    final x = head.left + 6;
    final page = at(x, head.bottom + 30);
    expect(at(x, head.top + 4), isNot(page), reason: 'tinted at the head');
    expect(at(x, head.bottom - 1), page, reason: 'faded out by the rule');
  });

  for (final (number, heading) in [(1, 'Share topic'), (2, 'Share post #2')]) {
    testWidgets('the date at the byline end opens "$heading"', (tester) async {
      await _pumpTopic(tester, width: 900, dark: false);
      final date = find.byKey(ValueKey('post-date-share-$number'));
      expect(date, findsOneWidget);
      final byline = find.ancestor(of: date, matching: find.byType(Row)).first;
      expect(
        tester.getRect(byline).right - tester.getRect(date).right,
        lessThan(1),
      );

      await tester.tap(date);
      await tester.pumpAndSettle();

      expect(find.text(heading), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-share-copy')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-share-reply-as-new-topic')),
        number == 1 ? findsNothing : findsOneWidget,
      );
    });
  }
}

Future<void> _pumpTopic(
  WidgetTester tester, {
  required double width,
  required bool dark,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 9, username: 'moderator', staff: true);
  final created = DateTime(2026, 11, 10);
  final posts = [
    Post(
      id: 1,
      postNumber: 1,
      createdAt: created,
      username: 'opener',
      cooked: '<p>What should the next release carry?</p>',
    ),
    Post(
      id: 2,
      postNumber: 2,
      createdAt: created,
      username: 'staffer',
      cooked: '<p>Between us, the migration is not ready yet.</p>',
      postType: Post.whisperPostType,
      locked: true,
    ),
    Post(
      id: 3,
      postNumber: 3,
      createdAt: created,
      username: 'reader',
      cooked: '<p>Looking forward to it.</p>',
    ),
  ];
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Next release',
          posts: posts,
          canReplyAsNewTopic: true,
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys['https://meta.example'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'next-release', title: 'Next release'),
  );
  await controller.loadTopic(7, 'next-release');
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme:
            AppTheme.forBrightness(
              dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Lato',
              readingFontFamily: 'Lato',
            ).copyWith(
              platform: width > 600 ? TargetPlatform.macOS : TargetPlatform.iOS,
            ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: TopicView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<ByteData> _pixels(WidgetTester tester) async {
  late ByteData bytes;
  await tester.runAsync(() async {
    final image = await _image(tester);
    bytes = (await image.toByteData())!;
    image.dispose();
  });
  return bytes;
}

Future<ui.Image> _image(WidgetTester tester) {
  final view = tester.binding.renderViews.first;
  final builder = ui.SceneBuilder();
  view.debugLayer!.addToScene(builder);
  final scene = builder.build();
  final image = scene.toImage(
    view.size.width.round(),
    view.size.height.round(),
  );
  scene.dispose();
  return image;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment[_renderDir];
  if (path == null) return;
  await tester.runAsync(() async {
    final image = await _image(tester);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
