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

  final List<
    ({
      String siteUrl,
      String apiKey,
      String? clientId,
      String groupName,
      String search,
      int offset,
      int limit,
    })
  >
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
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
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

final class _DelayedCredentialReader extends FakeApiCredentialReader {
  final keysRead = <Completer<String?>>[];

  @override
  Future<String?> apiKeyFor(String siteUrl) => keysRead.removeAt(0).future;
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
      assignmentsCount: assignmentCount - 2,
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
  test('complete assignment totals include every loaded member page', () async {
    AssignedGroupMembersPage page(int offset, int count) =>
        AssignedGroupMembersPage.fromJson(
          {
            'members': [
              for (var index = 0; index < count; index++)
                {
                  'id': offset + index + 1,
                  'username': 'member${offset + index + 1}',
                  'assignments_count': 1,
                },
            ],
            'assignment_count': count + 2,
            'group_assignment_count': 2,
          },
          _site,
          offset: offset,
          limit: 50,
        );
    final api = _ControlledAssignedGroupApi()
      ..memberResults.addAll([
        _completed(page(0, 50)),
        _completed(page(50, 1)),
      ]);
    final controller = AssignedGroupController(
      api: api,
      requests: _requests(SiteLifecycle()),
    );
    addTearDown(controller.dispose);

    await controller.loadMembers(siteUrl: _site, groupName: 'support');
    expect(
      controller.membersStateFor(_site, 'support').exactAssignmentCount,
      isNull,
    );
    await controller.loadMoreMembers(siteUrl: _site, groupName: 'support');

    final state = controller.membersStateFor(_site, 'support');
    expect(state.members, hasLength(51));
    expect(state.hasMore, isFalse);
    expect(state.assignmentCount, 53);
    expect(state.exactAssignmentCount, 53);
    expect(api.memberCalls.map((call) => call.offset), [0, 50]);
  });

  test('exhausted member searches do not expose an Everyone count', () async {
    final api = _ControlledAssignedGroupApi()
      ..memberResults.addAll([
        _completed(_members(1)),
        _completed(_members(2)),
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
      search: ' member2 ',
    );

    expect(
      controller.membersStateFor(_site, 'support').exactAssignmentCount,
      10,
    );
    final filtered = controller.membersStateFor(
      _site,
      'support',
      search: 'member2',
    );
    expect(filtered.assignmentCount, 10);
    expect(filtered.hasMore, isFalse);
    expect(filtered.exactAssignmentCount, isNull);
    await controller.loadMoreMembers(
      siteUrl: _site,
      groupName: 'support',
      search: 'member2',
    );
    expect(api.memberCalls, hasLength(2));
  });

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

  for (final fail in [false, true]) {
    for (final refreshing in [false, true]) {
      test(
        'stale pagination ${fail ? 'failure' : 'response'} leaves '
        '${refreshing ? 'refresh' : 'replacement pagination'} pending',
        () async {
          final old = Completer<TopicList>();
          final refresh = Completer<TopicList>();
          final replacement = Completer<TopicList>();
          final api = _ControlledAssignedGroupApi()
            ..topicResults.addAll([
              _completed(_topics(11, more: '/assigned?page=1')),
              refresh,
            ])
            ..pageResults.addAll([old, replacement]);
          final store = Store();
          final controller = AssignedGroupController(
            api: api,
            requests: _requests(SiteLifecycle()),
            topics: store,
          );
          addTearDown(controller.dispose);
          const filter = AssignedGroupFilter.everyone();
          Future<void> load({bool refresh = false}) => controller.loadTopics(
            siteUrl: _site,
            groupName: 'support',
            filter: filter,
            refresh: refresh,
          );
          Future<void> page() => controller.loadMoreTopics(
            siteUrl: _site,
            groupName: 'support',
            filter: filter,
          );

          await load();
          final oldLoad = page();
          await pumpEventQueue();
          final refreshLoad = load(refresh: true);
          await pumpEventQueue();
          Future<void>? replacementLoad;
          if (!refreshing) {
            refresh.complete(_topics(13, more: '/assigned?page=2'));
            await refreshLoad;
            replacementLoad = page();
            await pumpEventQueue();
          }

          var notifications = 0;
          controller.addListener(() => notifications++);
          if (fail) {
            old.completeError(StateError('old topic page failed'));
          } else {
            old.complete(_topics(12));
          }
          await oldLoad;

          expect(notifications, 0);
          expect(store.read<Topic>(_site, 12), isNull);
          final feed = controller.topicFeedFor(_site, 'support', filter);
          expect(feed.topicIds, refreshing ? [11] : [13]);
          expect(feed.loading, refreshing);
          expect(feed.loadingMore, !refreshing);
          expect(feed.error, isNull);
          await load();
          await page();
          expect(api.topicCalls, hasLength(2));
          expect(api.pageCalls, hasLength(refreshing ? 1 : 2));

          if (refreshing) {
            refresh.complete(_topics(13));
            await refreshLoad;
          } else {
            replacement.complete(_topics(14));
            await replacementLoad;
          }
          expect(
            controller
                .topicsFor(_site, 'support', filter)
                .map((topic) => topic.id),
            refreshing ? [13] : [13, 14],
          );
        },
      );
    }
  }

  test('completing a topic request does not promote its query', () async {
    final topics = Completer<TopicList>();
    final api = _ControlledAssignedGroupApi()..topicResults.add(topics);
    final controller = AssignedGroupController(
      api: api,
      requests: _requests(SiteLifecycle()),
    );
    addTearDown(controller.dispose);
    const filter = AssignedGroupFilter.everyone();
    final load = controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await pumpEventQueue();
    for (var index = 0; index < 16; index++) {
      if (index == 15) {
        topics.complete(_topics(11));
        await load;
      }
      api.topicResults.add(_completed(_topics(200 + index)));
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: filter,
        query: AssignedGroupTopicQuery(search: 'query-$index'),
      );
    }

    expect(controller.topicFeedFor(_site, 'support', filter).loaded, isFalse);
    expect(
      controller
          .topicFeedFor(
            _site,
            'support',
            filter,
            query: const AssignedGroupTopicQuery(search: 'query-0'),
          )
          .loaded,
      isTrue,
    );
  });

