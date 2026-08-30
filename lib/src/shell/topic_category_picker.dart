import 'package:flutter/material.dart';

import '../models/topic.dart';
import 'anchored_picker.dart';
import 'shell_scope.dart';

typedef TopicCategoryMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu, bool saving);

/// Gives the topic sidebar category the same adaptive picker as its tags.
class TopicCategoryMenuAnchor extends StatefulWidget {
  const TopicCategoryMenuAnchor({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.categoryId,
    required this.enabled,
    required this.builder,
  });

  final String siteUrl;
  final int topicId;
  final int? categoryId;
  final bool enabled;
  final TopicCategoryMenuAnchorBuilder builder;

  @override
  State<TopicCategoryMenuAnchor> createState() =>
      _TopicCategoryMenuAnchorState();
}

class _TopicCategoryMenuAnchorState extends State<TopicCategoryMenuAnchor> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _showing = false;
  bool _saving = false;

  Future<void> _show() async {
    if (_showing ||
        _saving ||
        !widget.enabled ||
        _anchorKey.currentContext == null) {
      return;
    }
    _showing = true;
    try {
      final shell = ShellScope.read(context);
      await shell.loadAllCategories(widget.siteUrl);
      final anchorContext = _anchorKey.currentContext;
      if (!mounted || !widget.enabled || anchorContext == null) return;
      if (!anchorContext.mounted) return;

      final feed = shell.categoryFeedFor(widget.siteUrl);
      final selected = await showTopicCategoryPicker(
        context: context,
        anchorContext: anchorContext,
        selectedCategoryId: widget.categoryId,
        categories: _editableTopicCategories(
          shell.topicComposerCategories(widget.siteUrl),
        ),
        errorMessage: feed.error,
      );
      if (!mounted || selected == null || selected == widget.categoryId) return;

      setState(() => _saving = true);
      final error = await shell.saveTopicCategory(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        categoryId: selected,
      );
      if (!mounted || error == null) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    } finally {
      _showing = false;
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: _anchorKey,
    child: widget.builder(
      context,
      widget.enabled && !_saving ? _show : null,
      _saving,
    ),
  );
}

/// Opens the lightweight category chooser used by the topic sidebar.
Future<int?> showTopicCategoryPicker({
  required BuildContext context,
  required BuildContext anchorContext,
  required int? selectedCategoryId,
  required List<TopicCategory> categories,
  String? errorMessage,
}) => showAnchoredPicker<int>(
  context: context,
  anchorContext: anchorContext,
  title: 'Category',
  barrierLabel: 'Dismiss category picker',
  popoverKey: const ValueKey('topic-category-picker-popover'),
  builder: (pickerContext) => TopicCategoryPicker(
    selectedCategoryId: selectedCategoryId,
    categories: categories,
    errorMessage: errorMessage,
    onSelected: Navigator.of(pickerContext).pop,
  ),
);

/// Search and category rows shared by the pointer popover and touch sheet.
class TopicCategoryPicker extends StatefulWidget {
  const TopicCategoryPicker({
    super.key,
    required this.selectedCategoryId,
    required this.categories,
    required this.onSelected,
    this.errorMessage,
  });

  final int? selectedCategoryId;
  final List<TopicCategory> categories;
  final ValueChanged<int> onSelected;
  final String? errorMessage;

  @override
  State<TopicCategoryPicker> createState() => _TopicCategoryPickerState();
}

class _TopicCategoryPickerState extends State<TopicCategoryPicker> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<TopicCategory> get _visibleCategories {
    final term = _query.text.trim().toLowerCase();
    if (term.isEmpty) return widget.categories;
    final names = {
      for (final category in widget.categories) category.id: category.name,
    };
    return [
      for (final category in widget.categories)
        if (category.name.toLowerCase().contains(term) ||
            (names[category.parentCategoryId]?.toLowerCase().contains(term) ??
                false))
          category,
    ];
  }

  void _submitQuery() {
    final visible = _visibleCategories;
    if (visible.isNotEmpty) widget.onSelected(visible.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visibleCategories;
    return AnchoredPickerContent(
      queryKey: const ValueKey('topic-category-picker-query'),
      queryController: _query,
      queryHint: 'Search categories…',
      onQueryChanged: (_) => setState(() {}),
      onQuerySubmitted: (_) => _submitQuery(),
      separatorKey: const ValueKey('topic-category-picker-divider'),
      children: [
        if (widget.errorMessage case final error? when visible.isEmpty)
          AnchoredPickerMessage(error, color: theme.colorScheme.error)
        else ...[
          for (final category in visible)
            AnchoredPickerOption(
              key: ValueKey('topic-category-option-${category.id}'),
              indent: category.parentCategoryId == null ? 0 : 16,
              selected: category.id == widget.selectedCategoryId,
              showSelectionIndicator: true,
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(category.colorValue),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              title: Text(category.name),
              onTap: () => widget.onSelected(category.id),
            ),
          if (visible.isEmpty)
            AnchoredPickerMessage(
              _query.text.trim().isEmpty
                  ? 'No categories are available.'
                  : 'No matching categories.',
            ),
        ],
      ],
    );
  }
}

List<TopicCategory> _editableTopicCategories(
  Iterable<TopicCategory> categories,
) {
  final permitted = categories.where((category) => category.canCreateTopic);
  final permittedIds = permitted.map((category) => category.id).toSet();
  final ordered = <TopicCategory>[];
  final visited = <int>{};

  void appendChildren(int? parentId) {
    final children =
        permitted
            .where(
              (category) => parentId == null
                  ? category.parentCategoryId == null ||
                        !permittedIds.contains(category.parentCategoryId)
                  : category.parentCategoryId == parentId,
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    for (final child in children) {
      if (!visited.add(child.id)) continue;
      ordered.add(child);
      appendChildren(child.id);
    }
  }

  appendChildren(null);
  return ordered;
}
