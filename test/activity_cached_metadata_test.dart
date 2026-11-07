import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const site = 'https://meta.example';
const otherSite = 'https://other.example';
const user = DiscourseUser(id: 1, username: 'reader');
const cached = Topic(
  id: 42,
  title: 'Current topic title',
  slug: 'cached',
  categoryId: 8,
  excerpt: 'The topic opening, not the action excerpt',
  postsCount: 25,
  likeCount: 19,
  unreadPosts: 10,
  newPosts: 2,
  seen: false,
  tags: [
    TopicTag(name: 'design'),
    TopicTag(name: 'mobile'),
    TopicTag(name: 'feedback'),
  ],
  posters: [
    TopicPoster(userId: 2, username: 'alice'),
    TopicPoster(userId: 3, username: 'bob', latest: true),
  ],
);
final action = UserActivityItem(
  actionType: 1,
  topicId: 42,
  postNumber: 7,
  title: 'Title from the activity',
  slug: 'cached',
  username: 'alice',
  excerpt: 'The post that was liked',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
);
const category = TopicCategory(id: 8, name: 'Product', color: 'ff9900');
const capture = ValueKey('activity-metadata-capture');

class _MetadataGuardApi extends FakeDiscourseApi {
  _MetadataGuardApi({List<UserActivityItem>? items})
    : super(user: user, userActivityItems: items ?? [action]);
  final unexpected = <String>[];
  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    unexpected.add(path);
    return const TopicList(topics: []);
  }

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    unexpected.add('/t/$id.json');
    return cached;
  }

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    unexpected.add('/u/$username/card.json');
    return UserCard(username: username);
  }
}

Future<(ShellController, _MetadataGuardApi)> host(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool fullPage = false,
  bool cachedTopic = true,
  List<UserActivityItem>? activityItems,
  UserActivityItem? row,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.reset);
  final api = _MetadataGuardApi(
    items: activityItems ?? (row == null ? null : [row]),
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
      instance('other.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys[site] = 'key'
      ..keys[otherSite] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  addTearDown(controller.dispose);
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pumpAndSettle();
  api.unexpected.clear();
  if (cachedTopic) controller.store.put(site, cached);
  controller.store.put(site, category);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(
          platform: width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS,
          textTheme: AppTheme.dark.textTheme.apply(fontFamily: 'Lato'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(key: capture, child: child!),
        ),
        home: Scaffold(
          body: fullPage
              ? const UserActivityView(siteUrl: site)
              : SingleChildScrollView(
                  child: UserActivityRow(
                    siteUrl: site,
                    item: row ?? action,
                    category: category,
                    onTap: () => controller.openUserActivityItem(action),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, api);
}

Future<void> export(WidgetTester tester, String name) async {
  final directory = Platform.environment['ACTIVITY_METADATA_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
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

  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'cached metadata renders at $width without requests and retains action words/time',
      (tester) async {
        final (controller, api) = await host(tester, width: width);
        expect(find.text('24'), findsOneWidget);
        expect(find.text('19'), findsOneWidget);
        expect(find.byType(DAvatarGroup), findsOneWidget);
        expect(find.text('Product'), findsOneWidget);
        expect(find.text('#design'), findsOneWidget);
        expect(find.text('Title from the activity'), findsOneWidget);
        expect(find.text('The post that was liked'), findsOneWidget);
        expect(find.text("Liked alice's post"), findsOneWidget);
        expect(find.text('2h'), findsOneWidget);
        expect(find.text('Current topic title'), findsNothing);
        expect(
          find.text('The topic opening, not the action excerpt'),
          findsNothing,
        );
        expect(
          tester.widget<TopicTitle>(find.byType(TopicTitle)).style!.fontWeight,
          FontWeight.w400,
        );
        expect(controller.store.read<Topic>(site, 42)!.unreadPosts, 10);
        await export(
          tester,
          width < 600 ? 'phone-cached-metadata' : 'desktop-cached-metadata',
        );
        await tester.pump(const Duration(seconds: 2));
        expect(api.unexpected, isEmpty);
        expect(api.userActivityRequests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an uncached row stays useful and never fetches its topic', (
    tester,
  ) async {
    final (_, api) = await host(tester, cachedTopic: false);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(TopicListMetadata), findsNothing);
    expect(find.text('The post that was liked'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(api.unexpected, isEmpty);
    expect(api.userActivityRequests, isEmpty);
  });

  testWidgets(
    'twenty uncached activity rows add no per-row or batch metadata requests',
    (tester) async {
      final items = [
        for (var i = 0; i < 20; i++)
          UserActivityItem(
            actionType: 5,
            topicId: 100 + i,
            postNumber: 2,
            title: 'Uncached activity $i',
            slug: 'activity',
            username: 'reader',
            excerpt: 'Post words',
          ),
      ];
      final (_, api) = await host(
        tester,
        fullPage: true,
        cachedTopic: false,
        activityItems: items,
      );
      await tester.scrollUntilVisible(
        find.text('Uncached activity 19'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(api.userActivityRequests, hasLength(1));
      expect(api.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal cache updates enrich an activity page without more activity or topic requests',
    (tester) async {
      final (controller, api) = await host(
        tester,
        fullPage: true,
        cachedTopic: false,
      );
      expect(api.userActivityRequests, hasLength(1));
      controller.store.put(site, cached);
      await tester.pumpAndSettle();
      expect(find.text('19'), findsOneWidget);
      await export(tester, 'activity-page-cached-metadata');
      controller.store.put(site, cached.copyWith(likeCount: 31));
      await tester.pumpAndSettle();
      expect(find.text('31'), findsOneWidget);
      expect(find.text('19'), findsNothing);
      expect(api.userActivityRequests, hasLength(1));
      expect(api.unexpected, isEmpty);
      await tester.tap(find.text('Title from the activity'));
      await tester.pump();
      expect(controller.currentContent!.topicId, 42);
      expect(controller.currentContent!.postNumber, 7);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cache metadata does not cross sites and disappears when the account cache retires',
    (tester) async {
      final (controller, api) = await host(tester, cachedTopic: false);
      controller.store.put(otherSite, cached);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListMetadata), findsNothing);
      controller.store.put(site, cached);
      await tester.pumpAndSettle();
      expect(find.text('19'), findsOneWidget);
      controller.lifecycle.invalidate(site);
      controller.store.forget(site);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListMetadata), findsNothing);
      expect(find.text('19'), findsNothing);
      expect(find.text('The post that was liked'), findsOneWidget);
      expect(api.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached metadata preserves activity hidden and closed indicators',
    (tester) async {
      const hidden = UserActivityItem(
        actionType: 5,
        topicId: 42,
        postNumber: 2,
        title: 'Hidden reply',
        slug: 'topic',
        username: 'reader',
        excerpt: 'Post words',
        hidden: true,
        closed: true,
      );
      final (controller, api) = await host(tester, row: hidden);
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      controller.store.remove<Topic>(site, 42);
      await tester.pumpAndSettle();
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.text('19'), findsNothing);
      expect(api.unexpected, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('metadata fits large text with its existing tag disclosure', (
    tester,
  ) async {
    final (_, api) = await host(tester, scale: 2);
    expect(find.byType(DAvatarGroup), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('19'), findsOneWidget);
    expect(api.unexpected, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
