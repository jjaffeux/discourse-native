import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../models/forum_workspace.dart';
import '../models/sidebar.dart';
import '../plugins/chat/chat_plugin.dart';
import '../plugins/chat/chat_route.dart';
import '../plugins/chat/chat_user_avatar.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'emoji.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';

/// Presentation data for one tab in a forum's horizontal tab bar.
///
/// Prefix precedence matches the instance sidebar: avatar, emoji, category
/// colour, then [icon]. Emoji URLs are resolved by the caller because custom
/// emoji belong to the forum that owns the tab.
@immutable
class ForumTabItem {
  const ForumTabItem({
    required this.id,
    required this.title,
    required this.icon,
    this.color,
    this.parentColor,
    this.iconColor,
    this.avatarUrl,
    this.avatarUserId,
    this.emojiUrl,
    this.emojiName,
    this.badge = SidebarBadge.none,
  }) : assert(
         (emojiUrl == null) == (emojiName == null),
         'emojiUrl and emojiName must be provided together',
       );

  final String id;
  final String title;
  final DIconData icon;
  final Color? color;
  final Color? parentColor;
  final Color? iconColor;
  final String? avatarUrl;
  final int? avatarUserId;
  final String? emojiUrl;
  final String? emojiName;
  final SidebarBadge badge;
}

/// The horizontal, forum-scoped tab bar shown above the main content header.
///
/// The caller owns the lifecycle. Tabs share the available width between the
/// experiment's 88px and 205px bounds, then scroll horizontally when they no
/// longer fit. The add action stays fixed and reachable at the trailing edge.
class ForumTabsBar extends StatefulWidget {
  ForumTabsBar({
    super.key,
    required this.forumName,
    required this.items,
    required this.selectedId,
    required this.onAdd,
    required this.onSelect,
    required this.onClose,
  }) : assert(items.isNotEmpty),
       assert(items.any((item) => item.id == selectedId));

  static const double height = shellHeaderHeight;

  /// Compact visuals still need an unambiguous finger and switch target.
  static const double minimumActionTarget = 44;

  /// Leaves a useful selection target beside the 44px close action.
  static const double minimumTabWidth = 88;

  final String forumName;
  final List<ForumTabItem> items;
  final String selectedId;
  final VoidCallback? onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  State<ForumTabsBar> createState() => _ForumTabsBarState();
}

class _ForumTabsBarState extends State<ForumTabsBar> {
  final Map<String, GlobalKey> _itemKeys = {};
  double? _lastViewportWidth;

  @override
  void initState() {
    super.initState();
    _scheduleRevealSelected();
  }

  @override
  void didUpdateWidget(ForumTabsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = {for (final item in widget.items) item.id};
    _itemKeys.removeWhere((id, _) => !liveIds.contains(id));
    var sameIds = oldWidget.items.length == widget.items.length;
    for (var index = 0; sameIds && index < widget.items.length; index++) {
      sameIds = oldWidget.items[index].id == widget.items[index].id;
    }
    if (oldWidget.selectedId != widget.selectedId || !sameIds) {
      _scheduleRevealSelected();
    }
  }

