import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'anchored_picker.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'forum_theme_surfaces.dart';
import 'message_archive_button.dart';
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

/// Fixed topic title, actions and taxonomy above the post viewport.
/// [bodyBuilder] supplies the virtualized post list below the retracting header.
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
    this.preview,
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

  /// Cached list metadata to display until the full topic response arrives.
  final Topic? preview;
  final ScrollController? scrollController;
  final bool hasEarlierPosts;
  final Widget Function(List<Widget> openingSlivers)? bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    // Reuse the read-only taxonomy presentation without promoting a list row
    // into the detail cache or inferring permissions from incomplete data.
    final topic =
        this.topic ??
        (preview == null
            ? null
            : TopicDetail(
                id: preview.id,
                title: preview.title,
                stream: const [],
                categoryId: preview.categoryId,
                tags: preview.tags,
                privateMessage: preview.privateMessage,
                postsCount: preview.postsCount,
                replyCount: preview.replyCount,
              ));
    final siteUrl = this.siteUrl;
    final hasTopic = topic != null && siteUrl != null;
    final showActivity = hasTopic;
    final taxonomy = hasTopic
        ? ColoredBox(
            color: ForumWindowBackground.surfaceColor(
              context,
              Theme.of(context).shell.content,
            ),
            child: _TopicHeaderReadingLane(
              child: Padding(
                padding: const EdgeInsets.only(bottom: DSpacing.sm),
                child: _TopicHeaderTaxonomy(
                  siteUrl: siteUrl,
                  topic: topic,
                  keepTopicListOpen: keepTopicListOpen,
                  registry: registry,
                  showProperties: this.topic != null,
                  mobileActions:
                      ShellScope.read(context).mobileNavigationEnabled &&
                          this.topic != null
                      ? _MobileTopicHeaderActions(
                          siteUrl: siteUrl,
                          topic: topic,
                          registry: registry,
                        )
                      : null,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    final activity = hasTopic
        ? _TopicHeaderReadingLane(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: TopicActivitySummary(siteUrl: siteUrl, topic: topic),
            ),
          )
        : const SizedBox.shrink();
    final toolbar = _TopicHeaderToolbar(header: this);
    final bodyBuilder = this.bodyBuilder;
    if (bodyBuilder == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [toolbar, taxonomy, if (showActivity) activity],
      );
    }
    return DPageSurface(
      hideHeaderOnScroll: true,
      framed: false,
      identity: (siteUrl, topic?.id, scrollController),
      header: Column(children: [toolbar, taxonomy, if (showActivity) activity]),
      child: bodyBuilder(const []),
    );
  }
}

