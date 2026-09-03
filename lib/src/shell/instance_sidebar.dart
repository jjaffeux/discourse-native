import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sidebar_section_store.dart';
import '../models/content_route.dart';
import '../models/group_route.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_tooltip.dart';
import 'avatar_image.dart';
import 'emoji.dart';
import 'forum_search.dart';
import 'instance_actions.dart';
import 'open_link.dart';
import 'platform.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

@immutable
final class _SidebarSnapshot {
  const _SidebarSnapshot({
    required this.siteUrl,
    required this.name,
    required this.destinationId,
    required this.draftCount,
    required this.canCreateTopic,
    required this.sections,
    required this.presentationToken,
    required this.topicTrackingRevision,
  });

  final String? siteUrl;
  final String? name;
  final String? destinationId;
  final int draftCount;
  final bool canCreateTopic;
  final List<SidebarSection> sections;
  final Object? presentationToken;
  final int topicTrackingRevision;

  @override
  bool operator ==(Object other) {
    if (other is! _SidebarSnapshot ||
        siteUrl != other.siteUrl ||
        name != other.name ||
        destinationId != other.destinationId ||
        draftCount != other.draftCount ||
        canCreateTopic != other.canCreateTopic ||
        !identical(presentationToken, other.presentationToken) ||
        topicTrackingRevision != other.topicTrackingRevision ||
        sections.length != other.sections.length) {
      return false;
    }
    for (var index = 0; index < sections.length; index++) {
      if (!identical(sections[index], other.sections[index])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    siteUrl,
    name,
    destinationId,
    draftCount,
    canCreateTopic,
    identityHashCode(presentationToken),
    topicTrackingRevision,
    Object.hashAll(sections.map(identityHashCode)),
  );
}

@immutable
final class _SidebarPanelSnapshot {
  const _SidebarPanelSnapshot({
    required this.contentId,
    required this.presentation,
  });

  final String? contentId;
  final Object? presentation;

  @override
  bool operator ==(Object other) =>
      other is _SidebarPanelSnapshot &&
      contentId == other.contentId &&
      presentation == other.presentation;

  @override
  int get hashCode => Object.hash(contentId, presentation);
}

const String _newTopicDestinationId = 'new-topic';
const String _moreDestinationId = 'sidebar-more-destinations';

const SidebarDestination _newTopicDestination = SidebarDestination(
  id: _newTopicDestinationId,
  label: 'New Topic',
  icon: DIcons.plus,
);

const SidebarDestination _moreDestination = SidebarDestination(
  id: _moreDestinationId,
  label: 'More',
  icon: DIcons.ellipsisVertical,
);

abstract final class _SidebarSpacing {
  static const double compactBreakpoint = 640;
  static const double wrapperVerticalPadding = 10;
  static const double wrapperHorizontalPadding = 6;
  static const double sectionVerticalPadding = 3;
  static const double rowHorizontalPadding = 6;
  static const double rowGap = 1;
  static const double prefixWidth = 20;
  static const double prefixGap = 6;
  static const double desktopRowHeight = 30;
  static const double compactRowHeight = 38.4;
  static const double desktopSectionHeaderHeight = 24;
  static const double sectionHeaderFontSize = 11;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= compactBreakpoint;

  static double rowHeight(BuildContext context) =>
      isCompact(context) ? compactRowHeight : desktopRowHeight;

  static double sectionHeaderHeight(BuildContext context) =>
      isCompact(context) ? compactRowHeight : desktopSectionHeaderHeight;

  static double labelFontSize(BuildContext context) =>
      isCompact(context) ? 16 : 14;

  static double prefixArtSize(BuildContext context) =>
      isCompact(context) ? 22 : 18;

  static double prefixIconSize(BuildContext context) =>
      isCompact(context) ? 16 : 15;

  static double indent(BuildContext context) => isCompact(context) ? 20 : 18;

  static double sectionPadding(BuildContext context) =>
      isCompact(context) ? 0 : sectionVerticalPadding;
}

class InstanceSidebar extends StatelessWidget {
  const InstanceSidebar({
    super.key,
    this.showUserMenu = false,
    this.sectionStore = const SidebarSectionStore(),
  });

  final bool showUserMenu;
  final SidebarSectionStore sectionStore;

  @override
  Widget build(BuildContext context) => ShellSelector<_SidebarSnapshot>(
    select: (controller) {
      final instance = controller.currentInstance;
      final currentContent = controller.currentContent;
      var selectedDestinationId = controller.destinationId;
      if (currentContent?.groupRoute != null) {
        selectedDestinationId = 'groups';
      } else if (currentContent?.isTopic == true &&
          selectedDestinationId == 'drafts') {
        // Reply drafts keep Drafts in their back stack, but the topic itself
        // is not the Drafts route.
        selectedDestinationId = null;
      }
      final categorySection = instance == null
          ? null
          : controller.categorySidebarSectionFor(instance.url);
      final tagSection = instance == null
          ? null
          : controller.tagSidebarSectionFor(instance.url);
      return _SidebarSnapshot(
        siteUrl: instance?.url,
        name: instance?.title,
        destinationId: selectedDestinationId,
        draftCount: instance?.user?.draftCount ?? 0,
        canCreateTopic: instance?.user?.canCreateTopic ?? false,
        presentationToken: instance == null
            ? null
            : controller.presentationTokenFor(instance.url),
        topicTrackingRevision: instance == null
            ? 0
            : controller.topicTrackingRevisionFor(instance.url),
        sections: instance == null
            ? const <SidebarSection>[]
            : [
                ...instance.sections,
                ...controller.customSidebarSectionsFor(instance.url),
                ?categorySection,
                ?tagSection,
              ],
      );
    },
    builder: (context, sidebar, _) {
      final theme = Theme.of(context);
      if (sidebar.siteUrl == null) {
        return ColoredBox(color: theme.shell.sidebar);
      }

      return ColoredBox(
        color: theme.shell.sidebar,
        child: SafeArea(
          left: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarHeader(name: sidebar.name!, showUserMenu: showUserMenu),
              Expanded(
                child: _SidebarPanelBody(
                  sidebar: sidebar,
                  showUserMenu: showUserMenu,
                  sectionStore: sectionStore,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SidebarPanelBody extends StatelessWidget {
  const _SidebarPanelBody({
    required this.sidebar,
    required this.showUserMenu,
    required this.sectionStore,
  });

  final _SidebarSnapshot sidebar;
  final bool showUserMenu;
  final SidebarSectionStore sectionStore;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.accountActivity.totalsListenable,
        ...registry.sidebarPanelListenables(context),
      ]),
      builder: (context, _) => ShellSelector<_SidebarPanelSnapshot>(
        select: (controller) {
          final instance = controller.currentInstance;
          return _SidebarPanelSnapshot(
            contentId: controller.currentContent?.id,
            presentation: instance == null
                ? null
                : (
                    instance.isConnected,
                    instance.user,
                    instance.config,
                    controller.currentTotals,
                  ),
          );
        },
        builder: (context, _, _) => _buildPanel(context),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final controller = ShellScope.read(context);
    final registry = PluginScope.of(context).registry;
    final panels = registry.sidebarPanels(context);
    OwnedSidebarPanel? selectedPanel;
    OwnedSidebarPanel? activePanel;
    for (final candidate in panels) {
      if (!candidate.panel.active) continue;
      selectedPanel ??= candidate;
      if (candidate.panel.separateWhenActive) activePanel ??= candidate;
    }
    final showCoreSections = activePanel == null;

    bool includePluginOwner(PluginId owner) {
      if (activePanel case final active?) return owner == active.owner;
      for (final candidate in panels) {
        if (candidate.owner == owner) {
          return candidate.panel.includeSectionsWhenInactive;
        }
      }
      return true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showUserMenu && showCoreSections) const _SidebarSearchRow(),
        _SidebarPanelSwitchRow(panels: panels, selectedPanel: selectedPanel),
        Expanded(
          child: ScrollbarTheme(
            data: const ScrollbarThemeData(
              thickness: WidgetStatePropertyAll(4),
            ),
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: _SidebarSpacing.wrapperVerticalPadding,
                  ),
                ),
                if (showCoreSections)
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      controller.accountActivity.totalsListenable,
                      controller.draftList,
                    ]),
                    builder: (context, _) => SliverMainAxisGroup(
                      slivers: [
                        for (final (index, section) in sidebar.sections.indexed)
                          _Section(
                            key: ValueKey((sidebar.siteUrl, section.id)),
                            siteUrl: sidebar.siteUrl!,
                            section: section,
                            first: index == 0,
                            store: sectionStore,
                            selectedId: sidebar.destinationId,
                            badgeFor: controller.sidebarBadgeFor,
                            insertedDestination:
                                sidebar.canCreateTopic &&
                                    section.destinations.any(
                                      (destination) =>
                                          destination.id == 'messages',
                                    )
                                ? _newTopicDestination
                                : null,
                            insertAfterDestinationId: 'messages',
                            onSelect: (destination) {
                              if (destination.id == _newTopicDestinationId) {
                                unawaited(controller.openNewTopicFromSidebar());
                                return;
                              }
                              final url = destination.url;
                              if (url == null) {
                                controller.selectDestination(destination);
                              } else {
                                unawaited(
                                  openLink(
                                    context,
                                    url,
                                    title: destination.label,
                                    siteUrl: sidebar.siteUrl,
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ListenableBuilder(
                  listenable: Listenable.merge(
                    registry.sidebarListenables(
                      context,
                      includeOwner: includePluginOwner,
                    ),
                  ),
                  builder: (context, _) {
                    final sections = registry.sidebarSections(
                      context,
                      includeOwner: includePluginOwner,
                    );
                    return SliverMainAxisGroup(
                      slivers: [
                        for (final (index, section) in sections.indexed)
                          _Section(
                            key: ValueKey((sidebar.siteUrl, section.id)),
                            siteUrl: sidebar.siteUrl!,
                            section: section,
                            first:
                                (!showCoreSections ||
                                    sidebar.sections.isEmpty) &&
                                index == 0,
                            store: sectionStore,
                            selectedId:
                                selectedPanel?.panel.selectedDestinationId ??
                                sidebar.destinationId,
                            badgeFor: controller.sidebarBadgeFor,
                            onSelect: controller.selectDestination,
                          ),
                      ],
                    );
                  },
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: _SidebarSpacing.wrapperVerticalPadding,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarSearchRow extends StatelessWidget {
  const _SidebarSearchRow();

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(8, 6, 8, 5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: _padding,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: const ForumSearch(
        key: ValueKey('instance-sidebar-search-target'),
        dense: true,
      ),
    );
  }
}

class _SidebarPanelSwitchRow extends StatelessWidget {
  const _SidebarPanelSwitchRow({
    required this.panels,
    required this.selectedPanel,
  });

  final List<OwnedSidebarPanel> panels;
  final OwnedSidebarPanel? selectedPanel;

  @override
  Widget build(BuildContext context) {
    final active = selectedPanel;
    final targets = <Widget>[
      if (active?.panel.showSwitch == true)
        Expanded(
          child: DButton(
            key: const ValueKey('sidebar-panel-switch-main'),
            label: const Text('Forum'),
            icon: const DIcon(DIcons.shuffle, size: 14),
            onPressed: active!.panel.onClose,
            size: DButtonSize.small,
            alignment: Alignment.centerLeft,
          ),
        ),
      for (final candidate in panels)
        if (!candidate.panel.active && candidate.panel.showSwitch)
          Expanded(
            child: DButton(
              key: ValueKey('sidebar-panel-switch-${candidate.owner.value}'),
              label: Text(candidate.panel.label),
              icon: DIcon(candidate.panel.icon, size: 14),
              onPressed: candidate.panel.onOpen,
              size: DButtonSize.small,
              alignment: Alignment.centerLeft,
            ),
          ),
    ];
    if (targets.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(spacing: 6, children: targets),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.name, required this.showUserMenu});

  final String name;
  final bool showUserMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const DIcon(DIcons.trashCan, size: 18),
          style: MenuItemButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            iconColor: theme.colorScheme.error,
          ),
          onPressed: () async {
            final instance = ShellScope.read(context).currentInstance;
            if (instance != null) {
              await confirmInstanceRemoval(context, instance);
            }
          },
          child: const Text('Remove forum'),
        ),
      ],
      builder: (context, menu, child) => InkWell(
        onTap: menu.open,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(ShellPanel.cornerRadius),
        ),
        child: child,
      ),
      child: Container(
        height: shellHeaderHeight,
        padding: EdgeInsets.only(left: 12, right: showUserMenu ? 8 : 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.shell.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            DIcon(
              DIcons.chevronDown,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            if (showUserMenu) ...[
              const SizedBox(width: 4),
              ...PluginScope.of(context).registry.shellHeaderActions(
                context,
                surface: PluginHeaderSurface.content,
                compact: true,
                ringColor: theme.shell.sidebar,
              ),
              const UserMenuButton(),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatefulWidget {
  const _Section({
    super.key,
    required this.siteUrl,
    required this.section,
    required this.first,
    required this.store,
    required this.selectedId,
    required this.badgeFor,
    required this.onSelect,
    this.insertedDestination,
    this.insertAfterDestinationId,
  });

  final String siteUrl;
  final SidebarSection section;
  final bool first;
  final SidebarSectionStore store;
  final String? selectedId;
  final SidebarBadge Function(String destinationId) badgeFor;
  final ValueChanged<SidebarDestination> onSelect;
  final SidebarDestination? insertedDestination;
  final String? insertAfterDestinationId;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _collapsed = false;
  int _restoreGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.section.collapsible) unawaited(_restore());
  }

  @override
  void didUpdateWidget(_Section oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.section.id != widget.section.id ||
        oldWidget.section.collapsible != widget.section.collapsible ||
        !identical(oldWidget.store, widget.store)) {
      _collapsed = false;
      _restoreGeneration++;
      if (widget.section.collapsible) unawaited(_restore());
    }
  }

  Future<void> _restore() async {
    final generation = ++_restoreGeneration;
    final collapsed = await widget.store.read(
      siteUrl: widget.siteUrl,
      sectionId: widget.section.id,
    );
    if (!mounted || generation != _restoreGeneration) return;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  void _toggle() {
    _restoreGeneration++;
    final collapsed = !_collapsed;
    setState(() => _collapsed = collapsed);
    unawaited(
      widget.store.write(
        siteUrl: widget.siteUrl,
        sectionId: widget.section.id,
        collapsed: collapsed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final rowHeight = _SidebarSpacing.rowHeight(context);
    final sectionHeaderHeight = _SidebarSpacing.sectionHeaderHeight(context);
    final sectionPadding = _SidebarSpacing.sectionPadding(context);
    final sectionRows = !section.collapsible || !_collapsed
        ? <SidebarDestination>[
            ...section.destinations,
            for (final destination in section.moreDestinations)
              if (destination.id == widget.selectedId) destination,
            if (section.moreDestinations.isNotEmpty) _moreDestination,
          ]
        : const <SidebarDestination>[];
    final menuDestinations = [
      for (final destination in section.moreDestinations)
        if (destination.id != widget.selectedId) destination,
    ];
    final rows = switch ((
      widget.insertedDestination,
      widget.insertAfterDestinationId,
    )) {
      (final inserted?, final after?) => <SidebarDestination>[
        for (final destination in sectionRows) ...[
          destination,
          if (destination.id == after) inserted,
        ],
      ],
      _ => sectionRows,
    };
    final rowIndexes = <String, int>{
      for (var index = 0; index < rows.length; index++) rows[index].id: index,
    };

    final bottomSectionPadding = rows.isEmpty
        ? sectionPadding
        : sectionPadding > _SidebarSpacing.rowGap
        ? sectionPadding - _SidebarSpacing.rowGap
        : 0.0;

    // Section shells remain eager so their persisted collapse state is restored
    // before scrolling. Only the fixed-height destination rows are lazy.
    return SliverMainAxisGroup(
      slivers: [
        if (!widget.first && sectionPadding > 0) ...[
          SliverToBoxAdapter(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(
                horizontal: _SidebarSpacing.wrapperHorizontalPadding,
              ),
              color: Theme.of(context).shell.divider,
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: sectionPadding)),
        ],
        SliverToBoxAdapter(
          child: section.showHeader
              ? _SectionHeader(
                  section: section,
                  collapsed: _collapsed,
                  onToggle: section.collapsible ? _toggle : null,
                  rowHeight: sectionHeaderHeight,
                )
              : const SizedBox.shrink(),
        ),
        if (rows.isNotEmpty)
          SliverFixedExtentList.builder(
            itemExtent: rowHeight + _SidebarSpacing.rowGap,
            itemCount: rows.length,
            // Separate section delegates would otherwise restart at zero.
            addSemanticIndexes: false,
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? rowIndexes[key.value] : null,
            itemBuilder: (context, index) {
              final destination = rows[index];
              if (destination.id == _moreDestinationId) {
                return _MoreDestinationsTile(
                  key: ValueKey(destination.id),
                  destinations: menuDestinations,
                  rowHeight: rowHeight,
                  gapAfter: _SidebarSpacing.rowGap,
                  onSelect: widget.onSelect,
                );
              }
              return _DestinationTile(
                key: ValueKey(destination.id),
                destination: destination,
                selected: destination.id == widget.selectedId,
                badge: widget.badgeFor(destination.id),
                rowHeight: rowHeight,
                gapAfter: _SidebarSpacing.rowGap,
                onTap: destination.onTap ?? () => widget.onSelect(destination),
              );
            },
          ),
        if (bottomSectionPadding > 0)
          SliverToBoxAdapter(child: SizedBox(height: bottomSectionPadding)),
      ],
    );
  }
}

class _MoreDestinationsTile extends StatelessWidget {
  const _MoreDestinationsTile({
    super.key,
    required this.destinations,
    required this.rowHeight,
    required this.gapAfter,
    required this.onSelect,
  });

  final List<SidebarDestination> destinations;
  final double rowHeight;
  final double gapAfter;
  final ValueChanged<SidebarDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      menuChildren: [
        for (final destination in destinations)
          MenuItemButton(
            leadingIcon: DIcon(
              destination.icon,
              size: 18,
              color: destination.iconColor,
            ),
            onPressed: destination.enabled
                ? destination.onTap ?? () => onSelect(destination)
                : null,
            child: Text(destination.label),
          ),
      ],
      builder: (context, menu, child) => _DestinationTile(
        destination: _moreDestination,
        selected: false,
        badge: SidebarBadge.none,
        rowHeight: rowHeight,
        gapAfter: gapAfter,
        onTap: menu.open,
      ),
    );
  }
}

class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.section,
    required this.collapsed,
    required this.onToggle,
    required this.rowHeight,
  });

  final SidebarSection section;
  final bool collapsed;
  final VoidCallback? onToggle;
  final double rowHeight;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  static const double _actionExtent = 24;

  bool _titleHovered = false;
  bool _chevronHovered = false;

  void _setTitleHovered(bool hovered) {
    if (_titleHovered == hovered) return;
    setState(() => _titleHovered = hovered);
  }

  void _setChevronHovered(bool hovered) {
    if (_chevronHovered == hovered) return;
    setState(() => _chevronHovered = hovered);
  }

  @override
  void didUpdateWidget(_SectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onToggle == null) {
      _titleHovered = false;
      _chevronHovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final toggle = widget.onToggle;
    final title = _SectionTitle(
      section: section,
      rowHeight: widget.rowHeight,
      color: _titleHovered
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
    );
    final iconStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal:
            _SidebarSpacing.wrapperHorizontalPadding +
            _SidebarSpacing.rowHorizontalPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: toggle == null
                ? title
                : InkWell(
                    excludeFromSemantics: true,
                    borderRadius: BorderRadius.circular(4),
                    onHover: _setTitleHovered,
                    onTap: toggle,
                    child: title,
                  ),
          ),
          if (section.onAction case final action?)
            _SectionAction(section: section, action: action, style: iconStyle),
          if (toggle != null)
            Tooltip(
              message:
                  '${widget.collapsed ? 'Expand' : 'Collapse'} ${section.title}',
              child: Semantics(
                button: true,
                expanded: !widget.collapsed,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onHover: _setChevronHovered,
                  onTap: toggle,
                  child: SizedBox.square(
                    dimension: _actionExtent,
                    child: Center(
                      child: DIcon(
                        widget.collapsed
                            ? DIcons.chevronRight
                            : DIcons.chevronDown,
                        size: 11,
                        color: _chevronHovered
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.section,
    required this.action,
    required this.style,
  });

  final SidebarSection section;
  final VoidCallback action;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      constraints: const BoxConstraints.tightFor(
        width: _SectionHeaderState._actionExtent,
        height: _SectionHeaderState._actionExtent,
      ),
      padding: EdgeInsets.zero,
      style: style,
      onPressed: action,
      icon: DIcon(section.actionIcon ?? DIcons.plus, size: 15),
    );
    final label = section.actionLabel;
    if (label == null) return button;
    final shortcut = section.actionShortcut;
    return DTooltip(
      message: label,
      shortcut: shortcut == null ? null : DShortcut(shortcut),
      child: button,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.section,
    required this.rowHeight,
    required this.color,
  });

  final SidebarSection section;
  final double rowHeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: rowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          section.title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: _SidebarSpacing.sectionHeaderFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _DestinationTile extends StatefulWidget {
  const _DestinationTile({
    super.key,
    required this.destination,
    required this.selected,
    required this.badge,
    required this.rowHeight,
    required this.gapAfter,
    required this.onTap,
  });

  final SidebarDestination destination;
  final bool selected;
  final SidebarBadge badge;
  final double rowHeight;
  final double gapAfter;
  final VoidCallback onTap;

  @override
  State<_DestinationTile> createState() => _DestinationTileState();
}

class _DestinationTileState extends State<_DestinationTile> {
  bool _hovered = false;
  bool _hoverActionFocused = false;

  SidebarDestination get destination => widget.destination;
  bool get selected => widget.selected;
  SidebarBadge get badge => widget.badge;
  VoidCallback get onTap => widget.onTap;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  void _setHoverActionFocused(bool focused) {
    if (_hoverActionFocused == focused) return;
    setState(() => _hoverActionFocused = focused);
  }

  Widget _prefixArt(BuildContext context, Color foreground) {
    final theme = Theme.of(context);
    final artSize = _SidebarSpacing.prefixArtSize(context);

    if (destination.prefixBuilder case final builder?) {
      return builder(context, artSize);
    }

    if (destination.avatarUrl case final url?) {
      return ClipOval(
        child: SizedBox(
          width: artSize,
          height: artSize,
          child: AvatarImage(
            url: url,
            size: artSize,
            fallback: ColoredBox(color: theme.shell.floating),
          ),
        ),
      );
    }

    if (destination.emoji case final emoji?) {
      final controller = ShellScope.read(context);
      final siteUrl = controller.currentInstance?.url;
      if (siteUrl != null) {
        return EmojiImage(
          url: controller.emojiUrlFor(siteUrl, emoji),
          size: _SidebarSpacing.prefixIconSize(context),
          alt: ':$emoji:',
          style: theme.textTheme.labelSmall,
        );
      }
    }

    if (destination.color case final color?) {
      final parentColor = destination.parentColor;
      return Container(
        key: ValueKey('sidebar-prefix-${destination.id}'),
        width: _SidebarSpacing.isCompact(context) ? 12 : 10,
        height: _SidebarSpacing.isCompact(context) ? 12 : 10,
        decoration: BoxDecoration(
          color: parentColor == null ? color : null,
          gradient: parentColor == null
              ? null
              : LinearGradient(
                  colors: [parentColor, color],
                  stops: const [0.5, 0.5],
                ),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return DIcon(
      destination.icon,
      size: _SidebarSpacing.prefixIconSize(context),
      color: destination.iconColor ?? foreground,
    );
  }

  Widget _prefix(BuildContext context, Color foreground) {
    final art = _prefixArt(context, foreground);
    final badge = destination.prefixBadgeIcon;
    if (badge == null) return art;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        art,
        Positioned(
          top: -3,
          right: -3,
          child: DIcon(badge, size: 9, color: foreground),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.shell.selectedForeground
        : destination.enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.disabledColor;

    // A destination built fresh from live state already has the answer; core's
    // `const` sections cannot carry a moving number and ask the shell instead.
    final badge = destination.badge ?? this.badge;

    final tile = Padding(
      padding: EdgeInsets.only(
        left:
            _SidebarSpacing.wrapperHorizontalPadding +
            destination.indent * _SidebarSpacing.indent(context),
        right: _SidebarSpacing.wrapperHorizontalPadding,
        bottom: widget.gapAfter,
      ),
      child: InkWell(
        onTap: destination.enabled ? onTap : null,
        mouseCursor: WidgetStateMouseCursor.clickable,
        onLongPress: destination.enabled && context.isTouch
            ? switch (destination.onLongPress) {
                final action? => () => action(context),
                null => null,
              }
            : null,
        onHover: destination.enabled ? _setHovered : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: widget.rowHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: _SidebarSpacing.rowHorizontalPadding,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? theme.shell.hover
                : selected
                ? theme.shell.selected
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _SidebarSpacing.prefixWidth,
                height: _SidebarSpacing.prefixWidth,
                child: Center(child: _prefix(context, foreground)),
              ),
              const SizedBox(width: _SidebarSpacing.prefixGap),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontSize: _SidebarSpacing.labelFontSize(context),
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (destination.labelSuffixBuilder case final builder?)
                      builder(context, 14),
                    if (badge.isVisible && badge.dot)
                      Container(
                        key: ValueKey('sidebar-badge-${destination.id}'),
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: badge.urgent
                              ? theme.discourse.success
                              : theme.discourse.unreadIndicator,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              if (destination.trailingLabel case final label?)
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
                  ),
                ),
              if (destination.onSecondaryTap case final action?)
                IconButton(
                  constraints: BoxConstraints.tightFor(
                    width: _SidebarSpacing.prefixWidth,
                    height: widget.rowHeight,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Open ${destination.label}',
                  onPressed: action,
                  icon: DIcon(
                    destination.trailingIcon ?? DIcons.chevronRight,
                    size: 14,
                    color: foreground,
                  ),
                ),
              if (badge.isVisible && !badge.dot)
                Text(
                  '${badge.count}',
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              if (!context.isTouch)
                if (destination.hoverActionBuilder case final builder?)
                  Focus(
                    onFocusChange: _setHoverActionFocused,
                    child: AnimatedOpacity(
                      key: ValueKey('sidebar-hover-action-${destination.id}'),
                      opacity: _hovered || _hoverActionFocused ? 1 : 0,
                      duration: const Duration(milliseconds: 100),
                      child: IgnorePointer(
                        ignoring: !_hovered && !_hoverActionFocused,
                        child: builder(context),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
    if (!destination.enabled) return tile;
    if (destination.url case final url?) {
      return LinkTarget(url: url, title: destination.label, child: tile);
    }
    if (destination.onTap != null) return tile;
    return LinkTarget.content(
      content: destination.id == 'groups'
          ? ContentRoute.group(const GroupRoute.directory())
          : ContentRoute.fromDestination(destination),
      child: tile,
    );
  }
}
