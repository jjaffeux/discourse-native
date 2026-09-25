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
import 'skeleton_fill.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_header_tags.dart';
import 'topic_skeleton.dart';
import 'topic_title.dart';

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
    this.loading = false,
    this.scrollController,
    this.hasEarlierPosts = false,
    this.bodyBuilder,
  });

  /// Null while loading a topic whose title no route or list row supplied.
  final String? title;
  final String? siteUrl;
  final bool canReturnToSidebar;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final ContentRoute? route;
  final TopicDetail? topic;

  /// The cached list row. Only its closed state is drawn, because that renders
  /// identically once the topic arrives; its other fields size placeholders.
  /// Taxonomy and activity depend on permissions and participants it lacks.
  final Topic? preview;

  /// Reserves the loaded header's rows with placeholders until [topic] arrives.
  final bool loading;
  final ScrollController? scrollController;
  final bool hasEarlierPosts;
  final Widget Function(List<Widget> openingSlivers)? bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final topic = this.topic;
    final siteUrl = this.siteUrl;
    final hasTopic = topic != null && siteUrl != null;
    final placeholders = loading && !hasTopic;
    final preview = this.preview;
    final Widget? taxonomy = hasTopic
        ? _TopicHeaderTaxonomy(
            siteUrl: siteUrl,
            topic: topic,
            keepTopicListOpen: keepTopicListOpen,
            registry: registry,
            mobileActions: ShellScope.read(context).mobileNavigationEnabled
                ? _MobileTopicHeaderActions(
                    siteUrl: siteUrl,
                    topic: topic,
                    registry: registry,
                  )
                : null,
          )
        : placeholders &&
              !(preview != null &&
                  preview.privateMessage &&
                  preview.tags.isEmpty)
        ? _TopicHeaderTaxonomyPlaceholder(
            categories: preview?.privateMessage != true,
          )
        : null;
    final rows = [
      _TopicHeaderToolbar(header: this),
      if (taxonomy != null)
        ColoredBox(
          color: ForumWindowBackground.surfaceColor(
            context,
            Theme.of(context).shell.content,
          ),
          child: _TopicHeaderReadingLane(
            child: Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: taxonomy,
            ),
          ),
        ),
    ];
    final bodyBuilder = this.bodyBuilder;
    if (bodyBuilder == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    return DPageSurface(
      hideHeaderOnScroll: true,
      framed: false,
      identity: (siteUrl, topic?.id, scrollController),
      header: Column(children: rows),
      child: bodyBuilder(const []),
    );
  }
}

/// The taxonomy and actions share the mockup's compact control height.
double _taxonomyRowHeight(BuildContext context) => DControlStyle.scaledHeight(
  DControlSize.filter,
  MediaQuery.textScalerOf(context),
  context: context,
);

class _TopicHeaderTaxonomyPlaceholder extends StatelessWidget {
  const _TopicHeaderTaxonomyPlaceholder({required this.categories});

