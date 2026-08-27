import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sidebar_section_store.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
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
import 'user_status.dart';

@immutable
final class _SidebarSnapshot {
  const _SidebarSnapshot({
    required this.siteUrl,
    required this.name,
    required this.destinationId,
    required this.draftCount,
    required this.sections,
    required this.presentationToken,
  });

  final String? siteUrl;
  final String? name;
  final String? destinationId;
  final int draftCount;
  final List<SidebarSection> sections;
  final Object? presentationToken;

  @override
  bool operator ==(Object other) {
    if (other is! _SidebarSnapshot ||
        siteUrl != other.siteUrl ||
        name != other.name ||
        destinationId != other.destinationId ||
        draftCount != other.draftCount ||
        !identical(presentationToken, other.presentationToken) ||
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
    identityHashCode(presentationToken),
    Object.hashAll(sections.map(identityHashCode)),
  );
}

/// Native equivalents of the spacing tokens in core's sidebar stylesheets.
///
/// Keep these values in sync with `sidebar.scss`, `sidebar-section.scss`, and
/// `sidebar-section-link.scss` in discourse/discourse.
abstract final class _SidebarSpacing {
  static const double compactBreakpoint = 640;
  static const double wrapperVerticalPadding = 16;
  static const double wrapperHorizontalPadding = 8;
  static const double sectionVerticalPadding = 4;
  static const double rowHorizontalPadding = 4;
  static const double rowGap = 2;
  static const double prefixWidth = 24;
  static const double prefixGap = 8;
  static const double desktopRowHeight = 35.2;
  static const double compactRowHeight = 38.4;
  static const double sectionHeaderFontSize = 12.1264;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= compactBreakpoint;

  static double rowHeight(BuildContext context) =>
      isCompact(context) ? compactRowHeight : desktopRowHeight;

  static double sectionPadding(BuildContext context) =>
      isCompact(context) ? 0 : sectionVerticalPadding;
}

/// Navigation within the selected instance. On compact layouts this fills the
/// whole area next to the rail; on wider ones it sits between the rail and the
/// main content.
class InstanceSidebar extends StatelessWidget {
  const InstanceSidebar({
    super.key,
    this.showUserMenu = false,
    this.sectionStore = const SidebarSectionStore(),
  });

  /// Whether the header carries the account avatar. Only true where the
  /// sidebar is the column reaching the top right corner — on compact layouts
  /// the main content is not on screen to hold it.
  final bool showUserMenu;
  final SidebarSectionStore sectionStore;

