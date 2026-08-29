import 'dart:async';

import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'shell_scope.dart';

typedef TopicTagMenuAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback? openMenu, bool saving);

/// Gives a sidebar property an adaptive tag editor without opening a composer.
///
/// The topic stays visible while a pointer gets a compact anchored menu. A
/// touch device gets the same picker in a sheet, where the keyboard and tap
/// targets have enough room. One choice is committed at a time so dismissing
/// the menu never hides unsaved work.
class TopicTagMenuAnchor extends StatefulWidget {
  const TopicTagMenuAnchor({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.categoryId,
    required this.tags,
    required this.enabled,
    required this.builder,
  });

  final String siteUrl;
  final int topicId;
  final int? categoryId;
  final List<TopicTag> tags;
  final bool enabled;
  final TopicTagMenuAnchorBuilder builder;

  @override
  State<TopicTagMenuAnchor> createState() => _TopicTagMenuAnchorState();
}

class _TopicTagMenuAnchorState extends State<TopicTagMenuAnchor> {
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
      final capabilities = await shell.prepareTopicTagEditor(widget.siteUrl);
      final anchorContext = _anchorKey.currentContext;
      if (!mounted || !widget.enabled || anchorContext == null) return;
      if (!anchorContext.mounted) return;
      final selected = await showTopicTagPicker(
        context: context,
        anchorContext: anchorContext,
        selectedTags: widget.tags,
        capabilities: capabilities,
        search: (term) => shell.searchTopicTagsForEditor(
          siteUrl: widget.siteUrl,
          categoryId: widget.categoryId,
          selectedTags: widget.tags,
          term: term,
        ),
      );
      if (!mounted || selected == null) return;
      setState(() => _saving = true);
      final error = await shell.updateTopicTagsFromSidebar(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        tags: selected,
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

typedef TopicTagSearchCallback = Future<TopicTagSearch> Function(String term);

/// Opens the lightweight tag chooser used by the topic sidebar.
Future<List<TopicTag>?> showTopicTagPicker({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<TopicTag> selectedTags,
  required TopicComposerCapabilities capabilities,
  required TopicTagSearchCallback search,
}) {
  Widget picker(BuildContext pickerContext) => TopicTagPicker(
    selectedTags: selectedTags,
    capabilities: capabilities,
    search: search,
    onSelected: Navigator.of(pickerContext).pop,
  );

  return showAnchoredPicker<List<TopicTag>>(
    context: context,
    anchorContext: anchorContext,
    title: 'Tags',
    barrierLabel: 'Dismiss tag picker',
    popoverKey: const ValueKey('topic-tag-picker-popover'),
    builder: picker,
  );
}

/// Search and choice rows shared by the pointer popover and touch sheet.
class TopicTagPicker extends StatefulWidget {
  const TopicTagPicker({
    super.key,
    required this.selectedTags,
    required this.capabilities,
    required this.search,
    required this.onSelected,
  });

  final List<TopicTag> selectedTags;
  final TopicComposerCapabilities capabilities;
  final TopicTagSearchCallback search;
  final ValueChanged<List<TopicTag>> onSelected;

  @override
  State<TopicTagPicker> createState() => _TopicTagPickerState();
}

class _TopicTagPickerState extends State<TopicTagPicker> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  int _revision = 0;
  bool _searchRunning = false;
  ({int revision, String term})? _queuedSearch;
  TopicTagSearch _result = const TopicTagSearch();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queuedSearch = null;
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  Future<void> _search(String term) async {
    final revision = ++_revision;
    setState(() => _loading = true);
    if (_searchRunning) {
      _queuedSearch = (revision: revision, term: term);
      return;
    }
    await _runSearch(revision, term);
  }

  Future<void> _runSearch(int revision, String term) async {
    _searchRunning = true;
    try {
      final result = await widget.search(term.trim());
      if (!mounted || revision != _revision) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _result = const TopicTagSearch(forbiddenMessage: "Couldn't load tags.");
        _loading = false;
      });
    } finally {
      _searchRunning = false;
      final queued = _queuedSearch;
      _queuedSearch = null;
      if (queued != null && mounted && queued.revision == _revision) {
        unawaited(_runSearch(queued.revision, queued.term));
      }
    }
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
    final available = _result.results.where(
      (tag) => !tag.disabled && (!_atMaximum || _selected(tag)),
    );
    if (available.isNotEmpty) _choose(available.first);
  }

  List<TopicTag> get _visibleResults {
    final seen = <String>{};
    return [
      for (final tag in [...widget.selectedTags, ..._result.results])
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
      queryHint: 'Add tags…',
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
            AnchoredPickerOption(
              key: ValueKey(('topic-tag-picker-option', tag.name)),
              enabled: !tag.disabled && (_selected(tag) || !_atMaximum),
              selected: _selected(tag),
              showSelectionIndicator: true,
              title: Text(tag.name),
              subtitle: tag.disabledReason == null
                  ? null
                  : Text(tag.disabledReason!),
              onTap: tag.disabled || (!_selected(tag) && _atMaximum)
                  ? null
                  : () => _choose(tag),
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
