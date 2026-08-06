import 'package:flutter/material.dart';

import '../models/sidebar.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

/// Navigation within the selected instance. On compact layouts this fills the
/// whole area next to the rail; on wider ones it sits between the rail and the
/// main content.
class InstanceSidebar extends StatelessWidget {
  const InstanceSidebar({super.key, this.showUserMenu = false});

  /// Whether the header carries the account avatar. Only true where the
  /// sidebar is the column reaching the top right corner — on compact layouts
  /// the main content is not on screen to hold it.
  final bool showUserMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);
    final instance = controller.currentInstance;
    if (instance == null) return ColoredBox(color: theme.shell.sidebar);

    return ColoredBox(
      color: theme.shell.sidebar,
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarHeader(
              name: instance.title,
              host: instance.host,
              showUserMenu: showUserMenu,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final section in instance.sections)
                    _Section(
                      section: section,
                      selectedId: controller.destinationId,
                      badgeFor: controller.sidebarBadgeFor,
                      onSelect: controller.selectDestination,
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

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.name,
    required this.host,
    required this.showUserMenu,
  });

  final String name;
  final String host;
  final bool showUserMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      // Site switcher / site settings menu, once there is something to show.
      onTap: () {},
      // The sidebar is the panel's left column, so this header sits in the
      // panel's rounded corner — the highlight has to follow it.
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(ShellPanel.cornerRadius),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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

class _Section extends StatelessWidget {
  const _Section({
    required this.section,
    required this.selectedId,
    required this.badgeFor,
    required this.onSelect,
  });

  final SidebarSection section;
  final String? selectedId;
  final int Function(String destinationId) badgeFor;
  final ValueChanged<SidebarDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            section.title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final destination in section.destinations)
          _DestinationTile(
            destination: destination,
            selected: destination.id == selectedId,
            badgeCount: badgeFor(destination.id),
            onTap: () => onSelect(destination),
          ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.16)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (destination.color case final color?)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
              else
                DIcon(destination.icon, size: 18, color: foreground),
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
              if (badgeCount > 0)
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
                    '$badgeCount',
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
