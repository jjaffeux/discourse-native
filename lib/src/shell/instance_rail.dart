import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'add_instance_sheet.dart';
import 'avatar_image.dart';
import 'instance_actions.dart';
import 'shell_scope.dart';

/// The far-left column of Discourse instances. Visible at every window size,
/// including on phones.
class InstanceRail extends StatelessWidget {
  const InstanceRail({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.of(context);

    return ColoredBox(
      color: theme.shell.rail,
      child: SafeArea(
        right: false,
        // The add button trails the instances inside the scrollable list, the
        // way Discord does it, rather than being pinned to the bottom.
        child: ListView.builder(
          // The traffic lights are cleared by the title bar above the shell, so
          // the rail only needs its own padding here.
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: controller.instances.length + 1,
          itemBuilder: (context, index) {
            if (index == controller.instances.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Center(child: _AddInstanceButton()),
              );
            }
            final instance = controller.instances[index];
            return _RailItem(
              instance: instance,
              selected: index == controller.instanceIndex,
              badgeCount: controller.railBadgeFor(instance),
              onTap: () => controller.selectInstance(index),
            );
          },
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.instance,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  final DiscourseInstance instance;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Discord-style selection pill, growing out of the left edge.
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 4,
            height: selected ? 32 : 0,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
          Center(
            child: InstanceActions(
              instance: instance,
              child: Tooltip(
                message: '${instance.title}\n${instance.host}',
                waitDuration: const Duration(milliseconds: 500),
                // Hovering still shows it — that path ignores the trigger mode
                // — but holding the item is how the actions are reached on a
                // touch screen, and the tooltip must not answer that too.
                triggerMode: TooltipTriggerMode.manual,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? instance.accentColor
                              : instance.accentColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(
                            selected ? 14 : 22,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _InstanceAvatar(
                          instance: instance,
                          selected: selected,
                        ),
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _UnreadBadge(count: badgeCount),
                        ),
                    ],
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

/// The site's own icon, falling back to a monogram while it loads or if the
/// site does not publish one.
class _InstanceAvatar extends StatelessWidget {
  const _InstanceAvatar({required this.instance, required this.selected});

  final DiscourseInstance instance;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final monogram = Center(
      child: Text(
        instance.monogram,
        style: theme.textTheme.labelLarge?.copyWith(
          color: selected ? Colors.white : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return AvatarImage(url: instance.iconUrl, size: 44, fallback: monogram);
  }
}

class _AddInstanceButton extends StatelessWidget {
  const _AddInstanceButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Add a Discourse site',
      child: InkWell(
        onTap: () => showAddInstanceSheet(context),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
          ),
          child: DIcon(DIcons.plus, size: 22, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.shell.rail, width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
