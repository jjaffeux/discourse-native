import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_api.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example.com';
const _otherSite = 'https://other.example.com';

final class _ControlledAssignedGroupApi implements AssignedGroupApi {
  final List<Completer<AssignedGroupMembersPage>> memberResults = [];
  final List<Completer<TopicList>> topicResults = [];
  final List<Completer<TopicList>> pageResults = [];

  final List<({String groupName, String search, int offset, int limit})>
  memberCalls = [];
  final List<
    ({
      String groupName,
      AssignedGroupFilter filter,
      AssignedGroupTopicQuery query,
    })
  >
  topicCalls = [];
  final List<String> pageCalls = [];

  @override
  Future<AssignedGroupMembersPage> members({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    String search = '',
    int offset = 0,
    int limit = AssignedGroupApiClient.memberPageSize,
    String? clientId,
  }) {
    memberCalls.add((
      groupName: groupName,
      search: search,
      offset: offset,
      limit: limit,
    ));
    return memberResults.removeAt(0).future;
  }

  @override
  Future<TopicList> topicPage({
    required String siteUrl,
    required String apiKey,
    required String path,
    String? clientId,
  }) {
    pageCalls.add(path);
    return pageResults.removeAt(0).future;
  }

  @override
  Future<TopicList> topics({
    required String siteUrl,
    required String apiKey,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
    String? clientId,
  }) {
    topicCalls.add((groupName: groupName, filter: filter, query: query));
    return topicResults.removeAt(0).future;
  }
}

Completer<T> _completed<T>(T value) => Completer<T>()..complete(value);

FakePluginRequestHost _requests(SiteLifecycle lifecycle) {
  final credentials = FakeApiCredentialReader()
    ..keys[_site] = 'key'
    ..keys[_otherSite] = 'other-key';
  return FakePluginRequestHost(credentials: credentials, lifecycle: lifecycle);
}

TopicList _topics(int id, {String? more}) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
  moreTopicsUrl: more,
);

AssignedGroupMembersPage _members(
  int id, {
  int offset = 0,
  bool hasMore = false,
  int assignmentCount = 10,
}) => AssignedGroupMembersPage(
  members: [
    AssignedGroupMember(
      id: id,
      username: 'member-$id',
      usernameLower: 'member-$id',
    ),
  ],
  assignmentCount: assignmentCount,
  groupAssignmentCount: 2,
  offset: offset,
  limit: 50,
  hasMore: hasMore,
);