class _TopicHeaderReadingLane extends StatelessWidget {
  const _TopicHeaderReadingLane({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(width: double.infinity, child: child),
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
      );
      final padding = lane.padding.add(
        EdgeInsets.symmetric(
          horizontal: 16,
          vertical: context.isTouch ? 4 : 12,
        ),
      );
      final firstLineConstraints = BoxConstraints(
        minHeight: math.max(
          readerHeaderHeight - padding.vertical,
          math.max(
            context.isTouch ? DSpacing.touchTarget : 0,
            DControlStyle.scaledHeight(
              DControlSize.regular,
              MediaQuery.textScalerOf(context),
              context: context,
            ),
          ),
        ),
      );
      return ColoredBox(
        color: ForumWindowBackground.surfaceColor(
          context,
          Theme.of(context).shell.content,
        ),
        child: ConstrainedBox(
          key: const ValueKey('topic-content-header'),
          constraints: const BoxConstraints(minHeight: readerHeaderHeight),
          child: Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!header.keepTopicListOpen ||
                    context.isTouch ||
                    !ShellScope.read(context).forumTabsEnabled)
                  ConstrainedBox(
                    constraints: firstLineConstraints,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: DSpacing.sm,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 1,
                        heightFactor: 1,
                        child: TopicCloseButton(
                          canReturnToSidebar: header.canReturnToSidebar,
                          backToList: !header.keepTopicListOpen,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ConstrainedBox(
                      constraints: firstLineConstraints,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        heightFactor: 1,
                        child: _TopicHeaderTitle(header: header),
                      ),
                    ),
                  ),
                ),
                if (!ShellScope.read(context).mobileNavigationEnabled)
                  ConstrainedBox(
                    constraints: firstLineConstraints,
                    child: _TopicHeaderActions(header: header),
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
    final style = Theme.of(context).textTheme.headlineSmall;
    final Widget title;
    if (topic?.canEdit == true && siteUrl != null) {
      title = InlineTopicTitleEditor(
        key: ValueKey(('topic-header-title', siteUrl, topic!.id)),
        title: header.title,
        siteUrl: siteUrl,
        style: style,
        maxLines: 3,
        onSave: (value) => ShellScope.read(
          context,
        ).saveTopicTitle(siteUrl: siteUrl, topicId: topic.id, title: value),
      );
    } else {
      final text = siteUrl == null
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
      title = DTooltip(message: header.title, child: text);
    }
    final lineHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(style?.fontSize ?? DiscourseTypography.lg) *
        (style?.height ?? DiscourseTypography.lineHeightLarge);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.sm,
      children: [
        if ((topic?.closed ?? header.preview?.closed) == true)
          Padding(
            padding: EdgeInsets.only(top: math.max(0, (lineHeight - 16) / 2)),
            child: DIcon(
              DIcons.lock,
              key: const ValueKey('topic-header-closed'),
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              semanticLabel: 'Topic closed',
            ),
          ),
        Expanded(child: title),
      ],
    );
  }
}

class _TopicHeaderActions extends StatelessWidget {
  const _TopicHeaderActions({required this.header});

  final TopicInboxHeader header;

  @override
  Widget build(BuildContext context) {
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    return Row(
      key: const ValueKey('topic-header-common-actions'),
      mainAxisSize: MainAxisSize.min,
      spacing: DSpacing.controlGap,
      children: [
        if (topic != null && siteUrl != null) ...[
          TopicStatusButton(
            siteUrl: siteUrl,
            topic: topic,
            topicFlags: ShellScope.read(
              context,
            ).availableTopicFlagTypes(siteUrl, topic),
          ),
        ],
        if (ShellTitleBar.columnsCarryUserMenu) const UserMenuButton(),
      ],
    );
  }
}

class _MobileTopicHeaderActions extends StatelessWidget {
  const _MobileTopicHeaderActions({
    required this.siteUrl,
    required this.topic,
    required this.registry,
  });

  final String siteUrl;
  final TopicDetail topic;
  final PluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    final rebuildOn = registry.topicPropertiesRebuildOn(
      context,
      siteUrl,
      topic,
    );
    return rebuildOn == null
        ? _buildActions(context)
        : ListenableBuilder(
            listenable: rebuildOn,
            builder: (context, _) => _buildActions(context),
          );
  }

  Widget _buildActions(BuildContext context) {
    final shell = ShellScope.of(context);
    final instance = shell.instanceFor(siteUrl);
    return Wrap(
      key: const ValueKey('mobile-topic-header-actions'),
      spacing: DSpacing.controlGap,
      runSpacing: DSpacing.controlGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (instance?.user != null)
          TopicBookmarkButton(
            siteUrl: siteUrl,
            topic: topic,
            busy: shell.bookmarkWriteInFlight(
              siteUrl: siteUrl,
              topicId: topic.id,
              targetType: BookmarkTargetType.topic,
              targetId: topic.id,
            ),
            variant: DButtonVariant.outline,
            size: DButtonSize.regular,
          ),
        if (instance?.isConnected == true)
          TopicNotificationLevelButton(
            siteUrl: siteUrl,
            topic: topic,
            variant: DButtonVariant.outline,
            size: DButtonSize.regular,
          ),
        if (topic.privateMessage &&
            instance?.isConnected == true &&
            instance?.user?.canSendPrivateMessages == true)
          MessageArchiveButton(siteUrl: siteUrl, topic: topic),
        if (registry.topicProperties(context, siteUrl, topic).isNotEmpty)
          _TopicHeaderProperties(
            siteUrl: siteUrl,
            topic: topic,
            registry: registry,
            compact: true,
          ),
        TopicStatusButton(
          siteUrl: siteUrl,
          topic: topic,
          topicFlags: shell.availableTopicFlagTypes(siteUrl, topic),
          variant: DButtonVariant.outline,
        ),
      ],
    );
  }
}

