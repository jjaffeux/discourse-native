import 'dart:async';

import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'anchored_picker.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_header_tags.dart';
import 'topic_list_layout.dart';
import 'topic_title.dart';
import 'user_menu_button.dart';

class TopicInboxHeader extends StatelessWidget {
  const TopicInboxHeader({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.canReturnToSidebar,
    required this.keepTopicListOpen,
    required this.registry,
    this.route,
    this.topic,
  });

  final String title;
  final String? siteUrl;
  final bool canReturnToSidebar;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final ContentRoute? route;
  final TopicDetail? topic;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildForWidth);

  Widget _buildForWidth(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final topic = this.topic;
    final siteUrl = this.siteUrl;
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: DiscourseTypography.fontUp3,
      height: 1.28,
      fontWeight: FontWeight.w600,
    );
    final lane = ContentReadingLane.geometryFor(
      context,
      availableWidth: constraints.maxWidth,
      basePadding: const EdgeInsets.symmetric(horizontal: 12),
    );
    final contentPadding = lane.padding.copyWith(
      left: lane.padding.left + 16,
      right: lane.padding.right + 16,
    );
    final taxonomy = topic != null && siteUrl != null
        ? _TopicHeaderTaxonomy(
            siteUrl: siteUrl,
            topic: topic,
            keepTopicListOpen: keepTopicListOpen,
          )
        : null;
    final actionDimension = DButton.iconOnlyDimensionFor(DButtonSize.small);
    final toolbarLeadingPadding = keepTopicListOpen
        ? topicInboxDividerInset
        : 16.0;
    final toolbarTopPadding = keepTopicListOpen
        ? (shellHeaderHeight - actionDimension) / 2
        : 4.0;
    final toolbarStart = toolbarLeadingPadding + actionDimension;
    // Share the toolbar only when the collapse control fits before the reading
    // lane. Taxonomy keeps the same leading edge as the title and posts.
    final inlineTaxonomy =
        taxonomy != null && contentPadding.left >= toolbarStart + 8;
    return DecoratedBox(
      key: const ValueKey('topic-content-header'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              toolbarLeadingPadding,
              toolbarTopPadding,
              12,
              0,
            ),
            child: Row(
              children: [
                DButton.iconOnly(
                  key: const ValueKey('topic-close-reader'),
                  icon: const DIcon(DNativeIcons.closeTopicPane, size: 20),
                  tooltip: 'Collapse topic',
                  variant: DButtonVariant.flat,
                  size: DButtonSize.small,
                  onPressed: () {
                    if (controller.topicListContent != null) {
                      controller.closeTopicListReader();
                    } else {
                      controller.handleBack(
                        canReturnToSidebar: canReturnToSidebar,
                      );
                    }
                  },
                ),
                Expanded(
                  child: inlineTaxonomy
                      ? Padding(
                          padding: EdgeInsets.only(
                            left: contentPadding.left - toolbarStart,
                            right: 8,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: lane.width - 32,
                              child: taxonomy,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (keepTopicListOpen) const _TopicInboxNavigation(),
                if (topic != null && siteUrl != null) ...[
                  TopicStatusButton(
                    siteUrl: siteUrl,
                    topic: topic,
                    topicFlags: controller.availableTopicFlagTypes(
                      siteUrl,
                      topic,
                    ),
                  ),
                  TopicShareButton(
                    siteUrl: siteUrl,
                    topic: topic,
                    route: route,
                  ),
                ],
                if (ShellTitleBar.columnsCarryUserMenu) const UserMenuButton(),
              ],
            ),
          ),
          Padding(
            padding: contentPadding.add(
              EdgeInsets.only(top: inlineTaxonomy ? 2 : 4, bottom: 12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (taxonomy != null && !inlineTaxonomy) ...[
                  taxonomy,
                  const SizedBox(height: 8),
                ],
                if (topic?.canEdit == true && siteUrl != null)
                  InlineTopicTitleEditor(
                    key: const ValueKey('topic-header-title'),
                    title: title,
                    siteUrl: siteUrl,
                    style: titleStyle,
                    maxLines: 3,
                    showEditingFrame: true,
                    onSave: (value) => controller.saveTopicTitle(
                      siteUrl: siteUrl,
                      topicId: topic!.id,
                      title: value,
                    ),
                  )
                else if (siteUrl != null)
                  TopicTitle(
                    title,
                    siteUrl: siteUrl,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                    key: const ValueKey('topic-header-title'),
                  )
                else
                  Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                if (topic != null && siteUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final summary = _TopicActivitySummary(
                          siteUrl: siteUrl,
                          topic: topic,
                        );
                        final properties = _TopicHeaderProperties(
                          siteUrl: siteUrl,
                          topic: topic,
                          registry: registry,
                        );
                        return constraints.maxWidth >= 560
                            ? Row(
                                children: [
                                  Expanded(child: summary),
                                  const SizedBox(width: 12),
                                  Expanded(child: properties),
                                ],
                              )
                            : Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [summary, properties],
                              );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicActivitySummary extends StatelessWidget {
  const _TopicActivitySummary({required this.siteUrl, required this.topic});
  final String siteUrl;
  final TopicDetail topic;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Topic?>(
    valueListenable: ShellScope.read(context).topicRef(siteUrl, topic.id),
    builder: (context, row, _) {
      final theme = Theme.of(context);
      final participants = topic.participants.take(3).toList();
      final style = theme.textTheme.labelSmall?.copyWith(
        fontSize: DiscourseTypography.fontDown2,
        color: theme.colorScheme.onSurfaceVariant,
      );
      return Wrap(
        key: const ValueKey('topic-header-activity'),
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (topic.closed)
            Semantics(
              key: const ValueKey('topic-header-closed'),
              label: 'Topic closed',
              excludeSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.shell.panel,
                  border: Border.all(color: theme.shell.divider),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DIcon(
                        DIcons.lock,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Closed',
                        style: style?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (participants.isNotEmpty)
            SizedBox(
              width: 20 + (participants.length - 1) * 15,
              height: 20,
              child: Stack(
                children: [
                  for (var i = 0; i < participants.length; i++)
                    Positioned(
                      left: i * 15,
                      child: Tooltip(
                        message: participants[i].displayName,
                        child: ClipOval(
                          child: AvatarImage(
                            url: participants[i].avatarUrl,
                            size: 20,
                            fallback: Container(
                              width: 20,
                              height: 20,
                              color: theme.shell.hover,
                              alignment: Alignment.center,
                              child: Text(
                                participants[i].username.isEmpty
                                    ? '?'
                                    : participants[i].username
                                          .substring(0, 1)
                                          .toUpperCase(),
                                style: style?.copyWith(
                                  fontSize: DiscourseTypography.fontDown3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Text(
            '${topic.replyCount} ${topic.replyCount == 1 ? 'reply' : 'replies'}',
            style: style,
          ),
          if (row?.bumpedAt case final activity?) ...[
            Text('·', style: style),
            Text(switch (relativeTime(activity)) {
              'now' => 'Last activity just now',
              final age => 'Last activity $age ago',
            }, style: style),
          ],
        ],
      );
    },
  );
}

class _TopicInboxNavigation extends StatelessWidget {
  const _TopicInboxNavigation();

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({int? previous, int? next, bool more, bool busy})>(
    select: (shell) {
      final ids = shell.currentFeed?.topicIds ?? const <int>[];
      final index = ids.indexOf(shell.currentContent?.topicId ?? -1);
      return (
        previous: index > 0 ? ids[index - 1] : null,
        next: index >= 0 && index + 1 < ids.length ? ids[index + 1] : null,
        more:
            index >= 0 &&
            index == ids.length - 1 &&
            shell.currentFeed?.hasMore == true,
        busy: shell.currentFeed?.loadingMore == true,
      );
    },
    builder: (context, state, _) {
      final shell = ShellScope.read(context);
      Future<void> open(int? id, {bool loadNext = false}) async {
        final siteUrl = shell.currentInstance?.url;
        final source = shell.currentFeedId;
        final current = shell.currentContent?.topicId;
        if (siteUrl == null) return;
        if (loadNext && source != null) {
          await shell.loadMoreFeed(source);
          if (shell.currentInstance?.url != siteUrl ||
              shell.currentFeedId != source ||
              shell.currentContent?.topicId != current) {
            return;
          }
          final ids = shell.currentFeed?.topicIds ?? const <int>[];
          final index = ids.indexOf(current ?? -1);
          id = index >= 0 && index + 1 < ids.length ? ids[index + 1] : null;
        }
        final topic = id == null ? null : shell.store.read<Topic>(siteUrl, id);
        if (topic != null) shell.openTopicFromList(topic);
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DButton.iconOnly(
            key: const ValueKey('inbox-previous-topic'),
            tooltip: 'Previous topic',
            icon: const DIcon(DIcons.chevronLeft, size: 13),
            onPressed: state.previous == null
                ? null
                : () => unawaited(open(state.previous)),
            variant: DButtonVariant.flat,
            size: DButtonSize.small,
          ),
          DButton.iconOnly(
            key: const ValueKey('inbox-next-topic'),
            tooltip: 'Next topic',
            icon: const DIcon(DIcons.chevronRight, size: 13),
            onPressed: state.busy || (state.next == null && !state.more)
                ? null
                : () =>
                      unawaited(open(state.next, loadNext: state.next == null)),
            variant: DButtonVariant.flat,
            size: DButtonSize.small,
          ),
        ],
      );
    },
  );
}

class _TopicHeaderTaxonomy extends StatelessWidget {
  const _TopicHeaderTaxonomy({
    required this.siteUrl,
    required this.topic,
    required this.keepTopicListOpen,
  });
  final String siteUrl;
  final TopicDetail topic;
  final bool keepTopicListOpen;

  @override
  Widget build(BuildContext context) => ShellSelector<Object>(
    select: (controller) => controller.presentationTokenFor(siteUrl),
    builder: (context, _, _) {
      final shell = ShellScope.read(context);
      final category = shell.categoryFor(topic.categoryId, siteUrl: siteUrl);
      final parent = shell.categoryFor(
        category?.parentCategoryId,
        siteUrl: siteUrl,
      );
      final root = parent ?? category;
      final uncategorized =
          shell.siteConfigFor(siteUrl).allowUncategorizedTopics
          ? shell
                .filterCategoriesFor(siteUrl)
                .where((item) => item.isUncategorized)
                .firstOrNull
          : null;
      Widget categoryControl(
        TopicCategory? value, {
        required bool subcategory,
      }) => TopicCategoryMenuAnchor(
        siteUrl: siteUrl,
        topicId: topic.id,
        categoryId: topic.categoryId,
        selectedCategoryId: value?.id,
        enabled: topic.canEdit,
        rootOnly: !subcategory,
        parentCategoryId: subcategory ? root?.id : null,
        removeCategoryId: subcategory ? root?.id : uncategorized?.id,
        removeLabel: subcategory
            ? 'Remove subcategory'
            : 'Move to Uncategorized',
        builder: (context, edit, saving) => _CategoryChip(
          category: value,
          siteUrl: siteUrl,
          label: value?.name ?? (subcategory ? '+ Subcategory' : '+ Category'),
          edit: edit,
          saving: saving,
          editLabel: subcategory
              ? 'Edit topic subcategory'
              : 'Edit topic category',
          navigate: value == null
              ? null
              : () => shell.browseTopicCategory(
                  value,
                  keepTopicOpen: keepTopicListOpen,
                ),
        ),
      );
      final hasCategories = !topic.privateMessage;
      final hasSubcategory =
          hasCategories &&
          (parent != null ||
              (root != null &&
                  topic.canEdit &&
                  shell
                      .filterCategoriesFor(siteUrl)
                      .any((item) => item.parentCategoryId == root.id)));
      final hasTags = topic.tags.isNotEmpty || topic.canEditTags;
      return LayoutBuilder(
        builder: (context, constraints) {
          final categoryWidth =
              (constraints.maxWidth * (hasSubcategory ? .28 : .42)).clamp(
                72.0,
                200.0,
              );
          return Row(
            key: const ValueKey('topic-header-taxonomy'),
            children: [
              if (hasCategories) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: categoryWidth),
                  child: categoryControl(root, subcategory: false),
                ),
                if (hasSubcategory) ...[
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: categoryWidth),
                    child: categoryControl(
                      parent == null ? null : category,
                      subcategory: true,
                    ),
                  ),
                ],
              ],
              if (hasTags) ...[
                if (hasCategories)
                  Container(
                    width: 1,
                    height: 15,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Theme.of(context).shell.divider,
                  ),
                Flexible(
                  child: TopicHeaderTags(
                    siteUrl: siteUrl,
                    topic: topic,
                    onTagNavigate: (tag, {newTab = false}) =>
                        shell.openTopicTag(
                          tag,
                          siteUrl: siteUrl,
                          privateMessage: topic.privateMessage,
                          newTab: newTab,
                        ),
                  ),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.siteUrl,
    required this.label,
    required this.editLabel,
    required this.edit,
    required this.navigate,
    required this.saving,
  });
  final TopicCategory? category;
  final String siteUrl;
  final String label;
  final String editLabel;
  final VoidCallback? edit;
  final VoidCallback? navigate;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : Color(category!.colorValue);
    final overlayColor = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.focused)) {
        return color.withValues(alpha: .16);
      }
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: .12);
      }
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: .08);
      }
      return Colors.transparent;
    });
    return Material(
      color: category == null
          ? Colors.transparent
          : color.withValues(alpha: .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: color.withValues(alpha: .25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Tooltip(
              message: edit == null ? label : editLabel,
              child: InkWell(
                onTap: edit,
                overlayColor: overlayColor,
                splashFactory: NoSplash.splashFactory,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (category != null) ...[
                        CategoryIcon(
                          category: category!,
                          siteUrl: siteUrl,
                          size: 12,
                          squareSize: 9,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: DiscourseTypography.fontDown2,
                          ),
                        ),
                      ),
                      if (edit != null && category != null && !saving) ...[
                        const SizedBox(width: 5),
                        DIcon(
                          DIcons.chevronDown,
                          size: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                      if (saving) ...[
                        const SizedBox(width: 6),
                        const SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (navigate != null)
            LinkTarget(
              url: '/c/${category!.id}',
              title: category!.name,
              siteUrl: siteUrl,
              child: Tooltip(
                message: 'Browse ${category!.name}',
                child: InkWell(
                  key: ValueKey('topic-header-browse-category-${category!.id}'),
                  onTap: navigate,
                  overlayColor: overlayColor,
                  splashFactory: NoSplash.splashFactory,
                  child: Container(
                    width: 25,
                    height: 28,
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: color.withValues(alpha: .22)),
                      ),
                    ),
                    child: Center(
                      child: DIcon(
                        DIcons.upRightFromSquare,
                        size: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicHeaderProperties extends StatelessWidget {
  const _TopicHeaderProperties({
    required this.siteUrl,
    required this.topic,
    required this.registry,
  });
  final String siteUrl;
  final TopicDetail topic;
  final PluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    Widget properties() {
      final sections = registry.topicProperties(context, siteUrl, topic);
      if (sections.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.zero,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final section in sections)
              Builder(
                builder: (anchorContext) {
                  void showDetails() => unawaited(
                    showAnchoredPicker<void>(
                      context: context,
                      anchorContext: anchorContext,
                      title: section.label,
                      barrierLabel: 'Dismiss ${section.label}',
                      popoverHeight: null,
                      popoverKey: ValueKey((
                        'topic-header-property',
                        section.label,
                      )),
                      builder: (_) => _TopicPropertyDetails(
                        siteUrl: siteUrl,
                        topicId: topic.id,
                        label: section.label,
                        registry: registry,
                        navigationRevision: ShellScope.read(
                          context,
                        ).topicNavigationRevision,
                      ),
                    ),
                  );
                  return section.header?.call(anchorContext, showDetails) ??
                      DButton(
                        label: Text(section.label),
                        size: DButtonSize.small,
                        onPressed: showDetails,
                      );
                },
              ),
          ],
        ),
      );
    }

    final rebuildOn = registry.topicPropertiesRebuildOn(
      context,
      siteUrl,
      topic,
    );
    return rebuildOn == null
        ? properties()
        : ListenableBuilder(
            listenable: rebuildOn,
            builder: (_, _) => properties(),
          );
  }
}

class _TopicPropertyDetails extends StatelessWidget {
  const _TopicPropertyDetails({
    required this.siteUrl,
    required this.topicId,
    required this.label,
    required this.registry,
    required this.navigationRevision,
  });
  final String siteUrl;
  final int topicId;
  final String label;
  final PluginRegistry registry;
  final int navigationRevision;

  @override
  Widget build(BuildContext context) => ShellSelector<(String?, int?, int)>(
    select: (shell) => (
      shell.currentInstance?.url,
      shell.currentContent?.topicId,
      shell.topicNavigationRevision,
    ),
    builder: (context, navigation, _) {
      if (navigation != (siteUrl, topicId, navigationRevision)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        });
      }
      return ValueListenableBuilder<TopicDetail?>(
        valueListenable: ShellScope.read(
          context,
        ).store.ref<TopicDetail>(siteUrl, topicId),
        builder: (context, topic, _) {
          if (topic == null) return const SizedBox.shrink();
          Widget details() {
            final section = registry
                .topicProperties(context, siteUrl, topic)
                .where((section) => section.label == label)
                .firstOrNull;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: section?.values ?? const [Text('None')],
              ),
            );
          }

          final rebuildOn = registry.topicPropertiesRebuildOn(
            context,
            siteUrl,
            topic,
          );
          return rebuildOn == null
              ? details()
              : ListenableBuilder(
                  listenable: rebuildOn,
                  builder: (_, _) => details(),
                );
        },
      );
    },
  );
}
