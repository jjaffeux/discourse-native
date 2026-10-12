import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

/// A filter in a title-bar menu. Counts represent unread items, never total rows.
class DesktopHeaderMenuFilter<T extends Object> {
  const DesktopHeaderMenuFilter(
    this.value,
    this.label, {
    this.unread = 0,
    this.key,
  });
  final T value;
  final String label;
  final int unread;
  final Key? key;
}

/// Shared chat/notification dropdown composition using Native interaction owners.
class DesktopHeaderMenu<T extends Object> extends StatelessWidget {
  const DesktopHeaderMenu({
    super.key,
    required this.title,
    required this.action,
    required this.onAction,
    required this.filters,
    required this.value,
    required this.onChanged,
    required this.child,
    this.busy = false,
    this.controlsKey,
  });

  final String title;
  final String action;
  final VoidCallback? onAction;
  final List<DesktopHeaderMenuFilter<T>> filters;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget child;
  final bool busy;

  /// Resets account-bound gestures without replacing the displayed feed.
  final Key? controlsKey;

  static const double width = 400;

  static bool isActiveOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DesktopHeaderMenuScope>() !=
      null;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(
      460,
      math.max(120, MediaQuery.sizeOf(context).height - 130),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 6, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Flexible(
                child: DButton(
                  key: controlsKey,
                  label: Text(action, softWrap: true),
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  loading: busy,
                  onPressed: onAction,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: DToggleGroup<T>(
            key: controlsKey,
            values: [value],
            onChanged: (values) => onChanged(values.single),
            onItemActivated: (activated) {
              if (activated == value) onChanged(activated);
            },
            allowEmptySelection: false,
            scrollable: true,
            size: DToggleSize.small,
            variant: DToggleVariant.outline,
            spacing: 1.5,
            semanticLabel: title,
            items: [
              for (final filter in filters)
                DToggleGroupItem(
                  value: filter.value,
                  semanticLabel: filter.unread > 0
                      ? context.l10n.unreadUsermenu(
                          filter.label,
                          '${filter.unread}',
                        )
                      : filter.label,
                  visualStyle: const DToggleVisualStyle(
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: KeyedSubtree(
                    key: filter.key,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Text(filter.label),
                        if (filter.unread > 0)
                          Text(filter.unread > 99 ? '99+' : '${filter.unread}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const DSeparator(space: 1),
        Expanded(child: _DesktopHeaderMenuScope(child: child)),
      ],
    ),
  );
}

/// One shared row geometry for title-bar chat and notification feeds.
class DesktopHeaderMenuRow extends StatelessWidget {
  const DesktopHeaderMenuRow({
    super.key,
    required this.title,
    required this.onPressed,
    required this.unread,
    this.description,
    this.leading,
    this.time,
    this.count = 0,
    this.semanticLabel,
  });
  final Widget title;
  final Widget? description;
  final Widget? leading;
  final String? time;
  final int count;
  final bool unread;
  final VoidCallback onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => DItem(
    size: DItemSize.sm,
    shape: DItemShape.menu,
    padding: const EdgeInsets.all(7),
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    children: [
      if (leading != null) DItemMedia(child: leading!),
      DItemContent(
        children: [
          DItemTitle(
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: title,
                  ),
                ),
                if (time != null)
                  Text(
                    time!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
          if (description != null) DItemDescription(child: description!),
        ],
      ),
      if (unread)
        DItemActions(
          children: [
            if (count > 0)
              DBadge(child: Text(count > 99 ? '99+' : '$count'))
            else
              DNotificationDot(color: DTokens.of(context).primary),
          ],
        ),
    ],
  );
}

class _DesktopHeaderMenuScope extends InheritedWidget {
  const _DesktopHeaderMenuScope({required super.child});
  @override
  bool updateShouldNotify(_DesktopHeaderMenuScope oldWidget) => false;
}
