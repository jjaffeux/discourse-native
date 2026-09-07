import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/topic.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'shell_scope.dart';

typedef TopicTagMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu, bool saving);

typedef TopicTagNavigationCallback = void Function(TopicTag tag, {bool newTab});

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
        capabilities: capabilities,
        onTagNavigate: target.onTagNavigate == null
            ? null
            : (tag, {newTab = false}) {
                if (isCurrent()) target.onTagNavigate!(tag, newTab: newTab);
              },
        search: (term) async {
          if (!isCurrent()) return const TopicTagSearch();
          try {
            final results = await shell.searchTopicTagsForEditor(
              siteUrl: target.siteUrl,
              categoryId: target.categoryId,
              selectedTags: tags,
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
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
    } finally {
      // A retired picker/save must not clear a replacement operation's state.
      if (identical(_ownsTarget, ownsTarget)) {
        _ownsTarget = null;
        if (mounted && _saving) setState(() => _saving = false);
      }
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

typedef TopicTagSearchCallback = Future<TopicTagSearch> Function(String term);

Future<List<TopicTag>?> showTopicTagPicker({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<TopicTag> selectedTags,
  required TopicComposerCapabilities capabilities,
  required TopicTagSearchCallback search,
  TopicTagNavigationCallback? onTagNavigate,
}) => showAnchoredPicker<List<TopicTag>>(
  context: context,
  anchorContext: anchorContext,
  title: 'Tags',
  barrierLabel: 'Dismiss tag picker',
  popoverKey: const ValueKey('topic-tag-picker-popover'),
  builder: (pickerContext) => TopicTagPicker(
    selectedTags: selectedTags,
    capabilities: capabilities,
    search: search,
    onSelected: Navigator.of(pickerContext).pop,
    onTagNavigate: onTagNavigate == null
        ? null
        : (tag, {newTab = false}) {
            Navigator.of(pickerContext).pop();
            onTagNavigate(tag, newTab: newTab);
          },
  ),
);

class TopicTagPicker extends StatefulWidget {
  const TopicTagPicker({
    super.key,
    required this.selectedTags,
    required this.capabilities,
    required this.search,
    required this.onSelected,
    this.onTagNavigate,
  });

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
  Timer? _debounce;
  late final LatestWinsQueuedLookupController<String, TopicTagSearch> _lookup;
  TopicTagSearch _result = const TopicTagSearch();
  bool _loading = true;

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
          _result = const TopicTagSearch(
            forbiddenMessage: "Couldn't load tags.",
          );
          _loading = false;
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
    setState(() => _loading = true);
    _lookup.request(term);
  }

  bool _selected(TopicTag tag) =>
      widget.selectedTags.any((selected) => _sameTag(selected, tag));

  bool get _atMaximum {
    final maximum = widget.capabilities.maxTagsPerTopic;
    return maximum != null && widget.selectedTags.length >= maximum;
  }

  void _choose(TopicTag tag) {
    if (tag.disabled) return;
    final tags = [...widget.selectedTags];
    final index = tags.indexWhere((selected) => _sameTag(selected, tag));
    if (index >= 0) {
      tags.removeAt(index);
    } else {
      if (_atMaximum) return;
      tags.add(tag);
    }
    widget.onSelected(List.unmodifiable(tags));
  }

  TopicTag? get _newTag {
    if (_result.isForbidden) return null;
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
    final theme = Theme.of(context);
    final newTag = _newTag;
    return AnchoredPickerContent(
      queryKey: const ValueKey('topic-tag-picker-query'),
      queryController: _query,
      queryHint: 'Find or add tags…',
      onQueryChanged: (value) {
        _changed(value);
        setState(() {});
      },
      onQuerySubmitted: (_) => _submitQuery(),
      separatorKey: const ValueKey('topic-tag-picker-divider'),
      children: [
        if (newTag != null)
          AnchoredPickerOption(
            key: const ValueKey('topic-tag-picker-create'),
            leading: const DIcon(DIcons.plus, size: 16),
            title: Text('Create new tag: “${newTag.name}”'),
            onTap: () => _choose(newTag),
          ),
        if (_loading)
          const AnchoredPickerProgress()
        else ...[
          if (_result.explanation case final message?)
            AnchoredPickerMessage(
              message,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              textAlign: TextAlign.start,
              color: theme.colorScheme.error,
            ),
          for (final tag in _visibleResults)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTertiaryTapUp: widget.onTagNavigate == null
                  ? null
                  : (_) => widget.onTagNavigate!(tag, newTab: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: AnchoredPickerOption(
                  key: ValueKey(('topic-tag-picker-option', tag.name)),
                  enabled: !tag.disabled && (_selected(tag) || !_atMaximum),
                  selected: _selected(tag),
                  showSelectionIndicator: true,
                  title: Text(tag.name),
                  subtitle: tag.disabledReason == null
                      ? null
                      : Text(tag.disabledReason!),
                  trailing: widget.onTagNavigate == null
                      ? null
                      : SizedBox.square(
                          dimension: 28,
                          child: DButton.iconOnly(
                            key: ValueKey(('topic-tag-picker-open', tag.name)),
                            icon: const DIcon(
                              DIcons.upRightFromSquare,
                              size: 12,
                            ),
                            tooltip: 'Open tag ${tag.name}',
                            onPressed: () => widget.onTagNavigate!(tag),
                            variant: DButtonVariant.flat,
                            size: DButtonSize.small,
                          ),
                        ),
                  onTap: tag.disabled || (!_selected(tag) && _atMaximum)
                      ? null
                      : () => _choose(tag),
                ),
              ),
            ),
          if (newTag == null &&
              _visibleResults.isEmpty &&
              _result.explanation == null)
            AnchoredPickerMessage(
              _query.text.trim().isEmpty
                  ? 'No tags available.'
                  : 'No matching tags.',
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
