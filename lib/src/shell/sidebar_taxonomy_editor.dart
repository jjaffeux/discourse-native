import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/category_sidebar.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/user_preferences.dart';
import 'category_icon.dart';
import 'platform.dart';
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
    desktopDialogConstraints: const BoxConstraints(
      maxWidth: 380,
      maxHeight: 560,
    ),
    scrollBody: context.isTouch,
    fillAvailableHeight: true,
    showHeaderDivider: false,
    padding: const EdgeInsets.symmetric(horizontal: 15),
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
    final tokens = DTokens.of(context);
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

    Widget row({
      required Key key,
      required int id,
      required String name,
      required Widget mark,
      int depth = 0,
    }) => Padding(
      padding: EdgeInsetsDirectional.only(start: 18.0 * depth),
      child: DCheckbox(
        key: key,
        size: DCheckboxSize.compact,
        value: _selected.contains(id),
        onChanged: _canAct ? (_) => _toggle(id) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 2,
            top: 7,
            bottom: 7,
          ),
          child: Row(
            spacing: 10,
            children: [
              mark,
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 13.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final rows = <Widget>[
      if (widget.categories)
        for (final category in _categories)
          if (_matches(category.id, category.name))
            row(
              key: ValueKey('sidebar-choice-category-${category.id}'),
              id: category.id,
              name: category.name,
              depth: depth(category),
              mark: CategoryIcon(
                category: category,
                size: 14,
                squareSize: 10,
                siteUrl: widget.siteUrl,
              ),
            ),
      if (!widget.categories)
        for (final tag in _tags)
          if (_matches(tag.id, tag.name))
            row(
              key: ValueKey('sidebar-choice-tag-${tag.id}'),
              id: tag.id,
              name: tag.name,
              mark: DIcon(DIcons.tag, size: 12, color: tokens.mutedForeground),
            ),
    ];
    final list = Column(
      key: const ValueKey('sidebar-taxonomy-choices'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.categories
                      ? context.l10n.sidebarNoCategoriesMatch
                      : context.l10n.sidebarNoTagsMatch,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: tokens.mutedForeground,
                  ),
                ),
              ),
            ]
          : rows,
    );
    final label = widget.categories
        ? context.l10n.sidebarSearchCategories
        : context.l10n.searchTagsTopictagselector;
    Widget chip(_Selection value, String text) => Semantics(
      key: ValueKey('sidebar-taxonomy-filter-${value.name}'),
      container: true,
      selected: _selection == value,
      child: DButton(
        variant: _selection == value
            ? DButtonVariant.quietSelected
            : DButtonVariant.quiet,
        size: DControlSize.filter,
        label: Text(text),
        onPressed: () => setState(() => _selection = value),
      ),
    );
    final fixed = <Widget>[
      DecoratedBox(
        key: const ValueKey('sidebar-taxonomy-search'),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: DInput(
            borderless: true,
            semanticLabel: label,
            hintText: label,
            style: const TextStyle(fontSize: 15, height: 1.4),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          chip(_Selection.all, context.l10n.all),
          chip(_Selection.selected, context.l10n.sidebarSelected),
          chip(_Selection.unselected, context.l10n.sidebarUnselected),
        ],
      ),
      const SizedBox(height: 6),
      if (_error != null)
        DAlert(
          variant: DAlertVariant.destructive,
          description: DAlertDescription(child: Text(_error!)),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...fixed,
        if (context.isTouch)
          list
        else
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .45,
              ),
              child: DScrollArea(child: list),
            ),
          ),
      ],
    );
  }

  Widget _footer(BuildContext context) => ShellSheetActions(
    key: const ValueKey('sidebar-taxonomy-actions'),
    children: [
      DButton(
        variant: DButtonVariant.outline,
        shape: DButtonShape.pill,
        size: DControlSize.field,
        backgroundColor: Colors.transparent,
        label: Text(context.l10n.sidebarResetDefault),
        onPressed: _canAct ? _reset : null,
      ),
      DButton(
        shape: DButtonShape.pill,
        size: DControlSize.field,
        label: Text(context.l10n.save),
        loading: _saving,
        onPressed: _canAct ? _save : null,
      ),
    ],
  );
}
