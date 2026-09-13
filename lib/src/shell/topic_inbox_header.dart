import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'anchored_picker.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'open_link.dart';
import 'platform.dart';
import 'relative_time.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_header_tags.dart';
import 'topic_title.dart';
import 'user_menu_button.dart';

/// Fixed topic title and actions with taxonomy in the post viewport.
/// [bodyBuilder] inserts the supplied slivers before the virtualized post list.
class TopicInboxHeader extends StatefulWidget {
  const TopicInboxHeader({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.canReturnToSidebar,
    required this.keepTopicListOpen,
    required this.registry,
    this.route,
    this.topic,
    this.scrollController,
    this.hasEarlierPosts = false,
    this.bodyBuilder,
  });

  final String title;
  final String? siteUrl;
  final bool canReturnToSidebar;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final ContentRoute? route;
  final TopicDetail? topic;
  final ScrollController? scrollController;
  final bool hasEarlierPosts;
  final Widget Function(List<Widget> openingSlivers, double pinnedExtent)?
  bodyBuilder;

  @override
  State<TopicInboxHeader> createState() => _TopicInboxHeaderState();
}

class _TopicInboxHeaderState extends State<TopicInboxHeader> {
  final _taxonomyKey = GlobalKey();
  final _pinnedExtent = FrameSafeValueNotifier(0.0);
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _updateAfterLayout();
  }

  @override
  void didUpdateWidget(TopicInboxHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAfterLayout();
  }

  void _updateAfterLayout() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) _updatePinnedExtent();
    });
  }

  void _updatePinnedExtent() {
    final taxonomy = _taxonomyKey.currentContext?.findRenderObject();
    if (taxonomy is RenderSliver) {
      _pinnedExtent.value = taxonomy.geometry?.maxScrollObstructionExtent ?? 0;
    }
  }

  @override
  void dispose() {
    _pinnedExtent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final siteUrl = widget.siteUrl;
    final hasTopic = topic != null && siteUrl != null;
    final showActivity = hasTopic && !widget.hasEarlierPosts;
    final taxonomy = hasTopic
        ? ColoredBox(
            color: Theme.of(context).shell.content,
            child: _TopicHeaderReadingLane(
              child: Padding(
                padding: const EdgeInsets.only(bottom: DSpacing.sm),
                child: _TopicHeaderTaxonomy(
                  siteUrl: siteUrl,
                  topic: topic,
                  keepTopicListOpen: widget.keepTopicListOpen,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    final activity = hasTopic
        ? _TopicHeaderReadingLane(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _TopicActivitySummary(siteUrl: siteUrl, topic: topic),
            ),
          )
        : const SizedBox.shrink();
    final toolbar = _TopicHeaderToolbar(header: widget);
    final bodyBuilder = widget.bodyBuilder;
    if (bodyBuilder == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [toolbar, taxonomy, if (showActivity) activity],
      );
    }
    return Column(
      children: [
        toolbar,
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _updateAfterLayout();
              return false;
            },
            child: ValueListenableBuilder<double>(
              valueListenable: _pinnedExtent,
              builder: (context, pinnedExtent, _) => bodyBuilder([
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    _updateAfterLayout();
                    return PinnedHeaderSliver(
                      key: _taxonomyKey,
                      child: taxonomy,
                    );
                  },
                ),
                SliverToBoxAdapter(
                  child: showActivity ? activity : const SizedBox.shrink(),
                ),
              ], pinnedExtent),
            ),
          ),
        ),
      ],
    );
  }
}

class _TopicHeaderReadingLane extends StatelessWidget {
  const _TopicHeaderReadingLane({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    ),
  );
}

class _TopicHeaderToolbar extends StatelessWidget {
  const _TopicHeaderToolbar({required this.header});

