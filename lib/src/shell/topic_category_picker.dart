import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/topic.dart';
import 'anchored_picker.dart';
import 'shell_scope.dart';

typedef TopicCategoryMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu, bool saving);

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
      final anchorContext = _anchorKey.currentContext;
      if (!mounted || !widget.enabled || anchorContext == null) return;
      if (!anchorContext.mounted) return;

      final selected = await showTopicCategoryPicker(
        context: context,
        anchorContext: anchorContext,
        selectedCategoryId: widget.categoryId,
        search: (term) => shell.searchTopicCategoriesForEditor(
          siteUrl: widget.siteUrl,
          term: term,
        ),
        pathLabelFor: (category) =>
            shell.topicCategoryPathLabel(category, siteUrl: widget.siteUrl),
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

typedef TopicCategorySearchCallback =
    Future<List<TopicCategory>> Function(String term);

Future<int?> showTopicCategoryPicker({
  required BuildContext context,
  required BuildContext anchorContext,
  required int? selectedCategoryId,
  required TopicCategorySearchCallback search,
  required String Function(TopicCategory category) pathLabelFor,
}) => showAnchoredPicker<int>(
  context: context,
  anchorContext: anchorContext,
  title: 'Category',
  barrierLabel: 'Dismiss category picker',
  popoverKey: const ValueKey('topic-category-picker-popover'),
  builder: (pickerContext) => TopicCategoryPicker(
    selectedCategoryId: selectedCategoryId,
    search: search,
    pathLabelFor: pathLabelFor,
    onSelected: Navigator.of(pickerContext).pop,
  ),
);

class TopicCategoryPicker extends StatefulWidget {
  const TopicCategoryPicker({
    super.key,
    required this.selectedCategoryId,
    required this.search,
    required this.onSelected,
    required this.pathLabelFor,
  });

  final int? selectedCategoryId;
  final TopicCategorySearchCallback search;
  final ValueChanged<int> onSelected;
  final String Function(TopicCategory category) pathLabelFor;

  @override
  State<TopicCategoryPicker> createState() => _TopicCategoryPickerState();
}

class _TopicCategoryPickerState extends State<TopicCategoryPicker> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  late final LatestWinsQueuedLookupController<String, List<TopicCategory>>
  _lookup;
  List<TopicCategory> _results = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookup = LatestWinsQueuedLookupController(
      lookup: (term) => widget.search(term.trim()),
      onResult: (result) {
        setState(() {
          _results = result;
          _loading = false;
        });
      },
      onError: (_, _) {
        setState(() {
          _results = const [];
          _loading = false;
          _error = "Couldn't load categories.";
        });
      },
    );
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lookup.dispose();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  void _search(String term) {
    setState(() {
      _loading = true;
      _error = null;
    });
    _lookup.request(term);
  }

  void _submitQuery() {
    if (_results.isNotEmpty) widget.onSelected(_results.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnchoredPickerContent(
      queryKey: const ValueKey('topic-category-picker-query'),
      queryController: _query,
      queryHint: 'Search categories…',
      onQueryChanged: _changed,
      onQuerySubmitted: (_) => _submitQuery(),
      separatorKey: const ValueKey('topic-category-picker-divider'),
      children: [
        if (_loading)
          const AnchoredPickerProgress()
        else if (_error case final error?)
          AnchoredPickerMessage(error, color: theme.colorScheme.error)
        else ...[
          for (final category in _results)
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
              title: Text(widget.pathLabelFor(category)),
              onTap: () => widget.onSelected(category.id),
            ),
          if (_results.isEmpty)
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
