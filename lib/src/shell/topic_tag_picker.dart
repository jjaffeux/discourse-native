import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/forum_workspace.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'open_link.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'topic_taxonomy_picker.dart';

typedef TopicTagMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu, bool saving);

typedef TopicTagNavigationCallback =
    void Function(TopicTag tag, {bool newTab, ForumPanel? panel});

class TopicTagMenuAnchor extends StatefulWidget {
  const TopicTagMenuAnchor({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.categoryId,
    required this.tags,
    required this.enabled,
    required this.builder,
    this.onTagNavigate,
  });

  final String siteUrl;
  final int topicId;
  final int? categoryId;
  final List<TopicTag> tags;
  final bool enabled;
  final TopicTagMenuAnchorBuilder builder;
  final TopicTagNavigationCallback? onTagNavigate;

  @override
  State<TopicTagMenuAnchor> createState() => _TopicTagMenuAnchorState();
}

class _TopicTagMenuAnchorState extends State<TopicTagMenuAnchor> {
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
  void didUpdateWidget(TopicTagMenuAnchor oldWidget) {
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
    final tags = List<TopicTag>.unmodifiable(target.tags);
    var pendingTags = tags;
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
        listEquals(widget.tags, tags);
    _ownsTarget = ownsTarget;
    bool isCurrent() => identical(_ownsTarget, ownsTarget) && ownsTarget();

    try {
      if (!isCurrent()) return;
      final capabilities = await shell.prepareTopicTagEditor(target.siteUrl);
      if (!mounted || !isCurrent()) return;
      final anchorContext = _anchorKey.currentContext;
      if (anchorContext == null) return;
      if (!anchorContext.mounted) return;
      final selected = await showTopicTagPicker(
        context: context,
        anchorContext: anchorContext,
        selectedTags: tags,
        onSelectionChanged: (value) => pendingTags = value,
        capabilities: capabilities,
        onTagNavigate: target.onTagNavigate == null
            ? null
            : (tag, {newTab = false, panel}) {
                if (isCurrent()) {
                  target.onTagNavigate!(tag, newTab: newTab, panel: panel);
                }
              },
        search: (term) async {
          if (!isCurrent()) return const TopicTagSearch();
          try {
            final results = await shell.searchTopicTagsForEditor(
              siteUrl: target.siteUrl,
              categoryId: target.categoryId,
              selectedTags: pendingTags,
              term: term,
            );
            return isCurrent() ? results : const TopicTagSearch();
          } catch (_) {
            if (isCurrent()) rethrow;
            return const TopicTagSearch();
          }
        },
      );
      if (!isCurrent() || selected == null) return;
      setState(() => _saving = true);
      final error = await shell.updateTopicTagsFromSidebar(
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        tags: selected,
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

typedef TopicTagSearchCallback = Future<TopicTagSearch> Function(String term);

Future<List<TopicTag>?> showTopicTagPicker({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<TopicTag> selectedTags,
  required TopicComposerCapabilities capabilities,
  required TopicTagSearchCallback search,
  TopicTagNavigationCallback? onTagNavigate,
  ValueChanged<List<TopicTag>>? onSelectionChanged,
}) async {
  if (context.isTouch) {
    var tags = List<TopicTag>.of(selectedTags);
    var navigated = false;
    final queryFocus = FocusNode();
    await showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      barrierLabel: appL10n.dismissTagsPicker,
      initialFocusNode: queryFocus,
      fillAvailableHeight: true,
      builder: (context, sheet) => DSheetContent(
        side: DSheetSide.bottom,
        semanticLabel: appL10n.tags,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        children: [
          DSheetHeader(children: [DSheetTitle(child: Text(appL10n.tags))]),
          Expanded(
            child: _TagPickerFocusOwner(
              focusNode: queryFocus,
              child: StatefulBuilder(
                builder: (context, setState) => TopicTagPicker(
                  selectedTags: tags,
                  queryFocusNode: queryFocus,
                  capabilities: capabilities,
                  search: search,
                  onSelected: (value) {
                    onSelectionChanged?.call(value);
                    setState(() => tags = value);
                  },
                  onTagNavigate: onTagNavigate == null
                      ? null
                      : (tag, {newTab = false, panel}) {
                          navigated = true;
                          sheet.close();
                          onTagNavigate(tag, newTab: newTab, panel: panel);
                        },
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return navigated || listEquals(tags, selectedTags) ? null : tags;
  }
  return TopicTaxonomyPickerAnchor.show<List<TopicTag>>(
    anchorContext: anchorContext,
    title: appL10n.tags,
    popoverKey: const ValueKey('topic-tag-picker-popover'),
    builder: (pickerContext, close) => TopicTagPicker(
      selectedTags: selectedTags,
      capabilities: capabilities,
      search: search,
      onSelected: close,
      onTagNavigate: onTagNavigate == null
          ? null
          : (tag, {newTab = false, panel}) {
              close(null);
              onTagNavigate(tag, newTab: newTab, panel: panel);
            },
    ),
  );
}

// The route retains its input focus node through the closing animation.
class _TagPickerFocusOwner extends StatefulWidget {
  const _TagPickerFocusOwner({required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  State<_TagPickerFocusOwner> createState() => _TagPickerFocusOwnerState();
}

class _TagPickerFocusOwnerState extends State<_TagPickerFocusOwner> {
  @override
  void dispose() {
    widget.focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TopicTagPicker extends StatefulWidget {
  const TopicTagPicker({
    super.key,
    required this.selectedTags,
    required this.capabilities,
    required this.search,
    required this.onSelected,
    this.onTagNavigate,
    this.queryFocusNode,
  });

  /// Borrowed search focus node; the caller retains ownership.
  final FocusNode? queryFocusNode;
  final List<TopicTag> selectedTags;
  final TopicComposerCapabilities capabilities;
  final TopicTagSearchCallback search;
  final ValueChanged<List<TopicTag>> onSelected;
  final TopicTagNavigationCallback? onTagNavigate;

  @override
  State<TopicTagPicker> createState() => _TopicTagPickerState();
}

class _TopicTagPickerState extends State<TopicTagPicker> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _ownedQueryFocus = FocusNode();
  FocusNode get _queryFocus => widget.queryFocusNode ?? _ownedQueryFocus;
  final Map<String, FocusNode> _rowFocusNodes = {};
  Timer? _debounce;
  late final LatestWinsQueuedLookupController<String, TopicTagSearch> _lookup;
  TopicTagSearch _result = const TopicTagSearch();
  bool _loading = true;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lookup = LatestWinsQueuedLookupController(
      lookup: (term) => widget.search(term.trim()),
      onResult: (result) {
        setState(() {
          _result = result;
          _loading = false;
        });
      },
      onError: (_, _) {
        setState(() {
          _result = TopicTagSearch(forbiddenMessage: appL10n.couldnTLoadTags);
          _loading = false;
        });
      },
    );
    _search('');
  }

  @override
  void didUpdateWidget(TopicTagPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (context.isTouch &&
        !listEquals(oldWidget.selectedTags, widget.selectedTags)) {
      _debounce?.cancel();
      _search(_query.text);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lookup.dispose();
    _query.dispose();
    _ownedQueryFocus.dispose();
    for (final node in _rowFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _lookup.invalidate();
    _searchGeneration++;
    setState(() {
      _result = const TopicTagSearch();
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  void _search(String term) {
    _searchGeneration++;
    setState(() => _loading = true);
    _lookup.request(term);
  }

  bool _selected(TopicTag tag) =>
      widget.selectedTags.any((selected) => _sameTag(selected, tag));

  bool get _atMaximum {
    final maximum = widget.capabilities.maxTagsPerTopic;
    return maximum != null && widget.selectedTags.length >= maximum;
  }

  void _choose(TopicTag tag, {int? generation}) {
    if (_loading ||
        (generation != null && generation != _searchGeneration) ||
        tag.disabled) {
      return;
    }
    final tags = [...widget.selectedTags];
    final index = tags.indexWhere((selected) => _sameTag(selected, tag));
    if (index >= 0) {
      tags.removeAt(index);
    } else {
      if (_atMaximum) return;
      tags.add(tag);
    }
    widget.onSelected(List.unmodifiable(tags));
    if (context.isTouch) _queryFocus.requestFocus();
  }

  TopicTag? get _newTag {
    if (_result.isForbidden || _result.explanation != null) return null;
    final name = _query.text.trim();
    if (!widget.capabilities.canCreateTagNamed(name) ||
        widget.selectedTags.any(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        ) ||
        _result.results.any(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        ) ||
        _atMaximum) {
      return null;
    }
    return TopicTag(name: name);
  }

  void _submitQuery() {
    if (_loading) return;
    final newTag = _newTag;
    if (newTag != null) {
      _choose(newTag);
      return;
    }
    final available = _visibleResults.where(
      (tag) => !tag.disabled && (!_atMaximum || _selected(tag)),
    );
    if (available.isNotEmpty) _choose(available.first);
  }

  List<TopicTag> get _visibleResults {
    if (_loading) return const [];
    final seen = <String>{};
    final term = _query.text.trim().toLowerCase();
    return [
      for (final tag in [
        ...widget.selectedTags.where(
          (tag) => tag.name.toLowerCase().contains(term),
        ),
        ..._result.results,
      ])
        if (seen.add(_tagIdentity(tag))) tag,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final newTag = _newTag;
    final generation = _searchGeneration;
    return TopicTaxonomyPickerContent(
      queryKey: const ValueKey('topic-tag-picker-query'),
      queryController: _query,
      queryFocusNode: _queryFocus,
      queryHint: context.l10n.findOrAddTags,
      onQueryChanged: _changed,
      onQuerySubmitted: (_) => _submitQuery(),
      separatorKey: const ValueKey('topic-tag-picker-divider'),
      children: [
        if (newTag != null)
          DButton(
            key: const ValueKey('topic-tag-picker-create'),
            icon: const DIcon(DIcons.plus),
            label: Text(
              context.l10n.createNewTag((newTag.name).toString()),
              maxLines: 2,
            ),
            variant: DButtonVariant.ghost,
            onPressed: _loading
                ? null
                : () => _choose(newTag, generation: generation),
          ),
        if (_loading)
          const TopicTaxonomyPickerProgress()
        else ...[
          if (_result.explanation case final message?)
            TopicTaxonomyPickerMessage(message, error: true),
          for (final tag in _visibleResults)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTertiaryTapUp: widget.onTagNavigate == null
                  ? null
                  : (_) => widget.onTagNavigate!(tag, newTab: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: DItem(
                  size: DItemSize.xs,
                  focusNode: _rowFocusNodes.putIfAbsent(
                    _tagIdentity(tag),
                    () => FocusNode(skipTraversal: true),
                  ),
                  onPressed: tag.disabled || (!_selected(tag) && _atMaximum)
                      ? null
                      : () => _choose(tag, generation: generation),
                  padding: EdgeInsets.zero,
                  children: [
                    DItemContent(
                      children: [
                        DCheckbox(
                          key: ValueKey(('topic-tag-picker-option', tag.name)),
                          enabled:
                              !tag.disabled && (_selected(tag) || !_atMaximum),
                          value: _selected(tag),
                          title: DLabel(
                            style: const TextStyle(
                              height: 1.375,
                              fontWeight: FontWeight.w400,
                            ),
                            child: Text(tag.name),
                          ),
                          subtitle: tag.disabledReason == null
                              ? null
                              : Text(tag.disabledReason!),
                          secondary: widget.onTagNavigate == null
                              ? null
                              : LinkTarget.action(
                                  action: ({required newTab, panel}) =>
                                      widget.onTagNavigate!(
                                        tag,
                                        newTab: newTab,
                                        panel: panel,
                                      ),
                                  child: DButton.iconOnly(
                                    key: ValueKey((
                                      'topic-tag-picker-open',
                                      tag.name,
                                    )),
                                    icon: const DIcon(DIcons.upRightFromSquare),
                                    tooltip: context.l10n.openTag(
                                      (tag.name).toString(),
                                    ),
                                    onPressed: () => widget.onTagNavigate!(tag),
                                    isLink: true,
                                    variant: DButtonVariant.ghost,
                                    size: DButtonSize.small,
                                  ),
                                ),
                          onChanged:
                              tag.disabled || (!_selected(tag) && _atMaximum)
                              ? null
                              : (_) => _choose(tag, generation: generation),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (newTag == null &&
              _visibleResults.isEmpty &&
              _result.explanation == null)
            TopicTaxonomyPickerMessage(
              _query.text.trim().isEmpty
                  ? context.l10n.noTagsAvailable
                  : context.l10n.noMatchingTags,
            ),
        ],
      ],
    );
  }
}

bool _sameTag(TopicTag left, TopicTag right) =>
    left.id != null && right.id != null
    ? left.id == right.id
    : left.name.toLowerCase() == right.name.toLowerCase();

String _tagIdentity(TopicTag tag) =>
    tag.id == null ? 'name:${tag.name.toLowerCase()}' : 'id:${tag.id}';
