// ignore_for_file: prefer_initializing_formals

import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../models/topic.dart';
import '../../models/topic_feed.dart';
import '../../plugin_api/core_plugin_host.dart';
import 'assigned_group.dart';
import 'assigned_group_api.dart';

typedef _MemberKey = ({String siteUrl, String groupName, String search});
typedef _TopicKey = ({
  String siteUrl,
  String groupName,
  AssignedGroupFilter filter,
  AssignedGroupTopicQuery query,
});

/// Pairs every response with its site lease and request token so superseded
/// account or query requests cannot publish.
final class AssignedGroupController extends FrameSafeNotifier {
  AssignedGroupController({
    required this.api,
    required PluginRequestHost requests,
    Store? topics,
    this.diagnostics = const PluginDiagnosticsReporter.noop(),
  }) : _requests = requests,
       _topics = topics ?? Store(),
       _ownsTopicStore = topics == null;

  final AssignedGroupApi api;
  final PluginRequestHost _requests;
  final Store _topics;
  final bool _ownsTopicStore;
  final PluginDiagnosticsReporter diagnostics;

  final Map<_MemberKey, AssignedGroupMembersState> _memberStates = {};
  final Map<_MemberKey, Object> _memberRequests = {};

  final Map<_TopicKey, TopicFeed> _topicFeeds = {};
  final Map<_TopicKey, Object> _topicRevisions = {};
  final Map<_TopicKey, Object> _topicLoads = {};
  final Map<_TopicKey, Object> _topicPageRequests = {};

  AssignedGroupMembersState membersStateFor(
    String siteUrl,
    String groupName, {
    String search = '',
  }) =>
      _memberStates[_memberKey(siteUrl, groupName, search)] ??
      const AssignedGroupMembersState();

  TopicFeed topicFeedFor(
    String siteUrl,
    String groupName,
    AssignedGroupFilter filter, {
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
  }) =>
      _topicFeeds[_topicKey(siteUrl, groupName, filter, query)] ??
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
    if (isDisposed) return;
    final key = _memberKey(siteUrl, groupName, search);
    final held = _memberStates[key] ?? const AssignedGroupMembersState();
    if (!refresh &&
        (_memberRequests.containsKey(key) ||
            (held.loaded && held.error == null))) {
      return;
    }

    final request = Object();
    final lease = _requests.capture(siteUrl);
    _memberRequests[key] = request;
    _memberStates[key] = held.loadingFirst();
    notifySafely();
    if (!_memberRequestCurrent(lease, key, request)) return;

    try {
      final credentials = await _requests.credentialsFor(siteUrl);
      if (!_memberRequestCurrent(lease, key, request)) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        _commitMember(lease, key, request, () {
          _memberStates[key] = held.withError(
            'Reconnect to view group assignments.',
          );
        });
        return;
      }