class TopicCloseButton extends StatelessWidget {
  const TopicCloseButton({
    super.key,
    required this.canReturnToSidebar,
    this.backToList = false,
  });

  final bool canReturnToSidebar;
  final bool backToList;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final content = controller.topicListContent?.isMessages == true
        ? 'message'
        : 'topic';
    return DButton.iconOnly(
      key: const ValueKey('topic-close-reader'),
      icon: DIcon(backToList ? DIcons.arrowLeft : DNativeIcons.closeTopicPane),
      tooltip: controller.mobileNavigationEnabled
          ? 'Back'
          : backToList
          ? 'Back to $content list'
          : 'Collapse $content',
      variant: DButtonVariant.transparentBackground,
      size: DButtonSize.regular,
      onPressed: () {
        if (controller.topicListContent != null) {
          controller.closeTopicListReader();
        } else {
          controller.handleBack(canReturnToSidebar: canReturnToSidebar);
        }
      },
    );
  }
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

/// Participant identities and topic-wide activity, using server totals.
class TopicActivitySummary extends StatelessWidget {
  const TopicActivitySummary({
    super.key,
    required this.siteUrl,
    required this.topic,
  });
  final String siteUrl;
  final TopicDetail topic;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Topic?>(
    valueListenable: ShellScope.read(context).topicRef(siteUrl, topic.id),
    builder: (context, row, _) {
      final theme = Theme.of(context);
      final participants = topic.participants.take(4).toList();
      final previewAvatars = participants.isEmpty
          ? row?.posterAvatars.take(4).toList() ?? const <String>[]
          : const <String>[];
      final wordsPerMinute = ShellScope.read(
        context,
      ).siteConfigFor(siteUrl).readTimeWordCount;
      final readMinutes = math
          .max(topic.wordCount / wordsPerMinute, topic.postsCount * 4 / 60)
          .ceil();
      final style = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      Widget stat(int value, String label) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' $label'),
          ],
        ),
        style: style,
      );
      final stats = <Widget>[
        stat(topic.replyCount, topic.replyCount == 1 ? 'reply' : 'replies'),
        stat(topic.views, topic.views == 1 ? 'view' : 'views'),
        stat(topic.likeCount, topic.likeCount == 1 ? 'like' : 'likes'),
        stat(topic.links.length, topic.links.length == 1 ? 'link' : 'links'),
        if (readMinutes > 0) stat(readMinutes, 'min read'),
        if (row?.bumpedAt case final activity?)
          Text(switch (relativeTime(activity)) {
            'now' => 'last activity just now',
            final age => 'last activity $age ago',
          }, style: style),
      ];
      return Column(
        key: const ValueKey('topic-header-activity'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (participants.isNotEmpty || previewAvatars.isNotEmpty) ...[
            DAvatarGroup(
              size: DAvatarSize.sm,
              children: [
                for (final url in previewAvatars)
                  DAvatar(
                    child: AvatarImage(
                      url: url,
                      size: DAvatarSize.sm.dimension,
                      fallback: const DAvatarFallback(child: Text('?')),
                    ),
                  ),
                for (final participant in participants)
                  DTooltip(
                    message: participant.displayName,
                    child: DAvatar(
                      semanticLabel: participant.displayName,
                      child: AvatarImage(
                        url: participant.avatarUrl,
                        size: DAvatarSize.sm.dimension,
                        fallback: DAvatarFallback(
                          child: Text(
                            participant.username.isEmpty
                                ? '?'
                                : participant.username.characters.first
                                      .toUpperCase(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < stats.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i > 0) ...[
                      Text('·', style: style),
                      const SizedBox(width: 8),
                    ],
                    Flexible(child: stats[i]),
                  ],
                ),
            ],
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
    required this.registry,
    this.showProperties = true,
    this.mobileActions,
  });
  final String siteUrl;
  final TopicDetail topic;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final bool showProperties;
  final Widget? mobileActions;

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
          final mobile = shell.mobileNavigationEnabled;
          final categoryWidth =
              (constraints.maxWidth *
                      (mobile
                          ? .25
                          : hasSubcategory
                          ? .28
                          : .42))
                  .clamp(56.0, 200.0);
          // Reserve room for category artwork, the privacy lock, and saving.
          // Add the browse button and roomier padding only when each chip fits.
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final compressed = categoryWidth < 140 * scale;
          final showBrowse =
              categoryWidth >= (context.isTouch ? 152 : 104) * scale;
          final tags = TopicHeaderTags(
            key: const ValueKey('topic-header-tags'),
            siteUrl: siteUrl,
            topic: topic,
            editOnTap: mobile,
            onTagNavigate: (tag, {newTab = false}) => shell.openTopicTag(
              tag,
              siteUrl: siteUrl,
              privateMessage: topic.privateMessage,
              newTab: newTab,
            ),
          );
          if (mobile) {
            return Wrap(
              key: const ValueKey('topic-header-taxonomy'),
              spacing: DSpacing.controlGap,
              runSpacing: DSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasCategories)
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
                      showBrowseButton: false,
                    ),
                  ),
                if (hasSubcategory)
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
                      showBrowseButton: false,
                    ),
                  ),
                if (hasTags)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(148 * scale, constraints.maxWidth),
                    ),
                    child: tags,
                  ),
                ?mobileActions,
              ],
            );
          }
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
                if (hasCategories)
                  const DSeparator(
                    orientation: Axis.vertical,
                    length: 20,
                    space: 17,
                  ),
                Flexible(child: tags),
              ],
              if (showProperties)
                _TopicHeaderProperties(
                  siteUrl: siteUrl,
                  topic: topic,
                  registry: registry,
                  compact: constraints.maxWidth < 620,
                  showSeparator: hasCategories || hasTags,
                ),
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
              size: DButtonSize.regular,
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
                      size: DControlStyle.iconDimension(
                        DControlSize.regular,
                        context: context,
                      ),
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
                size: DButtonSize.regular,
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
    this.showSeparator = false,
  });
  final String siteUrl;
  final TopicDetail topic;
  final PluginRegistry registry;
  final bool compact;
  final bool showSeparator;

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
      final content = compact
          ? Row(mainAxisSize: MainAxisSize.min, children: children)
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: children,
            );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSeparator)
            const DSeparator(orientation: Axis.vertical, length: 20, space: 17),
          content,
        ],
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
  Listenable? _propertyRequests;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requests = ShellScope.read(context).topicPropertyRequests;
    if (!identical(requests, _propertyRequests)) {
      _propertyRequests?.removeListener(_openRequestedProperty);
      _propertyRequests = requests..addListener(_openRequestedProperty);
    }
  }

  void _openRequestedProperty() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ShellScope.read(context).consumeTopicProperty(
        widget.siteUrl,
        widget.topicId,
        widget.section.label,
      )) {
        return;
      }
      if (context.isTouch) {
        _showTouch(context);
      } else {
        _controller.open();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(_TopicPropertyPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.topicId != widget.topicId ||
        oldWidget.navigationRevision != widget.navigationRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.close();
      });
    }
  }

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
            icon: const DIcon(DIcons.ellipsis),
            tooltip: section.label,
            size: DButtonSize.large,
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
          size: DButtonSize.large,
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
        builder: (anchorContext) {
          _openRequestedProperty();
          return _trigger(anchorContext, () => _showTouch(anchorContext));
        },
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
        builder: (context, trigger) {
          // Queue after DPopover has scheduled its initial state sync.
          _openRequestedProperty();
          return _trigger(
            context,
            trigger.toggle,
            focusNode: trigger.focusNode,
            expanded: trigger.open,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _propertyRequests?.removeListener(_openRequestedProperty);
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
