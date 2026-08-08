import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'shell_scope.dart';
import 'topic_filter_controller.dart';
import 'topic_list_view.dart';

class TopicFilterPage extends StatefulWidget {
  const TopicFilterPage({
    super.key,
    required this.siteUrl,
    required this.feed,
    required this.categories,
  });

  final String siteUrl;
  final TopicFeed feed;
  final List<TopicCategory> categories;

  @override
  State<TopicFilterPage> createState() => _TopicFilterPageState();
}

class _TopicFilterPageState extends State<TopicFilterPage> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);
  final FocusNode _focus = FocusNode();

  TopicFilterController? _filter;

  TopicFilterController get filter => _filter!;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focus.hasFocus && _filter != null) {
      unawaited(filter.openSuggestions());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _filter ??= _buildController();
  }

  @override
  void didUpdateWidget(TopicFilterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) {
      _filter?.removeListener(_onFilterChanged);
      _filter?.dispose();
      _filter = _buildController();
      return;
    }
    filter.updateEngine(_engine());
  }

  TopicFilterController _buildController() {
    final shell = ShellScope.read(context);
    final controller = TopicFilterController(
      initialQuery: shell.filterQueryFor(widget.siteUrl),
      submitQuery: shell.submitTopicFilter,
      engine: _engine(),
    );
    controller.addListener(_onFilterChanged);
    return controller;
  }

  TopicFilterSuggestions _engine() {
    final shell = ShellScope.read(context);
    return TopicFilterSuggestions(
      options: widget.feed.filterOptions,
      categories: widget.categories,
      tags: (term) =>
          shell.searchFilterTags(siteUrl: widget.siteUrl, term: term),
      tagGroups: (term) =>
          shell.searchFilterTagGroups(siteUrl: widget.siteUrl, term: term),
      users: (term) =>
          shell.searchFilterUsers(siteUrl: widget.siteUrl, term: term),
      groups: (term) =>
          shell.searchFilterGroups(siteUrl: widget.siteUrl, term: term),
    );
  }

  void _onFilterChanged() {
    if (!mounted) return;
    if (filter.isOpen) {
      _anchor.value = _anchorRect();
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  Rect? _anchorRect() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return null;
    return Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when filter.isOpen:
        filter.moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when filter.isOpen:
        filter.moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape when filter.isOpen:
        filter.dismiss();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab when filter.isOpen:
        unawaited(
          filter.ensureFreshSuggestions().then((_) => filter.acceptSelected()),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (filter.isOpen && filter.selected != null) {
          unawaited(
            filter.ensureFreshSuggestions().then(
              (_) => filter.acceptSelected(),
            ),
          );
        } else {
          unawaited(filter.submit());
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _filter?.removeListener(_onFilterChanged);
    _filter?.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _anchor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
                valueListenable: _anchor,
                builder: (context, anchor, child) => CustomSingleChildLayout(
                  delegate: AnchoredLayout(
                    anchor: anchor,
                    maxWidth: anchor?.width ?? 720,
                    preferAbove: false,
                  ),
                  child: child!,
                ),
                child: _SuggestionList(filter: filter),
              ),
              child: KeyedSubtree(
                key: _anchorKey,
                child: TextField(
                  key: const ValueKey('topic-filter-input'),
                  controller: filter.text,
                  focusNode: _focus,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText:
                        'Filter topics by category, tag, or other criteria',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: DIcon(DIcons.filter, size: 17),
                    ),
                    suffixIcon: filter.text.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('clear-topic-filter'),
                            tooltip: 'Clear filter',
                            onPressed: () => unawaited(filter.clear()),
                            icon: const DIcon(DIcons.xmark, size: 17),
                          ),
                    filled: true,
                    fillColor: theme.shell.content,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    filter.inputChanged(value);
                    setState(() {});
                  },
                  onTap: () {
                    if (!filter.menuRequested) {
                      unawaited(filter.openSuggestions());
                    }
                  },
                  onTapOutside: (_) {
                    filter.dismiss();
                    _focus.unfocus();
                  },
                ),
              ),
            ),
          ),
        ),
        Expanded(child: TopicListView(feed: widget.feed)),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.filter});

  final TopicFilterController filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: filter,
      builder: (context, _) {
        if (!filter.isOpen) return const SizedBox.shrink();
        return Material(
          color: theme.shell.floating,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              border: Border.all(color: theme.shell.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filter.suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = filter.suggestions[index];
                final isSelected = index == filter.selectedIndex;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => filter.select(index),
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(filter.accept(suggestion)),
                      child: Container(
                        key: ValueKey('topic-filter-suggestion-$index'),
                        color: isSelected ? theme.shell.hover : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            DIcon(
                              suggestion.category == null
                                  ? DIcons.filter
                                  : DIcons.folder,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                suggestion.category?.name ?? suggestion.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (suggestion.category == null)
                              if (suggestion.description
                                  case final description?) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
