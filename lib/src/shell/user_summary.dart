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
import 'external_link.dart';
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
  Widget build(BuildContext context) => _SummaryLayout(
    profile: _ProfileCard(instance: widget.instance, summary: widget.summary),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.error case final error?)
          _SummaryErrorBanner(
            error: error,
            refreshing: widget.refreshing,
            onRetry: widget.onRefresh,
          ),
        DTabs<_SummaryTab>.controlled(
          value: _tab,
          onChanged: _selectTab,
          children: [
            DTabList<_SummaryTab>(
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
            const SizedBox(height: DSpacing.sm),
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
  );
}

// These are application compositions of Native components, not new kit owners.
class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({required this.profile, required this.content});

  final Widget profile;
  final Widget content;

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    widthLimit: 1136,
    basePadding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
    builder: (context, lane) {
      final width = ContentReadingLane.breakpointWidthOf(context, lane.width);
      final wide =
          width >= 760 && MediaQuery.textScalerOf(context).scale(14) <= 21;
      if (!wide) {
        return DScrollArea(
          key: const PageStorageKey('user-summary-scroll'),
          padding: lane.padding,
          thumbVisibility: false,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              profile,
              const SizedBox(height: DSpacing.xl),
              content,
            ],
          ),
        );
      }
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Padding(
        padding: EdgeInsets.only(
          left: rtl ? 0 : lane.padding.left,
          right: rtl ? lane.padding.right : 0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width >= 1040 ? 248 : 208,
              child: DScrollArea(
                thumbVisibility: false,
                padding: EdgeInsets.only(
                  top: lane.padding.top,
                  bottom: lane.padding.bottom,
                  left: 1,
                  right: 1,
                ),
                child: profile,
              ),
            ),
            const SizedBox(width: DSpacing.xxl),
            Expanded(
              child: DScrollArea(
                key: const PageStorageKey('user-summary-scroll'),
                padding: EdgeInsets.only(
                  top: lane.padding.top,
                  bottom: lane.padding.bottom,
                  left: rtl ? lane.padding.left + 1 : 1,
                  right: rtl ? 1 : lane.padding.right + 1,
                ),
                thumbVisibility: false,
                physics: const AlwaysScrollableScrollPhysics(),
                child: content,
              ),
            ),
          ],
        ),
      );
    },
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
    final time = durationLabel(summary.timeRead);
    return DCard(
      key: const ValueKey('user-summary-profile'),
      spacing: DSpacing.xl,
      children: [
        DCardContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryAvatar(
                username: user.username,
                avatarUrl: user.avatarUrl,
                size: DAvatarSize.lg,
              ),
              const SizedBox(height: DSpacing.lg),
              DText(
                name == null || name.isEmpty ? user.username : name,
                variant: DTextVariant.h3,
                headingLevel: 1,
                style: const TextStyle(
                  fontSize: DiscourseTypography.xxl,
                  height: 32 / 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: DSpacing.xs),
              _Caption('@${user.username}'),
              const SizedBox(height: DSpacing.lg),
              Row(
                children: [
                  const ExcludeSemantics(child: DIcon(DIcons.globe, size: 14)),
                  const SizedBox(width: DSpacing.sm),
                  Expanded(
                    child: DText(
                      instance.title,
                      variant: DTextVariant.small,
                      style: const TextStyle(
                        fontSize: DiscourseTypography.xs,
                        height: DiscourseTypography.lineHeightCaption,
                      ),
                    ),
                  ),
                ],
              ),
              if (summary.canSeeSummaryStats) ...[
                const SizedBox(height: DSpacing.xl),
                const DSeparator(),
                _DetailStats(
                  values: [
                    (
                      label: context.l10n.daysVisited,
                      value: _number(summary.daysVisited),
                      semantics: null,
                    ),
                    (
                      label: context.l10n.timeReading,
                      value: time.short,
                      semantics: context.l10n.readTimeAllTime(
                        (time.long).toString(),
                      ),
                    ),
                    (
                      label: context.l10n.likesGiven,
                      value: _number(summary.likesGiven),
                      semantics: null,
                    ),
                    if (summary.bookmarkCount > 0)
                      (
                        label: context.l10n.bookmarks,
                        value: _number(summary.bookmarkCount),
                        semantics: null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
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
                    if (summary.bookmarkCount > 0)
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
                label: context.l10n.repliesWritten,
                value: _number(summary.postCount),
              ),
              _Stat(
                label: context.l10n.topicsStarted,
                value: _number(summary.topicCount),
              ),
            ];
            if (MediaQuery.textScalerOf(context).scale(12) > 18 ||
                constraints.maxWidth < 240) {
              return _SectionStack(children: stats);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < stats.length; index++) ...[
                    if (index > 0)
                      const DSeparator(
                        orientation: Axis.vertical,
                        space: DSpacing.lg,
                      ),
                    Expanded(child: stats[index]),
                  ],
                ],
              ),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = ContentReadingLane.breakpointWidthOf(
        context,
        constraints.maxWidth,
      );
      if (width < 680 || MediaQuery.textScalerOf(context).scale(14) > 21) {
        return _SectionStack(children: [left, right]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: DSpacing.xl),
          Expanded(child: right),
        ],
      );
    },
  );
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DCard(
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
      : DItemGroup(
          spacing: DSpacing.sm,
          children: [
            for (final link in links)
              _SummaryLinkRow(siteUrl: siteUrl, link: link),
          ],
        );
}

