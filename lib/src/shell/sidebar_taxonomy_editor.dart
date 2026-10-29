import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/category_sidebar.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/user_preferences.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

Future<void> showSidebarTaxonomyEditor({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required bool categories,
}) async {
  final lease = controller.lifecycle.capture(siteUrl);
  if (controller.currentUserFor(siteUrl) == null) return;
  await showShellSheet<void>(
    context: context,
    title: categories
        ? context.l10n.sidebarEditCategories
        : context.l10n.sidebarEditTags,
    dialogOnDesktop: true,
    scrollBody: false,
    fillAvailableHeight: true,
    nested: true,
    surfaceBuilder: (_, sheet) => SidebarTaxonomyEditor(
      controller: controller,
      siteUrl: siteUrl,
      categories: categories,
      ownsAccount: () => lease.isCurrent,
      sheet: sheet,
    ),
    builder: (context) =>
        ShellSheetForm.of<_SidebarTaxonomyEditorState>(context)._body(context),
    footerBuilder: (context) => ShellSheetForm.of<_SidebarTaxonomyEditorState>(
      context,
    )._footer(context),
  );
}

enum _Selection { all, selected, unselected }

class SidebarTaxonomyEditor extends StatefulWidget {
  const SidebarTaxonomyEditor({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.categories,
    required this.ownsAccount,
    required this.sheet,
  });
  final ShellController controller;
  final String siteUrl;
  final bool categories;
  final bool Function() ownsAccount;
  final Widget sheet;

  @override
  State<SidebarTaxonomyEditor> createState() => _SidebarTaxonomyEditorState();
}

