import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final name in ['celebration', 'wave']) {
      final loader = SvgAssetLoader(
        'packages/discourse_native/src/ui/assets/post_notice/$name.svg',
      );
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
    }
  });

  testWidgets('returning-user notice has no celebration animation', (
    tester,
  ) async {
    final controller = await _controller(noticeType: 'returning_user');
    addTearDown(controller.dispose);
    expect(await _openReader(tester, controller), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old first-post notices stay visible without confetti', (
    tester,
  ) async {
    final controller = await _controller(createdAt: DateTime.utc(2020, 1, 1));
    addTearDown(controller.dispose);
    expect(await _openReader(tester, controller), isFalse);
    expect(find.textContaining('This is the first time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome does not replay when the topic reader is reopened', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    expect(await _openReader(tester, controller), isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());

    expect(await _openReader(tester, controller), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome does not replay after the app controller is recreated', (
    tester,
  ) async {
    final first = await _controller();
    expect(await _openReader(tester, first), isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();

    final restarted = await _controller();
    addTearDown(restarted.dispose);
    expect(await _openReader(tester, restarted), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an inactive retained reader cannot replay an already seen welcome',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      final showSecond = ValueNotifier(false);
      addTearDown(showSecond.dispose);
      const first = Scaffold(key: ValueKey('first-reader'), body: TopicView());
      const second = Scaffold(
        key: ValueKey('retained-reader'),
        body: TopicView(),
      );
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.forBrightness(
              Brightness.light,
            ).copyWith(platform: TargetPlatform.iOS),
            home: ValueListenableBuilder<bool>(
              valueListenable: showSecond,
              builder: (context, secondVisible, child) => Stack(
                children: [
                  TickerMode(
                    enabled: !secondVisible,
                    child: Offstage(offstage: secondVisible, child: first),
                  ),
                  TickerMode(
                    enabled: secondVisible,
                    child: Offstage(offstage: !secondVisible, child: second),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();

      showSecond.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('retained-reader')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('welcome history is scoped to the post, forum and account', (
    tester,
  ) async {
    for (final (site, postId, userId) in [
      ('meta.example', 1, 9),
      ('meta.example', 2, 9),
      ('other.example', 1, 9),
      ('meta.example', 1, 10),
    ]) {
      final controller = await _controller(
        site: site,
        postId: postId,
        userId: userId,
      );
      expect(await _openReader(tester, controller), isTrue);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('two visible readers share one welcome celebration', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.forBrightness(
            Brightness.light,
          ).copyWith(platform: TargetPlatform.iOS),
          home: const Stack(
            children: [
              Scaffold(body: TopicView()),
              Scaffold(body: TopicView()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.binding.transientCallbackCount, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<ShellController> _controller({
  String site = 'meta.example',
  int postId = 1,
  int userId = 9,
  String noticeType = 'new_user',
  DateTime? createdAt,
}) async {
  final user = DiscourseUser(id: userId, username: 'reader');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance(site).copyWith(user: user)]),
    api: FakeDiscourseApi(
      user: user,
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Welcoming a new member',
          posts: [
            Post(
              id: postId,
              postNumber: 1,
              username: 'new_member',
              createdAt: createdAt ?? DateTime.now(),
              cooked: '<p>Hello everyone.</p>',
              notice: PostNotice(type: noticeType),
            ),
          ],
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys['https://$site'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'welcome',
      title: 'Welcoming a new member',
    ),
  );
  await controller.loadTopic(7, 'welcome');
  return controller;
}

Future<bool> _openReader(
  WidgetTester tester,
  ShellController controller,
) async {
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.forBrightness(
          Brightness.light,
        ).copyWith(platform: TargetPlatform.iOS),
        home: const Scaffold(body: TopicView()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.textContaining('new_member'), findsWidgets);
  return tester.binding.transientCallbackCount > 0;
}