  test(
    'duplicate-only topic pages retain a changed continuation cursor',
    () async {
      final api = _ControlledAssignedGroupApi()
        ..topicResults.add(_completed(_topics(11, more: '/assigned?page=1')))
        ..pageResults.addAll([
          _completed(_topics(11, more: '/assigned?page=2')),
          _completed(_topics(12)),
        ]);
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(SiteLifecycle()),
      );
      addTearDown(controller.dispose);
      const filter = AssignedGroupFilter.everyone();
      Future<void> page() => controller.loadMoreTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: filter,
      );

      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: filter,
      );
      await page();
      expect(controller.topicFeedFor(_site, 'support', filter).topicIds, [11]);
      expect(controller.topicFeedFor(_site, 'support', filter).hasMore, isTrue);
      await page();
      expect(api.pageCalls, ['/assigned.json?page=1', '/assigned.json?page=2']);
      expect(controller.topicFeedFor(_site, 'support', filter).topicIds, [
        11,
        12,
      ]);
      expect(
        controller.topicFeedFor(_site, 'support', filter).hasMore,
        isFalse,
      );
    },
  );

  for (final borrowed in [false, true]) {
    test(
      'forget clears feeds with ${borrowed ? 'a borrowed' : 'an owned'} Store',
      () async {
        final api = _ControlledAssignedGroupApi()
          ..topicResults.addAll([
            _completed(_topics(11)),
            _completed(_topics(12)),
          ]);
        final store = borrowed ? Store() : null;
        final controller = AssignedGroupController(
          api: api,
          requests: _requests(SiteLifecycle()),
          topics: store,
        );
        addTearDown(controller.dispose);
        const filter = AssignedGroupFilter.everyone();

        for (final site in [_site, _otherSite]) {
          await controller.loadTopics(
            siteUrl: site,
            groupName: 'support',
            filter: filter,
          );
        }
        controller.forget(_site);

        expect(controller.topicsFor(_site, 'support', filter), isEmpty);
        expect(
          controller.topicFeedFor(_site, 'support', filter).loaded,
          isFalse,
        );
        expect(
          controller.topicsFor(_otherSite, 'support', filter).single.id,
          12,
        );
        if (borrowed) expect(store!.read<Topic>(_site, 11)?.id, 11);
      },
    );
  }

  test(
    'normalized topic queries share loads and retain sort identity',
    () async {
      final first = Completer<TopicList>();
      final api = _ControlledAssignedGroupApi()
        ..topicResults.addAll([
          first,
          _completed(_topics(12)),
          _completed(_topics(13)),
        ]);
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(SiteLifecycle()),
      );
      addTearDown(controller.dispose);
      final filter = AssignedGroupFilter.member(' SAM ');
      const query = AssignedGroupTopicQuery(
        order: AssignedGroupOrder.views,
        ascending: true,
        search: 'incident',
      );

      final load = controller.loadTopics(
        siteUrl: _site,
        groupName: ' support ',
        filter: filter,
        query: const AssignedGroupTopicQuery(
          order: AssignedGroupOrder.views,
          ascending: true,
          search: ' incident ',
        ),
      );
      await pumpEventQueue();
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: AssignedGroupFilter.member('sam'),
        query: query,
      );
      expect(api.topicCalls, hasLength(1));
      expect(api.topicCalls.single.groupName, 'support');
      expect(api.topicCalls.single.query, query);

      first.complete(_topics(11));
      await load;
      await controller.loadTopics(
        siteUrl: _site,
        groupName: 'support',
        filter: filter,
        query: query,
      );
      expect(api.topicCalls, hasLength(1));

      for (final differentSort in [
        const AssignedGroupTopicQuery(
          order: AssignedGroupOrder.posts,
          ascending: true,
          search: 'incident',
        ),
        const AssignedGroupTopicQuery(
          order: AssignedGroupOrder.views,
          search: 'incident',
        ),
      ]) {
        await controller.loadTopics(
          siteUrl: _site,
          groupName: 'support',
          filter: filter,
          query: differentSort,
        );
      }
      expect(api.topicCalls, hasLength(3));
      expect(
        controller.topicsFor(_site, 'support', filter, query: query).single.id,
        11,
      );
    },
  );

  for (final retire in [false, true]) {
    test(
      'Store listener ${retire ? 'retirement' : 'refresh'} revokes page publication',
      () async {
        final old = Completer<TopicList>();
        final fresh = Completer<TopicList>();
        final api = _ControlledAssignedGroupApi()
          ..topicResults.addAll([
            _completed(_topics(10, more: '/assigned?page=1')),
            fresh,
          ])
          ..pageResults.add(old);
        final store = Store();
        final controller = AssignedGroupController(
          api: api,
          requests: _requests(SiteLifecycle()),
          topics: store,
        );
        addTearDown(controller.dispose);
        const filter = AssignedGroupFilter.everyone();
        Future<void> load({bool refresh = false}) => controller.loadTopics(
          siteUrl: _site,
          groupName: 'support',
          filter: filter,
          refresh: refresh,
        );
        await load();
        final cell = store.ref<Topic>(_site, 11);
        Future<void>? replacement;
        void interrupt() {
          cell.removeListener(interrupt);
          if (retire) {
            controller.forget(_site);
          } else {
            replacement = load(refresh: true);
          }
        }

        cell.addListener(interrupt);
        final page = controller.loadMoreTopics(
          siteUrl: _site,
          groupName: 'support',
          filter: filter,
        );
        await pumpEventQueue();
        var notifications = 0;
        controller.addListener(() => notifications++);
        old.complete(
          const TopicList(
            topics: [
              Topic(id: 11, title: 'First', slug: 'first'),
              Topic(id: 12, title: 'Revoked', slug: 'revoked'),
            ],
          ),
        );
        await page;
        expect(store.read<Topic>(_site, 12), isNull);
        final feed = controller.topicFeedFor(_site, 'support', filter);
        expect(feed.topicIds, retire ? isEmpty : [10]);
        expect(feed.loading, !retire);
        expect(notifications, 1);
        if (!retire) {
          fresh.complete(_topics(13));
          await replacement;
          expect(controller.topicFeedFor(_site, 'support', filter).topicIds, [
            13,
          ]);
        }
      },
    );
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
      _completed(_members(2, offset: 50, assignmentCount: 3)),
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
    expect(members.assignmentCount, 11);
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

  for (final fail in [false, true]) {
    for (final refreshing in [false, true]) {
      test('stale member page ${fail ? 'failure' : 'response'} leaves '
          '${refreshing ? 'refresh' : 'replacement page'} pending', () async {
        final old = Completer<AssignedGroupMembersPage>();
        final fresh = Completer<AssignedGroupMembersPage>();
        final replacement = Completer<AssignedGroupMembersPage>();
        final api = _ControlledAssignedGroupApi()
          ..memberResults.addAll([
            _completed(_members(1, hasMore: true)),
            old,
            fresh,
            replacement,
          ]);
        final controller = AssignedGroupController(
          api: api,
          requests: _requests(SiteLifecycle()),
        );
        addTearDown(controller.dispose);
        Future<void> load({bool refresh = false}) => controller.loadMembers(
          siteUrl: _site,
          groupName: ' support ',
          search: ' sam ',
          refresh: refresh,
        );
        Future<void> page() => controller.loadMoreMembers(
          siteUrl: _site,
          groupName: 'support',
          search: 'sam',
        );
        AssignedGroupMembersState state() =>
            controller.membersStateFor(_site, 'support', search: 'sam');

        await load();
        final oldLoad = page();
        await pumpEventQueue();
        final refreshLoad = load(refresh: true);
        await pumpEventQueue();
        expect(state().members.single.id, 1);
        Future<void>? replacementLoad;
        if (!refreshing) {
          fresh.complete(_members(3, hasMore: true, assignmentCount: 20));
          await refreshLoad;
          replacementLoad = page();
          await pumpEventQueue();
        }
        var notifications = 0;
        controller.addListener(() => notifications++);
        if (fail) {
          old.completeError(StateError('old member page failed'));
        } else {
          old.complete(_members(2, offset: 50));
        }
        await oldLoad;
        expect(notifications, 0);
        expect(state().members.single.id, refreshing ? 1 : 3);
        expect(state().loading, refreshing);
        expect(state().loadingMore, !refreshing);
        expect(state().error, isNull);
        await load();
        await page();
        expect(api.memberCalls, hasLength(refreshing ? 3 : 4));
        expect(
          api.memberCalls.every(
            (call) => call.groupName == 'support' && call.search == 'sam',
          ),
          isTrue,
        );
        if (refreshing) {
          fresh.complete(_members(3, assignmentCount: 20));
          await refreshLoad;
        } else {
          replacement.complete(_members(4, offset: 50));
          await replacementLoad;
        }
        expect(
          state().members.map((member) => member.id),
          refreshing ? [3] : [3, 4],
        );
        expect(state().assignmentCount, refreshing ? 20 : 28);
        expect(state().loading, isFalse);
        expect(state().loadingMore, isFalse);
      });
    }
  }

  for (final page in [false, true]) {
    for (final missingCredentials in [false, true]) {
      test(
        'member ${page ? 'page' : 'refresh'} retains results after '
        '${missingCredentials ? 'missing credentials' : 'failure'}',
        () async {
          final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
          final failure = Completer<AssignedGroupMembersPage>();
          final api = _ControlledAssignedGroupApi()
            ..memberResults.addAll([
              _completed(_members(1, hasMore: true)),
              if (!missingCredentials) failure,
            ]);
          final controller = AssignedGroupController(
            api: api,
            requests: FakePluginRequestHost(credentials: credentials),
          );
          addTearDown(controller.dispose);
          Future<void> load() => page
              ? controller.loadMoreMembers(siteUrl: _site, groupName: 'support')
              : controller.loadMembers(
                  siteUrl: _site,
                  groupName: 'support',
                  refresh: true,
                );
          await controller.loadMembers(siteUrl: _site, groupName: 'support');
          if (missingCredentials) credentials.keys.clear();
          final failedLoad = load();
          await pumpEventQueue();
          if (!missingCredentials) failure.completeError(StateError('offline'));
          await failedLoad;
          final state = controller.membersStateFor(_site, 'support');
          expect(state.members.single.id, 1);
          expect(state.assignmentCount, 10);
          expect(state.nextOffset, 50);
          expect(state.hasMore, isTrue);
          expect(state.error, isNotNull);
          expect(state.pageError, page);
          expect(state.loading, isFalse);
          expect(state.loadingMore, isFalse);
          final calls = api.memberCalls.length;
          if (!page) {
            await controller.loadMoreMembers(
              siteUrl: _site,
              groupName: 'support',
            );
            expect(api.memberCalls, hasLength(calls));
          }
          credentials.keys[_site] = 'restored';
          api.memberResults.add(_completed(_members(2, offset: page ? 50 : 0)));
          await load();
          expect(api.memberCalls.last.offset, page ? 50 : 0);
          expect(controller.membersStateFor(_site, 'support').error, isNull);
          expect(
            controller
                .membersStateFor(_site, 'support')
                .members
                .map((member) => member.id),
            page ? [1, 2] : [2],
          );
        },
      );
    }
  }

  for (final dispose in [false, true]) {
    test('member loading listener ${dispose ? 'disposes' : 'forgets'} '
        'before credentials or API dispatch', () async {
      final api = _ControlledAssignedGroupApi();
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(SiteLifecycle()),
      );
      if (!dispose) addTearDown(controller.dispose);
      var retired = false;
      controller.addListener(() {
        if (retired) return;
        retired = true;
        if (dispose) {
          controller.dispose();
        } else {
          controller.forget(_site);
        }
      });
      await controller.loadMembers(siteUrl: _site, groupName: 'support');
      expect(api.memberCalls, isEmpty);
      expect(controller.membersStateFor(_site, 'support').loaded, isFalse);
      expect(controller.membersStateFor(_site, 'support').loading, isFalse);
    });
  }

  for (final fail in [false, true]) {
    test('member account replacement rejects late ${fail ? 'error' : 'page'} '
        'and finally notifications', () async {
      final old = Completer<AssignedGroupMembersPage>();
      final fresh = Completer<AssignedGroupMembersPage>();
      final api = _ControlledAssignedGroupApi()
        ..memberResults.addAll([old, fresh]);
      final lifecycle = SiteLifecycle();
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(lifecycle),
      );
      addTearDown(controller.dispose);
      final oldLoad = controller.loadMembers(
        siteUrl: _site,
        groupName: 'support',
      );
      await pumpEventQueue();
      lifecycle.invalidate(_site);
      controller.forget(_site);
      final freshLoad = controller.loadMembers(
        siteUrl: _site,
        groupName: 'support',
      );
      await pumpEventQueue();
      var notifications = 0;
      controller.addListener(() => notifications++);
      if (fail) {
        old.completeError(StateError('old account failed'));
      } else {
        old.complete(_members(1));
      }
      await oldLoad;
      expect(notifications, 0);
      expect(controller.membersStateFor(_site, 'support').loading, isTrue);
      await controller.loadMembers(siteUrl: _site, groupName: 'support');
      expect(api.memberCalls, hasLength(2));
      fresh.complete(_members(2));
      await freshLoad;
      expect(controller.membersStateFor(_site, 'support').members.single.id, 2);
    });
  }

  test(
    'member retirement during credentials does not dispatch old API work',
    () async {
      final oldKey = Completer<String?>();
      final credentials = _DelayedCredentialReader()
        ..keysRead.addAll([oldKey, _completed('new-key')]);
      final fresh = Completer<AssignedGroupMembersPage>();
      final api = _ControlledAssignedGroupApi()..memberResults.add(fresh);
      final lifecycle = SiteLifecycle();
      final controller = AssignedGroupController(
        api: api,
        requests: FakePluginRequestHost(
          credentials: credentials,
          lifecycle: lifecycle,
        ),
      );
      addTearDown(controller.dispose);
      final oldLoad = controller.loadMembers(
        siteUrl: _site,
        groupName: 'support',
      );
      await pumpEventQueue();
      lifecycle.invalidate(_site);
      controller.forget(_site);
      final freshLoad = controller.loadMembers(
        siteUrl: _site,
        groupName: 'support',
      );
      await pumpEventQueue();
      var notifications = 0;
      controller.addListener(() => notifications++);
      oldKey.complete('old-key');
      await oldLoad;
      expect(api.memberCalls, hasLength(1));
      expect(api.memberCalls.single.apiKey, 'new-key');
      expect(api.memberCalls.single.clientId, 'test-client');
      expect(api.memberCalls.single.siteUrl, _site);
      expect(notifications, 0);
      expect(controller.membersStateFor(_site, 'support').loading, isTrue);
      fresh.complete(_members(2));
      await freshLoad;
      expect(controller.membersStateFor(_site, 'support').members.single.id, 2);
    },
  );

  test(
    'member success listener refresh keeps the replacement request active',
    () async {
      final fresh = Completer<AssignedGroupMembersPage>();
      final api = _ControlledAssignedGroupApi()
        ..memberResults.addAll([_completed(_members(1)), fresh]);
      final controller = AssignedGroupController(
        api: api,
        requests: _requests(SiteLifecycle()),
      );
      addTearDown(controller.dispose);
      Future<void>? refresh;
      void onResult() {
        final state = controller.membersStateFor(_site, 'support');
        if (!state.loaded || state.loading) return;
        controller.removeListener(onResult);
        refresh = controller.loadMembers(
          siteUrl: _site,
          groupName: 'support',
          refresh: true,
        );
      }

      controller.addListener(onResult);
      await controller.loadMembers(siteUrl: _site, groupName: 'support');
      await pumpEventQueue();
      expect(controller.membersStateFor(_site, 'support').loading, isTrue);
      await controller.loadMembers(siteUrl: _site, groupName: 'support');
      expect(api.memberCalls, hasLength(2));
      fresh.complete(_members(2));
      await refresh;
      expect(controller.membersStateFor(_site, 'support').members.single.id, 2);
    },
  );
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