  @override
  Widget build(BuildContext context) => ShellSelector<_SidebarSnapshot>(
    select: (controller) {
      final instance = controller.currentInstance;
      final categorySection = instance == null
          ? null
          : controller.categorySidebarSectionFor(instance.url);
      return _SidebarSnapshot(
        siteUrl: instance?.url,
        name: instance?.title,
        destinationId: controller.destinationId,
        draftCount: instance?.user?.draftCount ?? 0,
        presentationToken: instance == null
            ? null
            : controller.presentationTokenFor(instance.url),
        sections: instance == null
            ? const <SidebarSection>[]
            : [
                ...instance.sections,
                ...controller.customSidebarSectionsFor(instance.url),
                ?categorySection,
              ],
      );
    },
    builder: (context, sidebar, _) {
      final theme = Theme.of(context);
      if (sidebar.siteUrl == null) {
        return ColoredBox(color: theme.shell.sidebar);
      }
      final controller = ShellScope.read(context);

      return ColoredBox(
        color: theme.shell.sidebar,
        child: SafeArea(
          left: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarHeader(name: sidebar.name!, showUserMenu: showUserMenu),
              if (showUserMenu) const _SidebarSearchRow(),
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
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          controller.accountActivity.totalsListenable,
                          controller.draftList,
                        ]),
                        builder: (context, _) => SliverMainAxisGroup(
                          slivers: [
                            for (final (index, section)
                                in sidebar.sections.indexed)
                              _Section(
                                key: ValueKey((sidebar.siteUrl, section.id)),
                                siteUrl: sidebar.siteUrl!,
                                section: section,
                                first: index == 0,
                                store: sectionStore,
                                selectedId: sidebar.destinationId,
                                badgeFor: controller.sidebarBadgeFor,
                                onSelect: (destination) {
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
                          PluginScope.of(context).registry
                              .sidebarListenables(context),
                        ),
                        builder: (context, _) {
                          final sections = PluginScope.of(context).registry
                              .sidebarSections(context);
                          return SliverMainAxisGroup(
                            slivers: [
                              // Optional features contribute below the routes
                              // every site has, in the order `sitePlugins`
                              // lists them.
                              for (final (index, section) in sections.indexed)
                                _Section(
                                  key: ValueKey((sidebar.siteUrl, section.id)),
                                  siteUrl: sidebar.siteUrl!,
                                  section: section,
                                  first: sidebar.sections.isEmpty && index == 0,
                                  store: sectionStore,
                                  selectedId: sidebar.destinationId,
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
          ),
        ),
      );
    },
  );
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
        // The sidebar is the panel's left column, so this header sits in the
        // panel's rounded corner — the highlight has to follow it.
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(ShellPanel.cornerRadius),
        ),
        child: child,
      ),
      child: Container(
        height: shellHeaderHeight,
        // The avatar keeps the main content header's inset, so it does not
        // shift when a compact layout swaps one pane for the other.
        padding: EdgeInsets.only(left: 16, right: showUserMenu ? 8 : 16),
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
              size: 20,
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
  });

  final String siteUrl;
  final SidebarSection section;
  final bool first;
  final SidebarSectionStore store;
  final String? selectedId;
  final int Function(String destinationId) badgeFor;
  final ValueChanged<SidebarDestination> onSelect;

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
    final sectionPadding = _SidebarSpacing.sectionPadding(context);
    final rows = <({SidebarDestination destination, bool child})>[];
    if (!section.collapsible || !_collapsed) {
      for (final destination in section.destinations) {
        rows.add((destination: destination, child: false));
        for (final child in destination.children) {
          rows.add((destination: child, child: true));
        }
      }
    }
    final rowIndexes = <String, int>{
      for (var index = 0; index < rows.length; index++)
        rows[index].destination.id: index,
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
                  rowHeight: rowHeight,
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
              final row = rows[index];
              final destination = row.destination;
              return _DestinationTile(
                key: ValueKey(destination.id),
                destination: destination,
                selected: !row.child && destination.id == widget.selectedId,
                badgeCount: row.child ? 0 : widget.badgeFor(destination.id),
                rowHeight: rowHeight,
                gapAfter: _SidebarSpacing.rowGap,
                onTap:
                    destination.onTap ??
                    (row.child ? () {} : () => widget.onSelect(destination)),
              );
            },
          ),
        if (bottomSectionPadding > 0)
          SliverToBoxAdapter(child: SizedBox(height: bottomSectionPadding)),
      ],
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
            IconButton(
              constraints: const BoxConstraints.tightFor(
                width: _actionExtent,
                height: _actionExtent,
              ),
              padding: EdgeInsets.zero,
              style: iconStyle,
              tooltip: section.actionLabel,
              onPressed: action,
              icon: DIcon(section.actionIcon ?? DIcons.plus, size: 15),
            ),
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
    required this.badgeCount,
    required this.rowHeight,
    required this.gapAfter,
    required this.onTap,
  });

  final SidebarDestination destination;
  final bool selected;
  final int badgeCount;
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
  int get badgeCount => widget.badgeCount;
  VoidCallback get onTap => widget.onTap;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  void _setHoverActionFocused(bool focused) {
    if (_hoverActionFocused == focused) return;
    setState(() => _hoverActionFocused = focused);
  }

  /// A face beats a picture beats a category badge beats a glyph. Emoji before
  /// colour matches Discourse's own sidebar, which draws a channel's emoji when
  /// it has one and tints its icon with the category colour when it does not.
  Widget _prefixArt(BuildContext context, Color foreground) {
    final theme = Theme.of(context);

    if (destination.avatarUrl case final url?) {
      final siteUrl = ShellScope.read(context).currentInstance?.url;
      final userId = destination.avatarUserId;
      if (siteUrl != null && userId != null) {
        final fallback = ColoredBox(color: theme.shell.floating);
        final avatar = PluginScope.of(context).registry.userAvatar(
          context,
          siteUrl: siteUrl,
          userId: userId,
          url: url,
          size: 22,
          fallback: fallback,
        );
        if (avatar != null) return avatar;
      }
      return ClipOval(
        child: SizedBox(
          width: 22,
          height: 22,
          child: AvatarImage(
            url: url,
            size: 22,
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
          size: 16,
          alt: ':$emoji:',
          style: theme.textTheme.labelSmall,
        );
      }
    }

    if (destination.color case final color?) {
      final parentColor = destination.parentColor;
      return Container(
        key: ValueKey('sidebar-prefix-${destination.id}'),
        width: 12,
        height: 12,
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
      size: 16,
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
    final siteUrl = ShellScope.read(context).currentInstance?.url;
    final foreground = selected
        ? theme.shell.selectedForeground
        : destination.enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.disabledColor;

    // A destination built fresh from live state already has the answer; core's
    // `const` sections cannot carry a moving number and ask the shell instead.
    final badge = destination.badge ?? SidebarBadge.count(badgeCount);

    return Padding(
      padding: EdgeInsets.only(
        left:
            _SidebarSpacing.wrapperHorizontalPadding + destination.indent * 20,
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
        borderRadius: BorderRadius.circular(4),
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
            borderRadius: BorderRadius.circular(4),
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
                          fontSize: 16,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if ((siteUrl, destination.userStatus) case (
                      final siteUrl?,
                      final status?,
                    ))
                      UserStatusMessage(
                        siteUrl: siteUrl,
                        userId: destination.avatarUserId,
                        status: status,
                        size: 14,
                        leadingGap: 5,
                      ),
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
  }
}
