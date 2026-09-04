part of '../group_page.dart';

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
            ListTile(
              key: ValueKey('$sheetOptionKeyPrefix-${option.value}'),
              minTileHeight: 48,
              leading: DIcon(iconFor(option.value), size: 18),
              title: Text(option.label),
              trailing: selected == option.value
                  ? const DIcon(DIcons.check, size: 16)
                  : null,
              selected: selected == option.value,
              selectedColor: Theme.of(sheetContext).shell.selectedForeground,
              selectedTileColor: Theme.of(sheetContext).shell.selected,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              onTap: () => Navigator.of(sheetContext).pop(option.value),
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
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => unawaited(_showPicker(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
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
          ),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: DButton(
        key: const ValueKey('group-load-more'),
        label: const Text('Load more'),
        loading: loading,
        onPressed: onPressed,
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ContentReadingLaneBox(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
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
    child: ContentReadingLaneBox(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(icon, size: 34),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            DButton(
              label: Text(actionLabel!),
              onPressed: onAction == null ? null : () => unawaited(onAction!()),
            ),
          ],
        ],
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

String _levelLabel(int value) => switch (value) {
  0 => 'Everyone',
  1 => 'Logged-in users',
  2 => 'Group members',
  3 => 'Group owners',
  4 => 'Staff',
  99 => 'Nobody',
  _ => 'Level $value',
};

String _humanizeLog(String action) {
  final words = action.replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Group changed';
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

InputDecoration _groupSearchDecoration(String hint) => InputDecoration(
  isDense: true,
  hintText: hint,
  prefixIcon: const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12),
    child: DIcon(DIcons.magnifyingGlass, size: 18),
  ),
  prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 37),
  contentPadding: const EdgeInsets.symmetric(vertical: 9),
  border: const OutlineInputBorder(),
);
