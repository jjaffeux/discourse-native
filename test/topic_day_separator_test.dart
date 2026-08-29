import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('only the rendered date is clickable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StreamDaySeparator(
            day: DateTime(2020, 1, 2),
            onTap: () => taps++,
          ),
        ),
      ),
    );

    final separator = find.byType(StreamDaySeparator);
    final button = find.descendant(
      of: separator,
      matching: find.byType(InkWell),
    );
    final date = find.descendant(
      of: separator,
      matching: find.text('2 January 2020'),
    );
    final separatorRect = tester.getRect(separator);
    final buttonRect = tester.getRect(button);

    expect(buttonRect.height, lessThan(separatorRect.height));

    await tester.tapAt(Offset(separatorRect.center.dx, separatorRect.top + 1));
    await tester.pump();
    expect(taps, 0);

    await tester.tap(date);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('calls out a gap strictly longer than the site threshold', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = [
      _post(1, day: DateTime(2020, 1, 1)),
      _post(2, day: DateTime(2020, 1, 8)),
      _post(3, day: DateTime(2020, 1, 16)),
    ];
    final controller = _controller(site);
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (final post in posts) post.id],
          postsCount: posts.length,
        ),
      )
      ..putAll(site.url, posts);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey(('topic-time-gap', 2))),
      findsNothing,
      reason: 'the web rule is strictly greater than the seven-day default',
    );

    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.listController!.jumpToItem(
      index: 2 * 2,
      scrollController: list.controller!,
      alignment: 1,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(('topic-time-gap', 3))), findsOneWidget);
    expect(find.text('8 days later'), findsOneWidget);
  });

  testWidgets('the last passed day floats and returns to its first post', (
    tester,
  ) async {
    final site = instance('meta.example');
    final firstDay = DateTime(2020, 1, 2);
    final secondDay = DateTime(2020, 1, 3);
    final posts = [
      for (var id = 1; id <= 12; id++)
        _post(id, day: id <= 6 ? firstDay : secondDay),
    ];
    final controller = _controller(site);
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (final post in posts) post.id],
          postsCount: posts.length,
        ),
      )
      ..putAll(site.url, posts);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    final theme = AppTheme.dark;
    await tester.pumpWidget(_topicView(controller, theme: theme));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey(('topic-day', firstDay))), findsOneWidget);
    expect(
      find.byKey(ValueKey(('topic-floating-day', firstDay))),
      findsNothing,
    );

    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.listController!.jumpToItem(
      index: 3 * 2,
      scrollController: list.controller!,
      alignment: 0,
    );
    await tester.pumpAndSettle();

    final floatingFirst = find.byKey(
      ValueKey(('topic-floating-day', firstDay)),
    );
    expect(floatingFirst, findsOneWidget);
    expect(tester.getSize(floatingFirst).height, 44);
    final floatingDecoration = tester
        .widgetList<Container>(
          find.descendant(of: floatingFirst, matching: find.byType(Container)),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .where(
          (decoration) =>
              decoration.border ==
              Border.all(color: theme.colorScheme.surfaceContainerHigh),
        )
        .single;
    expect(floatingDecoration.color, theme.colorScheme.surfaceContainerLow);
    expect(
      floatingDecoration.border,
      Border.all(color: theme.colorScheme.surfaceContainerHigh),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(floatingFirst));
    await tester.pump();

    final hoveredDecoration = tester
        .widgetList<Container>(
          find.descendant(of: floatingFirst, matching: find.byType(Container)),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .where(
          (decoration) =>
              decoration.border ==
              Border.all(color: theme.colorScheme.surfaceContainerHigh),
        )
        .single;
    expect(hoveredDecoration.color, theme.shell.hover);

    await mouse.moveTo(Offset.zero);
    await tester.pump();

    final floatingFirstSemantics = find.bySemanticsLabel(
      'Go to start of 2 January 2020',
    );
    expect(floatingFirstSemantics, findsOneWidget);
    expect(
      tester.getSemantics(floatingFirstSemantics),
      matchesSemantics(
        label: 'Go to start of 2 January 2020',
        isButton: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(floatingFirst);
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(SuperListView));
    expect(tester.getTopLeft(find.byKey(const ValueKey(1))).dy, viewport.top);
    expect(floatingFirst, findsNothing);

    list.listController!.jumpToItem(
      index: 8 * 2,
      scrollController: list.controller!,
      alignment: 0,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey(('topic-floating-day', firstDay))),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey(('topic-floating-day', secondDay))),
      findsOneWidget,
    );
  });

  testWidgets('a date click pages back to the real start of that day', (
    tester,
  ) async {
    final site = instance('meta.example');
    final previousDay = DateTime(2020, 1, 1);
    final targetDay = DateTime(2020, 1, 2);
    final posts = {
      for (var id = 1; id <= 60; id++)
        id: _post(id, day: id <= 20 ? previousDay : targetDay, long: true),
    };
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: posts,
    );
    final controller = _controller(site, api: api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (var id = 1; id <= 60; id++) id],
          postsCount: 60,
        ),
      )
      ..putAll(site.url, [for (var id = 41; id <= 60; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 59),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();

    final floating = find.byKey(ValueKey(('topic-floating-day', targetDay)));
    expect(floating, findsOneWidget);
    expect(api.postFetches, isEmpty);

    await tester.tap(floating);
    await tester.pumpAndSettle();

    expect(api.postFetches, [
      [for (var id = 21; id <= 40; id++) id],
      [for (var id = 1; id <= 20; id++) id],
    ]);
    final viewport = tester.getRect(find.byType(SuperListView));
    expect(tester.getTopLeft(find.byKey(const ValueKey(21))).dy, viewport.top);
    expect(find.byKey(ValueKey(('topic-day', targetDay))), findsOneWidget);
  });
}

Post _post(int id, {required DateTime day, bool long = false}) => Post(
  id: id,
  postNumber: id,
  username: 'sam',
  cooked: List.filled(long ? 8 : 4, '<p>Post $id</p>').join(),
  createdAt: day.add(Duration(minutes: id)),
);

ShellController _controller(DiscourseInstance site, {FakeDiscourseApi? api}) {
  final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
  return ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
}

Widget _topicView(ShellController controller, {ThemeData? theme}) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: theme ?? AppTheme.light,
    home: const Scaffold(body: TopicView()),
  ),
);
