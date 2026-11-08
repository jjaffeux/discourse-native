import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/blank_png.dart';
import 'support/fake_image_http_client.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart' as harness;

const site = 'https://meta.example';
const me = DiscourseUser(id: 1, username: 'reader');
const card = UserCard(
  username: 'sam',
  name: 'Sam Example',
  title: 'Community guide',
  bioExcerpt: '<p>Builds things with the community.</p>',
  location: 'Paris',
);
final rows = [
  UserActivityItem(
    actionType: 4,
    topicId: 12,
    postNumber: 1,
    title: 'A topic Sam started',
    slug: 'topic',
    username: 'sam',
    excerpt: 'Opening words',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
  UserActivityItem(
    actionType: 5,
    topicId: 13,
    postNumber: 7,
    title: 'A reply from Sam',
    slug: 'reply',
    username: 'sam',
    excerpt: 'Reply words',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  UserActivityItem(
    actionType: 1,
    topicId: 13,
    postNumber: 7,
    title: 'A post Sam liked',
    slug: 'reply',
    username: 'alice',
    excerpt: 'Liked words',
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
  ),
];
const capture = ValueKey('activity-capture');

Future<(ShellController, FakeDiscourseApi)> pumpCard(
  WidgetTester tester, {
  bool desktop = false,
  bool reduced = false,
  bool longHistory = false,
  UserCard profile = card,
  double devicePixelRatio = 1,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize =
      (desktop ? const Size(1200, 900) : const Size(390, 844)) *
      devicePixelRatio;
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
  final api = FakeDiscourseApi(
    user: me,
    cards: {'sam': profile},
    userActivityItems: longHistory
        ? [
            for (var i = 0; i < 30; i++)
              UserActivityItem(
                actionType: 5,
                topicId: 100 + i,
                postNumber: 2,
                title: 'History $i',
                slug: 'history',
                username: 'sam',
                excerpt: 'Reply words',
              ),
          ]
        : rows,
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: me),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(
          platform: desktop ? TargetPlatform.macOS : TargetPlatform.iOS,
          textTheme: AppTheme.dark.textTheme.apply(fontFamily: 'Lato'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: RepaintBoundary(key: capture, child: child!),
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: UserCardTarget(
              username: 'sam',
              siteUrl: site,
              child: Text('Open Sam'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open Sam'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump();
  return (controller, api);
}

Future<void> export(WidgetTester tester, String name) async {
  final directory = Platform.environment['USER_CARD_ACTIVITY_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  testWidgets(
    'phone rests below the card, peeks by 40, then settles and swipes into real activity',
    (tester) async {
      final (shell, api) = await pumpCard(tester);
      final hint = find.byType(DSheetSwipeHint);
      expect(tester.getTopLeft(hint).dy, closeTo(844 - 34 - 6, 1));
      final rest = tester.getTopLeft(find.text('Sam Example')).dy;
      await export(tester, 'phone-rest');
      await tester.pump(const Duration(milliseconds: 399));
      expect(tester.getTopLeft(find.text('Sam Example')).dy, closeTo(rest, .1));
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 460));
      expect(
        tester.getTopLeft(find.text('Sam Example')).dy,
        closeTo(rest - 40, 1),
      );
      await export(tester, 'phone-peek');
      await tester.pump(const Duration(milliseconds: 3700));
      await tester.pump(const Duration(milliseconds: 460));
      expect(tester.getTopLeft(find.text('Sam Example')).dy, closeTo(rest, 1));
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(find.text('A post Sam liked').hitTestable(), findsOneWidget);
      expect(api.userActivityRequests.single.username, 'sam');
      await export(tester, 'phone-expanded');
      await tester.tap(find.text('Likes').last);
      await tester.pumpAndSettle();
      expect(find.text('A reply from Sam'), findsNothing);
      expect(find.text("Liked alice's post"), findsOneWidget);
      await export(tester, 'phone-likes');
      await tester.tap(find.text('A post Sam liked'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-card-surface')), findsNothing);
      expect(shell.currentContent?.topicId, 13);
      expect(shell.currentContent?.postNumber, 7);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone card activity uses cached metadata without requesting another feed',
    (tester) async {
      final (shell, api) = await pumpCard(tester);
      final existingFeeds = List<String>.of(api.feedPaths);
      shell.store.put(
        site,
        const Topic(
          id: 13,
          title: 'Cached topic title',
          slug: 'reply',
          postsCount: 48,
          likeCount: 19,
          tags: [
            TopicTag(name: 'design'),
            TopicTag(name: 'mobile'),
          ],
          posters: [
            TopicPoster(userId: 2, username: 'alice'),
            TopicPoster(userId: 3, username: 'bob', latest: true),
          ],
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Likes').last);
      await tester.pumpAndSettle();
      expect(find.text('47'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      expect(find.byType(DAvatarGroup), findsOneWidget);
      expect(find.text('#design'), findsOneWidget);
      expect(find.text("Liked alice's post"), findsOneWidget);
      expect(find.text('A post Sam liked'), findsOneWidget);
      expect(find.text('Cached topic title'), findsNothing);
      expect(api.userActivityRequests, hasLength(1));
      expect(api.feedPaths, existingFeeds);
      await export(tester, 'phone-card-cached-metadata');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'touch cancels the automatic peek and a short pull snaps back before dismissal',
    (tester) async {
      await pumpCard(tester);
      final name = find.text('Sam Example');
      final rest = tester.getTopLeft(name).dy;
      await tester.tap(name);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.getTopLeft(name).dy, closeTo(rest, 1));
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, 20),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(name).dy, closeTo(rest, 1));
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, 180),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-card-surface')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one upward gesture transfers into activity scrolling and wheel input expands the card',
    (tester) async {
      await pumpCard(tester, longHistory: true);
      final surface = find.byKey(const ValueKey('user-card-surface'));
      final scrollable = find
          .descendant(of: surface, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Sam Example')),
      );
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -950));
      await tester.pump();
      expect(
        position.pixels,
        greaterThan(0),
        reason: 'the remainder of the expansion gesture scrolls activity',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, 90),
      );
      await tester.pumpAndSettle();
      final restingTop = tester.getTopLeft(surface).dy;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.text('Sam Example')),
          scrollDelta: const Offset(0, 40),
        ),
      );
      await tester.pump(const Duration(milliseconds: 141));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(surface).dy, lessThan(restingTop - 40));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'raised activity runs to the screen foot while the resting card and the last row clear the inset',
    (tester) async {
      await pumpCard(tester, longHistory: true);
      await tester.pump(const Duration(milliseconds: 401));
      await tester.pump(const Duration(milliseconds: 460));
      final tab = find.text('Replies');
      expect(tester.getCenter(tab).dy, inExclusiveRange(844 - 40, 844));
      expect(
        tab.hitTestable(),
        findsNothing,
        reason: 'the peeking card stops above the home indicator',
      );
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('user-card-surface')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      Finder row(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(UserActivityRow),
      );
      Future<void> scrollTo(Finder target) async {
        for (var step = 0; step < 200 && target.evaluate().isEmpty; step++) {
          position.jumpTo(
            math.min(position.pixels + 120, position.maxScrollExtent),
          );
          await tester.pump();
        }
        expect(target, findsOneWidget);
      }

      final overInset = row('History 20');
      await scrollTo(overInset);
      position.jumpTo(position.pixels + tester.getCenter(overInset).dy - 830);
      await tester.pump();
      expect(overInset.hitTestable(), findsOneWidget);
      await export(tester, 'phone-expanded-foot');
      final last = row('History 29');
      await scrollTo(last);
      await tester.pump();
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(844 - 34));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the banner stays attached to the card while activity scrolls it away',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 320, 160),
          Paint()..color = const Color(0xff36576b),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, 160);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      });
      debugNetworkImageHttpClientProvider = () => FakeImageHttpClient(bytes!);
      addTearDown(() => debugNetworkImageHttpClientProvider = null);
      await pumpCard(
        tester,
        longHistory: true,
        profile: const UserCard(
          username: 'sam',
          name: 'Sam Example',
          title: 'Community guide',
          cardBackgroundUrl: 'https://meta.example/banner.png',
          bioExcerpt: '<p>Builds things with the community.</p>',
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          tester
              .widget<Image>(
                find.descendant(
                  of: find.byType(DSheetContent),
                  matching: find.byType(Image),
                ),
              )
              .image,
          tester.element(find.byType(DSheetContent)),
        ),
      );
      await tester.pump();
      await export(tester, 'phone-banner-rest');
      final banner = find.descendant(
        of: find.byType(DSheetContent),
        matching: find.byType(Image),
      );
      final originalOffset =
          tester.getTopLeft(find.text('Sam Example')).dy -
          tester.getTopLeft(banner).dy;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Sam Example')),
      );
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -1000));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(banner).dy, lessThan(0));
      expect(
        tester.getTopLeft(find.text('Sam Example')).dy -
            tester.getTopLeft(banner).dy,
        closeTo(originalOffset, .01),
      );
      await export(tester, 'phone-banner-scrolled');
      debugNetworkImageHttpClientProvider = null;
      expect(tester.takeException(), isNull);
    },
  );

  group('the phone sheet banner', () {
    Future<ui.Image> pumpBanner(WidgetTester tester, Size source) async {
      PaintingBinding.instance.imageCache.clear();
      addTearDown(PaintingBinding.instance.imageCache.clear);
      debugNetworkImageHttpClientProvider = () => FakeImageHttpClient(
        blankPng(width: source.width.toInt(), height: source.height.toInt()),
      );
      // Flutter checks this debug variable is unset before tear-downs run.
      try {
        await pumpCard(
          tester,
          devicePixelRatio: 2,
          profile: const UserCard(
            username: 'sam',
            name: 'Sam Example',
            cardBackgroundUrl: 'https://meta.example/banner.png',
          ),
        );
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          final image = tester
              .widget<RawImage>(
                find.descendant(
                  of: find.byType(DSheetContent),
                  matching: find.byType(RawImage),
                ),
              )
              .image;
          if (PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
              image != null) {
            return image;
          }
        }
        fail('The banner did not decode');
      } finally {
        debugNetworkImageHttpClientProvider = null;
      }
    }

    testWidgets('decodes near its drawn size', (tester) async {
      final image = await pumpBanner(tester, const Size(1920, 1080));

      final bytes = PaintingBinding.instance.imageCache.currentSizeBytes;
      // ignore: avoid_print
      print('PERF_PROOF cover-decode user-card-sheet_decoded_bytes=$bytes');
      expect(bytes, lessThanOrEqualTo(1600000));
      expect(image.width, greaterThanOrEqualTo(390 * 2));
    });

    testWidgets('keeps a panorama sharp across its height', (tester) async {
      final image = await pumpBanner(tester, const Size(3840, 400));

      expect(image.height, greaterThanOrEqualTo(132 * 2));
    });

    testWidgets('never upscales a small source', (tester) async {
      final image = await pumpBanner(tester, const Size(60, 30));

      expect((image.width, image.height), (60, 30));
    });
  });

  testWidgets('reduced motion retains the hint without an animated shimmer', (
    tester,
  ) async {
    await pumpCard(tester, reduced: true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final shaders = find.descendant(
      of: find.byType(DSheetSwipeHint),
      matching: find.byType(ShaderMask),
    );
    final rect = tester.getRect(find.byType(DSheetSwipeHint));
    final painter = tester.widget<ShaderMask>(shaders);
    expect(painter.shaderCallback, isNotNull);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.getRect(find.byType(DSheetSwipeHint)), rect);
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'the sheet and hint do not keep an animation ticking',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop card selects that person; normal Activity returns to the signed-in user',
    (tester) async {
      final (shell, _) = await pumpCard(tester, desktop: true);
      await export(tester, 'desktop-card');
      await tester.tap(find.text('View activity'));
      await tester.pumpAndSettle();
      final route = shell.currentContent!;
      expect((route.destination as PageDestination).activityUsername, 'sam');
      expect(route.title, "Sam Example's activity");
      expect(
        ContentRoute.fromJson(route.toJson()).destination.identity,
        route.destination.identity,
      );
      expect(find.byKey(const ValueKey('user-card-surface')), findsNothing);
      shell.openUserActivity(site);
      expect(
        (shell.currentContent!.destination as PageDestination).activityUsername,
        isNull,
      );
      expect(shell.currentContent!.title, 'Activity');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full Activity selects a person, includes likes, and resets the kind on a fresh card visit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeDiscourseApi(user: me, userActivityItems: rows);
      await harness.pumpShell(
        tester,
        harness.desktop,
        instances: [instance('meta.example').copyWith(user: me)],
        api: api,
        authenticator: FakeAuthenticator()..keys[site] = 'key',
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      shell.openUserActivity(site, username: 'sam', displayName: 'Sam Example');
      await tester.pumpAndSettle();
      expect(find.text("Sam Example's activity"), findsWidgets);
      expect(find.text("Liked alice's post"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-kind-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Likes').last);
      await tester.pumpAndSettle();
      expect(find.text('A topic Sam started'), findsNothing);
      shell.openUserActivity(site, username: 'sam', displayName: 'Sam Example');
      await tester.pumpAndSettle();
      expect(find.text('A topic Sam started'), findsOneWidget);
      shell.openContentInPanel(
        ContentRoute.userActivity(username: 'alice', displayName: 'Alice'),
        panel: ForumPanel.secondary,
      );
      await tester.pumpAndSettle();
      expect(find.text("Sam Example's activity"), findsWidgets);
      expect(find.text("Alice's activity"), findsWidgets);
      final alice = find.byType(UserActivityView).last;
      await tester.tap(
        find.descendant(
          of: alice,
          matching: find.byKey(const ValueKey('activity-kind-filter')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Likes').last);
      await tester.pumpAndSettle();
      expect(
        find.text('A topic Sam started'),
        findsOneWidget,
        reason: 'the other pane keeps its All activity filter',
      );
      shell.openUserActivity(site);
      await tester.pumpAndSettle();
      expect(
        (shell.currentContent!.destination as PageDestination).activityUsername,
        isNull,
      );
      expect(
        api.userActivityRequests.map((r) => r.username),
        containsAll(['reader', 'sam', 'alice']),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('like and authored action on the same post remain separate', () {
    expect(rows[1].identity, isNot(rows[2].identity));
    expect(rows[2].isUsable, isTrue);
  });
}
