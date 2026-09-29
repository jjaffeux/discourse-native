import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../foundation/calendar_day.dart';
import '../foundation/count_label.dart';
import '../models/topic.dart';
import '../plugin_api/global_search.dart' show GlobalSearchLookup;
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'global_search_api.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'open_link.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'site_url.dart';

part 'global_search_category_editor.dart';
part 'global_search_filter_picker.dart';

final RegExp _whitespace = RegExp(r'\s+');

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
                          final scopes = DScrollArea(
                            axes: DScrollAxes.horizontal,
                            showScrollbar: false,
                            child: Row(
                              spacing: DSpacing.controlGap,
                              children: [
                                for (final scope in controller.scopes)
                                  DToggle(
                                    key: ValueKey(
                                      'global-search-scope-${scope.keyName}',
                                    ),
                                    pressed: controller.scope == scope,
                                    onPressedChanged: (_) =>
                                        controller.setScope(scope),
                                    variant: DToggleVariant.outline,
                                    size: DToggleSize.small,
                                    selectedIcon: const DIcon(DIcons.check),
                                    semanticLabel: context.l10n
                                        .searchGlobalsearchpanel(
                                          (scope.label).toString(),
                                        ),
                                    child: Text(scope.label),
                                  ),
                              ],
                            ),
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
          borderRadius: BorderRadius.circular(DRadius.panel),
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
                  label: Text(context.l10n.clear),
                  onPressed: controller.clearConditions,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  semanticLabel: context.l10n.clearAllSearchConditions,
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
        context.l10n.keepTyping,
        context.l10n.enterAtLeastCharactersToSearch(
          (controller.capabilities.minimumLength).toString(),
        ),
      );
    }
    final results = controller.results;
    if (phase == GlobalSearchPhase.loading && results.isEmpty) {
      return const SizedBox.shrink();
    }
    if (phase == GlobalSearchPhase.failed && results.isEmpty) {
      return _status(
        context.l10n.searchCouldNotLoad,
        controller.error ?? context.l10n.pleaseTryAgain,
        error: true,
      );
    }
    if (phase == GlobalSearchPhase.empty) {
      return _status(
        context.l10n.noResultsFound,
        context.l10n.tryDifferentWordsOrRemoveACondition,
        clear: controller.conditions.isNotEmpty,
      );
    }
    final children = <Widget>[
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
                    label: Text(context.l10n.viewAll),
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                    onPressed: () => controller.setScope(section.scope),
                    semanticLabel: context.l10n.viewAllResults(
                      (section.scope.label).toString(),
                    ),
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
                  label: Text(context.l10n.retry),
                  onPressed: controller.retry,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                ),
              ],
            ),
          ),
        for (final result in section.results) _result(result),
      ],
      if (controller.error != null &&
          results.isNotEmpty &&
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
              label: Text(context.l10n.loadMore),
              loading: controller.loadingMore,
              onPressed: controller.loadMore,
              variant: DButtonVariant.outline,
            ),
          ),
        ),
    ];
    final ids = {for (final result in results) result.id};
    _resultKeys.removeWhere((id, _) => !ids.contains(id));
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
          if (controller.recentSearches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                context.l10n.recentSearches,
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
                        context.l10n.clearHistory,
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
            label: Text(appL10n.tryAgain),
            onPressed: widget.controller.retry,
            variant: DButtonVariant.outline,
          ),
        if (clear)
          DButton(
            label: Text(appL10n.clearConditions),
            onPressed: widget.controller.clearConditions,
            variant: DButtonVariant.outline,
          ),
      ],
    ),
  );

  Widget _result(GlobalSearchResult result) {
    final controller = widget.controller;
    final site = controller.siteUrl;
    return KeyedSubtree(
      key: _resultKeys.putIfAbsent(result.id, GlobalKey.new),
      child: LinkTarget(
        url: site == null
            ? result.path
            : resolveSiteRootPath(site, result.path),
        siteUrl: site,
        title: result.title,
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            if (focused) widget.onSelect?.call(result.id);
          },
          // The shell notifies for every navigation and tracking event; only
          // this row's category may change what the row draws.
          child: ShellSelector<TopicCategory?>(
            select: (shell) => shell.categoryFor(
              result.categoryId,
              siteUrl: controller.siteUrl,
            ),
            builder: (context, category, _) =>
                _resultItem(context, result, category),
          ),
        ),
      ),
    );
  }

  Widget _resultItem(
    BuildContext context,
    GlobalSearchResult result,
    TopicCategory? category,
  ) {
    final controller = widget.controller;
    final properties = controller.properties;
    final tokens = DTokens.of(context);
    final metadata = <Widget>[
      if (properties.contains(GlobalSearchDisplayProperty.author) &&
          result.username?.isNotEmpty == true)
        Text('@${result.username}'),
      if (result.contextLabel?.isNotEmpty == true) Text(result.contextLabel!),
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
      if (result.likes case final likes?
          when properties.contains(GlobalSearchDisplayProperty.likes))
        Text(countLabel(likes, CountNoun.like)),
      if (result.replies case final replies?
          when properties.contains(GlobalSearchDisplayProperty.replies))
        Text(countLabel(replies, CountNoun.reply)),
      if (result.memberCount case final members?)
        Text(countLabel(members, CountNoun.member)),
      if (result.createdAt != null) Text(_searchDate(result.createdAt!)),
      if (result.privateMessage) Text(context.l10n.personalMessage),
      if (result.closed) Text(context.l10n.closed),
      if (result.archived) Text(context.l10n.archived),
    ];
    return DItem(
      key: ValueKey('global-search-result-${result.id}'),
      size: DItemSize.standard,
      onPressed: () {
        widget.onSelect?.call(result.id);
        widget.onOpen(result);
      },
      link: true,
      selected: widget.selectedResultId == result.id,
      showSelectionIndicator: false,
      children: [
        DItemMedia(
          child: result.scope.showAvatar
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
                siteUrl: controller.siteUrl!,
                text: result.title,
                query: controller.query,
              ),
            ),
            if (properties.contains(GlobalSearchDisplayProperty.excerpt) &&
                result.excerpt.isNotEmpty)
              DItemDescription(
                maxLines: 2,
                child: _SearchHighlight(
                  siteUrl: controller.siteUrl!,
                  text: result.excerpt,
                  query: controller.query,
                ),
              ),
            if (metadata.isNotEmpty)
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: DiscourseTypography.xs,
                  color: tokens.mutedForeground,
                ),
                child: Wrap(spacing: 10, runSpacing: 3, children: metadata),
              ),
          ],
        ),
      ],
    );
  }
}

