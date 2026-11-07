// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'assigned_group.dart';
import 'assigned_group_api.dart';

typedef _MemberKey = ({String siteUrl, String groupName, String search});
typedef _TopicKey = ({
  String siteUrl,
  String groupName,
  AssignedGroupFilter filter,
  AssignedGroupTopicQuery query,
});

const _assignedTopicStorePolicy = StorePolicy(
  maxEntries: 1024,
  maxEntriesPerSite: 512,
  maxEntriesPerSiteAndType: 512,
);

/// Pairs every response with its site lease and request token so superseded
/// account or query requests cannot publish.
final class AssignedGroupController extends FrameSafeNotifier {
  AssignedGroupController({
    required this.api,
    required PluginRequestHost requests,
    Store? topics,
  }) : _requests = requests,
       _topics = topics ?? Store(policy: _assignedTopicStorePolicy),
       _ownsTopicStore = topics == null;

  final AssignedGroupApi api;
  final PluginRequestHost _requests;
  final Store _topics;
  final bool _ownsTopicStore;
  final _accounts = <String, _AssignedGroupAccount>{};
  bool _closing = false;

  _AssignedGroupAccount? _existingAccount(String siteUrl) {
    final held = _accounts[siteUrl];
    return !isDisposed && !_closing && held?.isCurrent == true ? held : null;
  }

  _AssignedGroupAccount? _account(String siteUrl) {
    if (isDisposed || _closing) return null;
    final previous = _accounts[siteUrl];
    if (previous != null && !previous.isCurrent) _retireAccount(previous);
    if (isDisposed || _closing) return null;
    if (_existingAccount(siteUrl) case final held?) return held;
    final account = _AssignedGroupAccount(siteUrl, _requests.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() => _retireAccount(account));
    return account.isCurrent ? account : null;
  }

  void _retireAccount(_AssignedGroupAccount account, {bool notify = true}) {
    final owns = identical(_accounts[account.siteUrl], account);
    if (owns) _accounts.remove(account.siteUrl);
    account.retire();
    if (!owns) return;
    // Clear owned records before notification can admit a successor account.
    if (_ownsTopicStore) _topics.forget(account.siteUrl);
    if (notify) notifySafely();
  }

  AssignedGroupMembersState membersStateFor(
    String siteUrl,
    String groupName, {
    String search = '',
  }) =>
      _existingAccount(
        siteUrl,
      )?.member(_memberKey(siteUrl, groupName, search))?.state ??
      const AssignedGroupMembersState();

  TopicFeed topicFeedFor(
    String siteUrl,
    String groupName,
    AssignedGroupFilter filter, {
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
  }) =>
      _existingAccount(
        siteUrl,
      )?.topic(_topicKey(siteUrl, groupName, filter, query))?.feed ??
      const TopicFeed();

  List<Topic> topicsFor(
    String siteUrl,
    String groupName,
    AssignedGroupFilter filter, {
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
  }) {
    final feed = topicFeedFor(siteUrl, groupName, filter, query: query);
    return List.unmodifiable([
      for (final id in feed.topicIds) ?_topics.read<Topic>(siteUrl, id),
    ]);
  }

  Future<void> loadMembers({
    required String siteUrl,
    required String groupName,
    String search = '',
    bool refresh = false,
  }) async {
    final account = _account(siteUrl);
    if (account == null) return;
    final key = _memberKey(siteUrl, groupName, search);
    final owner =
        account.member(key) ??
        (account.members[key] = _AssignedMemberQuery(
          key: key,
          api: api,
          requests: _requests,
          lease: account.lease,
          notify: notifySafely,
        ));
    account.trimMembers();
    await owner.load(refresh: refresh);
  }

  Future<void> loadMoreMembers({
    required String siteUrl,
    required String groupName,
    String search = '',
  }) async {
    if (isDisposed) return;
    final owner = _existingAccount(
      siteUrl,
    )?.member(_memberKey(siteUrl, groupName, search));
    await owner?.loadMore();
  }

  Future<void> loadTopics({
    required String siteUrl,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
    bool refresh = false,
  }) async {
    final account = _account(siteUrl);
    if (account == null) return;
    final key = _topicKey(siteUrl, groupName, filter, query);
    final owner =
        account.topic(key) ??
        (account.topics[key] = _AssignedTopicQuery(
          key: key,
          api: api,
          requests: _requests,
          topics: _topics,
          lease: account.lease,
          notify: notifySafely,
        ));
    account.trimTopics();
    await owner.load(refresh: refresh);
  }

