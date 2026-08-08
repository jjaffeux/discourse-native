import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sidebar_section_store.dart';
import '../models/sidebar.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'emoji.dart';
import 'forum_search.dart';
import 'instance_actions.dart';
import 'open_link.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

typedef _SidebarSnapshot = ({
  String? siteUrl,
  String? name,
  String? destinationId,
  int draftCount,
  List<SidebarSection> sections,
});

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
      return (
        siteUrl: instance?.url,
        name: instance?.title,
        destinationId: controller.destinationId,
        draftCount: instance?.user?.draftCount ?? 0,
        sections: instance == null
            ? const <SidebarSection>[]
            : [
                ...instance.sections,
                ...controller.customSidebarSectionsFor(instance.url),
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
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        controller.accountActivity.totalsListenable,
                        controller.draftList,
                      ]),
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final section in sidebar.sections)
                            _Section(
                              key: ValueKey((sidebar.siteUrl, section.id)),
                              siteUrl: sidebar.siteUrl!,
                              section: section,
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
                      listenable: Listenable.merge([
                        for (final plugin in sitePlugins)
                          plugin.sidebarListenable(context),
                      ]),
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Optional features contribute below the routes every
                          // site has, in the order `sitePlugins` lists them.
                          for (final plugin in sitePlugins)
                            for (final section in plugin.sidebarSections(
                              context,
                            ))
                              _Section(
                                key: ValueKey((sidebar.siteUrl, section.id)),
                                siteUrl: sidebar.siteUrl!,
                                section: section,
                                store: sectionStore,
                                selectedId: sidebar.destinationId,
                                badgeFor: controller.sidebarBadgeFor,
                                onSelect: controller.selectDestination,
                              ),
                        ],
                      ),
                    ),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: const ForumSearch(dense: true),
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
    required this.store,
    required this.selectedId,
    required this.badgeFor,
    required this.onSelect,
  });

  final String siteUrl;
  final SidebarSection section;
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
    unawaited(_restore());
  }

  @override
  void didUpdateWidget(_Section oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.section.id != widget.section.id ||
        !identical(oldWidget.store, widget.store)) {
      _collapsed = false;
      unawaited(_restore());
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
    final theme = Theme.of(context);
    final section = widget.section;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message:
                      '${_collapsed ? 'Expand' : 'Collapse'} ${section.title}',
                  child: Semantics(
                    button: true,
                    expanded: !_collapsed,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _toggle,
                      child: SizedBox(
                        height: 32,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                section.title.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            DIcon(
                              _collapsed
                                  ? DIcons.chevronRight
                                  : DIcons.chevronDown,
                              size: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (section.onAction case final action?)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: section.actionLabel,
                  onPressed: action,
                  icon: DIcon(section.actionIcon ?? DIcons.plus, size: 15),
                ),
            ],
          ),
        ),
        if (!_collapsed)
          for (final destination in section.destinations) ...[
            _DestinationTile(
              key: ValueKey(destination.id),
              destination: destination,
              selected: destination.id == widget.selectedId,
              badgeCount: widget.badgeFor(destination.id),
              onTap: destination.onTap ?? () => widget.onSelect(destination),
            ),
            for (final child in destination.children)
              _DestinationTile(
                key: ValueKey(child.id),
                destination: child,
                selected: false,
                badgeCount: 0,
                onTap: child.onTap ?? () {},
              ),
          ],
      ],
    );
  }
}

class _DestinationTile extends StatefulWidget {
  const _DestinationTile({
    super.key,
    required this.destination,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  final SidebarDestination destination;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  State<_DestinationTile> createState() => _DestinationTileState();
}

class _DestinationTileState extends State<_DestinationTile> {
  bool _hovered = false;

  SidebarDestination get destination => widget.destination;
  bool get selected => widget.selected;
  int get badgeCount => widget.badgeCount;
  VoidCallback get onTap => widget.onTap;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  /// A face beats a picture beats a category badge beats a glyph. Emoji before
  /// colour matches Discourse's own sidebar, which draws a channel's emoji when
  /// it has one and tints its icon with the category colour when it does not.
  Widget _prefix(BuildContext context, Color foreground) {
    final theme = Theme.of(context);

    if (destination.avatarUrl case final url?) {
      return ClipOval(
        child: SizedBox(
          width: 18,
          height: 18,
          child: AvatarImage(
            url: url,
            size: 18,
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
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return DIcon(
      destination.icon,
      size: 18,
      color: destination.iconColor ?? foreground,
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
    final badge = destination.badge ?? SidebarBadge.count(badgeCount);

    return Padding(
      padding: EdgeInsets.only(
        left: 8.0 + destination.indent * 20,
        right: 8,
        top: 1,
        bottom: 1,
      ),
      child: InkWell(
        onTap: destination.enabled ? onTap : null,
        onHover: destination.enabled ? _setHovered : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                width: 18,
                height: 18,
                child: Center(child: _prefix(context, foreground)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
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
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open ${destination.label}',
                  onPressed: action,
                  icon: DIcon(
                    destination.trailingIcon ?? DIcons.chevronRight,
                    size: 14,
                    color: foreground,
                  ),
                ),
              if (badge.isVisible)
                if (badge.dot)
                  // Red for what is addressed to the reader, the quieter colour
                  // for what merely happened near them.
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: badge.urgent
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${badge.count}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onError,
                        fontWeight: FontWeight.w700,
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
