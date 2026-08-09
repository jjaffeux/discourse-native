import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/sidebar.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'emoji.dart';

/// Presentation data for one entry in an [OpenTabsSection].
///
/// The prefix follows the same precedence as the rest of the instance sidebar:
/// an avatar, an emoji, a category colour, then [icon]. Emoji URLs are resolved
/// by the caller because custom emoji belong to the forum that owns the tab.
@immutable
class OpenTabItem {
  const OpenTabItem({
    required this.id,
    required this.title,
    required this.icon,
    this.color,
    this.parentColor,
    this.iconColor,
    this.avatarUrl,
    this.emojiUrl,
    this.emojiName,
    this.badge = SidebarBadge.none,
  }) : assert(
         (emojiUrl == null) == (emojiName == null),
         'emojiUrl and emojiName must be provided together',
       );

  /// Stable identity used by selection and close callbacks.
  final String id;
  final String title;
  final DIconData icon;

  /// A category-style colour swatch drawn in place of [icon].
  final Color? color;

  /// When present, shares the swatch with [color] for a subcategory.
  final Color? parentColor;

  /// Tint for [icon] when the prefix is not a colour swatch.
  final Color? iconColor;

  final String? avatarUrl;

  /// An already-resolved URL for a forum's standard or custom emoji.
  final String? emojiUrl;

  /// The bare emoji name, used for accessible fallback text.
  final String? emojiName;

  final SidebarBadge badge;
}

/// The always-expanded list of tabs open for the current forum.
///
/// This widget deliberately owns presentation only. The caller owns tab
/// lifecycle and receives stable item IDs for every interaction.
class OpenTabsSection extends StatelessWidget {
  const OpenTabsSection({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onAdd,
    required this.onSelect,
    required this.onClose,
  });

  final List<OpenTabItem> items;
  final String? selectedId;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OpenTabsHeader(onAdd: onAdd),
        for (final item in items)
          _OpenTabRow(
            key: ValueKey(item.id),
            item: item,
            selected: item.id == selectedId,
            onSelect: () => onSelect(item.id),
            onClose: () => onClose(item.id),
          ),
      ],
    );
  }
}

class _OpenTabsHeader extends StatelessWidget {
  const _OpenTabsHeader({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 24,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'OPEN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('open-tabs-add'),
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            padding: EdgeInsets.zero,
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            tooltip: 'Open a new tab',
            onPressed: onAdd,
            icon: const DIcon(DIcons.plus, size: 15),
          ),
        ],
      ),
    );
  }
}

class _OpenTabRow extends StatefulWidget {
  const _OpenTabRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final OpenTabItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_OpenTabRow> createState() => _OpenTabRowState();
}

class _OpenTabRowState extends State<_OpenTabRow> {
  bool _hovered = false;
  bool _selectFocused = false;
  bool _closeFocused = false;

  bool get _hidesIdleClose => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => true,
    _ => false,
  };

  bool get _showClose =>
      widget.selected ||
      _hovered ||
      _selectFocused ||
      _closeFocused ||
      !_hidesIdleClose;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  void _setSelectFocused(bool focused) {
    if (_selectFocused == focused) return;
    setState(() => _selectFocused = focused);
  }

  void _setCloseFocused(bool focused) {
    if (_closeFocused == focused) return;
    setState(() => _closeFocused = focused);
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
      return ClipOval(
        child: SizedBox.square(
          dimension: 18,
          child: AvatarImage(
            url: url,
            size: 18,
            fallback: ColoredBox(color: theme.shell.floating),
          ),
        ),
      );
    }

    if ((item.emojiUrl, item.emojiName) case (final url?, final name?)) {
      return EmojiImage(
        url: url,
        size: 16,
        alt: ':$name:',
        style: theme.textTheme.labelSmall,
      );
    }

    if (item.color case final color?) {
      final parentColor = item.parentColor;
      return Container(
        key: ValueKey('open-tab-prefix-${item.id}'),
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

    return DIcon(item.icon, size: 18, color: item.iconColor ?? foreground);
  }

  Widget _badge(BuildContext context, Color foreground) {
    final badge = widget.item.badge;
    if (!badge.isVisible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    if (badge.dot) {
      return Container(
        key: ValueKey('open-tab-badge-${widget.item.id}'),
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: badge.urgent
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
      );
    }

    return Text(
      '${badge.count}',
      key: ValueKey('open-tab-badge-${widget.item.id}'),
      style: theme.textTheme.bodySmall?.copyWith(color: foreground),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = widget.selected
        ? theme.shell.selectedForeground
        : theme.colorScheme.onSurfaceVariant;
    final closeLabel = 'Close ${widget.item.title}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Container(
          key: ValueKey('open-tab-row-${widget.item.id}'),
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? theme.shell.hover
                : widget.selected
                ? theme.shell.selected
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: _setSelectFocused,
                  child: Semantics(
                    key: ValueKey('open-tab-${widget.item.id}'),
                    container: true,
                    button: true,
                    selected: widget.selected,
                    label: _selectionSemanticsLabel,
                    onTap: widget.onSelect,
                    child: ExcludeSemantics(
                      child: InkWell(
                        onTap: widget.onSelect,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: Center(
                                  child: _prefix(context, foreground),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: foreground,
                                    fontWeight: widget.selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              _badge(context, foreground),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Focus(
                canRequestFocus: false,
                onFocusChange: _setCloseFocused,
                child: Semantics(
                  key: ValueKey('open-tab-close-${widget.item.id}'),
                  container: true,
                  button: true,
                  label: closeLabel,
                  onTap: widget.onClose,
                  child: ExcludeSemantics(
                    child: AnimatedOpacity(
                      key: ValueKey('open-tab-close-opacity-${widget.item.id}'),
                      opacity: _showClose ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      alwaysIncludeSemantics: true,
                      child: Tooltip(
                        message: closeLabel,
                        excludeFromSemantics: true,
                        child: IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 34,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
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
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}
