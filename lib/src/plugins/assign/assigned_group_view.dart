import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/topic.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/content_reading_lane.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'assign_services.dart';
import 'assign_shell_service.dart';
import 'assigned_group.dart';
import 'assigned_group_controller.dart';
import 'assigned_group_presentation.dart';

typedef AssignedGroupPresentationFactory =
    AssignedGroupPresentation Function(
      String siteUrl,
      String groupName,
      String? subsection,
    );

class AssignedGroupView extends StatefulWidget {
  const AssignedGroupView({
    super.key,
    required this.siteUrl,
    required this.groupName,
    required this.subsection,
    this.presentationFactory,
  });

  final String siteUrl;
  final String groupName;
  final String? subsection;
  final AssignedGroupPresentationFactory? presentationFactory;

  @override
  State<AssignedGroupView> createState() => _AssignedGroupViewState();
}

class _AssignedGroupViewState extends State<AssignedGroupView> {
  AssignedGroupPresentation? _presentation;
  AssignedGroupController? _domainController;
  AssignShellService? _navigationService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePresentation();
  }

  @override
  void didUpdateWidget(AssignedGroupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.groupName != widget.groupName ||
        oldWidget.subsection != widget.subsection ||
        oldWidget.presentationFactory != widget.presentationFactory) {
      _ensurePresentation(replace: true);
    }
  }

  void _ensurePresentation({bool replace = false}) {
    final factory = widget.presentationFactory;
    if (factory != null) {
      if (replace || _presentation == null) {
        _replacePresentation(
          factory(widget.siteUrl, widget.groupName, widget.subsection),
        );
      }
      return;
    }

    final domain = PluginUiScope.require(
      context,
      assignedGroupControllerService,
    );
    final navigation = PluginUiScope.require(
      context,
      assignGroupNavigationService,
    );
    if (!replace &&
        _presentation != null &&
        identical(_domainController, domain) &&
        identical(_navigationService, navigation)) {
      return;
    }
    _domainController = domain;
    _navigationService = navigation;
    _replacePresentation(
      AssignedGroupPresentationController(
        siteUrl: widget.siteUrl,
        groupName: widget.groupName,
        subsection: widget.subsection,
        controller: domain,
        onSelectFilter: navigation.selectGroupFilter,
        onOpenTopic: navigation.openTopic,
      ),
    );
  }

  void _replacePresentation(AssignedGroupPresentation next) {
    _presentation?.dispose();
    _presentation = next;
    _scheduleLoad(next);
  }

  void _scheduleLoad(AssignedGroupPresentation presentation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_presentation, presentation)) return;
      unawaited(presentation.load());
    });
  }

  @override
  void dispose() {
    _presentation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    if (presentation == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: presentation,
      builder: (context, _) => AssignedGroupPresentationView(
        state: presentation.state,
        onRefresh: () => presentation.load(refresh: true),
        onSelect: presentation.selectFilter,
        onQueryChanged: presentation.replaceQuery,
        onMemberSearch: presentation.searchMembers,
        onLoadMoreMembers: presentation.loadMoreMembers,
        onLoadMoreTopics: presentation.loadMoreTopics,
        onOpenTopic: presentation.openTopic,
      ),
    );
  }
}

class AssignedGroupPresentationView extends StatelessWidget {
  const AssignedGroupPresentationView({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onSelect,
    required this.onQueryChanged,
    required this.onMemberSearch,
    required this.onLoadMoreMembers,
    required this.onLoadMoreTopics,
    required this.onOpenTopic,
  });

