import 'dart:async';

import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

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

  if (context.isTouch) {
    return showShellSheet<List<TopicTag>>(
      context: context,
      title: 'Tags',
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      builder: picker,
    );
  }

  final navigator = Navigator.of(context);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final anchor = anchorRect(
    anchor: anchorContext.findRenderObject() as RenderBox?,
    overlay: overlay,
  );
  final media = MediaQuery.of(context);
  final alignment = anchor == null
      ? Alignment.center
      : Alignment(
          anchor.center.dx > media.size.width / 2 ? 1 : -1,
          anchor.center.dy > media.size.height / 2 ? 1 : -1,
        );
  final duration = media.disableAnimations
      ? Duration.zero
      : discourseMenuOpenDuration;

  return navigator.push<List<TopicTag>>(
    PageRouteBuilder<List<TopicTag>>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Dismiss tag picker',
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      reverseTransitionDuration: media.disableAnimations
          ? Duration.zero
          : discourseMenuCloseDuration,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          CustomSingleChildLayout(
            delegate: AnchoredLayout(
              anchor: anchor,
              maxWidth: _TopicTagPickerSurface.width,
              gap: 4,
              margin: 10,
            ),
            child: _TopicTagPickerTransition(
              animation: animation,
              alignment: alignment,
              child: _TopicTagPickerSurface(child: picker(routeContext)),
            ),
          ),
    ),
  );
}

class _TopicTagPickerTransition extends StatelessWidget {
  const _TopicTagPickerTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        alignment: alignment,
        child: child,
      ),
    );
  }
}

class _TopicTagPickerSurface extends StatelessWidget {
  const _TopicTagPickerSurface({required this.child});

  static const double width = 360;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      key: const ValueKey('topic-tag-picker-popover'),
      color: theme.shell.floating,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          border: Border.all(color: theme.shell.divider),
          borderRadius: radius,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: child,
        ),
      ),
    );
  }
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
    if (!widget.capabilities.canCreateTag || _result.isForbidden) return null;
    final name = _query.text.trim();
    if (name.isEmpty ||
        widget.selectedTags.any(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        ) ||
        _result.results.any(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        ) ||
        _atMaximum) {
      return null;
    }
    final maximumLength = widget.capabilities.maxTagLength;
    if (maximumLength != null && name.length > maximumLength) return null;
    final source = widget.capabilities.tagsFilterRegexp;
    if (source != null && source.isNotEmpty) {
      try {
        var pattern = source;
        if (pattern.startsWith('/') && pattern.lastIndexOf('/') > 0) {
          pattern = pattern.substring(1, pattern.lastIndexOf('/'));
        }
        final match = RegExp(pattern).firstMatch(name);
        if (match == null || match.start != 0 || match.end != name.length) {
          return null;
        }
      } catch (_) {
        return null;
      }
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('topic-tag-picker-query'),
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            _changed(value);
            setState(() {});
          },
          onSubmitted: (_) => _submitQuery(),
          decoration: const InputDecoration(
            hintText: 'Add tags…',
            border: InputBorder.none,
          ),
        ),
        Divider(height: 1, color: theme.shell.divider),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else ...[
          if (_result.explanation case final message?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (newTag != null)
            ListTile(
              key: const ValueKey('topic-tag-picker-create'),
              dense: true,
              leading: const DIcon(DIcons.plus, size: 16),
              title: Text('Create new tag: “${newTag.name}”'),
              onTap: () => _choose(newTag),
            ),
          for (final tag in _visibleResults)
            ListTile(
              key: ValueKey(('topic-tag-picker-option', tag.name)),
              dense: true,
              enabled: !tag.disabled && (_selected(tag) || !_atMaximum),
              title: Text(tag.name),
              subtitle: tag.disabledReason == null
                  ? null
                  : Text(tag.disabledReason!),
              trailing: _selected(tag)
                  ? const DIcon(DIcons.check, size: 16)
                  : null,
              onTap: tag.disabled || (!_selected(tag) && _atMaximum)
                  ? null
                  : () => _choose(tag),
            ),
          if (newTag == null &&
              _visibleResults.isEmpty &&
              _result.explanation == null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                _query.text.trim().isEmpty
                    ? 'No tags available.'
                    : 'No matching tags.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
