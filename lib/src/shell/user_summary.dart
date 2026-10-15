import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../data/site_lifecycle.dart';
import '../foundation/count_label.dart';
import '../models/discourse_instance.dart';
import '../models/user_summary.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'global_search_models.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';
import 'topic_title.dart';
import 'user_card.dart';

class UserSummaryView extends StatefulWidget {
  const UserSummaryView({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<UserSummaryView> createState() => _UserSummaryViewState();
}

class _UserSummaryViewState extends State<UserSummaryView> {
  (ShellController, String, String, SiteLease)? _loadedIdentity;
  bool _requestScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(UserSummaryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _request();
  }

  DiscourseInstance? _instance(ShellController controller) => controller
      .instances
      .where((instance) => instance.url == widget.siteUrl)
      .firstOrNull;

  void _request() {
    final controller = ShellScope.read(context);
    final instance = _instance(controller);
    if (instance?.isConnected != true) return;
    final username = instance!.user!.username;
    final loaded = _loadedIdentity;
    if (loaded != null &&
        identical(loaded.$1, controller) &&
        loaded.$2 == widget.siteUrl &&
        loaded.$3 == username &&
        loaded.$4.isCurrent) {
      return;
    }
    _loadedIdentity = (
      controller,
      widget.siteUrl,
      username,
      controller.lifecycle.capture(widget.siteUrl),
    );
    unawaited(controller.userSummary.load(instance));
  }

  void _scheduleRequest() {
    if (_requestScheduled) return;
    _requestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScheduled = false;
      if (mounted) _request();
    });
  }

  Future<void> _refresh() async {
    final controller = ShellScope.read(context);
    final instance = _instance(controller);
    if (instance != null) {
      await controller.userSummary.load(instance, refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ListenableBuilder(
      listenable: controller.userSummary,
      builder: (context, _) {
        final instance = _instance(controller);
        if (instance?.isConnected != true) {
          return _SummaryState(
            icon: DIcons.user,
            title: context.l10n.connectThisAccountToSeeItsSummary,
          );
        }

        final state = controller.userSummary.stateFor(widget.siteUrl);
        if (!state.loading && !state.loaded) _scheduleRequest();
        final summary = state.summary;
        if (summary == null) {
          if (state.error case final error?) {
            return _SummaryState(
              icon: DIcons.triangleExclamation,
              title: error,
              actionLabel: context.l10n.tryAgain,
              onAction: _refresh,
            );
          }
          return const _SummaryLoadingSkeleton(
            key: ValueKey('user-summary-loading-skeleton'),
          );
        }

        return _SummaryContent(
          key: ValueKey((widget.siteUrl, instance!.user!.username)),
          instance: instance,
          summary: summary,
          error: state.error,
          refreshing: state.loading,
          onRefresh: _refresh,
        );
      },
    );
  }
}

enum _SummaryTab { highlights, connections, reading }

class _SummaryContent extends StatefulWidget {
  const _SummaryContent({
    super.key,
    required this.instance,
    required this.summary,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
  });

  final DiscourseInstance instance;
  final UserSummary summary;
  final String? error;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  State<_SummaryContent> createState() => _SummaryContentState();
}

class _SummaryContentState extends State<_SummaryContent> {
  _SummaryTab _tab = _SummaryTab.highlights;
  bool _restored = false;

  Object get _storageId =>
      ('user-summary-tab', widget.instance.url, widget.instance.user!.username);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    _tab =
        PageStorage.maybeOf(context)?.readState(context, identifier: _storageId)
            as _SummaryTab? ??
        _SummaryTab.highlights;
  }

  void _selectTab(_SummaryTab? value) {
    if (value == null || value == _tab) return;
    setState(() => _tab = value);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, value, identifier: _storageId);
  }

