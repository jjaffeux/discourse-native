part of '../group_page.dart';

class _GroupSectionLoadingSkeleton extends StatelessWidget {
  const _GroupSectionLoadingSkeleton({
    required this.semanticsLabel,
    this.showAvatar = false,
  });

  final String semanticsLabel;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: semanticsLabel,
    color: skeletonFill(context),
    expand: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final count = math.max(1, (constraints.maxHeight / 40).ceil());
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: ContentReadingLaneBox(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < count; row++) ...[
                    if (row > 0) const DSeparator(space: 1),
                    DItem(
                      shape: DItemShape.fullWidth,
                      children: [
                        if (showAvatar)
                          const DItemMedia(
                            child: DSkeleton.circle(diameter: 40),
                          ),
                        const DItemContent(
                          spacing: DSpacing.sm,
                          children: [
                            DSkeleton(width: 150, height: 14),
                            DSkeleton(width: 100, height: 12),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

@immutable
final class _Subtab {
  const _Subtab(this.value, this.label);

  final String value;
  final String label;
}

class _SubsectionSidebar extends StatelessWidget {
  const _SubsectionSidebar({
    super.key,
    required this.title,
    required this.selected,
    required this.options,
    required this.iconFor,
    required this.onSelect,
  });

  final String title;
  final String selected;
  final List<_Subtab> options;
  final DIconData Function(String subsection) iconFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final option in options)
          _SubsectionNavigationItem(
            key: ValueKey('group-subtab-${option.value}'),
            option: option,
            icon: iconFor(option.value),
            selected: selected == option.value,
            onTap: () => onSelect(option.value),
          ),
      ],
    ),
  );
}

class _MobileSubsectionPicker extends StatelessWidget {
  const _MobileSubsectionPicker({
    super.key,
    required this.title,
    required this.selected,
    required this.options,
    required this.iconFor,
    required this.sheetOptionKeyPrefix,
    required this.currentSectionKey,
    required this.onSelect,
  });

  final String title;
  final String selected;
  final List<_Subtab> options;
  final DIconData Function(String subsection) iconFor;
  final String sheetOptionKeyPrefix;
  final String currentSectionKey;
  final ValueChanged<String> onSelect;

  Future<void> _showPicker(BuildContext context) async {
    final choice = await showShellSheet<String>(
      context: context,
      title: title,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            DItem(
              key: ValueKey('$sheetOptionKeyPrefix-${option.value}'),
              onPressed: () =>
                  DDialogClose.close<String>(sheetContext, option.value),
              selected: selected == option.value,
              children: [
                DItemMedia(child: DIcon(iconFor(option.value), size: 18)),
                DItemContent(children: [DItemTitle(child: Text(option.label))]),
                DItemActions(
                  children: [
                    if (selected == option.value)
                      const DIcon(DIcons.check, size: 16),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
    if (choice != null && choice != selected) onSelect(choice);
  }

  @override
  Widget build(BuildContext context) {
    final label = options
        .firstWhere((option) => option.value == selected)
        .label;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).shell.divider),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DItem(
          size: DItemSize.sm,
          onPressed: () => unawaited(_showPicker(context)),
          children: [
            DItemContent(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      label,
                      key: ValueKey(currentSectionKey),
                      style: TextStyle(
                        color: Theme.of(context).shell.selectedForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const DIcon(DIcons.chevronDown, size: 14),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubsectionNavigationItem extends StatelessWidget {
  const _SubsectionNavigationItem({
    super.key,
    required this.option,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final _Subtab option;
  final DIconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Material(
      color: selected ? Theme.of(context).shell.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: DItem(
        size: DItemSize.sm,
        onPressed: onTap,
        children: [
          DItemContent(
            children: [
              Row(
                children: [
                  DIcon(
                    icon,
                    size: 16,
                    color: selected
                        ? Theme.of(context).shell.selectedForeground
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: selected
                            ? Theme.of(context).shell.selectedForeground
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _GroupPageFooter extends StatelessWidget {
  const _GroupPageFooter({
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool loading;
  final String? error;
  final bool hasMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(child: DProgress(semanticsLabel: context.l10n.loading));
    }
    if (error case final message?) {
      return Column(
        children: [
          _InlineError(message: message),
          if (onLoadMore != null && hasMore)
            DButton(label: Text(context.l10n.tryAgain), onPressed: onLoadMore),
        ],
      );
    }
    if (!hasMore || onLoadMore == null) return const SizedBox.shrink();
    return ScrollPageTrigger(
      enabled: true,
      onLoad: onLoadMore!,
      child: const SizedBox.shrink(),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: DAlert(
      variant: DAlertVariant.destructive,
      icon: const DIcon(DIcons.triangleExclamation),
      description: DAlertDescription(child: Text(message)),
    ),
  );
}

class _GroupState extends StatelessWidget {
  const _GroupState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String title;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: ContentReadingLaneBox(
        child: DEmpty(
          children: [
            DEmptyHeader(
              children: [
                DEmptyMedia(
                  variant: DEmptyMediaVariant.icon,
                  child: DIcon(icon),
                ),
                DEmptyTitle(title),
              ],
            ),
            if (actionLabel != null)
              DEmptyContent(
                children: [
                  DButton(
                    label: Text(actionLabel!),
                    onPressed: onAction == null
                        ? null
                        : () => unawaited(onAction!()),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

String _fieldLabel(String key) {
  final words = key
      .replaceAll('_category_ids', '')
      .replaceAll('_tags', '')
      .replaceAll('_', ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// `Group.visibility_levels`.
String _visibilityLevelLabel(int value) => switch (value) {
  0 => appL10n.everyone,
  1 => appL10n.loggedInUsers,
  2 => appL10n.groupOwnersMembersAndModerators,
  3 => appL10n.groupOwnersAndModerators,
  4 => appL10n.groupOwners,
  _ => appL10n.level((value).toString()),
};

/// `Group::ALIAS_LEVELS`.
String _interactionLevelLabel(int value) => switch (value) {
  0 => appL10n.nobody,
  1 => appL10n.onlyAdmins,
  2 => appL10n.onlyModeratorsAndAdmins,
  3 => appL10n.onlyGroupMembersModeratorsAndAdmins,
  4 => appL10n.onlyGroupOwnersModeratorsAndAdmins,
  99 => appL10n.everyone,
  _ => appL10n.level((value).toString()),
};

/// `NotificationLevels.all`.
String _notificationLevelLabel(int value) => switch (value) {
  0 => appL10n.muted,
  1 => appL10n.normal,
  2 => appL10n.tracking,
  3 => appL10n.watching,
  4 => appL10n.watchingFirstPost,
  _ => appL10n.level((value).toString()),
};

String _humanizeLog(String action) {
  final words = action.replaceAll('_', ' ').trim();
  if (words.isEmpty) return appL10n.groupChanged;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
