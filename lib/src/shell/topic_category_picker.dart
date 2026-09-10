import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'shell_scope.dart';

typedef TopicCategoryMenuAnchorBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback? openMenu,
      bool saving,
      DComboboxTriggerState<int> trigger,
    );

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

  Object get _target => (
    siteUrl,
    topicId,
    categoryId,
    enabled,
    rootOnly,
    parentCategoryId,
    removeCategoryId,
    removeLabel,
    selectedCategoryId,
  );

  @override
  State<TopicCategoryMenuAnchor> createState() =>
      _TopicCategoryMenuAnchorState();
}

class _TopicCategoryMenuAnchorState extends State<TopicCategoryMenuAnchor> {
  Object? _scope;
  Object _generation = Object();
  Object? _save;

  @override
  void deactivate() {
    _generation = Object();
    _save = null;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget;
    final shell = ShellScope.of(context);
    final lease = shell.lifecycle.capture(target.siteUrl);
    final scope = (shell, lease.session, target._target);
    if (_scope != scope) {
      _scope = scope;
      _generation = Object();
      _save = null;
    }
    final generation = _generation;
    bool isCurrent() =>
        mounted &&
        identical(_generation, generation) &&
        !shell.accountSessionDisposed &&
        lease.isCurrent &&
        identical(ShellScope.maybeRead(context), shell) &&
        widget.enabled &&
        widget._target == target._target;

    Future<void> select(int? categoryId) async {
      if (!isCurrent() ||
          _save != null ||
          categoryId == null ||
          categoryId == target.categoryId) {
        return;
      }
      final save = Object();
      setState(() => _save = save);
      try {
        final error = await shell.saveTopicCategory(
          siteUrl: target.siteUrl,
          topicId: target.topicId,
          categoryId: categoryId,
        );
        if (context.mounted &&
            isCurrent() &&
            identical(_save, save) &&
            error != null) {
          DToast.show(context, error, type: DToastType.error);
        }
      } finally {
        if (isCurrent() && identical(_save, save)) {
          setState(() => _save = null);
        }
      }
    }

    final saving = _save != null;
    final enabled = target.enabled && !saving;
    return TopicCategorySelector(
      key: ObjectKey(generation),
      keyPrefix: 'topic-category-picker',
      siteUrl: target.siteUrl,
      categories: const [],
      selected: shell.categoryFor(
        target.selectedCategoryId ?? target.categoryId,
        siteUrl: target.siteUrl,
      ),
      parent: shell.categoryFor(
        target.parentCategoryId,
        siteUrl: target.siteUrl,
      ),
      clearSelectionLabel: target.removeCategoryId == null
          ? null
          : target.removeLabel ?? 'Remove category',
      search: (term) async {
        if (!isCurrent()) return const [];
        try {
          final results = await shell.searchTopicCategoriesForEditor(
            siteUrl: target.siteUrl,
            term: term,
          );
          if (!isCurrent()) return const [];
          return results
              .where(
                (category) => target.rootOnly
                    ? category.parentCategoryId == null
                    : target.parentCategoryId == null ||
                          category.parentCategoryId == target.parentCategoryId,
              )
              .toList();
        } catch (_) {
          if (isCurrent()) rethrow;
          return const [];
        }
      },
      labelFor: (category) => isCurrent()
          ? shell.topicCategoryPathLabel(category, siteUrl: target.siteUrl)
          : category.name,
      onSelected: enabled
          ? (category) =>
                unawaited(select(category?.id ?? target.removeCategoryId))
          : null,
      triggerBuilder: (context, trigger) => target.builder(
        context,
        enabled
            ? () {
                if (isCurrent()) trigger.toggle();
              }
            : null,
        saving,
        trigger,
      ),
    );
  }
}