  @override
  Widget build(BuildContext context) => DTabs<_SummaryTab>.controlled(
    value: _tab,
    onChanged: _selectTab,
    children: [
      Expanded(
        child: _SummaryLayout(
          profile: _ProfileCard(
            instance: widget.instance,
            summary: widget.summary,
          ),
          controls: DTabList<_SummaryTab>(
            variant: DTabListVariant.line,
            children: [
              DTabTrigger(
                value: _SummaryTab.highlights,
                child: Text(context.l10n.highlights),
              ),
              DTabTrigger(
                value: _SummaryTab.connections,
                child: Text(context.l10n.connections),
              ),
              DTabTrigger(
                value: _SummaryTab.reading,
                child: Text(context.l10n.reading),
              ),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.error case final error?)
                _SummaryErrorBanner(
                  error: error,
                  refreshing: widget.refreshing,
                  onRetry: widget.onRefresh,
                ),
              Stack(
                alignment: AlignmentDirectional.topStart,
                children: [
                  DTabPanel(
                    value: _SummaryTab.highlights,
                    child: _Highlights(
                      instance: widget.instance,
                      summary: widget.summary,
                    ),
                  ),
                  DTabPanel(
                    value: _SummaryTab.connections,
                    child: _Connections(
                      siteUrl: widget.instance.url,
                      summary: widget.summary,
                    ),
                  ),
                  DTabPanel(
                    value: _SummaryTab.reading,
                    child: _Reading(
                      instance: widget.instance,
                      summary: widget.summary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// Profile, line tabs and content share the Start page's reading column.
class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({
    required this.profile,
    required this.content,
    this.controls,
  });
  final Widget profile;
  final Widget content;
  final Widget? controls;

  @override
  Widget build(BuildContext context) => DPageSurface.headed(
    limitContentSize: false,
    title: ContentReadingLaneBox(child: profile),
    controls: controls == null ? null : ContentReadingLaneBox(child: controls!),
    bodyBuilder: (context, header) => ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      builder: (context, lane) => DScrollArea(
        key: const PageStorageKey('user-summary-scroll'),
        thumbVisibility: false,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header.spacer,
            // Scroll motion can reuse the stacked cards and tables; their
            // own updates still repaint this layer normally.
            RepaintBoundary(
              child: Padding(padding: lane.padding, child: content),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.instance, required this.summary});
  final DiscourseInstance instance;
  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final user = instance.user!;
    final name = user.name?.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        return Row(
          key: const ValueKey('user-summary-profile'),
          spacing: DSpacing.sm,
          children: [
            _SummaryAvatar(username: user.username, avatarUrl: user.avatarUrl),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  name == null || name.isEmpty ? user.username : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (constraints.maxWidth > 520 * scale)
              _Caption('@${user.username}'),
            if (constraints.maxWidth > 680 * scale) ...[
              const DIcon(DIcons.globe, size: 12),
              Flexible(child: _Caption(instance.title)),
            ],
            if (constraints.maxWidth > 800 * scale &&
                summary.canSeeSummaryStats)
              _Caption(
                '${_number(summary.daysVisited)} ${context.l10n.daysVisited.toLowerCase()}',
              ),
          ],
        );
      },
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.instance, required this.summary});
  final DiscourseInstance instance;
  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasBadges =
        instance.config.badgesEnabled && summary.badges.isNotEmpty;
    return _SectionStack(
      children: [
        if (summary.canSeeSummaryStats) _HeadlineStats(summary: summary),
        if (summary.topics.isEmpty && summary.replies.isEmpty && !hasBadges)
          _EmptyCard(
            title: context.l10n.yourStoryStartsWithAConversation,
            description: context
                .l10n
                .asYouReadReplyAndConnectWithPeopleYourHighlightsWill,
          )
        else ...[
          _PairedSections(
            left: _SummarySection(
              title: context.l10n.topTopics,
              child: _TopicRows(
                emptyMessage: context.l10n.noTopicsYet,
                rows: [
                  for (final topic in summary.topics)
                    _SummaryTopicRow(
                      siteUrl: instance.url,
                      topic: topic,
                      createdAt: topic.createdAt,
                      likes: topic.likeCount,
                    ),
                ],
              ),
            ),
            right: _SummarySection(
              title: context.l10n.topReplies,
              child: _TopicRows(
                emptyMessage: context.l10n.noRepliesYet,
                rows: [
                  for (final reply in summary.replies)
                    _SummaryTopicRow(
                      siteUrl: instance.url,
                      topic: reply.topic,
                      postNumber: reply.postNumber,
                      createdAt: reply.createdAt,
                      likes: reply.likeCount,
                    ),
                ],
              ),
            ),
          ),
          if (instance.config.badgesEnabled)
            _SummarySection(
              title: context.l10n.yourMilestones,
              child: _BadgeRows(badges: summary.badges),
            ),
        ],
      ],
    );
  }
}

class _Connections extends StatelessWidget {
  const _Connections({required this.siteUrl, required this.summary});
  final String siteUrl;
  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.mostRepliedToUsers.isEmpty &&
        summary.mostLikedByUsers.isEmpty &&
        summary.mostLikedUsers.isEmpty) {
      return _EmptyCard(
        title: context.l10n.noConnectionsYet,
        description:
            context.l10n.thePeopleYouReplyToAndExchangeLikesWithWillAppear,
      );
    }
    return _SectionStack(
      children: [
        _SummarySection(
          title: context.l10n.mostRepliedTo,
          child: _UserRows(
            siteUrl: siteUrl,
            users: summary.mostRepliedToUsers,
            emptyMessage: context.l10n.noRepliesYet,
            noun: CountNoun.reply,
          ),
        ),
        _PairedSections(
          left: _SummarySection(
            title: context.l10n.mostLikedBy,
            child: _UserRows(
              siteUrl: siteUrl,
              users: summary.mostLikedByUsers,
              emptyMessage: context.l10n.noLikesYet,
              noun: CountNoun.like,
            ),
          ),
          right: _SummarySection(
            title: context.l10n.mostLiked,
            child: _UserRows(
              siteUrl: siteUrl,
              users: summary.mostLikedUsers,
              emptyMessage: context.l10n.noLikesYet,
              noun: CountNoun.like,
            ),
          ),
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.instance, required this.summary});
  final DiscourseInstance instance;
  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final time = durationLabel(summary.timeRead);
    final recent = durationLabel(summary.recentTimeRead);
    return _SectionStack(
      children: [
        if (summary.canSeeSummaryStats)
          _SummarySection(
            title: context.l10n.timeWellSpent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(
                  time.short,
                  semanticsLabel: context.l10n.readTimeAllTime(
                    (time.long).toString(),
                  ),
                  style: const TextStyle(
                    fontSize: DiscourseTypography.xxxl,
                    height: 36 / 30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: DSpacing.xs),
                if (summary.showRecentTimeRead)
                  _Caption(
                    context.l10n.inTheLast60Days((recent.short).toString()),
                    semantics: context.l10n.recentReadTimeInTheLast60Days(
                      (recent.long).toString(),
                    ),
                  )
                else
                  _Caption(context.l10n.allTimeReading),
                const SizedBox(height: DSpacing.sm),
                _DetailStats(
                  values: [
                    (
                      label: context.l10n.topicsViewed,
                      value: _number(summary.topicsEntered),
                      semantics: null,
                    ),
                    (
                      label: context.l10n.postsRead,
                      value: _number(summary.postsReadCount),
                      semantics: null,
                    ),
                    (
                      label: context.l10n.bookmarks,
                      value: _number(summary.bookmarkCount),
                      semantics: null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (summary.topCategories.isNotEmpty)
          _SummarySection(
            title: context.l10n.topCategories,
            child: _CategoryRows(
              siteUrl: instance.url,
              username: instance.user!.username,
              categories: summary.topCategories,
            ),
          ),
        _SummarySection(
          title: context.l10n.topLinks,
          child: _LinkRows(siteUrl: instance.url, links: summary.links),
        ),
      ],
    );
  }
}

class _HeadlineStats extends StatelessWidget {
  const _HeadlineStats({required this.summary});
  final UserSummary summary;

  @override
  Widget build(BuildContext context) => DCard(
    children: [
      DCardContent(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stats = [
              _Stat(
                label: context.l10n.likesReceived,
                value: _number(summary.likesReceived),
              ),
              _Stat(
                label: context.l10n.likesGiven,
                value: _number(summary.likesGiven),
              ),
              _Stat(
                label: context.l10n.repliesWritten,
                value: _number(summary.postCount),
              ),
              _Stat(
                label: context.l10n.topicsStarted,
                value: _number(summary.topicCount),
              ),
            ];
            final columns =
                constraints.maxWidth < 440 ||
                    MediaQuery.textScalerOf(context).scale(12) > 18
                ? 2
                : 4;
            return Column(
              children: [
                for (var start = 0; start < stats.length; start += columns) ...[
                  if (start > 0) const SizedBox(height: DSpacing.lg),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = start;
                          index < start + columns;
                          index++
                        ) ...[
                          if (index > start)
                            const DSeparator(
                              orientation: Axis.vertical,
                              space: DSpacing.lg,
                            ),
                          Expanded(child: stats[index]),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label: $value',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Caption(label),
          const SizedBox(height: DSpacing.sm),
          DText(
            value,
            style: const TextStyle(
              fontSize: DiscourseTypography.xxl,
              height: 32 / 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

typedef _DetailStat = ({String label, String value, String? semantics});

class _DetailStats extends StatelessWidget {
  const _DetailStats({required this.values});
  final List<_DetailStat> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 180 ||
          (constraints.maxWidth < 400 &&
              MediaQuery.textScalerOf(context).scale(12) > 18);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < values.length; index++) ...[
            if (index > 0) const DSeparator(),
            Semantics(
              container: true,
              label:
                  values[index].semantics ??
                  '${values[index].label}: ${values[index].value}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: DSpacing.md),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Caption(values[index].label),
                            const SizedBox(height: DSpacing.xs),
                            _value(values[index].value),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _Caption(values[index].label)),
                            const SizedBox(width: DSpacing.sm),
                            Expanded(
                              child: _value(
                                values[index].value,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );

  Widget _value(String value, {TextAlign textAlign = TextAlign.start}) => DText(
    value,
    variant: DTextVariant.small,
    textAlign: textAlign,
    style: const TextStyle(
      fontSize: DiscourseTypography.xs,
      height: DiscourseTypography.lineHeightCaption,
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.semantics});
  final String text;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final child = DText(
      text,
      variant: DTextVariant.muted,
      semanticsLabel: semantics,
      style: const TextStyle(
        fontSize: DiscourseTypography.xs,
        height: DiscourseTypography.lineHeightCaption,
      ),
    );
    return semantics == null ? child : Semantics(container: true, child: child);
  }
}

class _SectionStack extends StatelessWidget {
  const _SectionStack({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(height: DSpacing.xl),
        children[index],
      ],
    ],
  );
}

class _PairedSections extends StatelessWidget {
  const _PairedSections({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => _SectionStack(children: [left, right]);
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DCard(
    backgroundColor: Color.alphaBlend(
      DTokens.of(context).muted.withValues(alpha: .5),
      DTokens.of(context).background,
    ),
    children: [
      DCardHeader(title: DCardTitle(child: Text(title))),
      DCardContent(child: child),
    ],
  );
}

class _TopicRows extends StatelessWidget {
  const _TopicRows({required this.emptyMessage, required this.rows});
  final String emptyMessage;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? _EmptySection(message: emptyMessage)
      : DItemGroup(
          spacing: 0,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const DSeparator(),
              rows[i],
            ],
          ],
        );
}

class _SummaryTopicRow extends StatelessWidget {
  const _SummaryTopicRow({
    required this.siteUrl,
    required this.topic,
    required this.createdAt,
    required this.likes,
    this.postNumber,
  });
  final String siteUrl;
  final UserSummaryTopic topic;
  final DateTime? createdAt;
  final int likes;
  final int? postNumber;

  // The age is part of the row's semantic label as well as its text, so the
  // whole row follows it.
  @override
  Widget build(BuildContext context) => switch (createdAt) {
    final at? => RelativeTimeBuilder(when: at, builder: _row),
    null => _row(context, null),
  };

  Widget _row(BuildContext context, String? date) {
    final category = ShellScope.read(
      context,
    ).categoryFor(topic.categoryId, siteUrl: siteUrl);
    final label = [
      context.l10n.openUsersummary((topic.title).toString()),
      ?date,
      if (likes > 0) countLabel(likes, CountNoun.like),
    ].join(', ');
    return DItem(
      size: DItemSize.xs,
      padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
      semanticLabel: label,
      onPressed: () => ShellScope.read(
        context,
      ).openSummaryTopic(topic, postNumber: postNumber),
      children: [
        DItemContent(
          spacing: DSpacing.xs,
          children: [
            ExcludeSemantics(
              child: DItemTitle(
                maxLines: null,
                child: TopicTitle(topic.title, siteUrl: siteUrl),
              ),
            ),
            if (category != null || date != null)
              ExcludeSemantics(
                child: DItemDescription(
                  child: Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: DSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (category != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CategoryIcon(
                              category: category,
                              siteUrl: siteUrl,
                              size: 12,
                              squareSize: 8,
                            ),
                            const SizedBox(width: DSpacing.xs),
                            Flexible(child: Text(category.name)),
                          ],
                        ),
                      if (date != null) Text(date),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (likes > 0)
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DIcon(
                  DIcons.heart,
                  size: 12,
                  color: DTokens.of(context).mutedForeground,
                ),
                const SizedBox(width: DSpacing.xs),
                _Caption(_number(likes)),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinkRows extends StatelessWidget {
  const _LinkRows({required this.siteUrl, required this.links});
  final String siteUrl;
  final List<UserSummaryLink> links;

  @override
  Widget build(BuildContext context) => links.isEmpty
      ? _EmptySection(message: context.l10n.noLinksYet)
      : LayoutBuilder(
          builder: (context, constraints) {
            final showSource =
                constraints.maxWidth >= 520 &&
                MediaQuery.textScalerOf(context).scale(12) <= 18;
            return DTable(
              columnWidths: {
                0: const FlexColumnWidth(),
                if (showSource) 1: const FlexColumnWidth(),
                (showSource ? 2 : 1): const IntrinsicColumnWidth(),
              },
              header: DTableHeader(
                rows: [
                  DTableRow(
                    cells: [
                      DTableHead(child: Text(context.l10n.link)),
                      if (showSource)
                        DTableHead(child: Text(context.l10n.summaryPostedIn)),
                      DTableHead(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(context.l10n.summaryClicks),
                      ),
                    ],
                  ),
                ],
              ),
              body: DTableBody(
                rows: [
                  for (final link in links)
                    DTableRow(
                      cells: [
                        DTableCell(
                          softWrap: true,
                          child: DButton(
                            variant: DButtonVariant.inline,
                            semanticLabel: context.l10n.openUsersummaryValue(
                              link.topic.title,
                            ),
                            onPressed: () =>
                                ShellScope.read(context).openSummaryTopic(
                                  link.topic,
                                  postNumber: link.postNumber,
                                ),
                            label: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  link.title ?? _shortUrl(link.url),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                _Caption(_shortUrl(link.url)),
                              ],
                            ),
                          ),
                        ),
                        if (showSource)
                          DTableCell(
                            softWrap: true,
                            child: TopicTitle(
                              link.topic.title,
                              siteUrl: siteUrl,
                              maxLines: 1,
                            ),
                          ),
                        DTableCell(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(_number(link.clicks)),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
}

class _UserRows extends StatelessWidget {
  const _UserRows({
    required this.siteUrl,
    required this.users,
    required this.emptyMessage,
    required this.noun,
  });
  final String siteUrl;
  final List<UserSummaryUser> users;
  final String emptyMessage;
  final CountNoun noun;

  @override
  Widget build(BuildContext context) => users.isEmpty
      ? _EmptySection(message: emptyMessage)
      : DTable(
          minimumWidth: MediaQuery.textScalerOf(context).scale(280),
          columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth()},
          header: DTableHeader(
            rows: [
              DTableRow(
                cells: [
                  DTableHead(child: Text(context.l10n.summaryPerson)),
                  DTableHead(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      noun == CountNoun.reply
                          ? context.l10n.replies
                          : context.l10n.likes,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: DTableBody(
            rows: [
              for (final user in users)
                DTableRow(
                  cells: [
                    DTableCell(
                      softWrap: true,
                      child: UserCardTarget(
                        username: user.username,
                        siteUrl: siteUrl,
                        semanticLabel: context.l10n.viewProfileForUsersummary(
                          user.displayName,
                          countLabel(user.count, noun),
                        ),
                        child: DItem(
                          size: DItemSize.xs,
                          children: [
                            _SummaryAvatar(
                              username: user.username,
                              avatarUrl: user.avatarUrl,
                              size: DAvatarSize.sm,
                            ),
                            DItemContent(
                              children: [
                                DItemTitle(child: Text(user.displayName)),
                                if (user.name != null)
                                  DItemDescription(
                                    child: Text('@${user.username}'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    DTableCell(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(_number(user.count)),
                    ),
                  ],
                ),
            ],
          ),
        );
}

class _SummaryAvatar extends StatelessWidget {
  const _SummaryAvatar({
    required this.username,
    this.avatarUrl,
    this.size = DAvatarSize.standard,
  });
  final String username;
  final String? avatarUrl;
  final DAvatarSize size;

  @override
  Widget build(BuildContext context) => DAvatar(
    size: size,
    decorative: true,
    child: AvatarImage(
      url: avatarUrl,
      size: size.dimension,
      fallback: DAvatarFallback(
        child: Text(username.characters.firstOrNull?.toUpperCase() ?? '?'),
      ),
    ),
  );
}

class _CategoryRows extends StatelessWidget {
  const _CategoryRows({
    required this.siteUrl,
    required this.username,
    required this.categories,
  });
  final String siteUrl;
  final String username;
  final List<UserSummaryCategory> categories;

  void _search(
    BuildContext context,
    UserSummaryCategory category, {
    required bool topics,
  }) {
    final shell = ShellScope.read(context);
    // The web links these counts to full-page search: the forum scope here.
    // Opening search resets scope and filters, so the expression is applied
    // after the surface opens; submitting turns its tokens into filters and
    // runs it without the typing debounce.
    shell.search.requestFocus();
    shell.globalSearch
      ..setScope(GlobalSearchScope.forum)
      ..setQuery('@$username #${category.slug}${topics ? ' in:first' : ''}')
      ..submit();
  }

  @override
  Widget build(BuildContext context) => DTable(
    semanticLabel: context.l10n.topCategories,
    columnWidths: const {
      0: IntrinsicColumnWidth(flex: 1),
      1: IntrinsicColumnWidth(),
      2: IntrinsicColumnWidth(),
    },
    header: DTableHeader(
      rows: [
        DTableRow(
          cells: [
            DTableHead(child: Text(context.l10n.category)),
            DTableHead(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(context.l10n.topics),
            ),
            DTableHead(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(context.l10n.replies),
            ),
          ],
        ),
      ],
    ),
    body: DTableBody(
      rows: [
        for (final category in categories)
          DTableRow(
            cells: [
              DTableCell(
                softWrap: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CategoryIcon.presentation(
                      key: ValueKey((
                        'user-summary-category-icon',
                        category.id,
                      )),
                      color: Color(category.colorValue),
                      styleType: category.styleType,
                      icon: category.icon,
                      emoji: category.emoji,
                      readRestricted: category.readRestricted,
                      siteUrl: siteUrl,
                      size: 14,
                      squareSize: 10,
                    ),
                    const SizedBox(width: DSpacing.sm),
                    Flexible(child: Text(category.name)),
                  ],
                ),
              ),
              for (final topics in [true, false])
                DTableCell(
                  alignment: AlignmentDirectional.centerEnd,
                  child:
                      (topics ? category.topicCount : category.postCount) <= 0
                      ? const Text('—')
                      : DButton(
                          variant: DButtonVariant.link,
                          semanticLabel: context.l10n.searchByIn(
                            (topics).toString(),
                            ((topics)
                                    ? (countLabel(
                                        category.topicCount,
                                        CountNoun.topic,
                                      ))
                                    : '')
                                .toString(),
                            (username).toString(),
                            (category.name).toString(),
                            ((!(topics))
                                    ? (countLabel(
                                        category.postCount,
                                        CountNoun.reply,
                                      ))
                                    : '')
                                .toString(),
                          ),
                          onPressed: () =>
                              _search(context, category, topics: topics),
                          label: Text(
                            _number(
                              topics ? category.topicCount : category.postCount,
                            ),
                          ),
                        ),
                ),
            ],
          ),
      ],
    ),
  );
}

class _BadgeRows extends StatelessWidget {
  const _BadgeRows({required this.badges});
  final List<UserSummaryBadge> badges;

  @override
  Widget build(BuildContext context) => badges.isEmpty
      ? _EmptySection(message: context.l10n.noBadgesYet)
      : Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            for (final badge in badges)
              Semantics(
                container: true,
                child: DTooltip(
                  message: badge.description ?? badge.name,
                  focusable: true,
                  child: DBadge(
                    variant: DBadgeVariant.outline,
                    semanticLabel: context.l10n.earnedUsersummary(
                      badge.count,
                      (badge.name).toString(),
                    ),
                    leading: DIcon(
                      pluginIconNamed(context, badge.icon) ??
                          DIcons.certificate,
                    ),
                    trailing: badge.count > 1 ? Text('×${badge.count}') : null,
                    child: Text(badge.name),
                  ),
                ),
              ),
          ],
        );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => DCard(
    child: DEmpty(
      children: [
        DEmptyHeader(
          children: [
            const DEmptyMedia(child: DIcon(DIcons.comment, size: 32)),
            DEmptyTitle(title, headingLevel: 2),
            DEmptyDescription(description),
          ],
        ),
      ],
    ),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => DEmpty(
    padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
    children: [DEmptyDescription(message)],
  );
}

class _SummaryErrorBanner extends StatelessWidget {
  const _SummaryErrorBanner({
    required this.error,
    required this.refreshing,
    required this.onRetry,
  });
  final String error;
  final bool refreshing;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: DSpacing.xl),
    child: DAlert(
      variant: DAlertVariant.destructive,
      icon: const DIcon(DIcons.triangleExclamation),
      description: DAlertDescription(child: Text(error)),
      action: DAlertAction(
        child: DButton(
          label: Text(context.l10n.retry),
          onPressed: refreshing ? null : () => unawaited(onRetry()),
          variant: DButtonVariant.link,
        ),
      ),
    ),
  );
}

class _SummaryState extends StatelessWidget {
  const _SummaryState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });
  final DIconData icon;
  final String title;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(child: DIcon(icon, size: 32)),
              Semantics(
                liveRegion: icon == DIcons.triangleExclamation,
                child: DEmptyTitle(title),
              ),
            ],
          ),
          if (actionLabel case final label?)
            DEmptyContent(
              children: [
                DButton(
                  label: Text(label),
                  onPressed: onAction == null
                      ? null
                      : () => unawaited(onAction!()),
                  variant: DButtonVariant.primary,
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _SummaryLoadingSkeleton extends StatelessWidget {
  const _SummaryLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    expand: true,
    semanticsLabel: context.l10n.loadingSummary,
    color: skeletonFill(context),
    child: const _SummaryLayout(
      profile: DCard(
        spacing: DSpacing.xl,
        children: [
          DCardContent(
            child: _SectionStack(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DSkeleton.circle(diameter: 40),
                ),
                DSkeleton(width: 140, height: 24),
                DSkeleton(width: 100, height: 12),
                DSkeleton(height: 180),
              ],
            ),
          ),
        ],
      ),
      content: _SectionStack(
        children: [
          DSkeleton(width: 240, height: 32),
          DSkeleton(height: 110),
          _PairedSections(
            left: DSkeleton(height: 320),
            right: DSkeleton(height: 320),
          ),
        ],
      ),
    ),
  );
}

String _number(int value) => NumberFormat.decimalPattern().format(value);

String _shortUrl(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.host.isEmpty) return source;
  final path = uri.path == '/' ? '' : uri.path;
  return '${uri.host}$path';
}
