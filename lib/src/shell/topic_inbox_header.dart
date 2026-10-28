import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'message_archive_button.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'skeleton_fill.dart';
import 'topic_actions.dart';
import 'topic_category_picker.dart';
import 'topic_header_tags.dart';
import 'topic_skeleton.dart';
import 'topic_title.dart';

/// Topic title, actions and taxonomy floating above the post viewport.
/// [bodyBuilder] inserts the header spacer into the virtualized post list.
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
    this.bodyBuilder,
    this.headerControls,
    this.headerSuppressed,
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
  final Widget Function(DPageHeaderGeometry header)? bodyBuilder;
  final Widget? headerControls;
  final ValueListenable<bool>? headerSuppressed;

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
        _TopicHeaderReadingLane(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: taxonomy,
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
    final shell = ShellScope.read(context);
    final tab = ForumTabScope.tabOf(context);
    final route = this.route ?? tab.currentContent;
    final topicId = topic?.id ?? route?.topicId ?? preview?.id;
    final row =
        preview ??
        (siteUrl != null && topicId != null
            ? shell.store.read<Topic>(siteUrl, topicId)
            : null);
    final openingPostNumber = topicId == null
        ? null
        : shell.topicScrollPostNumber(topicId, tabId: tab.tabId) ??
              route?.postNumber ??
              topic?.resumePostNumber ??
              row?.lastUnreadPostNumber;
    return DPageSurface.scrollable(
      headerSuppressed: headerSuppressed,
      hideHeaderOnScroll: true,
      framed: false,
      identity: (siteUrl, topicId),
      initialCompactHeader: shell.mobileNavigationEnabled
          ? (openingPostNumber ?? 1) > 1
          : null,
      // The mockups draw every topic header control flat in either material.
      header: _morphHeader(context, compact: false, rows: rows),
      compactHeader: shell.mobileNavigationEnabled
          ? _morphHeader(context, compact: true, rows: rows)
          : null,
      compactHeaderBand: shell.mobileNavigationEnabled,
      headerControls: headerControls,
      bodyBuilder: (_, header) => bodyBuilder(header),
    );
  }

  Widget _morphHeader(
    BuildContext context, {
    required bool compact,
    required List<Widget> rows,
  }) {
    if (!ShellScope.read(context).mobileNavigationEnabled) {
      return Column(children: rows);
    }
    // The rounded head shares the canvas fill while attached to the top.
    // Pulling the page exposes its existing curves. Both states keep this
    // box so the morph keeps its state.
    return DecoratedBox(
      key: const ValueKey('topic-header-band'),
      decoration: compact
          ? BoxDecoration(
              color: DTokens.of(context).wellFill,
              borderRadius: BorderRadius.circular(
                DMobileDockGeometry.capsuleRadius,
              ),
            )
          : const BoxDecoration(),
      child: _morphBody(context, compact: compact, rows: rows),
    );
  }

  Widget _morphBody(
    BuildContext context, {
    required bool compact,
    required List<Widget> rows,
  }) {
    return DHeaderMorph(
      key: const ValueKey('topic-header-morph'),
      compact: compact,
      builder: (context, compact, part) {
        if (loading || topic == null) {
          if (!compact) return Column(children: rows);
          final instance = siteUrl == null
              ? null
              : ShellScope.read(context).instanceFor(siteUrl!);
          final style = Theme.of(
            context,
          ).textTheme.labelSmall!.copyWith(fontSize: DiscourseTypography.micro);
          return ContentReadingLaneBox(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                key: const ValueKey('topic-header-compact-layout'),
                spacing: 10,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        part(
                          'title',
                          _TopicHeaderTitle(header: this, compact: true),
                        ),
                        part(
                          'meta',
                          SizedBox(
                            height:
                                MediaQuery.textScalerOf(
                                  context,
                                ).scale(DiscourseTypography.micro) *
                                (style.height ?? 1),
                            child: TopicSkeletonReveal(
                              child: DSkeletonRegion(
                                semanticsLabel:
                                    context.l10n.loadingTopicDetails,
                                color: skeletonFill(context),
                                child: const Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: DSkeleton(width: 130, height: 8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  part(
                    'tools',
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(0, constraints.maxWidth - 90),
                      ),
                      child: DControlWrap(
                        key: const ValueKey('topic-header-tools'),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (instance?.user != null ||
                              instance?.isConnected == true)
                            DButtonGroup.tool(
                              children: [
                                if (instance?.user != null)
                                  const TopicBookmarkButtonPlaceholder(
                                    variant: DButtonVariant.tool,
                                    size: DButtonSize.filter,
                                  ),
                                if (instance?.isConnected == true)
                                  const TopicNotificationLevelPlaceholder(
                                    showChevron: true,
                                    variant: DButtonVariant.tool,
                                    size: DButtonSize.filter,
                                  ),
                              ],
                            ),
                          const _TopicActionsPlaceholder(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final shell = ShellScope.read(context);
        final detail = topic!;
        final category = shell.categoryFor(detail.categoryId, siteUrl: siteUrl);
        final parent = shell.categoryFor(
          category?.parentCategoryId,
          siteUrl: siteUrl,
        );
        if (!compact) {
          return Column(
            children: [
              part(
                'title',
                _TopicHeaderReadingLane(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _TopicHeaderTitle(header: this),
                  ),
                ),
              ),
              if (rows.length > 1) part('meta', rows[1]),
            ],
          );
        }
        return ContentReadingLaneBox(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              key: const ValueKey('topic-header-compact-layout'),
              spacing: 10,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      part(
                        'title',
                        _TopicHeaderTitle(header: this, compact: true),
                      ),
                      part(
                        'meta',
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final names = [
                              if (parent != null) parent.name,
                              if (category != null) category.name,
                              for (final tag in detail.tags) '#${tag.name}',
                            ];
                            final style = Theme.of(context)
                                .textTheme
                                .labelSmall!
                                .copyWith(fontSize: DiscourseTypography.micro);
                            var shown = names.length;
                            String line(int count) =>
                                '${names.take(count).join('  ›  ')}${count < names.length ? '  +${names.length - count}' : ''}';
                            while (shown > 0) {
                              final painter = TextPainter(
                                text: TextSpan(text: line(shown), style: style),
                                textDirection: Directionality.of(context),
                                textScaler: MediaQuery.textScalerOf(context),
                              )..layout();
                              final fits =
                                  painter.width <= constraints.maxWidth;
                              painter.dispose();
                              if (fits) break;
                              shown--;
                            }
                            return Text(
                              line(shown),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                part(
                  'tools',
                  ConstrainedBox(
                    // Keep the mockup's tools beside the compact title. At
                    // large text sizes, wrap groups within the available space.
                    constraints: BoxConstraints(
                      maxWidth: math.max(0, constraints.maxWidth - 90),
                    ),
                    child: _TopicHeaderTaxonomy(
                      siteUrl: siteUrl!,
                      topic: detail,
                      keepTopicListOpen: keepTopicListOpen,
                      registry: registry,
                      showTaxonomy: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
          semanticsLabel: context.l10n.loadingTopicDetails,
          liveRegion: false,
          color: skeletonFill(context),
          child: Row(
            spacing: DSpacing.sm,
            children: [
              if (categories) ...[chip(112), chip(88)],
              chip(104),
              if (ShellScope.read(context).mobileNavigationEnabled)
                const _TopicActionsPlaceholder()
              else
                const TopicStatusButtonPlaceholder(
                  variant: DButtonVariant.tool,
                  size: DButtonSize.filter,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's one actions button, disabled while its topic loads.
class _TopicActionsPlaceholder extends StatelessWidget {
  const _TopicActionsPlaceholder();

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    icon: const DIcon(DIcons.ellipsis),
    tooltip: context.l10n.topicActionsMenu,
    variant: DButtonVariant.tool,
    size: DButtonSize.filter,
    onPressed: null,
  );
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
        semanticsLabel: context.l10n.loadingTopicActivity,
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
      return ConstrainedBox(
        key: const ValueKey('topic-content-header'),
        constraints: const BoxConstraints(minHeight: readerHeaderHeight),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!ShellScope.read(context).mobileNavigationEnabled)
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
      );
    },
  );
}

class _TopicHeaderTitle extends StatelessWidget {
  const _TopicHeaderTitle({required this.header, this.compact = false});
  final TopicInboxHeader header;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final topic = header.topic;
    final siteUrl = header.siteUrl;
    final style = compact
        ? Theme.of(context).textTheme.titleSmall!.copyWith(
            fontSize: DiscourseTypography.sm,
            fontWeight: FontWeight.w700,
          )
        : Theme.of(context).textTheme.headlineSmall;
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
                semanticsLabel: context.l10n.loadingTopicTitle,
                liveRegion: false,
                color: skeletonFill(context),
                child: DSkeleton(height: lineHeight * .6),
              ),
            ),
          ),
        ),
      );
    } else if (compact) {
      title = Text(
        known ?? topic?.displayTitle ?? '',
        key: const ValueKey('topic-header-compact-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    } else if (topic?.canEdit == true && siteUrl != null) {
      title = InlineTopicTitleEditor(
        key: ValueKey(('topic-header-title', siteUrl, topic!.id)),
        title: topic.title,
        localizedTitle: topic.localizedTitle,
        siteUrl: siteUrl,
        style: style,
        maxLines: 3,
        onSave: (value, {required originalTitle}) =>
            ShellScope.read(context).saveTopicTitle(
              siteUrl: siteUrl,
              topicId: topic.id,
              title: value,
              originalTitle: originalTitle,
            ),
      );
    } else {
      final value = known ?? context.l10n.topic;
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
      // The title text already names the topic in full, even when clipped.
      title = DTooltip(message: value, excludeFromSemantics: true, child: text);
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
              semanticLabel: context.l10n.topicClosed,
            ),
          ),
        Expanded(child: title),
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
    final tab = ForumTabScope.tabOf(context);
    final content = tab.topicListContent?.isMessages == true
        ? 'message'
        : 'topic';
    final source = tab.topicListContent;
    final sourceTitle = source?.tabTitle ?? context.l10n.back;
    final label = sourceTitle == 'Latest'
        ? context.l10n.latestTopics
        : sourceTitle;
    return DButton(
      key: const ValueKey('topic-close-reader'),
      icon: const DIcon(DIcons.chevronLeft),
      label: Text(label),
      tooltip: controller.mobileNavigationEnabled
          ? context.l10n.back
          : backToList
          ? context.l10n.backToList((content).toString())
          : context.l10n.collapseTopicinboxheader((content).toString()),
      variant: DButtonVariant.inline,
      density: DButtonDensity.backLink,
      onPressed: () {
        if (tab.topicListContent != null) {
          tab.closeTopicListReader();
        } else {
          tab.handleBack(canReturnToSidebar: canReturnToSidebar);
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
      if (readMinutes > 0) stat(readMinutes, context.l10n.minRead),
      if (lastActivity case final activity?)
        RelativeTimeBuilder(
          when: activity,
          builder: (context, age) => Text(switch (age) {
            'now' => context.l10n.lastActivityJustNow,
            _ => context.l10n.lastActivityAgo((age).toString()),
          }, style: style),
        ),
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
    this.showTaxonomy = true,
  });
  final String siteUrl;
  final TopicDetail topic;
  final bool keepTopicListOpen;
  final PluginRegistry registry;
  final bool showTaxonomy;

  @override
  Widget build(
    BuildContext context,
  ) => ForumTabSelector<({Object presentation, int navigationRevision})>(
    select: (controller, tab) => (
      presentation: controller.presentationTokenFor(siteUrl),
      navigationRevision: tab.topicNavigationRevision,
    ),
    builder: (context, state, _) {
      final shell = ShellScope.read(context);
      final mobile = shell.mobileNavigationEnabled;
      Widget head(BuildContext context) {
        final instance = shell.instanceFor(siteUrl);
        final sections = registry.topicProperties(context, siteUrl, topic);
        bool gathered(TopicPropertySection section) =>
            mobile && section.actions.isNotEmpty;
        final toolChildren = <Widget>[
          if (instance?.user != null || instance?.isConnected == true)
            DButtonGroup.tool(
              semanticLabel: context.l10n.topicReminders,
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
                    variant: DButtonVariant.tool,
                    size: DButtonSize.filter,
                    buttonKey: const ValueKey('topic-header-bookmark-button'),
                  ),
                if (instance?.isConnected == true)
                  TopicNotificationLevelButton(
                    showChevron: true,
                    siteUrl: siteUrl,
                    topic: topic,
                    variant: DButtonVariant.tool,
                    size: DButtonSize.filter,
                    buttonKey: const ValueKey(
                      'topic-header-notification-button',
                    ),
                  ),
              ],
            ),
          if (mobile &&
              topic.privateMessage &&
              instance?.isConnected == true &&
              instance?.user?.canSendPrivateMessages == true)
            DButtonGroup(
              children: [
                MessageArchiveButton(
                  siteUrl: siteUrl,
                  topic: topic,
                  compact: true,
                ),
              ],
            ),
          for (final section in sections)
            if (!gathered(section))
              DButtonGroup(
                key: ValueKey(('topic-header-property', section.label)),
                children: [
                  _TopicPropertyPopover(
                    siteUrl: siteUrl,
                    topicId: topic.id,
                    section: section,
                    registry: registry,
                    compact: true,
                    navigationRevision: state.navigationRevision,
                  ),
                ],
              ),
          if (mobile)
            TopicActionsButton(
              siteUrl: siteUrl,
              topic: topic,
              topicFlags: shell.availableTopicFlagTypes(siteUrl, topic),
              sectionActions: [
                for (final section in sections)
                  if (gathered(section)) section.actions,
              ],
            )
          else
            DButtonGroup(
              children: [
                TopicStatusButton(
                  siteUrl: siteUrl,
                  topic: topic,
                  topicFlags: shell.availableTopicFlagTypes(siteUrl, topic),
                  variant: DButtonVariant.tool,
                  size: DButtonSize.filter,
                ),
              ],
            ),
        ];
        // Drawn in to its bar, the head's tools may take a second line at the
        // largest text sizes rather than leave the screen.
        if (!showTaxonomy) {
          return DControlWrap(
            key: const ValueKey('topic-header-tools'),
            spacing: DSpacing.sm,
            runSpacing: DSpacing.sm,
            children: toolChildren,
          );
        }
        final tools = Row(
          key: const ValueKey('topic-header-tools'),
          mainAxisSize: MainAxisSize.min,
          spacing: DSpacing.sm,
          children: toolChildren,
        );
        return ConstrainedBox(
          key: const ValueKey('topic-header-taxonomy'),
          constraints: BoxConstraints(minHeight: _taxonomyRowHeight(context)),
          child: TopicHeaderTags(
            key: const ValueKey('topic-header-tags'),
            siteUrl: siteUrl,
            topic: topic,
            editOnTap: mobile,
            path: _path(context, shell),
            tools: tools,
            onTagNavigate: (tag, {newTab = false, panel}) => shell.openTopicTag(
              tag,
              siteUrl: siteUrl,
              privateMessage: topic.privateMessage,
              newTab: newTab,
              panel: panel,
            ),
          ),
        );
      }

      final rebuildOn = registry.topicPropertiesRebuildOn(
        context,
        siteUrl,
        topic,
      );
      return rebuildOn == null
          ? head(context)
          : ListenableBuilder(
              listenable: rebuildOn,
              builder: (context, _) => head(context),
            );
    },
  );

  /// The categories the topic sits under, then the one it is in. A topic that
  /// could be moved into a subcategory offers one after its own category,
  /// which stays when the line is short.
  List<TopicHeadStep> _path(BuildContext context, ShellController shell) {
    if (topic.privateMessage) return const [];
    final category = shell.categoryFor(topic.categoryId, siteUrl: siteUrl);
    final parent = shell.categoryFor(
      category?.parentCategoryId,
      siteUrl: siteUrl,
    );
    final root = parent ?? category;
    final hasSubcategory = _showTopicSubcategory(
      topic: topic,
      category: category,
      parent: parent,
      categories: shell.filterCategoriesFor(siteUrl),
    );
    final rootStep = TopicHeadStep(
      label: root?.name ?? context.l10n.categoryTopicinboxheader,
      marked: root != null,
      own: parent == null,
      chip: _TopicCategoryControl(
        key: const ValueKey('topic-header-parent-category'),
        siteUrl: siteUrl,
        topic: topic,
        category: root,
        subcategory: false,
        keepTopicListOpen: keepTopicListOpen,
        showBrowseButton: false,
      ),
    );
    if (!hasSubcategory) return [rootStep];
    final subStep = TopicHeadStep(
      label: parent == null ? context.l10n.subcategory : category!.name,
      marked: parent != null,
      own: parent != null,
      chip: _TopicCategoryControl(
        key: const ValueKey('topic-header-category'),
        siteUrl: siteUrl,
        topic: topic,
        category: parent == null ? null : category,
        subcategory: true,
        parentCategoryId: root?.id,
        keepTopicListOpen: keepTopicListOpen,
        showBrowseButton: false,
      ),
    );
    return [rootStep, subStep];
  }
}

class _TopicCategoryControl extends StatelessWidget {
  const _TopicCategoryControl({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.category,
    required this.subcategory,
    required this.keepTopicListOpen,
    this.parentCategoryId,
    this.showBrowseButton = true,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicCategory? category;
  final bool subcategory;
  final int? parentCategoryId;
  final bool keepTopicListOpen;
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
      removeLabel: subcategory
          ? context.l10n.removeSubcategory
          : context.l10n.moveToUncategorized,
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
          label:
              value?.name ??
              (subcategory
                  ? context.l10n.subcategory
                  : context.l10n.categoryTopicinboxheader),
          edit: browseOnly ? browse : edit,
          primaryIsLink: browseOnly,
          contextOnly: value != null && value.id != topic.categoryId,
          saving: saving,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          editLabel: browseOnly
              ? context.l10n.browseTopicinboxheader((value?.name).toString())
              : subcategory
              ? context.l10n.editTopicSubcategory
              : context.l10n.editTopicCategory,
          navigate: showBrowseButton ? browse : null,
        );
        return browseOnly && value != null
            ? LinkTarget(
                url: resolveSiteRootPath(siteUrl, '/c/${value.id}'),
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
    this.primaryIsLink = false,
    this.contextOnly = false,
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
  final bool primaryIsLink;
  final bool contextOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category == null
        ? theme.colorScheme.onSurfaceVariant
        : Color(category!.colorValue);
    final tokens = DTokens.of(context);
    final surface = category == null
        ? tokens.quietControlSurface()
        : tokens.categoryControlSurface(color);
    // Flat and round as the head's other tools: only the category a topic is
    // in is filled; the ones it sits under are context, and read as such.
    final fill = contextOnly ? Colors.transparent : surface.background;
    final hover = surface.hover;
    final foreground = contextOnly
        ? tokens.mutedForeground
        : surface.foreground;
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
              variant: DButtonVariant.tool,
              size: DButtonSize.filter,
              backgroundColor: fill,
              foregroundColor: foreground,
              interactiveBackgroundColor: hover,
              loading: saving,
              loadingSemanticLabel: context.l10n.savingCategory,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != null) ...[
                    CategoryIcon(
                      category: category!,
                      siteUrl: siteUrl,
                      squareSize: 10,
                      size: DControlStyle.iconDimension(
                        DControlSize.filter,
                        context: context,
                      ),
                    ),
                    const SizedBox(width: DSpacing.controlGap),
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
              url: resolveSiteRootPath(siteUrl, '/c/${category!.id}'),
              title: category!.name,
              siteUrl: siteUrl,
              child: DButton.iconOnly(
                key: ValueKey('topic-header-browse-category-${category!.id}'),
                icon: const DIcon(DIcons.upRightFromSquare),
                tooltip: context.l10n.browseTopicinboxheaderValue(
                  (category!.name).toString(),
                ),
                isLink: true,
                onPressed: navigate,
                variant: DButtonVariant.tool,
                size: DButtonSize.filter,
                backgroundColor: fill,
                foregroundColor: foreground,
                interactiveBackgroundColor: hover,
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicPropertyPopover extends StatefulWidget {
  const _TopicPropertyPopover({
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
    final tab = ForumTabScope.tabOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!tab.isCurrent ||
          tab.siteUrl != widget.siteUrl ||
          tab.currentContent?.topicId != widget.topicId ||
          tab.topicNavigationRevision != widget.navigationRevision) {
        return;
      }
      if (!ShellScope.read(context).consumeTopicProperty(
        widget.siteUrl,
        widget.topicId,
        widget.section.label,
      )) {
        return;
      }
      _controller.open();
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
            size: DButtonSize.filter,
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

  @override
  Widget build(BuildContext context) {
    return DPopover(
      controller: _controller,
      sheetOnMobile: true,
      mobileSheetVariant: DSheetVariant.adaptiveMenu,
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
  Widget build(BuildContext context) => ForumTabSelector<(String?, int?, int)>(
    select: (shell, tab) => (
      tab.isCurrent ? tab.siteUrl : null,
      tab.currentContent?.topicId,
      tab.topicNavigationRevision,
    ),
    builder: (context, navigation, _) {
      if (navigation != (siteUrl, topicId, navigationRevision)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final tab = ForumTabScope.tabOf(context);
          final current = (
            tab.isCurrent ? tab.siteUrl : null,
            tab.currentContent?.topicId,
            tab.topicNavigationRevision,
          );
          if (current != (siteUrl, topicId, navigationRevision)) {
            onDismiss();
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
                children: section?.values ?? [Text(context.l10n.none)],
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