  Future<void> loadMoreTopics({
    required String siteUrl,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
  }) async {
    if (isDisposed) return;
    final owner = _existingAccount(
      siteUrl,
    )?.topic(_topicKey(siteUrl, groupName, filter, query));
    await owner?.loadMore();
  }

  void forget(String siteUrl) {
    final account = _accounts[siteUrl];
    if (account != null) _retireAccount(account);
  }

  static _MemberKey _memberKey(
    String siteUrl,
    String groupName,
    String search,
  ) => (siteUrl: siteUrl, groupName: groupName.trim(), search: search.trim());

  static _TopicKey _topicKey(
    String siteUrl,
    String groupName,
    AssignedGroupFilter filter,
    AssignedGroupTopicQuery query,
  ) => (
    siteUrl: siteUrl,
    groupName: groupName.trim(),
    filter: filter,
    query: AssignedGroupTopicQuery(
      order: query.order,
      ascending: query.ascending,
      search: query.search.trim(),
    ),
  );

  @override
  void dispose() {
    if (_closing) return;
    _closing = true;
    for (final account in _accounts.values.toList()) {
      _retireAccount(account, notify: false);
    }
    super.dispose();
  }
}

final class _AssignedGroupAccount {
  _AssignedGroupAccount(this.siteUrl, this.lease);

  final String siteUrl;
  final PluginSiteLease lease;
  void Function()? detach;
  bool _retired = false;
  bool get isCurrent => !_retired && lease.isCurrent;

  // Preserve separate, bounded histories for member searches and topic filters.
  static const _cachedQueries = 16;
  final members = <_MemberKey, _AssignedMemberQuery>{};
  final topics = <_TopicKey, _AssignedTopicQuery>{};

  _AssignedMemberQuery? member(_MemberKey key) => _touch(members, key);
  _AssignedTopicQuery? topic(_TopicKey key) => _touch(topics, key);

  // Reads and admission count as access; completions never change cache order.
  static V? _touch<K, V extends Object>(Map<K, V> cache, K key) {
    final held = cache.remove(key);
    if (held != null) cache[key] = held;
    return held;
  }

  void trimMembers() {
    while (members.length > _cachedQueries) {
      members.remove(members.keys.first)?.retire();
    }
  }

  void trimTopics() {
    while (topics.length > _cachedQueries) {
      topics.remove(topics.keys.first)?.retire();
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    for (final query in members.values) {
      query.retire();
    }
    for (final query in topics.values) {
      query.retire();
    }
    members.clear();
    topics.clear();
  }
}

final class _AssignedMemberQuery {
  _AssignedMemberQuery({
    required this.key,
    required this.api,
    required this.requests,
    required this.lease,
    required this.notify,
  });

  final _MemberKey key;
  final AssignedGroupApi api;
  final PluginRequestHost requests;
  final PluginSiteLease lease;
  final void Function() notify;

  AssignedGroupMembersState state = const AssignedGroupMembersState();
  Object? _request;
  bool _retired = false;

  Future<void> load({bool refresh = false}) =>
      _load(page: false, refresh: refresh);

  Future<void> loadMore() => _load(page: true);

  Future<void> _load({required bool page, bool refresh = false}) async {
    if (_retired || !lease.isCurrent) return;
    final held = state;
    if (page) {
      if (_request != null ||
          held.loading ||
          held.loadingMore ||
          !held.loaded ||
          !held.hasMore ||
          (held.error != null && !held.pageError)) {
        return;
      }
    } else if (!refresh &&
        (_request != null || (held.loaded && held.error == null))) {
      return;
    }

    final request = Object();
    _request = request;
    state = page ? held.loadingNextPage() : held.loadingFirst();
    notify();
    if (!_current(lease, request)) return;

    try {
      final credentials = await requests.credentialsFor(key.siteUrl);
      if (!_current(lease, request)) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        _commit(lease, request, () {
          state = held.withError(
            page
                ? appL10n.reconnectToLoadMoreAssignedMembers
                : appL10n.reconnectToViewGroupAssignments,
            page: page,
          );
        });
        return;
      }

      final result = await credentials.run(
        () => api.members(
          siteUrl: key.siteUrl,
          apiKey: apiKey,
          clientId: credentials.clientId,
          groupName: key.groupName,
          search: key.search,
          offset: page ? held.nextOffset : 0,
        ),
      );
      _commit(lease, request, () {
        state = (page ? held : state).withPage(
          result,
          filtered: key.search.isNotEmpty,
        );
      });
    } catch (error) {
      if (!_current(lease, request)) return;
      _commit(lease, request, () {
        state = held.withError(
          page
              ? appL10n.couldnTLoadMoreAssignedMembers
              : appL10n.couldnTLoadThisGroupSAssignedMembers,
          page: page,
        );
      });
    } finally {
      if (!_retired && identical(_request, request)) {
        _request = null;
        notify();
      }
    }
  }

