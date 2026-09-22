import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

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
        key: ObjectKey(presentation),
        siteUrl: widget.siteUrl,
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
    required this.siteUrl,
    required this.state,
    required this.onRefresh,
    required this.onSelect,
    required this.onQueryChanged,
    required this.onMemberSearch,
    required this.onLoadMoreMembers,
    required this.onLoadMoreTopics,
    required this.onOpenTopic,
  });

  final String siteUrl;
  final AssignedGroupPresentationState state;
  final RefreshCallback onRefresh;
  final ValueChanged<AssignedGroupFilter> onSelect;
  final ValueChanged<AssignedGroupTopicQuery> onQueryChanged;
  final ValueChanged<String> onMemberSearch;
  final VoidCallback onLoadMoreMembers;
  final VoidCallback onLoadMoreTopics;
  final ValueChanged<Topic> onOpenTopic;

  @override
  Widget build(BuildContext context) => _build(context);

  Widget _build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Topics',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TopicListActions(
              filter: DPopover(
                content: DPopoverContent(
                  align: DPopoverAlign.end,
                  width: 320,
                  child: DInput(
                    key: const ValueKey('assigned-topic-search'),
                    initialValue: state.query.search,
                    labelText: 'Filter assignments',
                    hintText: 'Words in the topic title',
                    onSubmitted: (search) => onQueryChanged(
                      AssignedGroupTopicQuery(
                        order: state.query.order,
                        ascending: state.query.ascending,
                        search: search,
                      ),
                    ),
                  ),
                ),
                child: DPopoverTrigger(
                  builder: (context, trigger) => DButton.iconOnly(
                    icon: const DIcon(DIcons.filter),
                    key: const ValueKey('assigned-query-menu'),
                    tooltip: 'Filter assignments',
                    variant: DButtonVariant.secondary,
                    focusNode: trigger.focusNode,
                    hasPopup: true,
                    expanded: trigger.open,
                    onPressed: trigger.toggle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const DSeparator(key: ValueKey('topic-list-heading-separator')),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const DBadge(
              variant: DBadgeVariant.secondary,
              child: Text('Assigned'),
            ),
            const Spacer(),
            DPopover(
              content: DPopoverContent(
                width: 320,
                align: DPopoverAlign.end,
                child: SizedBox(
                  height: 420,
                  child: _AssignedPeoplePanel(
                    key: const ValueKey('assigned-people-rail'),
                    groupName: state.groupName,
                    filter: state.filter,
                    members: state.members,
                    onSelect: onSelect,
                    onMemberSearch: onMemberSearch,
                    onLoadMoreMembers: onLoadMoreMembers,
                  ),
                ),
              ),
              child: DPopoverTrigger(
                builder: (context, trigger) => DButton(
                  key: const ValueKey('assigned-person-menu'),
                  label: Text(switch (state.filter) {
                    AssignedGroupEveryoneFilter() => 'Everyone',
                    AssignedGroupDirectFilter() => '@${state.groupName}',
                    AssignedGroupMemberFilter(:final usernameLower) =>
                      '@$usernameLower',
                  }),
                  icon: const DIcon(DIcons.users),
                  variant: DButtonVariant.transparentBackground,
                  focusNode: trigger.focusNode,
                  hasPopup: true,
                  expanded: trigger.open,
                  onPressed: trigger.toggle,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(child: _buildFeed(horizontalPadding: 0)),
      TopicSourceFooter(
        onNext: state.topics.isEmpty
            ? null
            : () => onOpenTopic(state.topics.first),
      ),
    ],
  );

  void _sortTopics(String column) {
    final order = AssignedGroupOrder.values.firstWhere(
      (value) => value.wireName == column,
    );
    final same = state.query.order == order;
    onQueryChanged(
      AssignedGroupTopicQuery(
        order: same && state.query.ascending ? null : order,
        ascending: same && !state.query.ascending,
        search: state.query.search,
      ),
    );
  }

  Widget _buildFeed({
    required double horizontalPadding,
    EdgeInsets insets = EdgeInsets.zero,
    Widget? people,
  }) {
    final feed = state.feed;
    final topics = state.topics;
    return DPullToRefresh(
      key: ValueKey((siteUrl, state.groupName, state.filter, state.query)),
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: PageStorageKey(
          'assigned-${state.groupName}-${state.filter.routeSegment(state.groupName)}',
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: insets,
            sliver: SliverMainAxisGroup(
              slivers: [
                if (people != null) SliverToBoxAdapter(child: people),
                if (feed.error case final error?)
                  SliverToBoxAdapter(
                    child: _AssignedError(message: error, onRetry: onRefresh),
                  ),
                if (!feed.loaded && feed.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: DSpinner(size: DSpacing.xl)),
                  )
                else if (topics.isEmpty && feed.error == null)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _AssignedEmpty(),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      4,
                      horizontalPadding,
                      28,
                    ),
                    sliver: SliverList.separated(
                      itemCount: topics.length,
                      separatorBuilder: (context, _) => const DSeparator(),
                      itemBuilder: (context, index) => TopicListRow(
                        topic: topics[index],
                        showViews: true,
                        onSort: _sortTopics,
                        order: state.query.order?.wireName,
                        ascending: state.query.ascending,
                        siteUrl: siteUrl,
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
                          key: const ValueKey('assigned-load-more-topics'),
                          label: const Text('Load more assignments'),
                          loading: feed.loadingMore,
                          onPressed: feed.loadingMore ? null : onLoadMoreTopics,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedPeoplePanel extends StatefulWidget {
  const _AssignedPeoplePanel({
    super.key,
    required this.groupName,
    required this.filter,
    required this.members,
    required this.onSelect,
    required this.onMemberSearch,
    required this.onLoadMoreMembers,
  });

  final String groupName;
  final AssignedGroupFilter filter;
  final AssignedGroupMembersState members;
  final ValueChanged<AssignedGroupFilter> onSelect;
  final ValueChanged<String> onMemberSearch;
  final VoidCallback onLoadMoreMembers;

  @override
  State<_AssignedPeoplePanel> createState() => _AssignedPeoplePanelState();
}

class _AssignedPeoplePanelState extends State<_AssignedPeoplePanel> {
  bool _showSearch = false;
  bool _loadMorePending = false;
  late final ScrollController _peopleScrollController;

  @override
  void initState() {
    super.initState();
    _peopleScrollController = ScrollController()..addListener(_loadMoreAtEnd);
  }

  @override
  void didUpdateWidget(_AssignedPeoplePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.members.loadingMore && !widget.members.loadingMore) ||
        oldWidget.members.members.length != widget.members.members.length ||
        !widget.members.hasMore) {
      _loadMorePending = false;
    }
  }

  @override
  void dispose() {
    _peopleScrollController
      ..removeListener(_loadMoreAtEnd)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <_AssignedPersonOption>[
      _AssignedPersonOption(
        label: 'Everyone',
        count: widget.members.assignmentCount,
        filter: const AssignedGroupFilter.everyone(),
        icon: DIcons.users,
      ),
      _AssignedPersonOption(
        label: '@${widget.groupName}',
        count: widget.members.groupAssignmentCount,
        filter: const AssignedGroupFilter.directGroup(),
        icon: DIcons.users,
      ),
      for (final member in widget.members.members)
        _AssignedPersonOption(
          label: '@${member.username}',
          count: member.assignmentsCount,
          filter: AssignedGroupFilter.member(member.usernameLower),
          member: member,
        ),
    ];

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Assigned to',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DButton.iconOnly(
            key: const ValueKey('assigned-member-search-toggle'),
            icon: DIcon(_showSearch ? DIcons.xmark : DIcons.magnifyingGlass),
            tooltip: _showSearch
                ? 'Hide person search'
                : 'Find assigned person',
            variant: DButtonVariant.ghost,
            size: DButtonSize.small,
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
        ],
      ),
    );
    final search = _showSearch
        ? Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: DInput(
              key: const ValueKey('assigned-member-search'),
              autofocus: true,
              labelText: 'Find assigned person',
              prefix: const DIcon(DIcons.magnifyingGlass, size: 16),
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onMemberSearch,
            ),
          )
        : null;
    final loading = widget.members.loading || widget.members.loadingMore
        ? const DProgress(
            semanticsLabel: 'Loading group members',
            track: DProgressTrack(height: 2),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        ?search,
        ?loading,
        Expanded(
          child: DScrollBar(
            key: const ValueKey('assigned-people-scrollbar'),
            controller: _peopleScrollController,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _peopleScrollController,
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 8),
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) => _AssignedPersonButton(
                option: options[index],
                selected: options[index].filter == widget.filter,
                onTap: () => widget.onSelect(options[index].filter),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _loadMoreAtEnd() {
    if (!_peopleScrollController.hasClients) return;
    if (_peopleScrollController.position.extentAfter <=
        paginationPrefetchDistance(_peopleScrollController.position)) {
      _requestMoreMembers();
    }
  }

  void _requestMoreMembers() {
    if (_loadMorePending ||
        !widget.members.hasMore ||
        widget.members.loading ||
        widget.members.loadingMore) {
      return;
    }
    _loadMorePending = true;
    widget.onLoadMoreMembers();
  }
}

@immutable
class _AssignedPersonOption {
  const _AssignedPersonOption({
    required this.label,
    required this.count,
    required this.filter,
    this.member,
    this.icon,
  });

  final String label;
  final int? count;
  final AssignedGroupFilter filter;
  final AssignedGroupMember? member;
  final DIconData? icon;
}

class _AssignedPersonButton extends StatelessWidget {
  const _AssignedPersonButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _AssignedPersonOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.shell.selectedForeground
        : theme.colorScheme.onSurfaceVariant;
    final count = option.count;
    final route = switch (option.filter) {
      AssignedGroupEveryoneFilter() => 'everyone',
      AssignedGroupDirectFilter() => 'direct-group',
      AssignedGroupMemberFilter(:final usernameLower) =>
        'member-$usernameLower',
    };
    return DItem(
      key: ValueKey('assigned-person-$route'),
      size: DItemSize.xs,
      selected: selected,
      onPressed: onTap,
      showSelectionIndicator: false,
      children: [
        DItemContent(
          children: [
            Row(
              children: [
                _AssignedPersonAvatar(option: option, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count != null) Text('$count'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _AssignedPersonAvatar extends StatelessWidget {
  const _AssignedPersonAvatar({required this.option, required this.color});

  final _AssignedPersonOption option;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    final theme = Theme.of(context);
    final fallback = ColoredBox(
      color: theme.shell.mention,
      child: Center(
        child: DIcon(option.icon ?? DIcons.user, size: 16, color: color),
      ),
    );
    return DAvatar.frame(
      child: SizedBox.square(
        dimension: size,
        child: switch (option.member) {
          final member? => AvatarImage(
            url: member.avatarUrl,
            size: size,
            fallback: fallback,
          ),
          null => fallback,
        },
      ),
    );
  }
}

class _AssignedError extends StatelessWidget {
  const _AssignedError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: DAlert(
      variant: DAlertVariant.destructive,
      icon: const DIcon(DIcons.triangleExclamation),
      description: DAlertDescription(child: Text(message)),
      action: DAlertAction(
        child: DButton(
          label: const Text('Try again'),
          onPressed: onRetry,
          variant: DButtonVariant.link,
        ),
      ),
    ),
  );
}

class _AssignedEmpty extends StatelessWidget {
  const _AssignedEmpty();

  @override
  Widget build(BuildContext context) => const Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(
                variant: DEmptyMediaVariant.icon,
                child: DIcon(DIcons.userPlus),
              ),
              DEmptyTitle('No active assignments match this filter.'),
            ],
          ),
        ],
      ),
    ),
  );
}