  final TopicInboxHeader header;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final lane = ContentReadingLane.geometryFor(
        context,
        availableWidth: constraints.maxWidth,
        basePadding: const EdgeInsets.symmetric(horizontal: 12),
      );
      return ColoredBox(
        color: Theme.of(context).shell.content,
        child: ConstrainedBox(
          key: const ValueKey('topic-content-header'),
          constraints: const BoxConstraints(minHeight: shellHeaderHeight),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: lane.padding.left + 16,
              end: 12,
              top: 8,
              bottom: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: _TopicHeaderTitle(header: header),
                  ),
                ),
                _TopicHeaderActions(
                  header: header,
                  width: constraints.maxWidth,
                ),
                if (!header.keepTopicListOpen)
                  TopicCloseButton(
                    canReturnToSidebar: header.canReturnToSidebar,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TopicHeaderTitle extends StatelessWidget {
  const _TopicHeaderTitle({required this.header});
  final TopicInboxHeader header;

  @override
  Widget build(BuildContext context) {
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    final style = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    if (topic?.canEdit == true && siteUrl != null) {
      return InlineTopicTitleEditor(
        key: ValueKey(('topic-header-title', siteUrl, topic!.id)),
        title: header.title,
        siteUrl: siteUrl,
        style: style,
        maxLines: 3,
        onSave: (value) => ShellScope.read(
          context,
        ).saveTopicTitle(siteUrl: siteUrl, topicId: topic.id, title: value),
      );
    }
    final title = siteUrl == null
        ? Text(
            header.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: style,
          )
        : TopicTitle(
            header.title,
            key: const ValueKey('topic-header-compact-title'),
            siteUrl: siteUrl,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
    return DTooltip(message: header.title, child: title);
  }
}

class _TopicHeaderActions extends StatelessWidget {
  const _TopicHeaderActions({required this.header, required this.width});

  final TopicInboxHeader header;
  final double width;

  @override
  Widget build(BuildContext context) {
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topic != null && siteUrl != null)
          _TopicHeaderProperties(
            siteUrl: siteUrl,
            topic: topic,
            registry: header.registry,
            compact: width < 620,
          ),
        Row(
          key: const ValueKey('topic-header-common-actions'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (topic != null && siteUrl != null) ...[
              TopicStatusButton(
                siteUrl: siteUrl,
                topic: topic,
                topicFlags: ShellScope.read(
                  context,
                ).availableTopicFlagTypes(siteUrl, topic),
              ),
              if (width >= 440)
                TopicShareButton(
                  siteUrl: siteUrl,
                  topic: topic,
                  route: header.route,
                ),
            ],
            if (ShellTitleBar.columnsCarryUserMenu) const UserMenuButton(),
          ],
        ),
      ],
    );
  }
}

class TopicCloseButton extends StatelessWidget {
  const TopicCloseButton({super.key, required this.canReturnToSidebar});

  final bool canReturnToSidebar;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: const ValueKey('topic-close-reader'),
    icon: const DIcon(DNativeIcons.closeTopicPane, size: 20),
    tooltip: 'Collapse topic',
    variant: DButtonVariant.ghost,
    size: DButtonSize.extraSmall,
    onPressed: () {
      final controller = ShellScope.read(context);
      if (controller.topicListContent != null) {
        controller.closeTopicListReader();
      } else {
        controller.handleBack(canReturnToSidebar: canReturnToSidebar);
      }
    },
  );
}