  bool _current(PluginSiteLease lease, Object request) =>
      !_retired && lease.isCurrent && identical(_request, request);

  void _commit(
    PluginSiteLease lease,
    Object request,
    void Function() mutation,
  ) {
    if (!_current(lease, request)) return;
    lease.commit(() {
      if (!identical(_request, request)) return;
      mutation();
      notify();
    });
  }

  void retire() {
    _retired = true;
    _request = null;
  }
}

final class _AssignedTopicQuery {
  _AssignedTopicQuery({
    required this.key,
    required this.api,
    required this.requests,
    required this.topics,
    required this.lease,
    required this.notify,
  });

  final _TopicKey key;
  final AssignedGroupApi api;
  final PluginRequestHost requests;
  final PluginSiteLease lease;
  final Store topics;
  final void Function() notify;

  TopicFeed feed = const TopicFeed();
  Object? _request;
  bool _retired = false;

  Future<void> load({bool refresh = false}) =>
      _load(page: false, refresh: refresh);

  Future<void> loadMore() => _load(page: true);

  Future<void> _load({required bool page, bool refresh = false}) async {
    if (_retired || !lease.isCurrent) return;
    final held = feed;
    if (page) {
      if (_request != null ||
          held.loading ||
          held.loadingMore ||
          !held.hasMore ||
          (held.error != null && !held.pageError)) {
        return;
      }
    } else if (!refresh &&
        (_request != null || (held.loaded && held.error == null))) {
      return;
    }

    final request = Object();
    final requestedPath = page ? held.nextPagePath! : null;
    _request = request;
    feed = page ? held.loadingNextPage() : held.refreshing();
    notify();
    if (!_current(lease, request)) return;

    try {
      final credentials = await requests.credentialsFor(key.siteUrl);
      if (!_current(lease, request)) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        _commit(lease, request, () {
          feed = held.withError(
            page
                ? appL10n.reconnectToLoadMoreAssignments
                : appL10n.reconnectToViewGroupAssignments,
            page: page,
          );
        });
        return;
      }

      final list = await credentials.run(
        () => page
            ? api.topicPage(
                siteUrl: key.siteUrl,
                apiKey: apiKey,
                clientId: credentials.clientId,
                path: requestedPath!,
              )
            : api.topics(
                siteUrl: key.siteUrl,
                apiKey: apiKey,
                clientId: credentials.clientId,
                groupName: key.groupName,
                filter: key.filter,
                query: key.query,
              ),
      );
      _commit(lease, request, () {
        for (final topic in list.topics) {
          if (!_current(lease, request)) return;
          topics.put(key.siteUrl, topic);
        }
        if (!_current(lease, request)) return;
        if (!page) {
          feed = TopicFeed.of(list);
          return;
        }
        final seen = feed.topicIds.toSet();
        final fresh = [
          for (final topic in list.topics)
            if (seen.add(topic.id)) topic.id,
        ];
        feed = feed.copyWith(
          topicIds: [...feed.topicIds, ...fresh],
          loadingMore: false,
          nextPagePath: list.nextPagePath,
          clearNextPage:
              list.nextPagePath == null || list.nextPagePath == requestedPath,
          clearError: true,
        );
      });
    } catch (error) {
      if (!_current(lease, request)) return;

      _commit(lease, request, () {
        feed = held.withError(
          page
              ? appL10n.couldnTLoadMoreAssignments
              : appL10n.couldnTLoadThisGroupSAssignments,
          page: page,
        );
      });
    } finally {
      if (!_retired && identical(_request, request)) {
        _request = null;
        notify();
      }
    }
  }

  bool _current(PluginSiteLease lease, Object request) =>
      !_retired && lease.isCurrent && identical(_request, request);

  void _commit(
    PluginSiteLease lease,
    Object request,
    void Function() mutation,
  ) {
    if (!_current(lease, request)) return;
    lease.commit(() {
      if (!_current(lease, request)) return;
      mutation();
      if (_current(lease, request)) notify();
    });
  }

  void retire() {
    _retired = true;
    _request = null;
  }
}