String _searchDate(DateTime value) {
  final day = calendarDay(value)!;
  return '${day.day} ${shortMonthName(day.month)} ${day.year}';
}

class _SearchHighlight extends StatelessWidget {
  const _SearchHighlight({
    required this.siteUrl,
    required this.text,
    required this.query,
  });
  final String siteUrl, text, query;
  @override
  Widget build(BuildContext context) {
    final words = query
        .split(_whitespace)
        .where((word) => word.length > 1 && !word.contains(':'))
        .map((word) => word.replaceAll('"', ''))
        .where((word) => word.isNotEmpty)
        .toSet();
    if (words.isEmpty) return SiteEmojiText.plain(text, siteUrl: siteUrl);
    final expression = RegExp(
      words.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final runs = <SiteEmojiTextRun>[];
    var cursor = 0;
    for (final match in expression.allMatches(text)) {
      if (match.start > cursor) {
        runs.add(SiteEmojiTextRun(text.substring(cursor, match.start)));
      }
      runs.add(
        SiteEmojiTextRun(
          match.group(0)!,
          style: TextStyle(
            color: DTokens.of(context).foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      runs.add(SiteEmojiTextRun(text.substring(cursor)));
    }
    return SiteEmojiText(runs, siteUrl: siteUrl);
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
      semanticLabel: context.l10n.orderingAndDisplay,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DLabel(child: Text(context.l10n.ordering)),
            const SizedBox(height: 8),
            DSelect<String>.controlled(
              key: const ValueKey('global-search-order'),
              value: controller.order,
              onChanged: (value) {
                if (value != null) controller.setOrder(value);
              },
              width: double.infinity,
              semanticLabel: context.l10n.orderSearchResults,
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
                  Expanded(child: Text(context.l10n.ascending)),
                  DSwitch(
                    value: controller.ascending,
                    onChanged: (value) =>
                        controller.setOrder(controller.order, ascending: value),
                    semanticLabel: context.l10n.ascendingOrder,
                  ),
                ],
              ),
            ],
            const DSeparator(space: 25),
            DLabel(child: Text(context.l10n.displayProperties)),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final property in GlobalSearchDisplayProperty.values.where(
                  (property) =>
                      controller.scope == GlobalSearchScope.all ||
                      controller.scope == GlobalSearchScope.forum ||
                      controller.scope.displayProperties.contains(property),
                ))
                  DCheckbox(
                    key: ValueKey('global-search-property-${property.name}'),
                    value: controller.properties.contains(property),
                    onChanged: (value) =>
                        controller.setDisplayProperty(property, value == true),
                    title: Text(switch (property) {
                      GlobalSearchDisplayProperty.excerpt =>
                        context.l10n.excerpt,
                      GlobalSearchDisplayProperty.category =>
                        context.l10n.category,
                      GlobalSearchDisplayProperty.tags => context.l10n.tags,
                      GlobalSearchDisplayProperty.author => context.l10n.author,
                      GlobalSearchDisplayProperty.likes => context.l10n.likes,
                      GlobalSearchDisplayProperty.replies =>
                        context.l10n.replies,
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
        tooltip: context.l10n.orderingAndDisplay,
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