bool _showTopicSubcategory({
  required TopicDetail topic,
  required TopicCategory? category,
  required TopicCategory? parent,
  required Iterable<TopicCategory> categories,
}) {
  final root = parent ?? category;
  return !topic.privateMessage &&
      (parent != null ||
          (root != null &&
              topic.canEdit &&
              categories.any(
                (item) =>
                    item.parentCategoryId == root.id && item.canCreateTopic,
              )));
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
                      Flexible(
                        child: Text(
                          'Closed',
                          style: style?.copyWith(fontWeight: FontWeight.w600),
                        ),
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
                      child: DTooltip(
                        message: participants[i].displayName,
                        child: DAvatar.frame(
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
                                    : participants[i].username.characters.first
                                          .toUpperCase(),
                                style: style?.copyWith(
                                  fontSize: DiscourseTypography.xs,
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
      final hasCategories = !topic.privateMessage;
      final hasSubcategory = _showTopicSubcategory(
        topic: topic,
        category: category,
        parent: parent,
        categories: shell.filterCategoriesFor(siteUrl),
      );
      final hasTags = topic.tags.isNotEmpty || topic.canEditTags;
      return LayoutBuilder(
        builder: (context, constraints) {
          final categoryWidth =
              (constraints.maxWidth * (hasSubcategory ? .28 : .42)).clamp(
                56.0,
                200.0,
              );
          // Reserve room for category artwork, the privacy lock, and saving.
          // Add the browse button and roomier padding only when each chip fits.
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final compressed = categoryWidth < 140 * scale;
          final showBrowse =
              categoryWidth >= (context.isTouch ? 152 : 104) * scale;
          return Row(
            key: const ValueKey('topic-header-taxonomy'),
            children: [
              if (hasCategories) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: categoryWidth),
                  child: _TopicCategoryControl(
                    key: const ValueKey('topic-header-parent-category'),
                    siteUrl: siteUrl,
                    topic: topic,
                    category: root,
                    subcategory: false,
                    keepTopicListOpen: keepTopicListOpen,
                    compressed: compressed,
                    showBrowseButton: showBrowse,
                  ),
                ),
                if (hasSubcategory) ...[
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: categoryWidth),
                    child: _TopicCategoryControl(
                      key: const ValueKey('topic-header-category'),
                      siteUrl: siteUrl,
                      topic: topic,
                      category: parent == null ? null : category,
                      subcategory: true,
                      parentCategoryId: root?.id,
                      keepTopicListOpen: keepTopicListOpen,
                      compressed: compressed,
                      showBrowseButton: showBrowse,
                    ),
                  ),
                ],
              ],
              if (hasTags) ...[
                if (hasCategories) const SizedBox(width: 8),
                Flexible(
                  child: TopicHeaderTags(
                    key: const ValueKey('topic-header-tags'),
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

class _TopicCategoryControl extends StatelessWidget {
  const _TopicCategoryControl({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.category,
    required this.subcategory,
    required this.keepTopicListOpen,
    required this.compressed,
    this.parentCategoryId,
    this.showBrowseButton = true,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicCategory? category;
  final bool subcategory;
  final int? parentCategoryId;
  final bool keepTopicListOpen;
  final bool compressed;
  final bool showBrowseButton;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final value = category;
    final uncategorized = shell.siteConfigFor(siteUrl).allowUncategorizedTopics
        ? shell
              .filterCategoriesFor(siteUrl)
              .where((item) => item.isUncategorized)
              .firstOrNull
        : null;
    return TopicCategoryMenuAnchor(
      siteUrl: siteUrl,
      topicId: topic.id,
      categoryId: topic.categoryId,
      selectedCategoryId: value?.id,
      enabled: topic.canEdit,
      rootOnly: !subcategory,
      parentCategoryId: subcategory ? parentCategoryId : null,
      removeCategoryId: subcategory ? parentCategoryId : uncategorized?.id,
      removeLabel: subcategory ? 'Remove subcategory' : 'Move to Uncategorized',
      builder: (context, edit, saving, trigger) {
        final browse = value == null
            ? null
            : () => shell.browseTopicCategory(
                value,
                keepTopicOpen: keepTopicListOpen,
              );
        final browseOnly = !showBrowseButton && !topic.canEdit;
        return _CategoryChip(
          category: value,
          siteUrl: siteUrl,
          label: value?.name ?? (subcategory ? '+ Subcategory' : '+ Category'),
          edit: browseOnly ? browse : edit,
          primaryIsLink: browseOnly,
          saving: saving,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          compact: compressed,
          editLabel: browseOnly
              ? 'Browse ${value?.name}'
              : subcategory
              ? 'Edit topic subcategory'
              : 'Edit topic category',
          navigate: showBrowseButton ? browse : null,
        );
      },
    );
  }
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
    required this.focusNode,
    required this.expanded,
    this.compact = false,
    this.primaryIsLink = false,
  });
  final TopicCategory? category;
  final String siteUrl;
  final String label;
  final String editLabel;
  final VoidCallback? edit;
  final VoidCallback? navigate;
  final bool saving;
  final FocusNode focusNode;
  final bool expanded;
  final bool compact;
  final bool primaryIsLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : Color(category!.colorValue);
    final tokens = DTokens.of(context);
    final fill = category == null
        ? tokens.controls?.outline.background
        : Color.lerp(tokens.background, color, .18);
    final border = category == null
        ? tokens.controls?.outline.border
        : Color.lerp(tokens.background, color, .38);
    final hover = category == null
        ? tokens.controls?.outline.hover
        : Color.lerp(tokens.background, color, .30);
    return IntrinsicWidth(
      child: DButtonGroup(
        semanticLabel: label,
        mainAxisSize: MainAxisSize.max,
        children: [
          DButtonGroupExpanded(
            child: DButton(
              onPressed: edit,
              focusNode: focusNode,
              expanded: expanded,
              hasPopup: !primaryIsLink && edit != null,
              isLink: primaryIsLink,
              tooltip: edit == null ? label : editLabel,
              semanticLabel: edit == null ? label : '$editLabel: $label',
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              backgroundColor: fill,
              borderColor: border,
              interactiveBackgroundColor: hover,
              loading: saving,
              loadingSemanticLabel: 'Saving category',
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != null) ...[
                    CategoryIcon(
                      category: category!,
                      siteUrl: siteUrl,
                      size: DControlStyle.iconDimension(DControlSize.small),
                    ),
                    SizedBox(width: compact ? 2 : 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!compact && edit != null && category != null) ...[
                    const SizedBox(width: 5),
                    const DIcon(DIcons.chevronDown),
                  ],
                ],
              ),
            ),
          ),
          if (navigate != null)
            LinkTarget(
              url: '/c/${category!.id}',
              title: category!.name,
              siteUrl: siteUrl,
              child: DButton.iconOnly(
                key: ValueKey('topic-header-browse-category-${category!.id}'),
                icon: const DIcon(DIcons.upRightFromSquare),
                tooltip: 'Browse ${category!.name}',
                isLink: true,
                onPressed: navigate,
                variant: DButtonVariant.outline,
                size: DButtonSize.small,
                backgroundColor: fill,
                borderColor: border,
                interactiveBackgroundColor: hover,
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
    this.compact = false,
  });
  final String siteUrl;
  final TopicDetail topic;
  final PluginRegistry registry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget properties() {
      final sections = registry.topicProperties(context, siteUrl, topic);
      if (sections.isEmpty) return const SizedBox.shrink();
      final children = <Widget>[
        for (final section in sections)
          _TopicPropertyPopover(
            key: ValueKey(('topic-header-property', section.label)),
            siteUrl: siteUrl,
            topicId: topic.id,
            section: section,
            registry: registry,
            compact: compact,
            navigationRevision: ShellScope.read(
              context,
            ).topicNavigationRevision,
          ),
      ];
      return compact
          ? Row(mainAxisSize: MainAxisSize.min, children: children)
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: children,
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

class _TopicPropertyPopover extends StatefulWidget {
  const _TopicPropertyPopover({
    super.key,
    required this.siteUrl,
    required this.topicId,
    required this.section,
    required this.registry,
    required this.compact,
    required this.navigationRevision,
  });

  final String siteUrl;
  final int topicId;
  final TopicPropertySection section;
  final PluginRegistry registry;
  final bool compact;
  final int navigationRevision;

  @override
  State<_TopicPropertyPopover> createState() => _TopicPropertyPopoverState();
}

class _TopicPropertyPopoverState extends State<_TopicPropertyPopover> {
  final _controller = DPopoverController();

  Widget _trigger(
    BuildContext context,
    VoidCallback showDetails, {
    FocusNode? focusNode,
    bool expanded = false,
  }) {
    final section = widget.section;
    if (widget.compact) {
      return section.compactHeader?.call(context, showDetails) ??
          DButton.iconOnly(
            icon: const DIcon(DIcons.ellipsis, size: 16),
            tooltip: section.label,
            size: DButtonSize.small,
            variant: DButtonVariant.ghost,
            hasPopup: true,
            expanded: expanded,
            focusNode: focusNode,
            onPressed: showDetails,
          );
    }
    return section.header?.call(context, showDetails) ??
        DButton(
          label: Text(section.label),
          size: DButtonSize.small,
          hasPopup: true,
          expanded: expanded,
          focusNode: focusNode,
          onPressed: showDetails,
        );
  }

  void _showTouch(BuildContext anchorContext) => unawaited(
    showAnchoredPicker<void>(
      context: context,
      anchorContext: anchorContext,
      title: widget.section.label,
      barrierLabel: 'Dismiss ${widget.section.label}',
      popoverHeight: null,
      popoverKey: ValueKey(('topic-header-property', widget.section.label)),
      builder: (pickerContext) => _TopicPropertyDetails(
        siteUrl: widget.siteUrl,
        topicId: widget.topicId,
        label: widget.section.label,
        registry: widget.registry,
        navigationRevision: widget.navigationRevision,
        onDismiss: () => Navigator.of(pickerContext).pop(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return Builder(
        builder: (anchorContext) =>
            _trigger(anchorContext, () => _showTouch(anchorContext)),
      );
    }
    return DPopover(
      controller: _controller,
      content: DPopoverContent(
        width: 252,
        padding: EdgeInsets.zero,
        semanticLabel: widget.section.label,
        align: DPopoverAlign.end,
        child: _TopicPropertyDetails(
          siteUrl: widget.siteUrl,
          topicId: widget.topicId,
          label: widget.section.label,
          registry: widget.registry,
          navigationRevision: widget.navigationRevision,
          onDismiss: _controller.close,
        ),
      ),
      child: DPopoverTrigger(
        builder: (context, trigger) => _trigger(
          context,
          trigger.toggle,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TopicPropertyDetails extends StatelessWidget {
  const _TopicPropertyDetails({
    required this.siteUrl,
    required this.topicId,
    required this.label,
    required this.registry,
    required this.navigationRevision,
    required this.onDismiss,
  });
  final String siteUrl;
  final int topicId;
  final String label;
  final PluginRegistry registry;
  final int navigationRevision;
  final VoidCallback onDismiss;

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
          if (context.mounted) onDismiss();
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
