// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/topic.dart';
import '../../models/topic_feed.dart';
import 'assigned_group.dart';
import 'assigned_group_controller.dart';

typedef AssignedGroupFilterAction =
    void Function(String groupName, AssignedGroupFilter filter);
typedef AssignedGroupTopicAction = void Function(Topic topic);

@immutable
final class AssignedGroupPresentationState {
  const AssignedGroupPresentationState({
    required this.groupName,
    required this.filter,
    required this.query,
    required this.members,
    required this.feed,
    required this.topics,
  });

  final String groupName;
  final AssignedGroupFilter filter;
  final AssignedGroupTopicQuery query;
  final AssignedGroupMembersState members;
  final TopicFeed feed;
  final List<Topic> topics;
}

abstract interface class AssignedGroupPresentation implements Listenable {
  AssignedGroupPresentationState get state;

  Future<void> load({bool refresh = false});

  void selectFilter(AssignedGroupFilter filter);

  void replaceQuery(AssignedGroupTopicQuery query);

  void searchMembers(String value);

  void loadMoreMembers();

  void loadMoreTopics();

  void openTopic(Topic topic);

  void dispose();
}

/// Coordinates route-local presentation state without exposing the plugin UI
/// to the shell or duplicating the Assign domain controller's caches.
final class AssignedGroupPresentationController extends ChangeNotifier
    implements AssignedGroupPresentation {
  AssignedGroupPresentationController({
    required this.siteUrl,
    required this.groupName,
    required String? subsection,
    required AssignedGroupController controller,
    required AssignedGroupFilterAction onSelectFilter,
    required AssignedGroupTopicAction onOpenTopic,
  }) : _controller = controller,
       _onSelectFilter = onSelectFilter,
       _onOpenTopic = onOpenTopic,
       _filter = _filterFor(groupName, subsection) {
    _controller.addListener(_domainChanged);
  }

  final String siteUrl;
  final String groupName;
  final AssignedGroupController _controller;
  final AssignedGroupFilterAction _onSelectFilter;
  final AssignedGroupTopicAction _onOpenTopic;
  final AssignedGroupFilter _filter;

  AssignedGroupTopicQuery _query = const AssignedGroupTopicQuery();
  String _memberSearch = '';
  bool _disposed = false;

  @override
  AssignedGroupPresentationState get state => AssignedGroupPresentationState(
    groupName: groupName,
    filter: _filter,
    query: _query,
    members: _controller.membersStateFor(
      siteUrl,
      groupName,
      search: _memberSearch,
    ),
    feed: _controller.topicFeedFor(siteUrl, groupName, _filter, query: _query),
    topics: _controller.topicsFor(siteUrl, groupName, _filter, query: _query),
  );

  @override
  Future<void> load({bool refresh = false}) => Future.wait([
    _controller.loadMembers(
      siteUrl: siteUrl,
      groupName: groupName,
      search: _memberSearch,
      refresh: refresh,
    ),
    _controller.loadTopics(
      siteUrl: siteUrl,
      groupName: groupName,
      filter: _filter,
      query: _query,
      refresh: refresh,
    ),
  ]);

  @override
  void selectFilter(AssignedGroupFilter filter) {
    _onSelectFilter(groupName, filter);
  }

  @override
  void replaceQuery(AssignedGroupTopicQuery query) {
    if (query == _query || _disposed) return;
    _query = query;
    notifyListeners();
    unawaited(
      _controller.loadTopics(
        siteUrl: siteUrl,
        groupName: groupName,
        filter: _filter,
        query: query,
        refresh: true,
      ),
    );
  }

  @override
  void searchMembers(String value) {
    final search = value.trim();
    if (search == _memberSearch || _disposed) return;
    _memberSearch = search;
    notifyListeners();
    unawaited(
      _controller.loadMembers(
        siteUrl: siteUrl,
        groupName: groupName,
        search: search,
        refresh: true,
      ),
    );
  }

  @override
  void loadMoreMembers() {
    unawaited(
      _controller.loadMoreMembers(
        siteUrl: siteUrl,
        groupName: groupName,
        search: _memberSearch,
      ),
    );
  }

  @override
  void loadMoreTopics() {
    unawaited(
      _controller.loadMoreTopics(
        siteUrl: siteUrl,
        groupName: groupName,
        filter: _filter,
        query: _query,
      ),
    );
  }

  @override
  void openTopic(Topic topic) {
    _onOpenTopic(topic);
  }

  void _domainChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_domainChanged);
    super.dispose();
  }

  static AssignedGroupFilter _filterFor(String groupName, String? subsection) {
    if (subsection == null || subsection == 'everyone') {
      return const AssignedGroupFilter.everyone();
    }
    if (subsection == groupName) {
      return const AssignedGroupFilter.directGroup();
    }
    return AssignedGroupFilter.member(subsection);
  }
}