  void _scheduleRevealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = _itemKeys[widget.selectedId]?.currentContext;
      if (selectedContext == null) return;
      final reducedMotion =
          MediaQuery.maybeOf(selectedContext)?.disableAnimations ?? false;
      unawaited(
        Scrollable.ensureVisible(
          selectedContext,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('forum-tabs-bar'),
      height: ForumTabsBar.height,
      padding: const EdgeInsets.fromLTRB(0, 4, 5, 0),
      decoration: BoxDecoration(
        color: theme.shell.sidebar,
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_lastViewportWidth != constraints.maxWidth) {
            _lastViewportWidth = constraints.maxWidth;
            _scheduleRevealSelected();
          }
          const addWidth = ForumTabsBar.minimumActionTarget;
          const gap = 1.0;
          final tabViewportWidth = math.max(
            0.0,
            constraints.maxWidth - addWidth - gap,
          );
          final gapsWidth = math.max(0, widget.items.length - 1) * gap;
          final equalShare = widget.items.isEmpty
              ? 70.0
              : (tabViewportWidth - gapsWidth) / widget.items.length;
          final tabWidth = equalShare.clamp(
            ForumTabsBar.minimumTabWidth,
            205.0,
          );

          return Row(
            children: [
              Expanded(
                child: ClipRect(
                  child: SingleChildScrollView(
                    key: const ValueKey('forum-tabs-scroll'),
                    scrollDirection: Axis.horizontal,
                    child: Semantics(
                      role: SemanticsRole.tabBar,
                      container: true,
                      explicitChildNodes: true,
                      label: 'Open tabs in ${widget.forumName}',
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < widget.items.length;
                            index++
                          ) ...[
                            SizedBox(
                              key: _itemKeys.putIfAbsent(
                                widget.items[index].id,
                                GlobalKey.new,
                              ),
                              width: tabWidth,
                              child: _ForumTab(
                                item: widget.items[index],
                                selected:
                                    widget.items[index].id == widget.selectedId,
                                onSelect: () =>
                                    widget.onSelect(widget.items[index].id),
                                onClose: () =>
                                    widget.onClose(widget.items[index].id),
                              ),
                            ),
                            if (index != widget.items.length - 1)
                              const SizedBox(width: gap),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: gap),
              _NewTabButton(onPressed: widget.onAdd),
            ],
          );
        },
      ),
    );
  }
}

class _NewTabButton extends StatelessWidget {
  const _NewTabButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = onPressed == null
        ? 'Close a tab before opening another'
        : 'Open a new tab';
    return Semantics(
      key: const ValueKey('forum-tabs-add'),
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: SizedBox(
            width: ForumTabsBar.minimumActionTarget,
            height: ForumTabsBar.minimumActionTarget,
            child: IconButton(
              constraints: const BoxConstraints.expand(),
              padding: EdgeInsets.zero,
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.hovered)
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.hovered)
                      ? theme.shell.hover
                      : Colors.transparent,
                ),
              ),
              onPressed: onPressed,
              icon: const DIcon(DIcons.plus, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForumTab extends StatefulWidget {
  const _ForumTab({
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final ForumTabItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_ForumTab> createState() => _ForumTabState();
}

class _ForumTabState extends State<_ForumTab> {
  bool _hovered = false;
  bool _selectedOnPointerDown = false;

  void _handleTapDown(TapDownDetails _) {
    _selectedOnPointerDown = true;
    widget.onSelect();
  }

  void _handleTap() {
    if (_selectedOnPointerDown) {
      _selectedOnPointerDown = false;
      return;
    }
    // Keyboard activation has no pointer-down gesture, so it still reaches
    // the same selection command through InkWell's normal tap action.
    widget.onSelect();
  }

  void _handleTapCancel() {
    _selectedOnPointerDown = false;
  }

  String get _selectionSemanticsLabel {
    final badge = widget.item.badge;
    if (!badge.isVisible) return widget.item.title;
    if (badge.dot) {
      return '${widget.item.title}, '
          '${badge.urgent ? 'urgent unread activity' : 'unread activity'}';
    }
    return '${widget.item.title}, ${badge.count} '
        '${badge.count == 1 ? 'unread item' : 'unread items'}';
  }

  Widget _prefix(BuildContext context, Color foreground) {
    final item = widget.item;
    final theme = Theme.of(context);

    if (item.avatarUrl case final url?) {
      final siteUrl = ShellScope.read(context).currentInstance?.url;
      final userId = item.avatarUserId;
      if (siteUrl != null && userId != null) {
        return ChatUserAvatar(
          siteUrl: siteUrl,
          userId: userId,
          url: url,
          size: 15,
          fallback: ColoredBox(color: theme.shell.floating),
        );
      }
      return ClipOval(
        child: SizedBox.square(
          dimension: 16,
          child: AvatarImage(
            url: url,
            size: 16,
            fallback: ColoredBox(color: theme.shell.floating),
          ),
        ),
      );
    }

    if ((item.emojiUrl, item.emojiName) case (final url?, final name?)) {
      return EmojiImage(
        url: url,
        size: 15,
        alt: ':$name:',
        style: theme.textTheme.labelSmall,
      );
    }

    if (item.color case final color?) {
      final parentColor = item.parentColor;
      return Container(
        key: ValueKey('forum-tab-prefix-${item.id}'),
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

    return DIcon(item.icon, size: 15, color: item.iconColor ?? foreground);
  }

  Widget _badge(BuildContext context) {
    final badge = widget.item.badge;
    if (!badge.isVisible) return const SizedBox.shrink();
    final theme = Theme.of(context);

    if (badge.dot) {
      return Container(
        key: ValueKey('forum-tab-badge-${widget.item.id}'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: badge.urgent
              ? theme.discourse.success
              : theme.discourse.unreadIndicator,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      key: ValueKey('forum-tab-badge-${widget.item.id}'),
      height: 18,
      constraints: const BoxConstraints(minWidth: 19),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badge.urgent ? theme.colorScheme.error : theme.shell.selected,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${badge.count}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: badge.urgent
              ? theme.colorScheme.onError
              : theme.colorScheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  bool _badgeFits(double selectWidth) {
    final badge = widget.item.badge;
    if (!badge.isVisible) return false;
    if (badge.dot) return selectWidth >= 45;
    final estimatedBadgeWidth = math.max(
      19,
      badge.count.toString().length * 6 + 10,
    );
    // Select padding, prefix and its gap consume 36px before label or badge.
    return selectWidth >= 36 + estimatedBadgeWidth;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = widget.selected || _hovered
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    final closeLabel = 'Close ${widget.item.title}';

    return Semantics(
      key: ValueKey('forum-tab-${widget.item.id}'),
      role: SemanticsRole.tab,
      container: true,
      explicitChildNodes: true,
      selected: widget.selected,
      label: _selectionSemanticsLabel,
      onTap: widget.onSelect,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          key: ValueKey('forum-tab-item-${widget.item.id}'),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.shell.content
                : _hovered
                ? theme.shell.hover
                : Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: InkWell(
                        // Desktop tabs conventionally activate on mouse-down.
                        // Waiting for the full tap gesture makes a fast local
                        // context switch feel needlessly remote.
                        onTapDown: _handleTapDown,
                        onTap: _handleTap,
                        onTapCancel: _handleTapCancel,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(7),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) => Padding(
                            padding: const EdgeInsets.fromLTRB(9, 0, 5, 0),
                            child: Row(
                              children: [
                                SizedBox.square(
                                  dimension: 15,
                                  child: Center(
                                    child: _prefix(context, foreground),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    widget.item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: foreground,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                        ),
                                  ),
                                ),
                                if (_badgeFits(constraints.maxWidth))
                                  _badge(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    key: ValueKey('forum-tab-close-${widget.item.id}'),
                    container: true,
                    button: true,
                    label: closeLabel,
                    onTap: widget.onClose,
                    child: ExcludeSemantics(
                      child: Tooltip(
                        message: closeLabel,
                        excludeFromSemantics: true,
                        child: SizedBox(
                          width: ForumTabsBar.minimumActionTarget,
                          height: double.infinity,
                          child: IconButton(
                            constraints: const BoxConstraints.expand(),
                            padding: EdgeInsets.zero,
                            style: ButtonStyle(
                              shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.hovered)
                                    ? theme.shell.selected
                                    : Colors.transparent,
                              ),
                            ),
                            onPressed: widget.onClose,
                            icon: DIcon(
                              DIcons.xmark,
                              size: 13,
                              color: foreground,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.selected)
                Positioned(
                  left: 9,
                  right: 9,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      key: ValueKey('forum-tab-indicator-${widget.item.id}'),
                      height: 2,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
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

@immutable
final class _CurrentForumTabsSnapshot {
  const _CurrentForumTabsSnapshot({
    required this.siteUrl,
    required this.forumName,
    required this.tabs,
    required this.activeTabId,
    required this.presentationToken,
  });

  final String? siteUrl;
  final String? forumName;
  final List<ForumTab> tabs;
  final String? activeTabId;
  final Object? presentationToken;

  @override
  bool operator ==(Object other) =>
      other is _CurrentForumTabsSnapshot &&
      siteUrl == other.siteUrl &&
      forumName == other.forumName &&
      identical(tabs, other.tabs) &&
      activeTabId == other.activeTabId &&
      identical(presentationToken, other.presentationToken);

  @override
  int get hashCode => Object.hash(
    siteUrl,
    forumName,
    identityHashCode(tabs),
    activeTabId,
    identityHashCode(presentationToken),
  );
}

/// Connects [ForumTabsBar] to the selected forum and its live chat metadata.
class CurrentForumTabsBar extends StatelessWidget {
  const CurrentForumTabsBar({super.key});

  @override
  Widget build(BuildContext context) =>
      ShellSelector<_CurrentForumTabsSnapshot>(
        select: (controller) {
          final instance = controller.currentInstance;
          return _CurrentForumTabsSnapshot(
            siteUrl: instance?.url,
            forumName: instance?.title,
            tabs: controller.tabsForCurrentForum,
            activeTabId: controller.activeTabId,
            presentationToken: instance == null
                ? null
                : controller.presentationTokenFor(instance.url),
          );
        },
        builder: (context, state, _) {
          final siteUrl = state.siteUrl;
          final forumName = state.forumName;
          final activeTabId = state.activeTabId;
          if (siteUrl == null ||
              forumName == null ||
              activeTabId == null ||
              state.tabs.isEmpty) {
            return const SizedBox.shrink();
          }

          final controller = ShellScope.read(context);
          return ListenableBuilder(
            listenable: controller.chat,
            builder: (context, _) {
              ForumTabItem itemFor(ForumTab tab) {
                final route = tab.currentContent;
                final chatRoute = ChatRoute.parse(route.id);
                if (chatRoute != null) {
                  final channel = controller.chat.channel(
                    siteUrl,
                    chatRoute.channelId,
                  );
                  if (channel != null) {
                    final destination = ChatPlugin.destination(channel);
                    final emoji = destination.emoji;
                    return ForumTabItem(
                      id: tab.id,
                      title: destination.label,
                      icon: destination.icon,
                      color: destination.color,
                      parentColor: destination.parentColor,
                      iconColor: destination.iconColor,
                      avatarUrl: destination.avatarUrl,
                      avatarUserId: destination.avatarUserId,
                      emojiUrl: emoji == null
                          ? null
                          : controller.emojiUrlFor(siteUrl, emoji),
                      emojiName: emoji,
                      badge: destination.badge ?? SidebarBadge.none,
                    );
                  }
                }

                return ForumTabItem(
                  id: tab.id,
                  title: route.title,
                  icon: route.icon,
                  color: route.color,
                );
              }

              return ForumTabsBar(
                key: ValueKey(('forum-tabs', siteUrl)),
                forumName: forumName,
                items: [for (final tab in state.tabs) itemFor(tab)],
                selectedId: activeTabId,
                onAdd: controller.canCreateTab ? controller.createTab : null,
                onSelect: controller.selectTab,
                onClose: controller.closeTab,
              );
            },
          );
        },
      );
}