      final page = await api.members(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: credentials.clientId,
        groupName: key.groupName,
        search: key.search,
      );
      _commitMember(lease, key, request, () {
        _memberStates[key] = (_memberStates[key] ?? held).withPage(page);
      });
    } catch (error, stackTrace) {
      if (!_memberRequestCurrent(lease, key, request)) return;
      _report(error, stackTrace, 'assign.groupMembers');
      _commitMember(lease, key, request, () {
        _memberStates[key] = held.withError(
          "Couldn't load this group's assigned members.",
        );
      });
    } finally {
      _finishMemberRequest(key, request);
    }
  }

  Future<void> loadMoreMembers({
    required String siteUrl,
    required String groupName,
    String search = '',
  }) async {
    if (isDisposed) return;
    final key = _memberKey(siteUrl, groupName, search);
    final held = _memberStates[key] ?? const AssignedGroupMembersState();
    if (_memberRequests.containsKey(key) ||
        held.loading ||
        held.loadingMore ||
        !held.loaded ||
        !held.hasMore ||
        (held.error != null && !held.pageError)) {
      return;
    }

    final request = Object();
    final lease = _requests.capture(siteUrl);
    _memberRequests[key] = request;
    _memberStates[key] = held.loadingNextPage();
    notifySafely();
    if (!_memberRequestCurrent(lease, key, request)) return;

    try {
      final credentials = await _requests.credentialsFor(siteUrl);
      if (!_memberRequestCurrent(lease, key, request)) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        _commitMember(lease, key, request, () {
          _memberStates[key] = held.withError(
            'Reconnect to load more assigned members.',
            page: true,
          );
        });
        return;
      }

      final page = await api.members(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: credentials.clientId,
        groupName: key.groupName,
        search: key.search,
        offset: held.nextOffset,
      );
      _commitMember(lease, key, request, () {
        _memberStates[key] = held.withPage(page);
      });
    } catch (error, stackTrace) {
      if (!_memberRequestCurrent(lease, key, request)) return;
      _report(
        error,
        stackTrace,
        'assign.groupMembers.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      _commitMember(lease, key, request, () {
        _memberStates[key] = held.withError(
          "Couldn't load more assigned members.",
          page: true,
        );
      });
    } finally {
      _finishMemberRequest(key, request);
    }
  }

  Future<void> loadTopics({
    required String siteUrl,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
    bool refresh = false,
  }) async {
    if (isDisposed) return;
    final key = _topicKey(siteUrl, groupName, filter, query);
    final held = _topicFeeds[key] ?? const TopicFeed();
    if (!refresh &&
        (_topicLoads.containsKey(key) || (held.loaded && held.error == null))) {
      return;
    }

    final revision = Object();
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _topicRevisions[key] = revision;
    _topicLoads[key] = request;
    _topicPageRequests.remove(key);
    _topicFeeds[key] = held.refreshing();
    notifySafely();
    if (!_topicLoadCurrent(lease, key, revision, request)) return;

    try {
      final credentials = await _requests.credentialsFor(siteUrl);
      if (!_topicLoadCurrent(lease, key, revision, request)) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        _commitTopicLoad(lease, key, revision, request, () {
          _topicFeeds[key] = held.withError(
            'Reconnect to view group assignments.',
          );
        });
        return;
      }

      final list = await api.topics(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: credentials.clientId,
        groupName: key.groupName,
        filter: key.filter,
        query: key.query,
      );
      _commitTopicLoad(lease, key, revision, request, () {
        _topics.putAll(siteUrl, list.topics);
        _topicFeeds[key] = TopicFeed.of(list);
      });
    } catch (error, stackTrace) {
      if (!_topicLoadCurrent(lease, key, revision, request)) return;
      _report(error, stackTrace, 'assign.groupTopics');
      _commitTopicLoad(lease, key, revision, request, () {
        _topicFeeds[key] = held.withError(
          "Couldn't load this group's assignments.",
        );
      });
    } finally {
      if (!isDisposed && identical(_topicLoads[key], request)) {
        _topicLoads.remove(key);
        notifySafely();
      }
    }
  }

  Future<void> loadMoreTopics({
    required String siteUrl,
    required String groupName,
    required AssignedGroupFilter filter,
    AssignedGroupTopicQuery query = const AssignedGroupTopicQuery(),
  }) async {
    if (isDisposed) return;
    final key = _topicKey(siteUrl, groupName, filter, query);
    final held = _topicFeeds[key];
    if (held == null ||
        held.loading ||
        held.loadingMore ||
        !held.hasMore ||
        _topicLoads.containsKey(key) ||
        _topicPageRequests.containsKey(key) ||
        (held.error != null && !held.pageError)) {
      return;
    }

    final revision = _topicRevisions[key];
    if (revision == null) return;
    final request = Object();
    final lease = _requests.capture(siteUrl);
    _topicPageRequests[key] = request;
    _topicFeeds[key] = held.loadingNextPage();
    notifySafely();
    if (!_topicPageCurrent(lease, key, revision, request)) return;

    try {
      final credentials = await _requests.credentialsFor(siteUrl);
      if (!_topicPageCurrent(lease, key, revision, request)) return;
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        _commitTopicPage(lease, key, revision, request, () {
          _topicFeeds[key] = held.withError(
            'Reconnect to load more assignments.',
            page: true,
          );
        });
        return;
      }

      final requestedPath = held.nextPagePath!;
      final next = await api.topicPage(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: credentials.clientId,
        path: requestedPath,
      );
      _commitTopicPage(lease, key, revision, request, () {
        _topics.putAll(siteUrl, next.topics);
        final current = _topicFeeds[key] ?? held;
        final seen = current.topicIds.toSet();
        final fresh = [
          for (final topic in next.topics)
            if (seen.add(topic.id)) topic.id,
        ];
        _topicFeeds[key] = current.copyWith(
          topicIds: [...current.topicIds, ...fresh],
          loadingMore: false,
          nextPagePath: next.nextPagePath,
          clearNextPage:
              next.nextPagePath == null || next.nextPagePath == requestedPath,
          clearError: true,
        );
      });
    } catch (error, stackTrace) {
      if (!_topicPageCurrent(lease, key, revision, request)) return;
      _report(
        error,
        stackTrace,
        'assign.groupTopics.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      _commitTopicPage(lease, key, revision, request, () {
        _topicFeeds[key] = held.withError(
          "Couldn't load more assignments.",
          page: true,
        );
      });
    } finally {
      if (!isDisposed && identical(_topicPageRequests[key], request)) {
        _topicPageRequests.remove(key);
        notifySafely();
      }
    }
  }

  void forget(String siteUrl) {
    final before = _memberStates.length + _topicFeeds.length;
    _memberStates.removeWhere((key, _) => key.siteUrl == siteUrl);
    _memberRequests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _topicFeeds.removeWhere((key, _) => key.siteUrl == siteUrl);
    _topicRevisions.removeWhere((key, _) => key.siteUrl == siteUrl);
    _topicLoads.removeWhere((key, _) => key.siteUrl == siteUrl);
    _topicPageRequests.removeWhere((key, _) => key.siteUrl == siteUrl);
    if (_ownsTopicStore) _topics.forget(siteUrl);
    if (before != _memberStates.length + _topicFeeds.length) notifySafely();
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

  bool _memberRequestCurrent(
    PluginSiteLease lease,
    _MemberKey key,
    Object request,
  ) =>
      !isDisposed &&
      lease.isCurrent &&
      identical(_memberRequests[key], request);

  void _commitMember(
    PluginSiteLease lease,
    _MemberKey key,
    Object request,
    void Function() mutation,
  ) {
    if (!_memberRequestCurrent(lease, key, request)) return;
    lease.commit(() {
      if (!identical(_memberRequests[key], request)) return;
      mutation();
      notifySafely();
    });
  }

  void _finishMemberRequest(_MemberKey key, Object request) {
    if (!isDisposed && identical(_memberRequests[key], request)) {
      _memberRequests.remove(key);
      notifySafely();
    }
  }

  bool _topicLoadCurrent(
    PluginSiteLease lease,
    _TopicKey key,
    Object revision,
    Object request,
  ) =>
      !isDisposed &&
      lease.isCurrent &&
      identical(_topicRevisions[key], revision) &&
      identical(_topicLoads[key], request);

  bool _topicPageCurrent(
    PluginSiteLease lease,
    _TopicKey key,
    Object revision,
    Object request,
  ) =>
      !isDisposed &&
      lease.isCurrent &&
      identical(_topicRevisions[key], revision) &&
      identical(_topicPageRequests[key], request);

  void _commitTopicLoad(
    PluginSiteLease lease,
    _TopicKey key,
    Object revision,
    Object request,
    void Function() mutation,
  ) {
    if (!_topicLoadCurrent(lease, key, revision, request)) return;
    lease.commit(() {
      if (!_topicLoadCurrent(lease, key, revision, request)) return;
      mutation();
      notifySafely();
    });
  }

  void _commitTopicPage(
    PluginSiteLease lease,
    _TopicKey key,
    Object revision,
    Object request,
    void Function() mutation,
  ) {
    if (!_topicPageCurrent(lease, key, revision, request)) return;
    lease.commit(() {
      if (!_topicPageCurrent(lease, key, revision, request)) return;
      mutation();
      notifySafely();
    });
  }

  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
  }) {
    diagnostics.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'assign',
      severity: severity,
      handled: true,
      degraded: true,
    );
  }

  @override
  void dispose() {
    _memberStates.clear();
    _memberRequests.clear();
    _topicFeeds.clear();
    _topicRevisions.clear();
    _topicLoads.clear();
    _topicPageRequests.clear();
    super.dispose();
  }
}