class _SidebarTaxonomyEditorState extends State<SidebarTaxonomyEditor> {
  var _loading = true;
  var _saving = false;
  String? _error;
  String _query = '';
  var _selection = _Selection.all;
  Set<int> _selected = {};
  List<TopicCategory> _categories = const [];
  List<SidebarTag> _tags = const [];
  UserPreferences? _attempted;
  PreferenceSection get _section => widget.categories
      ? PreferenceSection.sidebarCategories
      : PreferenceSection.sidebarTags;
  bool get _canAct => widget.ownsAccount() && !_loading && !_saving;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    // A cancelled failed attempt must not leak its draft into another view.
    final state = widget.controller.preferences.stateFor(widget.siteUrl);
    final attempt = _attempted;
    if (widget.ownsAccount() &&
        attempt != null &&
        state?.confirmed != null &&
        (widget.categories
            ? listEquals(
                state?.draft?.sidebarCategoryIds,
                attempt.sidebarCategoryIds,
              )
            : listEquals(state?.draft?.sidebarTags, attempt.sidebarTags))) {
      widget.controller.preferences.edit(
        widget.siteUrl,
        _section,
        (draft) => draft.withSectionFrom(_section, state!.confirmed!),
      );
    }
    super.dispose();
  }

  Future<void> _load() async {
    final shell = widget.controller;
    final instance = shell.instanceFor(widget.siteUrl);
    if (!widget.ownsAccount() || instance == null) return;
    await Future.wait([
      shell.preferences.load(instance),
      widget.categories
          ? shell.loadCategories(widget.siteUrl)
          : shell.loadTags(widget.siteUrl),
    ]);
    if (!mounted || !widget.ownsAccount()) return;
    final preferences = shell.preferences.stateFor(widget.siteUrl);
    final confirmed = preferences?.confirmed;
    setState(() {
      _loading = false;
      _error = preferences?.error;
      if (confirmed == null) return;
      if (widget.categories) {
        final config = shell.siteConfigFor(widget.siteUrl);
        _categories = orderedSidebarCategories(
          shell
              .filterCategoriesFor(widget.siteUrl)
              .where(
                (c) => config.allowUncategorizedTopics || !c.isUncategorized,
              )
              .toList(),
          fixedCategoryPositions: config.fixedCategoryPositions,
        );
        _selected = confirmed.sidebarCategoryIds.toSet();
      } else {
        final byId = {
          for (final tag in [
            ...shell.tagDirectoryFeedFor(widget.siteUrl).tags,
            ...confirmed.sidebarTags,
          ])
            tag.id: tag,
        };
        _tags = byId.values.toList()
          ..sort((a, b) => b.count.compareTo(a.count));
        _selected = confirmed.sidebarTags.map((tag) => tag.id).toSet();
        _error = shell.tagDirectoryFeedFor(widget.siteUrl).error ?? _error;
      }
    });
  }

  void _reset() {
    if (!_canAct) return;
    final config = widget.controller.siteConfigFor(widget.siteUrl);
    setState(
      () => _selected = widget.categories
          ? config.defaultNavigationMenuCategoryIds.toSet()
          : _tags
                .where(
                  (tag) =>
                      config.defaultNavigationMenuTagNames.contains(tag.name),
                )
                .map((tag) => tag.id)
                .toSet(),
    );
  }

  Future<void> _save() async {
    if (!_canAct) return;
    final shell = widget.controller;
    final instance = shell.instanceFor(widget.siteUrl);
    if (instance == null ||
        shell.preferences.stateFor(widget.siteUrl)?.confirmed?.canEdit !=
            true) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    shell.preferences.edit(widget.siteUrl, _section, (draft) {
      final next = widget.categories
          ? draft.copyWith(sidebarCategoryIds: _selected.toList())
          : draft.copyWith(
              sidebarTags: _tags
                  .where((tag) => _selected.contains(tag.id))
                  .toList(),
            );
      _attempted = next;
      return next;
    });
    final saved = await shell.preferences.save(instance, _section);
    if (!mounted || !widget.ownsAccount()) return;
    if (saved) {
      DDialogClose.close<void>(context);
    } else {
      setState(() {
        _saving = false;
        _error = shell.preferences.stateFor(widget.siteUrl)?.error;
      });
    }
  }

  bool _matches(int id, String name) =>
      name.toLowerCase().contains(_query.toLowerCase()) &&
      (_selection == _Selection.all ||
          (_selection == _Selection.selected) == _selected.contains(id));

  void _toggle(int id) {
    if (!_canAct) return;
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ShellSheetForm<_SidebarTaxonomyEditorState>(
      state: this,
      child: widget.sheet,
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: DSpinner());
    final byId = {for (final c in _categories) c.id: c};
    int depth(TopicCategory category) {
      if (_query.isNotEmpty || _selection != _Selection.all) return 0;
      var current = byId[category.parentCategoryId];
      final visited = {category.id};
      var value = 0;
      while (current != null && visited.add(current.id)) {
        value++;
        current = byId[current.parentCategoryId];
      }
      return value;
    }

    final rows = <Widget>[
      if (widget.categories)
        for (final category in _categories)
          if (_matches(category.id, category.name))
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: depth(category) * DSpacing.lg,
              ),
              child: DCheckbox(
                key: ValueKey('sidebar-choice-category-${category.id}'),
                value: _selected.contains(category.id),
                onChanged: _canAct ? (_) => _toggle(category.id) : null,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: DSpacing.sm,
                ),
                title: Row(
                  spacing: DSpacing.sm,
                  children: [
                    CategoryIcon(
                      category: category,
                      size: 14,
                      siteUrl: widget.siteUrl,
                    ),
                    Expanded(child: Text(category.name)),
                  ],
                ),
              ),
            ),
      if (!widget.categories)
        for (final tag in _tags)
          if (_matches(tag.id, tag.name))
            DCheckbox(
              key: ValueKey('sidebar-choice-tag-${tag.id}'),
              value: _selected.contains(tag.id),
              onChanged: _canAct ? (_) => _toggle(tag.id) : null,
              contentPadding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
              title: Text(tag.name),
            ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DInput(
          semanticLabel: widget.categories
              ? context.l10n.sidebarSearchCategories
              : context.l10n.searchTagsTopictagselector,
          hintText: widget.categories
              ? context.l10n.sidebarSearchCategories
              : context.l10n.searchTagsTopictagselector,
          prefix: const DIcon(DIcons.magnifyingGlass, size: 16),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: DSpacing.sm),
        DToggleGroup<_Selection>(
          values: [_selection],
          allowEmptySelection: false,
          wrap: true,
          density: DToggleDensity.menuFilter,
          onChanged: (values) => setState(() => _selection = values.single),
          items: [
            DToggleGroupItem(
              value: _Selection.all,
              child: Text(context.l10n.all),
            ),
            DToggleGroupItem(
              value: _Selection.selected,
              child: Text(context.l10n.sidebarSelected),
            ),
            DToggleGroupItem(
              value: _Selection.unselected,
              child: Text(context.l10n.sidebarUnselected),
            ),
          ],
        ),
        const SizedBox(height: DSpacing.sm),
        if (_error != null)
          DAlert(
            variant: DAlertVariant.destructive,
            description: DAlertDescription(child: Text(_error!)),
          ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: DScrollArea(
              key: const ValueKey('sidebar-taxonomy-choices'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows.isEmpty
                    ? [Text(context.l10n.sidebarNoMatches)]
                    : rows,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) => Wrap(
    key: const ValueKey('sidebar-taxonomy-actions'),
    alignment: WrapAlignment.spaceBetween,
    spacing: DSpacing.sm,
    runSpacing: DSpacing.sm,
    children: [
      DButton(
        variant: DButtonVariant.outline,
        label: Text(context.l10n.sidebarResetDefault),
        onPressed: _canAct ? _reset : null,
      ),
      DButton(
        label: Text(context.l10n.save),
        loading: _saving,
        onPressed: _canAct ? _save : null,
      ),
    ],
  );
}
