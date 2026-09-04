import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/shell/aggregate_view.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TopicListView aligns its 825px child lane and keeps its offset',
    (tester) async {
      await _withDesktop(tester, const Size(1200, 800), () async {
        final site = instance('one.example');
        final topics = [
          for (var id = 1; id <= 40; id++)
            Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
        ];
        final controller = await _shell(
          site,
          FakeDiscourseApi(feeds: const {'/latest.json': []}),
        );
        addTearDown(controller.dispose);
        controller.store.putAll(site.url, topics);
        final feed = TopicFeed(
          topicIds: [for (final topic in topics) topic.id],
          loaded: true,
        );

        await tester.pumpWidget(
          _shellSurface(controller, TopicListView(feed: feed)),
        );
        await tester.pumpAndSettle();

        final viewport = find.byType(SuperListView);
        final scroll = tester.widget<SuperListView>(viewport).controller!;
        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          final row = find.byKey(const ValueKey(1));
          expect(tester.getSize(viewport).width, 1200);
          expect(tester.getSize(row).width, closeTo(825, 0.001));
          expect(
            tester.getTopLeft(row).dx,
            closeTo(_laneLeft(1200, alignment), 0.001),
          );
          expect(
            tester.widget<SuperListView>(viewport).controller,
            same(scroll),
          );
        }

        scroll.jumpTo(200);
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        expect(offset, greaterThan(0));
        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(
            tester.widget<SuperListView>(viewport).controller,
            same(scroll),
          );
          expect(scroll.offset, closeTo(offset, 0.001));
        }
      });
    },
  );

  testWidgets(
    'TopicView gives its pinned sidebar a structural column beside the lane',
    (tester) async {
      await _withDesktop(tester, const Size(1400, 800), () async {
        final site = instance('one.example');
        final controller = await _shell(
          site,
          FakeDiscourseApi(feeds: const {'/latest.json': []}),
        );
        addTearDown(controller.dispose);
        final posts = [
          for (var id = 1; id <= 40; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'sam',
              cooked: '<p>Post $id</p>',
            ),
        ];
        controller.store
          ..put(
            site.url,
            TopicDetail(
              id: 7,
              title: 'Reading lane topic',
              stream: [for (final post in posts) post.id],
              postsCount: posts.length,
            ),
          )
          ..putAll(site.url, posts);
        controller.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'reading-lane-topic',
            title: 'Topic',
          ),
        );

        await tester.pumpWidget(
          _shellSurface(controller, const TopicView(showSidebar: true)),
        );
        await tester.pumpAndSettle();

        final header = find.byKey(const ValueKey('topic-content-header'));
        final sidebar = find.byKey(const ValueKey('topic-sidebar-panel'));
        final list = find.byType(SuperListView);
        final post = find.byKey(const ValueKey(1));
        expect(tester.getSize(header).width, 1056);
        expect(tester.getSize(sidebar).width, 344);
        expect(tester.getTopLeft(sidebar).dx, closeTo(1056, 0.001));
        expect(tester.getSize(list).width, 1056);
        expect(tester.getSize(post).width, closeTo(825, 0.001));

        final scroll = tester.widget<SuperListView>(list).controller!;
        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(
            tester.getTopLeft(post).dx,
            closeTo(_laneLeft(1056, alignment), 0.001),
          );
          expect(tester.getSize(post).width, closeTo(825, 0.001));
          expect(tester.widget<SuperListView>(list).controller, same(scroll));
        }

        scroll.jumpTo(200);
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        expect(offset, greaterThan(0));
        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(tester.widget<SuperListView>(list).controller, same(scroll));
          expect(scroll.offset, closeTo(offset, 0.001));
        }

        // The sidebar breakpoint is deliberately independent from lane alignment.
        await tester.binding.setSurfaceSize(const Size(983, 800));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
        expect(tester.getSize(header).width, 983);
        await tester.binding.setSurfaceSize(const Size(984, 800));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-sidebar-panel')),
          findsOneWidget,
        );
        expect(tester.getSize(sidebar).width, 344);
        expect(tester.getSize(header).width, 640);
      });
    },
  );

  testWidgets(
    'AggregateView aligns cards while hero and toolbar stay full width',
    (tester) async {
      await _withDesktop(tester, const Size(1400, 800), () async {
        const user = DiscourseUser(username: 'sam');
        final one = instance('one.example', title: 'One').copyWith(user: user);
        final two = instance('two.example', title: 'Two').copyWith(user: user);
        const topic = Topic(
          id: 42,
          title: 'Aggregate topic',
          slug: 'aggregate',
        );
        final controller = await _shell(
          one,
          FakeDiscourseApi(
            feeds: {
              '/latest.json': const [],
              '/filter.json?per_page=15': [topic],
            },
          ),
          extraSites: [two],
        );
        addTearDown(controller.dispose);
        await controller.refreshAggregate();

        await tester.pumpWidget(
          _shellSurface(controller, const AggregateView()),
        );
        await tester.pumpAndSettle();
        final viewport = find.byType(ListView);
        final card = find.byKey(ValueKey('aggregate-topic-card-${one.url}-42'));
        final hero = find.byKey(const ValueKey('aggregate-hero'));
        final toolbar = find.byKey(const ValueKey('aggregate-tab-toolbar'));
        expect(tester.getSize(viewport).width, 1400);
        expect(tester.getSize(card).width, closeTo(825, 0.001));
        expect(tester.getTopLeft(card).dx, closeTo(287.5, 0.001));
        expect(tester.getSize(hero).width, 1400);
        expect(tester.getSize(toolbar).width, 1400);

        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(tester.getSize(card).width, closeTo(825, 0.001));
          expect(
            tester.getTopLeft(card).dx,
            closeTo(_aggregateCardLeft(1400, alignment), 0.001),
          );
          expect(tester.getSize(hero).width, 1400);
          expect(tester.getSize(toolbar).width, 1400);
        }

        final scroll = tester.widget<ListView>(viewport).controller!;
        await tester.drag(viewport, const Offset(0, -300));
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(tester.getSize(toolbar).width, 1400);
          expect(tester.widget<ListView>(viewport).controller, same(scroll));
          expect(scroll.offset, closeTo(offset, 0.001));
        }
      });
    },
  );

  testWidgets(
    'ChatMessageStream uses the lane inside a split-pane-sized viewport',
    (tester) async {
      await _withDesktop(tester, const Size(2000, 800), () async {
        final site = instance('one.example');
        final controller = await _shell(
          site,
          FakeDiscourseApi(feeds: const {'/latest.json': []}),
          plugins: installedPlugins,
        );
        addTearDown(controller.dispose);
        final messages = [for (var id = 1; id <= 40; id++) _chatMessage(id)];
        controller.chatRecords.putAll(site.url, messages);
        final stream = ChatStreamState(
          messageIds: [for (final message in messages) message.id],
          fetchedOnce: true,
          fetches: 1,
        );
        final items = buildChatStream(messages);

        await tester.pumpWidget(
          _shellSurface(
            controller,
            Row(
              children: [
                SizedBox(
                  width: 1000,
                  child: PluginUiScope.own(
                    chatPluginId,
                    ChatMessageStream(
                      siteUrl: site.url,
                      target: const ChatChannelTarget(9),
                      items: items,
                      stream: stream,
                    ),
                  ),
                ),
                const Expanded(child: ColoredBox(color: Colors.black12)),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final viewport = find.byType(SuperListView);
        final tile = find.byKey(const ValueKey('chat-message-40'));
        final scroll = tester.widget<SuperListView>(viewport).controller!;
        expect(tester.getSize(viewport).width, 1000);
        expect(tester.getSize(tile).width, closeTo(825, 0.001));

        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(tester.getSize(tile).width, closeTo(825, 0.001));
          expect(
            tester.getTopLeft(tile).dx,
            closeTo(_laneLeft(1000, alignment), 0.001),
          );
        }

        scroll.jumpTo(200);
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        expect(offset, greaterThan(0));

        for (final alignment in ContentAlignment.values) {
          await controller.appSettings.setContentAlignment(alignment);
          await tester.pump();
          expect(
            tester.widget<SuperListView>(viewport).controller,
            same(scroll),
          );
          expect(scroll.offset, closeTo(offset, 0.001));
        }
      });
    },
  );
}

Future<ShellController> _shell(
  DiscourseInstance primary,
  FakeDiscourseApi api, {
  List<DiscourseInstance> extraSites = const [],
  InstalledPlugins? plugins,
}) async {
  final sites = [primary, ...extraSites];
  final authenticator = FakeAuthenticator();
  for (final site in sites) {
    authenticator.keys[site.url] = 'key';
  }
  final controller = ShellController(
    instanceStore: FakeInstanceStore(sites),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins,
  );
  await controller.load();
  return controller;
}

Widget _shellSurface(ShellController controller, Widget child) =>
    ContentAlignmentScope(
      controller: controller.appSettings,
      child: ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      ),
    );

Future<void> _withDesktop(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  await tester.binding.setSurfaceSize(size);
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
    await tester.binding.setSurfaceSize(null);
  }
}

double _laneLeft(double availableWidth, ContentAlignment alignment) {
  final extra = availableWidth - ContentReadingLane.maxWidth;
  return switch (alignment) {
    ContentAlignment.left => 0,
    ContentAlignment.center => extra / 2,
    ContentAlignment.right => extra,
  };
}

double _aggregateCardLeft(double availableWidth, ContentAlignment alignment) =>
    switch (alignment) {
      ContentAlignment.left => 16,
      ContentAlignment.center => 16 + (availableWidth - 32 - 825) / 2,
      ContentAlignment.right => availableWidth - 16 - 825,
    };

ChatMessage _chatMessage(int id) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>Message $id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: id)),
);
