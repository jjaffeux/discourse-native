import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/topic.dart';
import 'category_icon.dart';
import 'shell_scope.dart';
import 'topic_taxonomy_picker.dart';

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
    this.rootOnly = false,
    this.parentCategoryId,
    this.removeCategoryId,
    this.removeLabel,
    this.selectedCategoryId,
  });

  final String siteUrl;
  final int topicId;
  final int? categoryId;
  final bool enabled;
  final TopicCategoryMenuAnchorBuilder builder;
  final bool rootOnly;
  final int? parentCategoryId;
  final int? removeCategoryId;
  final String? removeLabel;
  final int? selectedCategoryId;

  @override
  State<TopicCategoryMenuAnchor> createState() =>
      _TopicCategoryMenuAnchorState();
}

class _TopicCategoryMenuAnchorState extends State<TopicCategoryMenuAnchor> {
  final GlobalKey _anchorKey = GlobalKey();
  bool Function()? _ownsTarget;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Account replacement can leave the URL and the widget unchanged.
    ShellScope.maybeOf(context);
    _retireStaleOperation();
  }

  @override
  void didUpdateWidget(TopicCategoryMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _retireStaleOperation();
  }

  @override
  void deactivate() {
    // The picker route can rebuild before this State is disposed.
    _ownsTarget = null;
    _saving = false;
    super.deactivate();
  }

  void _retireStaleOperation() {
    if (_ownsTarget?.call() == false) {
      _ownsTarget = null;
      _saving = false;
    }
  }

  Future<void> _show() async {
    _retireStaleOperation();
    if (_ownsTarget != null ||
        _saving ||
        !widget.enabled ||
        _anchorKey.currentContext == null) {
      return;
    }
    final target = widget;
    final shell = ShellScope.read(context);
    final lease = shell.lifecycle.capture(target.siteUrl);
    bool ownsTarget() =>
        mounted &&
        !shell.accountSessionDisposed &&
        lease.isCurrent &&
        identical(ShellScope.maybeRead(context), shell) &&
        widget.enabled &&
        widget.siteUrl == target.siteUrl &&
        widget.topicId == target.topicId &&
        widget.categoryId == target.categoryId &&
        widget.rootOnly == target.rootOnly &&
        widget.parentCategoryId == target.parentCategoryId &&
        widget.selectedCategoryId == target.selectedCategoryId &&
        widget.removeCategoryId == target.removeCategoryId &&
        widget.removeLabel == target.removeLabel;
    _ownsTarget = ownsTarget;
    bool isCurrent() => identical(_ownsTarget, ownsTarget) && ownsTarget();

    try {
      if (!isCurrent()) return;
      final anchorContext = _anchorKey.currentContext;
      if (anchorContext == null) return;
      if (!anchorContext.mounted) return;

      final selected = await showTopicCategoryPicker(
        context: context,
        anchorContext: anchorContext,
        siteUrl: target.siteUrl,
        selectedCategoryId: target.selectedCategoryId ?? target.categoryId,
        removeCategoryId: target.removeCategoryId,
        removeLabel: target.removeLabel,
        search: (term) async {
          if (!isCurrent()) return const [];
          final List<TopicCategory> results;
          try {
            results = await shell.searchTopicCategoriesForEditor(
              siteUrl: target.siteUrl,
              term: term,
            );
          } catch (_) {
            if (isCurrent()) rethrow;
            return const [];
          }
          if (!isCurrent()) return const [];
          return results
              .where(
                (category) => target.rootOnly
                    ? category.parentCategoryId == null
                    : target.parentCategoryId == null ||
                          category.parentCategoryId == target.parentCategoryId,
              )
              .toList();
        },
        pathLabelFor: (category) => isCurrent()
            ? shell.topicCategoryPathLabel(category, siteUrl: target.siteUrl)
            : category.name,
      );
      if (!isCurrent() || selected == null || selected == target.categoryId) {
        return;
      }

      setState(() => _saving = true);
      final error = await shell.saveTopicCategory(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        categoryId: selected,
      );
      if (!mounted || !isCurrent() || error == null) return;
      DToast.show(context, error, type: DToastType.error);
    } finally {
      // A retired picker/save must not clear a replacement operation's state.
      if (identical(_ownsTarget, ownsTarget)) {
        _ownsTarget = null;
        if (mounted && _saving) setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => TopicTaxonomyPickerAnchor(
    child: SizedBox(
      key: _anchorKey,
      child: widget.builder(
        context,
        widget.enabled && !_saving ? _show : null,
        _saving,
      ),
    ),
  );
}

typedef TopicCategorySearchCallback =
    Future<List<TopicCategory>> Function(String term);

Future<int?> showTopicCategoryPicker({
  required BuildContext context,
  required BuildContext anchorContext,
  required String siteUrl,
  required int? selectedCategoryId,
  required TopicCategorySearchCallback search,
  required String Function(TopicCategory category) pathLabelFor,
  int? removeCategoryId,
  String? removeLabel,
}) => TopicTaxonomyPickerAnchor.show<int>(
  anchorContext: anchorContext,
  title: 'Category',
  popoverKey: const ValueKey('topic-category-picker-popover'),
  builder: (pickerContext, close) => TopicCategoryPicker(
    siteUrl: siteUrl,
    selectedCategoryId: selectedCategoryId,
    search: search,
    pathLabelFor: pathLabelFor,
    onSelected: close,
    removeCategoryId: removeCategoryId,
    removeLabel: removeLabel,
  ),
);

class TopicCategoryPicker extends StatefulWidget {
  const TopicCategoryPicker({
    super.key,
    required this.siteUrl,
    required this.selectedCategoryId,
    required this.search,
    required this.onSelected,
    required this.pathLabelFor,
    this.removeCategoryId,
    this.removeLabel,
  });

  final int? removeCategoryId;
  final String? removeLabel;
  final String siteUrl;
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
    return TopicTaxonomyPickerContent(
      queryKey: const ValueKey('topic-category-picker-query'),
      queryController: _query,
      queryHint: 'Search categories…',
      onQueryChanged: _changed,
      onQuerySubmitted: (_) => _submitQuery(),
      separatorKey: const ValueKey('topic-category-picker-divider'),
      children: [
        if (widget.removeCategoryId case final id?)
          DButton(
            key: const ValueKey('topic-category-remove'),
            label: Text(widget.removeLabel ?? 'Remove category'),
            variant: DButtonVariant.ghost,
            onPressed: () => widget.onSelected(id),
          ),
        if (_loading)
          const TopicTaxonomyPickerProgress()
        else if (_error case final error?)
          TopicTaxonomyPickerMessage(error, error: true)
        else ...[
          for (final category in _results)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: category.parentCategoryId == null ? 0 : 16,
                top: 2,
                bottom: 2,
              ),
              child: DCheckbox(
                key: ValueKey('topic-category-option-${category.id}'),
                value: category.id == widget.selectedCategoryId,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Row(
                  children: [
                    CategoryIcon(
                      key: ValueKey((
                        'topic-category-option-icon',
                        category.id,
                      )),
                      category: category,
                      siteUrl: widget.siteUrl,
                      size: 14,
                      squareSize: 10,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(widget.pathLabelFor(category))),
                  ],
                ),
                onChanged: (_) => widget.onSelected(category.id),
              ),
            ),
          if (_results.isEmpty)
            TopicTaxonomyPickerMessage(
              _query.text.trim().isEmpty
                  ? 'No categories are available.'
                  : 'No matching categories.',
            ),
        ],
      ],
    );
  }
}
