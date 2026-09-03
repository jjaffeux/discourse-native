part of '../group_page.dart';

@immutable
final class _Subtab {
  const _Subtab(this.value, this.label);

  final String value;
  final String label;
}

class _Subtabs extends StatelessWidget {
  const _Subtabs({
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  final String selected;
  final List<_Subtab> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('group-subtab-${option.value}'),
                label: Text(option.label),
                selected: selected == option.value,
                onSelected: (_) => onSelect(option.value),
              ),
            ),
        ],
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
    child: Padding(
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
    child: Padding(
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
