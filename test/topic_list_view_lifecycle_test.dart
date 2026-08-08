import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

void main() {
  final sites = [instance('one.example'), instance('two.example')];

  testWidgets('the same destination has an independent position per site', (
    tester,
  ) async {
    final topics = _topics(1, 40);
    final controller = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..putAll(sites[0].url, topics)
      ..putAll(sites[1].url, topics);
    final feed = TopicFeed(
      topicIds: [for (final topic in topics) topic.id],
      loaded: true,
    );

    await tester.pumpWidget(_TestList(controller: controller, feed: feed));
    await tester.pumpAndSettle();

    final first = tester.widget<SuperListView>(find.byType(SuperListView));
    await tester.drag(find.byType(SuperListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(first.controller!.offset, greaterThan(0));

    controller.selectInstance(1);
    await tester.pump();

    final second = tester.widget<SuperListView>(find.byType(SuperListView));
    expect(second.controller, isNot(same(first.controller)));
    expect(second.controller!.offset, 0);
  });

  testWidgets('a queued page request cannot cross a site switch', (
    tester,
  ) async {
    final api = _PagingApi();
    final controller = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pump();
    controller.selectInstance(1);
    await tester.pump();
    controller.selectInstance(0);
    await tester.pump();
    expect(controller.currentFeed?.hasMore, isTrue);
    expect(api.pageSites, isEmpty);

    var showList = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return showList
                    ? TopicListView(feed: controller.currentFeed!)
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.selectInstance(1);
      rebuild(() => showList = false);
    });
    rebuild(() => showList = true);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.pageSites, isNot(contains(sites[1].url)));
  });
}

final class _TestList extends StatelessWidget {
  const _TestList({required this.controller, required this.feed});

  final ShellController controller;
  final TopicFeed feed;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: TopicListView(feed: feed)),
    ),
  );
}

final class _PagingApi extends FakeDiscourseApi {
  final List<String> pageSites = [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (path.contains('page=')) {
      pageSites.add(siteUrl);
      return TopicList(topics: _topics(10, 2));
    }
    return TopicList(topics: _topics(1, 3), moreTopicsUrl: '/latest?page=1');
  }
}

List<Topic> _topics(int first, int count) => [
  for (var id = first; id < first + count; id++)
    Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
];