class _SummaryLinkRow extends StatelessWidget {
  const _SummaryLinkRow({required this.siteUrl, required this.link});
  final String siteUrl;
  final UserSummaryLink link;

  @override
  Widget build(BuildContext context) => DItem(
    size: DItemSize.xs,
    padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
    semanticLabel: context.l10n.openExternalLink(
      (_shortUrl(link.url)).toString(),
      (countLabel(link.clicks, CountNoun.click)).toString(),
    ),
    link: true,
    onPressed: () => unawaited(openExternalLink(link.url)),
    footer: DItemFooter(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DButton(
          variant: DButtonVariant.link,
          semanticLabel: context.l10n.openUsersummaryValue(
            (link.topic.title).toString(),
          ),
          onPressed: () => ShellScope.read(
            context,
          ).openSummaryTopic(link.topic, postNumber: link.postNumber),
          label: TopicTitle(link.topic.title, siteUrl: siteUrl, maxLines: 2),
        ),
      ),
    ),
    children: [
      const DItemMedia(
        child: ExcludeSemantics(child: DIcon(DIcons.link, size: 14)),
      ),
      DItemContent(
        children: [
          ExcludeSemantics(
            child: DItemTitle(
              maxLines: null,
              child: Text(link.title ?? _shortUrl(link.url)),
            ),
          ),
          ExcludeSemantics(
            child: DItemDescription(child: Text(_shortUrl(link.url))),
          ),
        ],
      ),
      ExcludeSemantics(
        child: _Caption(
          countLabel(
            link.clicks,
            CountNoun.click,
            number: _number(link.clicks),
          ),
        ),
      ),
    ],
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
      : DItemGroup(
          spacing: DSpacing.xs,
          children: [
            for (final user in users)
              UserCardTarget(
                username: user.username,
                siteUrl: siteUrl,
                semanticLabel: context.l10n.viewProfileForUsersummary(
                  (user.displayName).toString(),
                  (countLabel(user.count, noun)).toString(),
                ),
                child: DItem(
                  size: DItemSize.xs,
                  padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
                  children: [
                    DItemMedia(
                      child: _SummaryAvatar(
                        username: user.username,
                        avatarUrl: user.avatarUrl,
                      ),
                    ),
                    DItemContent(
                      children: [
                        DItemTitle(
                          maxLines: null,
                          child: Text(user.displayName),
                        ),
                        if (user.name != null)
                          DItemDescription(child: Text('@${user.username}')),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DText(_number(user.count), variant: DTextVariant.small),
                        _Caption(countNoun(user.count, noun)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
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
