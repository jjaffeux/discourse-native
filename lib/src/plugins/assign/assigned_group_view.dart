import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/topic.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../shell/avatar_image.dart';
import '../../shell/content_reading_lane.dart';
import '../../shell/topic_list_view.dart';
import '../../theme/app_theme.dart';
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

const double _assignedDesktopBreakpoint = 720;
const double _assignedPeopleRailWidth = 220;

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
  Widget build(BuildContext context) {
    return ContentReadingLane(
      basePadding: const EdgeInsets.symmetric(horizontal: 16),
      builder: (context, lane) {
        final desktop =
            ContentReadingLane.breakpointWidthOf(context, lane.width) >=
            _assignedDesktopBreakpoint;
        if (!desktop) {
          return _buildFeed(
            horizontalPadding: 16,
            people: _AssignedPeoplePanel(
              key: const ValueKey('assigned-people-grid'),
              compact: true,
              groupName: state.groupName,
              filter: state.filter,
              members: state.members,
              onSelect: onSelect,
              onMemberSearch: onMemberSearch,
              onLoadMoreMembers: onLoadMoreMembers,
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            left: lane.padding.left,
            right: lane.padding.right,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _assignedPeopleRailWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 28),
                  child: _AssignedPeoplePanel(
                    key: const ValueKey('assigned-people-rail'),
                    compact: false,
                    groupName: state.groupName,
                    filter: state.filter,
                    members: state.members,
                    onSelect: onSelect,
                    onMemberSearch: onMemberSearch,
                    onLoadMoreMembers: onLoadMoreMembers,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildFeed(horizontalPadding: 0)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeed({required double horizontalPadding, Widget? people}) {
    final feed = state.feed;
    final topics = state.topics;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: PageStorageKey(
          'assigned-${state.groupName}-${state.filter.routeSegment(state.groupName)}',
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverMainAxisGroup(
            slivers: [
              if (people != null) SliverToBoxAdapter(child: people),
              SliverToBoxAdapter(
                child: _AssignedQueryControls(
                  horizontalPadding: horizontalPadding,
                  query: state.query,
                  onQueryChanged: onQueryChanged,
                ),
              ),
              if (feed.error case final error?)
                SliverToBoxAdapter(
                  child: _AssignedError(message: error, onRetry: onRefresh),
                ),
              if (!feed.loaded && feed.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive()),
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
                    separatorBuilder: (context, _) => Divider(
                      height: 1,
                      color: Theme.of(context).shell.divider,
                    ),
                    itemBuilder: (context, index) => TopicListRow(
                      topic: topics[index],
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
        ],
      ),
    );
  }
}

class _AssignedPeoplePanel extends StatefulWidget {
  const _AssignedPeoplePanel({
    super.key,
    required this.compact,
    required this.groupName,
    required this.filter,
    required this.members,
    required this.onSelect,
    required this.onMemberSearch,
    required this.onLoadMoreMembers,
  });

  final bool compact;
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
    _loadAllMembersOnCompactLayouts();

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
            icon: DIcon(
              _showSearch ? DIcons.xmark : DIcons.magnifyingGlass,
              size: 16,
            ),
            tooltip: _showSearch
                ? 'Hide person search'
                : 'Find assigned person',
            variant: DButtonVariant.flat,
            size: DButtonSize.small,
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
        ],
      ),
    );
    final search = _showSearch
        ? Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: TextField(
              key: const ValueKey('assigned-member-search'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Find assigned person',
                prefixIcon: DIcon(DIcons.magnifyingGlass, size: 16),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onMemberSearch,
            ),
          )
        : null;
    final loading = widget.members.loading || widget.members.loadingMore
        ? const LinearProgressIndicator(minHeight: 2)
        : null;

    final panel = Material(
      color: theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                ?search,
                ?loading,
                GridView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: options.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 48,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemBuilder: (context, index) => _AssignedPersonButton(
                    option: options[index],
                    selected: options[index].filter == widget.filter,
                    onTap: () => widget.onSelect(options[index].filter),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                ?search,
                ?loading,
                Expanded(
                  child: Scrollbar(
                    key: const ValueKey('assigned-people-scrollbar'),
                    controller: _peopleScrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _peopleScrollController,
                      padding: const EdgeInsets.fromLTRB(6, 4, 10, 8),
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) => SizedBox(
                        height: 48,
                        child: _AssignedPersonButton(
                          option: options[index],
                          selected: options[index].filter == widget.filter,
                          onTap: () => widget.onSelect(options[index].filter),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    if (!widget.compact) return panel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: panel,
    );
  }

  void _loadMoreAtEnd() {
    if (widget.compact || !_peopleScrollController.hasClients) return;
    if (_peopleScrollController.position.extentAfter <= 80) {
      _requestMoreMembers();
    }
  }

  void _loadAllMembersOnCompactLayouts() {
    if (!widget.compact || widget.members.pageError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.compact) _requestMoreMembers();
    });
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
    return Semantics(
      key: ValueKey('assigned-person-$route'),
      button: true,
      selected: selected,
      label: count == null
          ? option.label
          : '${option.label}, $count assignments',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? theme.shell.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                children: [
                  _AssignedPersonAvatar(option: option, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
    return ClipOval(
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

class _AssignedQueryControls extends StatelessWidget {
  const _AssignedQueryControls({
    required this.horizontalPadding,
    required this.query,
    required this.onQueryChanged,
  });

  final double horizontalPadding;
  final AssignedGroupTopicQuery query;
  final ValueChanged<AssignedGroupTopicQuery> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const ValueKey('assigned-topic-search'),
      decoration: const InputDecoration(
        labelText: 'Search assignments',
        prefixIcon: DIcon(DIcons.magnifyingGlass, size: 16),
        border: OutlineInputBorder(),
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
    );
    final order = DropdownButtonFormField<AssignedGroupOrder?>(
      key: ValueKey('assigned-order-${query.order?.wireName ?? 'default'}'),
      initialValue: query.order,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('Default order')),
        DropdownMenuItem(
          value: AssignedGroupOrder.activity,
          child: Text('Activity'),
        ),
        DropdownMenuItem(value: AssignedGroupOrder.posts, child: Text('Posts')),
        DropdownMenuItem(value: AssignedGroupOrder.views, child: Text('Views')),
      ],
      onChanged: (value) => onQueryChanged(
        AssignedGroupTopicQuery(
          order: value,
          ascending: query.ascending,
          search: query.search,
        ),
      ),
    );
    final direction = IconButton(
      tooltip: query.ascending ? 'Descending' : 'Ascending',
      onPressed: () => onQueryChanged(
        AssignedGroupTopicQuery(
          order: query.order,
          ascending: !query.ascending,
          search: query.search,
        ),
      ),
      icon: Icon(query.ascending ? Icons.arrow_upward : Icons.arrow_downward),
    );

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          14,
          horizontalPadding,
          10,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (ContentReadingLane.breakpointWidthOf(
                  context,
                  constraints.maxWidth,
                ) >=
                520) {
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  SizedBox(width: 170, child: order),
                  const SizedBox(width: 4),
                  direction,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: order),
                    const SizedBox(width: 4),
                    direction,
                  ],
                ),
              ],
            );
          },
        ),
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
