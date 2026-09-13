import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'shell_scope.dart';

part 'global_search_filter_picker.dart';

/// Search scopes, conditions and results below the shell's persistent input.
/// The caller owns the anchored surface and result navigation.
class GlobalSearchPanel extends StatefulWidget {
  const GlobalSearchPanel({
    super.key,
    required this.controller,
    required this.onOpen,
    this.selectedResultId,
    this.onSelect,
  });

  final GlobalSearchController controller;
  final ValueChanged<GlobalSearchResult> onOpen;
  final String? selectedResultId;
  final ValueChanged<String>? onSelect;

  @override
  State<GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _GlobalSearchPanelState extends State<GlobalSearchPanel> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _resultKeys = {};

  @override
  void didUpdateWidget(GlobalSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedResultId != widget.selectedResultId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _resultKeys[widget.selectedResultId]?.currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .55,
              ),
              child: DScrollArea(
                thumbVisibility: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final tools = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _GlobalSearchFilterPicker(controller: controller),
                              const SizedBox(width: 4),
                              _GlobalSearchDisplay(controller: controller),
                            ],
                          );
                          final scopes = Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final scope in controller.scopes)
                                DToggle(
                                  key: ValueKey(
                                    'global-search-scope-${scope.name}',
                                  ),
                                  pressed: controller.scope == scope,
                                  onPressedChanged: (_) =>
                                      controller.setScope(scope),
                                  variant: DToggleVariant.outline,
                                  size: DToggleSize.small,
                                  semanticLabel: 'Search ${scope.label}',
                                  child: Text(scope.label),
                                ),
                            ],
                          );
                          if (constraints.maxWidth < 530) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                scopes,
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: tools,
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: scopes),
                              const SizedBox(width: 8),
                              tools,
                            ],
                          );
                        },
                      ),
                    ),
                    if (controller.conditions.isNotEmpty) _conditions(context),
                  ],
                ),
              ),
            ),
            const DSeparator(),
            Expanded(child: _body(context)),
          ],
        ),
      );
    },
  );

  Widget _conditions(BuildContext context) {
    final controller = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DTokens.of(context).muted,
          borderRadius: DTokens.of(context).borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (
                  var index = 0;
                  index < controller.conditions.length;
                  index++
                )
                  _GlobalSearchFilterPicker(
                    key: ValueKey('global-search-condition-$index'),
                    controller: controller,
                    conditionIndex: index,
                    maxChipWidth: constraints.maxWidth,
                  ),
                _GlobalSearchFilterPicker(
                  controller: controller,
                  addOnly: true,
                ),
                DButton(
                  key: const ValueKey('global-search-clear-conditions'),
                  label: const Text('Clear'),
                  onPressed: controller.clearConditions,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  semanticLabel: 'Clear all search conditions',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    final phase = controller.phase;
    if (phase == GlobalSearchPhase.idle) return _history(context);
    if (phase == GlobalSearchPhase.tooShort) {
      return _status(
        'Keep typing',
        'Enter at least ${controller.capabilities.minimumLength} characters to search.',
      );
    }
    if (phase == GlobalSearchPhase.loading && controller.results.isEmpty) {
      return const Center(child: DSpinner(semanticLabel: 'Searching'));
    }
    if (phase == GlobalSearchPhase.failed && controller.results.isEmpty) {
      return _status(
        'Search could not load',
        controller.error ?? 'Please try again.',
        error: true,
      );
    }
    if (phase == GlobalSearchPhase.empty) {
      return _status(
        'No results found',
        'Try different words or remove a condition.',
        clear: controller.conditions.isNotEmpty,
      );
    }
    final children = <Widget>[
      if (phase == GlobalSearchPhase.loading)
        const Padding(
          padding: EdgeInsets.all(12),
          child: DSpinner(size: 16, semanticLabel: 'Updating search'),
        ),
      for (final section in controller.sections.where(
        (section) =>
            controller.scope != GlobalSearchScope.all ||
            section.results.isNotEmpty ||
            section.error != null,
      )) ...[
        if (controller.scope == GlobalSearchScope.all)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 8, 4),
            child: Row(
              children: [
                Expanded(child: DLabel(child: Text(section.scope.label))),
                if (section.results.isNotEmpty)
                  DButton(
                    label: const Text('View all'),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                    onPressed: () => controller.setScope(section.scope),
                    semanticLabel: 'View all ${section.scope.label} results',
                  ),
              ],
            ),
          ),
        if (section.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.error!,
                  style: TextStyle(color: DTokens.of(context).destructive),
                ),
                DButton(
                  label: const Text('Retry'),
                  onPressed: controller.retry,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                ),
              ],
            ),
          ),
        for (final result in section.results) _result(context, result),
      ],
      if (controller.error != null &&
          controller.results.isNotEmpty &&
          !controller.sections.any(
            (section) => section.error == controller.error,
          ))
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            controller.error!,
            style: TextStyle(color: DTokens.of(context).destructive),
          ),
        ),
      if (controller.hasMore || controller.loadingMore)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: DButton(
              key: const ValueKey('global-search-load-more'),
              label: const Text('Load more'),
              loading: controller.loadingMore,
              onPressed: controller.loadMore,
              variant: DButtonVariant.outline,
            ),
          ),
        ),
    ];
    _resultKeys.removeWhere(
      (id, _) => !controller.results.any((result) => result.id == id),
    );
    return DScrollBar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: children,
      ),
    );
  }

  Widget _history(BuildContext context) {
    final controller = widget.controller;
    return DScrollBar(
      controller: _scroll,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text(
              'Recent searches',
              style: TextStyle(color: DTokens.of(context).mutedForeground),
            ),
          ),
          for (final query in controller.recentSearches)
            DItem(
              size: DItemSize.sm,
              onPressed: () => controller.useRecentSearch(query),
              children: [
                DItemContent(children: [DItemTitle(child: Text(query))]),
              ],
            ),
          if (controller.recentSearches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Your searches will appear here.',
                style: TextStyle(color: DTokens.of(context).mutedForeground),
              ),
            ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  controller.error!,
                  style: TextStyle(color: DTokens.of(context).destructive),
                ),
              ),
            ),
          if (controller.recentSearches.isNotEmpty)
            DItem(
              key: const ValueKey('global-search-clear-history'),
              size: DItemSize.sm,
              onPressed: controller.clearHistory,
              children: [
                DItemMedia(
                  child: DIcon(
                    DIcons.xmark,
                    size: 14,
                    color: DTokens.of(context).mutedForeground,
                  ),
                ),
                DItemContent(
                  children: [
                    DItemTitle(
                      child: Text(
                        'Clear history',
                        style: TextStyle(
                          color: DTokens.of(context).mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _status(
    String title,
    String description, {
    bool error = false,
    bool clear = false,
  }) => SingleChildScrollView(
    child: DEmpty(
      padding: const EdgeInsets.all(24),
      children: [
        DEmptyHeader(
          children: [
            DEmptyMedia(
              variant: DEmptyMediaVariant.icon,
              child: DIcon(
                error ? DIcons.triangleExclamation : DIcons.magnifyingGlass,
              ),
            ),
            DEmptyTitle(title),
            DEmptyDescription(description),
          ],
        ),
        if (error)
          DButton(
            label: const Text('Try again'),
            onPressed: widget.controller.retry,
            variant: DButtonVariant.outline,
          ),
        if (clear)
          DButton(
            label: const Text('Clear conditions'),
            onPressed: widget.controller.clearConditions,
            variant: DButtonVariant.outline,
          ),
      ],
    ),
  );

  Widget _result(BuildContext context, GlobalSearchResult result) {
    final controller = widget.controller;
    final properties = controller.properties;
    final tokens = DTokens.of(context);
    final category = ShellScope.maybeOf(
      context,
    )?.categoryFor(result.categoryId, siteUrl: controller.siteUrl);
    final metadata = <Widget>[
      if (properties.contains(GlobalSearchDisplayProperty.author) &&
          result.username?.isNotEmpty == true)
        Text('@${result.username}'),
      if (result.channelTitle?.isNotEmpty == true)
        Text('# ${result.channelTitle}'),
      if (properties.contains(GlobalSearchDisplayProperty.category) &&
          category != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(
              category: category,
              size: 12,
              siteUrl: controller.siteUrl,
            ),
            const SizedBox(width: 4),
            Text(category.name),
          ],
        ),
      if (properties.contains(GlobalSearchDisplayProperty.tags))
        for (final tag in result.tags) Text('#$tag'),
      if (properties.contains(GlobalSearchDisplayProperty.likes) &&
          result.likes != null)
        Text('${result.likes} likes'),
      if (properties.contains(GlobalSearchDisplayProperty.replies) &&
          result.replies != null)
        Text('${result.replies} replies'),
      if (result.memberCount != null) Text('${result.memberCount} members'),
      if (result.createdAt != null) Text(_searchDate(result.createdAt!)),
      if (result.privateMessage) const Text('Personal message'),
      if (result.closed) const Text('Closed'),
      if (result.archived) const Text('Archived'),
    ];
    return KeyedSubtree(
      key: _resultKeys.putIfAbsent(result.id, GlobalKey.new),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          if (focused) widget.onSelect?.call(result.id);
        },
        child: DItem(
          key: ValueKey('global-search-result-${result.id}'),
          size: controller.compact ? DItemSize.xs : DItemSize.standard,
          onPressed: () {
            widget.onSelect?.call(result.id);
            widget.onOpen(result);
          },
          link: true,
          selected: widget.selectedResultId == result.id,
          showSelectionIndicator: false,
          children: [
            DItemMedia(
              child:
                  result.scope == GlobalSearchScope.users ||
                      result.scope == GlobalSearchScope.chat
                  ? DAvatar(
                      size: DAvatarSize.standard,
                      decorative: true,
                      child: AvatarImage(
                        url: result.avatarUrl,
                        size: 32,
                        fallback: DAvatarFallback(
                          child: Text(
                            (result.username ?? result.title).characters
                                .take(1)
                                .toString()
                                .toUpperCase(),
                          ),
                        ),
                      ),
                    )
                  : DIcon(
                      result.scope == GlobalSearchScope.groups
                          ? DIcons.users
                          : DIcons.comments,
                      size: 18,
                      color: tokens.mutedForeground,
                    ),
            ),
            DItemContent(
              children: [
                DItemTitle(
                  maxLines: 2,
                  child: _SearchHighlight(
                    text: result.title,
                    query: controller.query,
                  ),
                ),
                if (properties.contains(GlobalSearchDisplayProperty.excerpt) &&
                    result.excerpt.isNotEmpty)
                  DItemDescription(
                    maxLines: controller.compact ? 1 : 2,
                    child: _SearchHighlight(
                      text: result.excerpt,
                      query: controller.query,
                    ),
                  ),
                if (metadata.isNotEmpty)
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.mutedForeground,
                    ),
                    child: Wrap(spacing: 10, runSpacing: 3, children: metadata),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _searchDate(DateTime value) =>
    '${value.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} ${value.year}';

class _SearchHighlight extends StatelessWidget {
  const _SearchHighlight({required this.text, required this.query});
  final String text, query;
  @override
  Widget build(BuildContext context) {
    final words = query
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 1 && !word.contains(':'))
        .map((word) => word.replaceAll('"', ''))
        .where((word) => word.isNotEmpty)
        .toSet();
    if (words.isEmpty) return Text(text);
    final expression = RegExp(
      words.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in expression.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: DTokens.of(context).foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(children: spans));
  }
}

class _GlobalSearchDisplay extends StatelessWidget {
  const _GlobalSearchDisplay({required this.controller});
  final GlobalSearchController controller;
  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 320,
      align: DPopoverAlign.end,
      semanticLabel: 'Ordering and display',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DLabel(child: Text('Ordering')),
            const SizedBox(height: 8),
            DSelect<String>.controlled(
              key: const ValueKey('global-search-order'),
              value: controller.order,
              onChanged: (value) {
                if (value != null) controller.setOrder(value);
              },
              width: double.infinity,
              semanticLabel: 'Order search results',
              entries: [
                for (final order in controller.orders)
                  DSelectItem(
                    value: order.value,
                    textValue: order.label,
                    child: Text(order.label),
                  ),
              ],
            ),
            if (controller.canOrderAscending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Text('Ascending')),
                  DSwitch(
                    value: controller.ascending,
                    onChanged: (value) =>
                        controller.setOrder(controller.order, ascending: value),
                    semanticLabel: 'Ascending order',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Compact rows')),
                DSwitch(
                  value: controller.compact,
                  onChanged: controller.setCompact,
                  semanticLabel: 'Compact results',
                ),
              ],
            ),
            const DSeparator(space: 25),
            const DLabel(child: Text('Display properties')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final property in GlobalSearchDisplayProperty.values.where(
                  (property) =>
                      controller.scope == GlobalSearchScope.all ||
                      controller.scope == GlobalSearchScope.forum ||
                      property == GlobalSearchDisplayProperty.excerpt ||
                      (controller.scope == GlobalSearchScope.chat &&
                          property == GlobalSearchDisplayProperty.likes),
                ))
                  DToggle(
                    pressed: controller.properties.contains(property),
                    onPressedChanged: (value) =>
                        controller.setDisplayProperty(property, value),
                    variant: DToggleVariant.outline,
                    size: DToggleSize.small,
                    child: Text(switch (property) {
                      GlobalSearchDisplayProperty.excerpt => 'Excerpt',
                      GlobalSearchDisplayProperty.category => 'Category',
                      GlobalSearchDisplayProperty.tags => 'Tags',
                      GlobalSearchDisplayProperty.author => 'Author',
                      GlobalSearchDisplayProperty.likes => 'Likes',
                      GlobalSearchDisplayProperty.replies => 'Replies',
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, state) => DButton.iconOnly(
        key: const ValueKey('global-search-display-trigger'),
        icon: const DIcon(DIcons.gear),
        tooltip: 'Ordering and display',
        variant: DButtonVariant.outline,
        size: DButtonSize.small,
        expanded: state.open,
        hasPopup: true,
        focusNode: state.focusNode,
        onPressed: state.toggle,
      ),
    ),
  );
}