Future<void> _loadQueries(
  AssignedGroupController controller,
  _ControlledAssignedGroupApi api, {
  String siteUrl = _site,
  String groupName = 'support',
  int start = 0,
  int count = 16,
}) async {
  for (var index = start; index < start + count; index++) {
    api.memberResults.add(_completed(_members(100 + index)));
    await controller.loadMembers(
      siteUrl: siteUrl,
      groupName: groupName,
      search: 'query-$index',
    );
    api.topicResults.add(_completed(_topics(200 + index)));
    await controller.loadTopics(
      siteUrl: siteUrl,
      groupName: groupName,
      filter: const AssignedGroupFilter.everyone(),
      query: AssignedGroupTopicQuery(search: 'query-$index'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'member and topic caches are separated by every query dimension',
    () async {
      final api = _ControlledAssignedGroupApi()
        ..memberResults.addAll([
          _completed(_members(1)),
          _completed(_members(2)),
        ])
        ..topicResults.addAll([
          _completed(_topics(11)),
          _completed(_topics(12)),
          _completed(_topics(13)),
        ]);
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(SiteLifecycle()),
      );
      addTearDown(controller.dispose);

      await controller.loadMembers(siteUrl: _site, groupName: 'support');
      await controller.loadMembers(
        siteUrl: _site,
        groupName: 'support',
        search: 'sam',
      );
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: const AssignedGroupFilter.everyone(),
      );
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: const AssignedGroupFilter.directGroup(),
      );
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: const AssignedGroupFilter.everyone(),
        query: const AssignedGroupTopicQuery(search: 'incident'),
      );

      expect(controller.membersStateFor(_site, 'support').members.single.id, 1);
      expect(
        controller
            .membersStateFor(_site, 'support', search: 'sam')
            .members
            .single
            .id,
        2,
      );
      expect(
        controller
            .topicsFor(_site, 'support', const AssignedGroupFilter.everyone())
            .single
            .id,
        11,
      );
      expect(
        controller
            .topicsFor(
              _site,
              'support',
              const AssignedGroupFilter.directGroup(),
            )
            .single
            .id,
        12,
      );
      expect(
        controller
            .topicsFor(
              _site,
              'support',
              const AssignedGroupFilter.everyone(),
              query: const AssignedGroupTopicQuery(search: 'incident'),
            )
            .single
            .id,
        13,
      );
    },
  );

  test(
    'bounds each query cache per site and retains accessed results',
    () async {
      final api = _ControlledAssignedGroupApi();
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(SiteLifecycle()),
      );
      addTearDown(controller.dispose);
      const filter = AssignedGroupFilter.everyone();

      await _loadQueries(controller, api, siteUrl: _otherSite);
      await _loadQueries(controller, api);

      // Reads keep the visible query recent, independently for each cache.
      expect(
        controller.membersStateFor(_site, 'support', search: 'query-0').loaded,
        isTrue,
      );
      expect(
        controller
            .topicsFor(
              _site,
              'support',
              filter,
              query: const AssignedGroupTopicQuery(search: 'query-1'),
            )
            .single
            .id,
        201,
      );
      final memberCalls = api.memberCalls.length;
      final topicCalls = api.topicCalls.length;
      await controller.loadMembers(
        siteUrl: _site,
        groupName: 'support',
        search: 'query-2',
      );
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: filter,
        query: const AssignedGroupTopicQuery(search: 'query-2'),
      );
      expect(api.memberCalls, hasLength(memberCalls));
      expect(api.topicCalls, hasLength(topicCalls));

      // A different group shares this site's budget, not the other site's.
      await _loadQueries(
        controller,
        api,
        groupName: 'another-group',
        start: 16,
        count: 3,
      );

      for (var index = 0; index < 16; index++) {
        expect(
          controller
              .membersStateFor(_site, 'support', search: 'query-$index')
              .loaded,
          ![1, 3, 4].contains(index),
          reason: 'member query $index',
        );
        expect(
          controller
              .topicFeedFor(
                _site,
                'support',
                filter,
                query: AssignedGroupTopicQuery(search: 'query-$index'),
              )
              .loaded,
          ![0, 3, 4].contains(index),
          reason: 'topic query $index',
        );
        expect(
          controller
              .membersStateFor(_otherSite, 'support', search: 'query-$index')
              .loaded,
          isTrue,
        );
        expect(
          controller
              .topicFeedFor(
                _otherSite,
                'support',
                filter,
                query: AssignedGroupTopicQuery(search: 'query-$index'),
              )
              .loaded,
          isTrue,
        );
      }
      for (var index = 16; index < 19; index++) {
        expect(
          controller
              .membersStateFor(_site, 'another-group', search: 'query-$index')
              .members
              .single
              .id,
          100 + index,
        );
        expect(
          controller
              .topicsFor(
                _site,
                'another-group',
                filter,
                query: AssignedGroupTopicQuery(search: 'query-$index'),
              )
              .single
              .id,
          200 + index,
        );
      }
    },
  );

  for (final more in [false, true]) {
    for (final revisit in [false, true]) {
      for (final fail in [false, true]) {
        test(
          'evicted ${more ? 'pages' : 'loads'} ${fail ? 'fail' : 'complete'} '
          '${revisit ? 'during replacement requests' : 'without a revisit'}',
          () async {
            final api = _ControlledAssignedGroupApi();
            final store = Store();
            final controller = AssignedGroupController(
              api: api,
              requests: _requests(SiteLifecycle()),
              topics: store,
            );
            addTearDown(controller.dispose);
            const filter = AssignedGroupFilter.everyone();

            Future<void> loadMembers() => more
                ? controller.loadMoreMembers(
                    siteUrl: _site,
                    groupName: 'support',
                  )
                : controller.loadMembers(siteUrl: _site, groupName: 'support');
            Future<void> loadTopics() => more
                ? controller.loadMoreTopics(
                    siteUrl: _site,
                    groupName: 'support',
                    filter: filter,
                  )
                : controller.loadTopics(
                    siteUrl: _site,
                    groupName: 'support',
                    filter: filter,
                  );
            Future<void> firstPages() async {
              api.memberResults.add(_completed(_members(1, hasMore: true)));
              api.topicResults.add(
                _completed(
                  _topics(
                    11,
                    more: '/topics/group-topics-assigned/support?page=1',
                  ),
                ),
              );
              await controller.loadMembers(
                siteUrl: _site,
                groupName: 'support',
              );
              await controller.loadTopics(
                siteUrl: _site,
                groupName: 'support',
                filter: filter,
              );
            }

            if (more) await firstPages();
            final oldMembers = Completer<AssignedGroupMembersPage>();
            final oldTopics = Completer<TopicList>();
            api.memberResults.add(oldMembers);
            (more ? api.pageResults : api.topicResults).add(oldTopics);
            final oldMemberLoad = loadMembers();
            final oldTopicLoad = loadTopics();
            await pumpEventQueue();

            await _loadQueries(controller, api);
            expect(
              controller.membersStateFor(_site, 'support').members,
              isEmpty,
            );
            expect(
              controller.membersStateFor(_site, 'support').loading,
              isFalse,
            );
            expect(
              controller.topicFeedFor(_site, 'support', filter).topicIds,
              isEmpty,
            );
            expect(
              controller.topicFeedFor(_site, 'support', filter).loading,
              isFalse,
            );

            final freshMembers = Completer<AssignedGroupMembersPage>();
            final freshTopics = Completer<TopicList>();
            Future<void>? freshMemberLoad;
            Future<void>? freshTopicLoad;
            if (revisit) {
              if (more) await firstPages();
              api.memberResults.add(freshMembers);
              (more ? api.pageResults : api.topicResults).add(freshTopics);
              freshMemberLoad = loadMembers();
              freshTopicLoad = loadTopics();
              await pumpEventQueue();
            }

            var notifications = 0;
            controller.addListener(() => notifications++);
            if (fail) {
              oldMembers.completeError(StateError('old member request failed'));
              oldTopics.completeError(StateError('old topic request failed'));
            } else {
              oldMembers.complete(_members(2, offset: more ? 50 : 0));
              oldTopics.complete(_topics(12));
            }
            await Future.wait([oldMemberLoad, oldTopicLoad]);

            expect(notifications, 0, reason: 'evicted requests cannot notify');
            expect(store.read<Topic>(_site, 12), isNull);
            final members = controller.membersStateFor(_site, 'support');
            final feed = controller.topicFeedFor(_site, 'support', filter);
            expect(
              members.members.map((member) => member.id),
              more && revisit ? [1] : isEmpty,
            );
            expect(feed.topicIds, more && revisit ? [11] : isEmpty);
            expect(members.loaded, more && revisit);
            expect(feed.loaded, more && revisit);
            expect(members.loading, !more && revisit);
            expect(feed.loading, !more && revisit);
            expect(members.loadingMore, more && revisit);
            expect(feed.loadingMore, more && revisit);
            expect(members.error, isNull);
            expect(feed.error, isNull);

            if (revisit) {
              final memberCalls = api.memberCalls.length;
              final topicCalls = api.topicCalls.length;
              final pageCalls = api.pageCalls.length;
              await loadMembers();
              await loadTopics();
              expect(api.memberCalls, hasLength(memberCalls));
              expect(api.topicCalls, hasLength(topicCalls));
              expect(api.pageCalls, hasLength(pageCalls));

              freshMembers.complete(_members(3, offset: more ? 50 : 0));
              freshTopics.complete(_topics(13));
              await freshMemberLoad;
              await freshTopicLoad;
              expect(
                controller
                    .membersStateFor(_site, 'support')
                    .members
                    .map((member) => member.id),
                more ? [1, 3] : [3],
              );
              expect(
                controller
                    .topicsFor(_site, 'support', filter)
                    .map((topic) => topic.id),
                more ? [11, 13] : [13],
              );
              expect(
                controller.membersStateFor(_site, 'support').loadingMore,
                isFalse,
              );
              expect(
                controller.topicFeedFor(_site, 'support', filter).loadingMore,
                isFalse,
              );
            }
          },
        );
      }
    }
  }

  test('a refreshing topic request wins over its older response', () async {
    final old = Completer<TopicList>();
    final fresh = Completer<TopicList>();
    final api = _ControlledAssignedGroupApi()
      ..topicResults.addAll([old, fresh]);
    final controller = AssignedGroupController(
      api: api,
      requests: _requests(SiteLifecycle()),
    );
    addTearDown(controller.dispose);
    const filter = AssignedGroupFilter.everyone();

    final oldLoad = controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await pumpEventQueue();
    final freshLoad = controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
      refresh: true,
    );
    await pumpEventQueue();

    fresh.complete(_topics(2));
    await freshLoad;
    old.complete(_topics(1));
    await oldLoad;

    expect(controller.topicsFor(_site, 'support', filter).single.id, 2);
  });

  test('site replacement and forget reject an old account response', () async {
    final old = Completer<TopicList>();
    final fresh = Completer<TopicList>();
    final api = _ControlledAssignedGroupApi()
      ..topicResults.addAll([old, fresh]);
    final lifecycle = SiteLifecycle();
    final controller = AssignedGroupController(
      api: api,
      requests: _requests(lifecycle),
    );
    addTearDown(controller.dispose);
    const filter = AssignedGroupFilter.everyone();

    final oldLoad = controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await pumpEventQueue();
    lifecycle.invalidate(_site);
    controller.forget(_site);

    final freshLoad = controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await pumpEventQueue();
    fresh.complete(_topics(2));
    await freshLoad;
    old.complete(_topics(1));
    await oldLoad;

    expect(controller.topicsFor(_site, 'support', filter).single.id, 2);
  });

  test('member and topic pagination append once and advance cursors', () async {
    final api = _ControlledAssignedGroupApi()
      ..memberResults.add(_completed(_members(1, hasMore: true)))
      ..topicResults.add(
        _completed(
          _topics(11, more: '/topics/group-topics-assigned/support?page=1'),
        ),
      )
      ..pageResults.add(
        _completed(
          const TopicList(
            topics: [
              Topic(id: 11, title: 'Topic 11', slug: 'topic-11'),
              Topic(id: 12, title: 'Topic 12', slug: 'topic-12'),
            ],
            moreTopicsUrl: '/topics/group-topics-assigned/support?page=1',
          ),
        ),
      );
    final controller = AssignedGroupController(
      api: api,
      requests: _requests(SiteLifecycle()),
    );
    addTearDown(controller.dispose);
    const filter = AssignedGroupFilter.everyone();

    await controller.loadMembers(siteUrl: _site, groupName: 'support');
    await controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    // Paging an older query makes it recent even without reading its state.
    await _loadQueries(controller, api, count: 15);
    api.memberResults.add(
      _completed(_members(2, offset: 50, assignmentCount: 1)),
    );
    await controller.loadMoreMembers(siteUrl: _site, groupName: 'support');
    await controller.loadMoreTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await _loadQueries(controller, api, start: 15, count: 1);

    final members = controller.membersStateFor(_site, 'support');
    expect(members.members.map((member) => member.id), [1, 2]);
    expect(members.assignmentCount, 10, reason: 'first page owns totals');
    expect(
      api.memberCalls
          .where((call) => call.search.isEmpty)
          .map((call) => call.offset),
      [0, 50],
    );
    expect(controller.topicsFor(_site, 'support', filter).map((t) => t.id), [
      11,
      12,
    ]);
    expect(controller.topicFeedFor(_site, 'support', filter).hasMore, isFalse);
    expect(
      controller.membersStateFor(_site, 'support', search: 'query-0').loaded,
      isFalse,
    );
    expect(
      controller
          .topicFeedFor(
            _site,
            'support',
            filter,
            query: const AssignedGroupTopicQuery(search: 'query-0'),
          )
          .loaded,
      isFalse,
    );
  });

  test('dispose drops in-flight responses', () async {
    final result = Completer<TopicList>();
    final api = _ControlledAssignedGroupApi()..topicResults.add(result);
    final controller = AssignedGroupController(
      api: api,
      requests: _requests(SiteLifecycle()),
    );
    const filter = AssignedGroupFilter.everyone();

    final load = controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await pumpEventQueue();
    controller.dispose();
    result.complete(_topics(1));
    await load;

    expect(controller.topicsFor(_site, 'support', filter), isEmpty);
  });
}
