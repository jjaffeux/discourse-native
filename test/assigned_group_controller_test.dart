import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_api.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example.com';

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
  final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
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
      ..memberResults.addAll([
        _completed(_members(1, hasMore: true)),
        _completed(_members(2, offset: 50, assignmentCount: 1)),
      ])
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
    await controller.loadMoreMembers(siteUrl: _site, groupName: 'support');
    await controller.loadTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );
    await controller.loadMoreTopics(
      siteUrl: _site,
      groupName: 'support',
      filter: filter,
    );

    final members = controller.membersStateFor(_site, 'support');
    expect(members.members.map((member) => member.id), [1, 2]);
    expect(members.assignmentCount, 10, reason: 'first page owns totals');
    expect(api.memberCalls.map((call) => call.offset), [0, 50]);
    expect(controller.topicsFor(_site, 'support', filter).map((t) => t.id), [
      11,
      12,
    ]);
    expect(controller.topicFeedFor(_site, 'support', filter).hasMore, isFalse);
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