  final bool categories;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DTokens.of(context).controlRadius);
    final height = DControlStyle.scaledHeight(
      DControlSize.filter,
      MediaQuery.textScalerOf(context),
      context: context,
    );
    Widget chip(double width) => Flexible(
      child: DSkeleton(width: width, height: height, borderRadius: radius),
    );
    return ConstrainedBox(
      key: const ValueKey('topic-header-taxonomy-placeholder'),
      constraints: BoxConstraints(
        minHeight: ShellScope.read(context).mobileNavigationEnabled
            ? height
            : _taxonomyRowHeight(context),
      ),
      child: TopicSkeletonReveal(
        child: DSkeletonRegion(
          semanticsLabel: 'Loading topic details',
          liveRegion: false,
          color: skeletonFill(context),
          child: Row(
            spacing: DSpacing.sm,
            children: [
              if (categories) ...[chip(112), chip(88)],
              chip(104),
              const TopicStatusButtonPlaceholder(
                variant: DButtonVariant.outline,
                size: DButtonSize.filter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows for [TopicActivitySummary]: its avatar row, and its
/// statistics estimated from the cached list [row] so they wrap alike.
class TopicActivityPlaceholder extends StatelessWidget {
  const TopicActivityPlaceholder({super.key, this.row});

  final Topic? row;

  @override
  Widget build(BuildContext context) {
    final row = this.row;
    return TopicSkeletonReveal(
      child: DSkeletonRegion(
        key: const ValueKey('topic-header-activity-placeholder'),
        semanticsLabel: 'Loading topic activity',
        liveRegion: false,
        color: skeletonFill(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DAvatarGroup(
              size: DAvatarSize.sm,
              children: [
                DAvatar(
                  size: DAvatarSize.sm,
                  border: false,
                  decorative: true,
                  child: DSkeleton(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TopicActivityStats(
              replies: row?.replyCount ?? 0,
              views: row?.views ?? 0,
              likes: row?.likeCount ?? 0,
              links: 0,
              readMinutes: math.max(
                1,
                ((row?.postsCount ?? 0) * 4 / 60).ceil(),
              ),
              lastActivity: row?.bumpedAt,
              placeholder: true,
            ),
          ],
        ),
      ),
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
        const EdgeInsetsDirectional.only(start: 16, end: 16, top: 16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TopicCloseButton(
                    canReturnToSidebar: header.canReturnToSidebar,
                    backToList: !header.keepTopicListOpen,
                  ),
                ),
                _TopicHeaderTitle(header: header),
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
    final lineHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(style?.fontSize ?? DiscourseTypography.lg) *
        (style?.height ?? DiscourseTypography.lineHeightLarge);
    final known = header.title;
    final Widget title;
    if (known == null && header.loading) {
      title = SizedBox(
        key: const ValueKey('topic-header-title-placeholder'),
        height: lineHeight,
        child: FractionallySizedBox(
          widthFactor: .56,
          alignment: AlignmentDirectional.centerStart,
          child: Center(
            child: TopicSkeletonReveal(
              child: DSkeletonRegion(
                semanticsLabel: 'Loading topic title',
                liveRegion: false,
                color: skeletonFill(context),
                child: DSkeleton(height: lineHeight * .6),
              ),
            ),
          ),
        ),
      );
    } else if (topic?.canEdit == true && siteUrl != null) {
      title = InlineTopicTitleEditor(
        key: ValueKey(('topic-header-title', siteUrl, topic!.id)),
        title: known ?? topic.title,
        siteUrl: siteUrl,
        style: style,
        maxLines: 3,
        onSave: (value) => ShellScope.read(
          context,
        ).saveTopicTitle(siteUrl: siteUrl, topicId: topic.id, title: value),
      );
    } else {
      final value = known ?? 'Topic';
      final text = siteUrl == null
          ? Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: style,
            )
          : TopicTitle(
              value,
              key: const ValueKey('topic-header-compact-title'),
              siteUrl: siteUrl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
      title = DTooltip(message: value, child: text);
    }
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
            size: DControlSize.chip,
            buttonKey: const ValueKey('topic-header-bookmark-button'),
          ),
        if (instance?.isConnected == true)
          TopicNotificationLevelButton(
            showChevron: true,
            siteUrl: siteUrl,
            topic: topic,
            variant: DButtonVariant.outline,
            size: DControlSize.chip,
            buttonKey: const ValueKey('topic-header-notification-button'),
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
    final source = controller.topicListContent;
    final sourceTitle = source?.tabTitle ?? 'Back';
    final label = sourceTitle == 'Latest' ? 'Latest topics' : sourceTitle;
    return DButton(
      key: const ValueKey('topic-close-reader'),
      icon: const DIcon(DIcons.chevronLeft),
      label: Text(label),
      tooltip: controller.mobileNavigationEnabled
          ? 'Back'
          : backToList
          ? 'Back to $content list'
          : 'Collapse $content',
      variant: DButtonVariant.transparentBackground,
      size: DButtonSize.chip,
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
          _TopicActivityStats(
            replies: topic.replyCount,
            views: topic.views,
            likes: topic.likeCount,
            links: topic.links.length,
            readMinutes: readMinutes,
            lastActivity: row?.bumpedAt,
          ),
        ],
      );
    },
  );
}

/// The statistics line of [TopicActivitySummary]. As a [placeholder], each
/// statistic keeps its text's width but draws a bar instead, so a placeholder
/// built from estimates wraps where the loaded line will.
class _TopicActivityStats extends StatelessWidget {
  const _TopicActivityStats({
    required this.replies,
    required this.views,
    required this.likes,
    required this.links,
    required this.readMinutes,
    required this.lastActivity,
    this.placeholder = false,
  });

  final int replies;
  final int views;
  final int likes;
  final int links;
  final int readMinutes;
  final DateTime? lastActivity;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      stat(replies, replies == 1 ? 'reply' : 'replies'),
      stat(views, views == 1 ? 'view' : 'views'),
      stat(likes, likes == 1 ? 'like' : 'likes'),
      stat(links, links == 1 ? 'link' : 'links'),
      if (readMinutes > 0) stat(readMinutes, 'min read'),
      if (lastActivity case final activity?)
        Text(switch (relativeTime(activity)) {
          'now' => 'last activity just now',
          final age => 'last activity $age ago',
        }, style: style),
    ];
    Widget reserve(Widget child) => placeholder
        ? Stack(
            children: [
              Opacity(opacity: 0, child: child),
              const Positioned.fill(child: Center(child: DSkeleton(height: 9))),
            ],
          )
        : child;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < stats.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) ...[
                Opacity(
                  opacity: placeholder ? 0 : 1,
                  child: Text('·', style: style),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(child: reserve(stats[i])),
            ],
          ),
      ],
    );
  }
}

class _TopicHeaderTaxonomy extends StatelessWidget {
  const _TopicHeaderTaxonomy({
    required this.siteUrl,
    required this.topic,
    required this.keepTopicListOpen,
    required this.registry,
    this.mobileActions,
  });
  final String siteUrl;
  final TopicDetail topic;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
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
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final compressed = categoryWidth < 140 * scale;
          final tags = TopicHeaderTags(
            key: const ValueKey('topic-header-tags'),
            siteUrl: siteUrl,
            topic: topic,
            editOnTap: mobile,
            showEditAction: false,
            onTagNavigate: (tag, {newTab = false, panel}) => shell.openTopicTag(
              tag,
              siteUrl: siteUrl,
              privateMessage: topic.privateMessage,
              newTab: newTab,
              panel: panel,
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
          final instance = shell.instanceFor(siteUrl);
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: _taxonomyRowHeight(context)),
            child: Wrap(
              key: const ValueKey('topic-header-taxonomy'),
              spacing: 8,
              runSpacing: 8,
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
                if (instance?.user != null || instance?.isConnected == true)
                  DButtonGroup(
                    semanticLabel: 'Topic reminders',
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
                          size: DButtonSize.filter,
                          buttonKey: const ValueKey(
                            'topic-header-bookmark-button',
                          ),
                        ),
                      if (instance?.isConnected == true)
                        TopicNotificationLevelButton(
                          showChevron: true,
                          siteUrl: siteUrl,
                          topic: topic,
                          variant: DButtonVariant.outline,
                          size: DButtonSize.filter,
                          buttonKey: const ValueKey(
                            'topic-header-notification-button',
                          ),
                        ),
                    ],
                  ),
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
                  size: DButtonSize.filter,
                ),
              ],
            ),
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
        final chip = _CategoryChip(
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
        return browseOnly && value != null
            ? LinkTarget(
                url: '/c/${value.id}',
                title: value.name,
                siteUrl: siteUrl,
                child: chip,
              )
            : chip;
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
              size: DButtonSize.filter,
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
                        DControlSize.filter,
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
                size: DButtonSize.filter,
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
      final content = compact
          ? Row(mainAxisSize: MainAxisSize.min, children: children)
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: children,
            );
      return Row(mainAxisSize: MainAxisSize.min, children: [content]);
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
            size: context.isTouch ? DButtonSize.chip : DButtonSize.filter,
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
          size: DButtonSize.filter,
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