  final AssignedGroupPresentationState state;
  final RefreshCallback onRefresh;
  final ValueChanged<AssignedGroupFilter> onSelect;
  final ValueChanged<AssignedGroupTopicQuery> onQueryChanged;
  final ValueChanged<String> onMemberSearch;
  final VoidCallback onLoadMoreMembers;
  final VoidCallback onLoadMoreTopics;
  final ValueChanged<Topic> onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final feed = state.feed;
    final topics = state.topics;
    return ContentReadingLane(
      basePadding: const EdgeInsets.symmetric(horizontal: 16),
      builder: (context, lane) => RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          key: PageStorageKey(
            'assigned-${state.groupName}-${state.filter.routeSegment(state.groupName)}',
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                left: lane.leftInset,
                right: lane.rightInset,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: _AssignedControls(
                      groupName: state.groupName,
                      filter: state.filter,
                      query: state.query,
                      members: state.members,
                      onSelect: onSelect,
                      onQueryChanged: onQueryChanged,
                      onMemberSearch: onMemberSearch,
                      onLoadMoreMembers: onLoadMoreMembers,
                    ),
                  ),
                  if (feed.loading && topics.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (feed.error case final error?)
                    SliverToBoxAdapter(
                      child: _AssignedError(message: error, onRetry: onRefresh),
                    ),
                  if (!feed.loaded && feed.loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
                    )
                  else if (topics.isEmpty && feed.error == null)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _AssignedEmpty(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      sliver: SliverList.separated(
                        itemCount: topics.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _AssignedTopicRow(
                          topic: topics[index],
                          onTap: () => onOpenTopic(topics[index]),
                        ),
                      ),
                    ),
                  if (feed.hasMore || feed.loadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Center(
                          child: DButton(
                            label: const Text('Load more assignments'),
                            loading: feed.loadingMore,
                            onPressed: feed.loadingMore
                                ? null
                                : onLoadMoreTopics,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignedControls extends StatelessWidget {
  const _AssignedControls({
    required this.groupName,
    required this.filter,
    required this.query,
    required this.members,
    required this.onSelect,
    required this.onQueryChanged,
    required this.onMemberSearch,
    required this.onLoadMoreMembers,
  });

  final String groupName;
  final AssignedGroupFilter filter;
  final AssignedGroupTopicQuery query;
  final AssignedGroupMembersState members;
  final ValueChanged<AssignedGroupFilter> onSelect;
  final ValueChanged<AssignedGroupTopicQuery> onQueryChanged;
  final ValueChanged<String> onMemberSearch;
  final VoidCallback onLoadMoreMembers;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('Everyone (${members.assignmentCount})'),
                  selected: filter is AssignedGroupEveryoneFilter,
                  onSelected: (_) =>
                      onSelect(const AssignedGroupFilter.everyone()),
                ),
                ChoiceChip(
                  label: Text('@$groupName (${members.groupAssignmentCount})'),
                  selected: filter is AssignedGroupDirectFilter,
                  onSelected: (_) =>
                      onSelect(const AssignedGroupFilter.directGroup()),
                ),
                for (final member in members.members)
                  ChoiceChip(
                    label: Text(
                      '@${member.username}'
                      '${member.assignmentsCount == null ? '' : ' (${member.assignmentsCount})'}',
                    ),
                    selected: switch (filter) {
                      AssignedGroupMemberFilter(:final usernameLower) =>
                        usernameLower == member.usernameLower,
                      _ => false,
                    },
                    onSelected: (_) => onSelect(
                      AssignedGroupFilter.member(member.usernameLower),
                    ),
                  ),
              ],
            ),
            if (members.hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: DButton(
                  label: const Text('More people'),
                  onPressed: onLoadMoreMembers,
                  variant: DButtonVariant.link,
                  loading: members.loadingMore,
                  loadingLabel: const Text('Loading people…'),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search assignments',
                      prefixIcon: DIcon(DIcons.magnifyingGlass, size: 16),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) => onQueryChanged(
                      AssignedGroupTopicQuery(
                        order: query.order,
                        ascending: query.ascending,
                        search: value.trim(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Find assigned person',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: onMemberSearch,
                  ),
                ),
                DropdownButton<AssignedGroupOrder?>(
                  value: query.order,
                  hint: const Text('Default order'),
                  onChanged: (value) => onQueryChanged(
                    AssignedGroupTopicQuery(
                      order: value,
                      ascending: query.ascending,
                      search: query.search,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AssignedGroupOrder.activity,
                      child: Text('Activity'),
                    ),
                    DropdownMenuItem(
                      value: AssignedGroupOrder.posts,
                      child: Text('Posts'),
                    ),
                    DropdownMenuItem(
                      value: AssignedGroupOrder.views,
                      child: Text('Views'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: query.ascending ? 'Descending' : 'Ascending',
                  onPressed: () => onQueryChanged(
                    AssignedGroupTopicQuery(
                      order: query.order,
                      ascending: !query.ascending,
                      search: query.search,
                    ),
                  ),
                  icon: Icon(
                    query.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AssignedTopicRow extends StatelessWidget {
  const _AssignedTopicRow({required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          leading: const DIcon(DIcons.userPlus, size: 18),
          title: Text(
            topic.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('${topic.postsCount} posts · ${topic.views} views'),
          trailing: const DIcon(DIcons.chevronRight, size: 14),
        ),
      ),
    ),
  );
}

class _AssignedError extends StatelessWidget {
  const _AssignedError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        const DIcon(DIcons.triangleExclamation, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
        DButton(
          label: const Text('Try again'),
          onPressed: onRetry,
          variant: DButtonVariant.link,
        ),
      ],
    ),
  );
}

class _AssignedEmpty extends StatelessWidget {
  const _AssignedEmpty();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DIcon(DIcons.userPlus, size: 34),
        SizedBox(height: 10),
        Text('No active assignments match this filter.'),
      ],
    ),
  );
}
