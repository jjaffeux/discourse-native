import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/topic_filter.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_filter_controller.dart';
import 'topic_filter_input.dart';
import 'topic_filter_scope.dart';

typedef _TopicListMenuOwner = ({Object context, Object feed});

bool _scopeToken(String token, String key) => key == 'category'
    ? RegExp(r'^=?category:').hasMatch(token)
    : RegExp(r'^-?(?:tags?|tag-group|tag_group):').hasMatch(token) ||
          const {'in:tagged', 'in:untagged'}.contains(token);

String topicListTagFilterLabel(String query, String placeholder) {
  final token = splitTopicFilterQuery(
    query,
  ).where((token) => _scopeToken(token, 'tag')).lastOrNull;
  if (token == null) return placeholder;
  if (token == 'in:untagged') return appL10n.filterTagScopeNone;
  if (token == 'in:tagged') return appL10n.filterTagScopeAny;
  var value = token.substring(token.indexOf(':') + 1);
  if (value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  if (token.startsWith('tag-group:') || token.startsWith('tag_group:')) {
    return appL10n.filterTagScopeGroup(value);
  }
  final tags = value.split(RegExp('[,+]'));
  return tags.length == 1
      ? token.startsWith('-')
            ? appL10n.filterTagScopeNoneOf(tags.single)
            : tags.single
      : appL10n.tagsTopictagselectorValue('${tags.length}');
}

/// Loads the server's autocomplete vocabulary only when the menu is opened.
/// External navigation retires the editor before a late lookup can apply.
/// Scoped choices can update the owning feed while keeping its menu open.
class TopicListFilterMenu extends StatefulWidget {
  const TopicListFilterMenu({
    super.key,
    required this.siteUrl,
    required this.query,
    this.label,
    this.filterKey,
    this.triggerKey,
    this.icon = const DIcon(DIcons.filter, size: 11),
    this.dimLabel = false,
    this.iconOnly = false,
    this.categoryParentId,
    this.onOpenChanged,
  }) : assert(!iconOnly || icon != null);
  final String siteUrl;
  final String query;
  final String? label;
  final String? filterKey;
  final Key? triggerKey;
  final Widget? icon;
  final bool dimLabel;
  final bool iconOnly;
  final int? categoryParentId;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<TopicListFilterMenu> createState() => _TopicListFilterMenuState();
}

class _TopicListFilterMenuState extends State<TopicListFilterMenu> {
  final _popover = DPopoverController();
  final _input = TopicFilterInputController();
  List<TopicFilterOption>? _options;
  bool _loading = false;
  bool _suggestionsReady = false;
  ShellController? _shell;
  String? _tabId;
  ShellTabContext? _tab;
  _TopicListMenuOwner? _owner;
  bool _retired = false;
  bool _publishingScope = false;
  int _loadEpoch = 0;
  Rect? _boundary;

  Rect? _panelBoundary() {
    Rect? boundary;
    context.visitAncestorElements((element) {
      if (element.widget is! DPageSurface) return true;
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        boundary = box.localToGlobal(Offset.zero) & box.size;
      }
      return false;
    });
    return boundary;
  }

  String get _scopeQuery => widget.filterKey == null
      ? widget.query
      : splitTopicFilterQuery(
          widget.query,
        ).where((token) => _scopeToken(token, widget.filterKey!)).join(' ');

  String _withScope(String query) => widget.filterKey == null
      ? query
      : [
          ...splitTopicFilterQuery(
            widget.query,
          ).where((token) => !_scopeToken(token, widget.filterKey!)),
          ...splitTopicFilterQuery(
            query,
          ).where((token) => _scopeToken(token, widget.filterKey!)),
        ].join(' ');

  _TopicListMenuOwner _ownerOf(ShellController shell) {
    final tab = _tab!;
    return (
      context: (
        shell,
        tab.siteUrl,
        tab.accountIdentity,
        tab.lease?.session,
        shell.rootMode,
        tab.activeTabId,
        tab.isCurrent,
      ),
      feed: (tab.topicListContent?.id, tab.topicListContent?.feedPath),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    final tabId = ForumTabScope.idOf(context);
    if (identical(shell, _shell) && tabId == _tabId) return;
    _shell?.removeListener(_checkOwner);
    _shell = shell;
    _tabId = tabId;
    _tab = ForumTabScope.tabOf(context);
    _retired = false;
    _owner = _ownerOf(shell);
    shell.addListener(_checkOwner);
  }

  void _checkOwner() {
    final owner = _ownerOf(_shell!);
    if (owner == _owner) return;
    if (_publishingScope && owner.context == _owner?.context) {
      // Applying a scope synchronously replaces the feed before loadFeed's
      // first await. Only that replacement belongs to this open editor.
      _owner = owner;
      return;
    }
    _retired = true;
    _loadEpoch++;
    _loading = false;
    _options = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _popover.close();
    });
  }

  Future<void> _load() async {
    if (_retired || _loading || _options != null) return;
    final epoch = _loadEpoch;
    setState(() => _loading = true);
    final options = await ShellScope.read(
      context,
    ).loadTopicFilterOptions(widget.siteUrl);
    if (mounted && !_retired && epoch == _loadEpoch) {
      setState(() {
        _options = options;
        _loading = false;
      });
    }
  }

  Future<void> _apply(String query, {bool close = true}) async {
    if (!mounted || _retired) return;
    final shell = ShellScope.read(context);
    if (_retired || !identical(shell, _shell) || _ownerOf(shell) != _owner) {
      return;
    }
    if (close) _popover.close();
    final complete = splitTopicFilterQuery(
      _withScope(query),
    ).where((token) => topicFilterClauseKey(token) != token).join(' ');
    late Future<void> applied;
    _publishingScope = true;
    try {
      applied = _tab!.applyTopicListFilterQuery(complete);
    } finally {
      _publishingScope = false;
    }
    await applied;
  }

  @override
  void dispose() {
    _shell?.removeListener(_checkOwner);
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.filterKey != null || widget.query.isEmpty
        ? null
        : topicFilterMenuCount(widget.query);
    final label =
        '${widget.label ?? context.l10n.startPageFilters}${count == null ? '' : ' · $count'}';
    // Short of room in its row, the Filters menu keeps its glyph and how many
    // filters it holds; said aloud and under the pointer at full length.
    final tight =
        DFitRow.tightOf(context) &&
        (widget.filterKey == null ||
            widget.filterKey == 'tag' && _scopeQuery.isEmpty);
    final iconOnly = widget.iconOnly || tight && count == null;
    final variant = widget.filterKey != 'category' && _scopeQuery.isNotEmpty
        ? DButtonVariant.quietSelected
        : DButtonVariant.quiet;
    return DPopover(
      controller: _popover,
      onEscape: _input.handleEscape,
      sheetOnMobile: true,
      mobileSheetVariant: DSheetVariant.adaptiveMenu,
      mobileSheetSizeToContent: false,
      // Tag rows can arrive after the filter vocabulary.
      mobileSheetContentLoading: _options == null || !_suggestionsReady,
      onOpenChange: (open, _) {
        widget.onOpenChanged?.call(open);
        if (open) {
          setState(() => _suggestionsReady = false);
          _retired = false;
          _owner = _ownerOf(_shell!);
          _boundary = _panelBoundary();
          unawaited(_load());
        }
      },
      content: DPopoverContent(
        width: 320,
        collisionBoundary: _boundary,
        sideOffset: widget.filterKey == null ? DSpacing.controlGap : 6,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        scrollable: false,
        align: DPopoverAlign.start,
        semanticLabel: context.l10n.filterTopics,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            if (!_retired)
              Flexible(
                child: TopicFilterInput(
                  controller: _input,
                  onSuggestionsReady: () {
                    if (mounted && !_retired && !_suggestionsReady) {
                      setState(() => _suggestionsReady = true);
                    }
                  },
                  siteUrl: widget.siteUrl,
                  initialQuery: _scopeQuery,
                  categoryParentId: widget.categoryParentId,
                  categoryContextId: parseTopicFilterScope(
                    widget.query.replaceAll('=category:', 'category:'),
                    ShellScope.read(
                      context,
                    ).filterCategoriesFor(widget.siteUrl),
                  ).categoryId,
                  options: _options ?? const [],
                  categories: ShellScope.read(
                    context,
                  ).filterCategoriesFor(widget.siteUrl),
                  hintText: switch (widget.filterKey) {
                    'category' => context.l10n.filterSearchCategories,
                    'tag' => context.l10n.searchTags,
                    _ => context.l10n.addAFilter,
                  },
                  tokenized: true,
                  embedded: true,
                  focusOnOpen: !const {
                    TargetPlatform.iOS,
                    TargetPlatform.android,
                    TargetPlatform.fuchsia,
                  }.contains(Theme.of(context).platform),
                  onlyKey: widget.filterKey,
                  multiline: false,
                  padding: EdgeInsets.zero,
                  onScopeChanged: widget.filterKey == null
                      ? null
                      : (query) => unawaited(_apply(query, close: false)),
                  onSubmitted: _apply,
                  onDismiss: _popover.close,
                ),
              ),
          ],
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => iconOnly
            ? DButton.iconOnly(
                key: widget.triggerKey ?? const ValueKey('topic-list-filter'),
                semanticLabel: label,
                tooltip: label,
                icon: widget.icon!,
                shape: DButtonShape.pill,
                size: DButtonSize.filter,
                variant: variant,
                focusNode: trigger.focusNode,
                expanded: trigger.open,
                hasPopup: true,
                onPressed: trigger.toggle,
              )
            : DButton(
                key: widget.triggerKey ?? const ValueKey('topic-list-filter'),
                semanticLabel: tight ? label : null,
                label: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.filterKey == 'tag'
                        ? MediaQuery.textScalerOf(context).scale(88)
                        : double.infinity,
                  ),
                  child: Text(
                    tight ? '$count' : label,
                    style: widget.dimLabel
                        ? TextStyle(
                            color: Color.lerp(
                              DTokens.of(context).background,
                              DTokens.of(context).foreground,
                              .40,
                            ),
                          )
                        : null,
                  ),
                ),
                tooltip: widget.query.isEmpty
                    ? context.l10n.filterTopics
                    : context.l10n.editActiveFilter,
                icon: widget.icon,
                size: DButtonSize.filter,
                variant: variant,
                focusNode: trigger.focusNode,
                expanded: trigger.open,
                hasPopup: true,
                onPressed: trigger.toggle,
              ),
      ),
    );
  }
}
