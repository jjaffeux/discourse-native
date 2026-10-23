import 'dart:async';
import 'dart:math' as math;

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
              child: Padding(
                padding: lane.padding.add(
                  EdgeInsets.only(bottom: DScrollChrome.bottomInsetOf(context)),
                ),
                child: content,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// The person where a page's title would be, and after the name what is known
// about them. The name keeps its room; the facts beside it give way first, a
// whole fact at a time.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.instance, required this.summary});
  final DiscourseInstance instance;
  final UserSummary summary;

  static const _avatar = 28.0;
  static const _gap = 10.0;
  // Room for a fact's mark and a few letters; less shows nothing at all.
  static const _minimumFacts = 32.0;

  @override
  Widget build(BuildContext context) {
    final user = instance.user!;
    final name = user.name?.trim();
    final label = name == null || name.isEmpty ? user.username : name;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: DefaultTextStyle.of(context).style,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final natural = painter.width.ceilToDouble();
        // The face stays the name's size as text grows.
        final avatar = MediaQuery.textScalerOf(context).scale(_avatar);
        painter.dispose();
        final room = constraints.hasBoundedWidth
            ? math.max(0.0, constraints.maxWidth - avatar - _gap)
            : natural;
        final nameWidth = math.min(natural, room);
        final factsWidth = room - nameWidth - _gap;
        return Row(
          key: const ValueKey('user-summary-profile'),
          children: [
            _SummaryAvatar(
              username: user.username,
              avatarUrl: user.avatarUrl,
              dimension: avatar,
            ),
            const SizedBox(width: _gap),
            SizedBox(
              width: nameWidth,
              child: Semantics(
                header: true,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (factsWidth >= _minimumFacts) ...[
              const SizedBox(width: _gap),
              SizedBox(
                width: factsWidth,
                child: _ProfileFacts(
                  facts: [
                    (icon: null, text: '@${user.username}'),
                    (icon: DIcons.globe, text: instance.title),
                    if (summary.canSeeSummaryStats)
                      (
                        icon: DIcons.calendarDays,
                        text:
                            '${_number(summary.daysVisited)} '
                            '${context.l10n.daysVisited.toLowerCase()}',
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// One line tall: a fact that no longer fits wraps out of sight rather than
// being cut.
class _ProfileFacts extends StatelessWidget {
  const _ProfileFacts({required this.facts});
  final List<({DIconData? icon, String text})> facts;

  @override
  Widget build(BuildContext context) {
    final color = DTokens.of(context).mutedForeground;
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(16),
      child: Wrap(
        clipBehavior: Clip.hardEdge,
        spacing: _ProfileCard._gap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final fact in facts)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fact.icon case final icon?) ...[
                  DIcon(icon, size: 11, color: color),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: DText(
                    fact.text,
                    variant: DTextVariant.muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: DiscourseTypography.xs,
                      height: 16 / 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
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
          _SummarySection(
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
          _SummarySection(
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
        for (final (title, users, empty, noun) in [
          (
            context.l10n.mostRepliedTo,
            summary.mostRepliedToUsers,
            context.l10n.noRepliesYet,
            CountNoun.reply,
          ),
          (
            context.l10n.mostLikedBy,
            summary.mostLikedByUsers,
            context.l10n.noLikesYet,
            CountNoun.like,
          ),
          (
            context.l10n.mostLiked,
            summary.mostLikedUsers,
            context.l10n.noLikesYet,
            CountNoun.like,
          ),
        ])
          _SummarySection(
            title: title,
            child: _UserRows(
              siteUrl: siteUrl,
              users: users,
              emptyMessage: empty,
              noun: noun,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: DSpacing.xs),
                      if (summary.showRecentTimeRead)
                        _Caption(
                          context.l10n.inTheLast60Days(
                            (recent.short).toString(),
                          ),
                          semantics: context.l10n.recentReadTimeInTheLast60Days(
                            (recent.long).toString(),
                          ),
                        )
                      else
                        _Caption(context.l10n.allTimeReading),
                    ],
                  ),
                ),
                _Figures(
                  values: [
                    (
                      label: context.l10n.topicsViewed,
                      value: _number(summary.topicsEntered),
                    ),
                    (
                      label: context.l10n.postsRead,
                      value: _number(summary.postsReadCount),
                    ),
                    (
                      label: context.l10n.bookmarks,
                      value: _number(summary.bookmarkCount),
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

// Four figures, one size, in a well: on a narrow page they fold into two rows
// rather than squeezing their labels.
class _HeadlineStats extends StatelessWidget {
  const _HeadlineStats({required this.summary});
  final UserSummary summary;

  @override
  Widget build(BuildContext context) => DCard(
    variant: DCardVariant.well,
    borderColor: DTokens.of(context).footerBorder,
    spacing: 0,
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
            constraints.maxWidth <= 440 ||
                MediaQuery.textScalerOf(context).scale(12) > 18
            ? 2
            : 4;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              for (var start = 0; start < stats.length; start += columns) ...[
                if (start > 0) const SizedBox(height: 14),
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
                          DSeparator(
                            orientation: Axis.vertical,
                            color: DTokens.of(context).footerBorder,
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: stats[index],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
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
          DText(
            label,
            variant: DTextVariant.muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: DiscourseTypography.xs,
              height: DiscourseTypography.lineHeightCaption,
            ),
          ),
          const SizedBox(height: DSpacing.xs),
          DText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: DiscourseTypography.magnifier,
              height: 1.2,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

typedef _Figure = ({String label, String value});

// The figures that go with a box's headline, as lines of a table on the same
// rules the tables use.
class _Figures extends StatelessWidget {
  const _Figures({required this.values});
  final List<_Figure> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 180 ||
          (constraints.maxWidth < 400 &&
              MediaQuery.textScalerOf(context).scale(12) > 18);
      final muted = DTokens.of(context).mutedForeground;
      Widget labelText(String text) => DText(
        text,
        style: TextStyle(
          fontSize: DiscourseTypography.preview,
          height: 20 / 12.5,
          color: muted,
        ),
      );
      Widget valueText(String text) => DText(
        text,
        style: const TextStyle(
          fontSize: DiscourseTypography.control,
          height: 20 / 13,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final value in values) ...[
            const _Rule(),
            Semantics(
              container: true,
              label: '${value.label}: ${value.value}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: DSpacing.md,
                  ),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            labelText(value.label),
                            const SizedBox(height: DSpacing.xs),
                            valueText(value.value),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: labelText(value.label)),
                            const SizedBox(width: DSpacing.md),
                            valueText(value.value),
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
        if (index > 0) const SizedBox(height: DSpacing.lg),
        children[index],
      ],
    ],
  );
}

// Every block down the page is the same kind of thing: a box with its title
// inside, on half the well's fill so the page does not turn into a stack of
// solid plates. What it holds runs to the box's edges and keeps its own inset,
// so a row's hover can span the whole width.
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DCard(
      variant: DCardVariant.well,
      size: DCardSize.small,
      spacing: 0,
      backgroundColor: Color.alphaBlend(
        Colors.black.withValues(alpha: .04),
        tokens.background,
      ),
      borderColor: tokens.footerBorder,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: DCardHeader(title: DCardTitle(child: Text(title))),
        ),
        child,
      ],
    );
  }
}

// The rule over each line of a box, held off the box's edges by its inset.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => DSeparator(
    indent: 16,
    endIndent: 16,
    color: DTokens.of(context).footerBorder,
  );
}

TextStyle _reading(BuildContext context) {
  final body = Theme.of(context).textTheme.bodyLarge!;
  return TextStyle(
    fontFamily: body.fontFamily,
    fontFamilyFallback: body.fontFamilyFallback,
  );
}

class _TopicRows extends StatelessWidget {
  const _TopicRows({required this.emptyMessage, required this.rows});
  final String emptyMessage;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? _EmptySection(message: emptyMessage)
      : Padding(
          padding: const EdgeInsets.only(top: DSpacing.xs),
          child: DItemGroup(
            spacing: 0,
            children: [
              for (final row in rows) ...[const _Rule(), row],
            ],
          ),
        );
}

// A topic as the lists have it, cut to what a summary needs: the title, and
// under it the category and age, with the likes it is ranked by at the end.
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
    final tokens = DTokens.of(context);
    final label = [
      context.l10n.openUsersummary((topic.title).toString()),
      ?date,
      if (likes > 0) countLabel(likes, CountNoun.like),
    ].join(', ');
    return DItem(
      size: DItemSize.xs,
      shape: DItemShape.fullWidth,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      semanticLabel: label,
      onPressed: () => ShellScope.read(
        context,
      ).openSummaryTopic(topic, postNumber: postNumber),
      children: [
        DItemContent(
          spacing: 3,
          children: [
            ExcludeSemantics(
              child: DItemTitle(
                child: TopicTitle(
                  topic.title,
                  siteUrl: siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _reading(context).copyWith(
                    fontSize: DiscourseTypography.rowTitle,
                    height: DiscourseTypography.lineHeightRowTitle,
                    fontWeight: FontWeight.w500,
                    color: tokens.foreground,
                  ),
                ),
              ),
            ),
            if (category != null || date != null)
              ExcludeSemantics(
                child: DItemDescription(
                  maxLines: 1,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: DiscourseTypography.xs,
                      height: 16 / 12,
                    ),
                    child: Row(
                      children: [
                        if (category != null) ...[
                          CategoryIcon(
                            category: category,
                            siteUrl: siteUrl,
                            size: 12,
                            squareSize: 9,
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: Text(category.name)),
                        ],
                        if (date != null) ...[
                          if (category != null) const SizedBox(width: 10),
                          Text(date),
                        ],
                      ],
                    ),
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
                DIcon(DIcons.heart, size: 9, color: tokens.mutedForeground),
                const SizedBox(width: DSpacing.xs),
                DText(
                  _number(likes),
                  variant: DTextVariant.muted,
                  style: const TextStyle(
                    fontSize: DiscourseTypography.metadata,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

typedef _Column = ({String label, double width});

// A table in its box: the name column takes what the values leave, each value
// is right-aligned in a column of its own width so figures of different
// lengths end on one edge, and every line has a rule over it.
class _SummaryTable extends StatelessWidget {
  const _SummaryTable({
    required this.name,
    required this.columns,
    required this.rows,
    this.semanticLabel,
  });
  final String name;
  final List<_Column> columns;
  final List<(Widget, List<Widget>)> rows;
  final String? semanticLabel;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final muted = DTokens.of(context).mutedForeground;
    final last = columns.length;
    EdgeInsetsGeometry inset(int column, double vertical) =>
        EdgeInsetsDirectional.only(
          start: column == 0 ? 0 : _gap,
          end: column == last ? 0 : _gap,
          top: vertical,
          bottom: vertical,
        );
    final values = TextStyle(
      fontSize: DiscourseTypography.xs,
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DTable(
        semanticLabel: semanticLabel,
        minimumWidth: scaler.scale(280),
        borderColor: DTokens.of(context).footerBorder,
        columnWidths: {
          0: const FlexColumnWidth(),
          for (var i = 0; i < columns.length; i++)
            i + 1: FixedColumnWidth(scaler.scale(columns[i].width)),
        },
        header: DTableHeader(
          rows: [
            DTableRow(
              cells: [
                for (final (index, label) in [
                  name,
                  for (final column in columns) column.label,
                ].indexed)
                  DTableHead(
                    padding: inset(index, 0),
                    alignment: index == 0
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DiscourseTypography.metadata,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: DTableBody(
          rows: [
            for (final (lead, cells) in rows)
              DTableRow(
                cells: [
                  DTableCell(padding: inset(0, 10), child: lead),
                  for (final (index, cell) in cells.indexed)
                    DTableCell(
                      padding: inset(index + 1, 10),
                      alignment: AlignmentDirectional.centerEnd,
                      textStyle: values,
                      child: cell,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// The name a table row is about: its mark, then the name and a note beside it
// on the one line. With [onPressed] the words are where the row goes.
class _RowName extends StatelessWidget {
  const _RowName({
    required this.mark,
    required this.title,
    this.note,
    this.onPressed,
    this.semanticLabel,
  });
  final Widget mark;
  final String title;
  final String? note;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    Widget words = Text.rich(
      TextSpan(
        text: title,
        style: _reading(context).copyWith(
          fontSize: DiscourseTypography.control,
          height: 20 / 13,
          fontWeight: FontWeight.w500,
          color: tokens.foreground,
        ),
        children: [
          if (note case final note?) ...[
            const WidgetSpan(child: SizedBox(width: 7)),
            TextSpan(
              text: note,
              style: TextStyle(
                fontSize: DiscourseTypography.metadata,
                fontWeight: FontWeight.w400,
                color: tokens.mutedForeground,
              ),
            ),
          ],
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    if (onPressed case final onPressed?) {
      words = DButton(
        variant: DButtonVariant.inline,
        semanticLabel: semanticLabel,
        onPressed: onPressed,
        label: words,
      );
    }
    return Row(
      children: [
        SizedBox.square(dimension: 22, child: Center(child: mark)),
        const SizedBox(width: 9),
        Flexible(child: words),
      ],
    );
  }
}

// The tinted tile a category, a link or a milestone is marked with, at a
// row's size.
class _Tile extends StatelessWidget {
  const _Tile({required this.color, required this.icon});
  final Color color;
  final DIconData icon;

  @override
  Widget build(BuildContext context) => DAvatar(
    dimension: 22,
    border: false,
    decorative: true,
    borderRadius: BorderRadius.circular(7),
    fallback: DAvatarFallback(
      backgroundColor: Color.lerp(DTokens.of(context).background, color, .2),
      child: DIcon(icon, size: 11, color: color),
    ),
  );
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
            // The post a link was in is the column that can go.
            final showSource =
                constraints.maxWidth > 520 &&
                MediaQuery.textScalerOf(context).scale(12) <= 18;
            final mark = _Tile(
              color: DTokens.of(context).mutedForeground,
              icon: DIcons.link,
            );
            return _SummaryTable(
              name: context.l10n.link,
              columns: [
                if (showSource)
                  (label: context.l10n.summaryPostedIn, width: 200),
                (label: context.l10n.summaryClicks, width: 56),
              ],
              rows: [
                for (final link in links)
                  (
                    _RowName(
                      mark: mark,
                      title: link.title ?? _host(link.url),
                      note: _host(link.url),
                      semanticLabel: context.l10n.openUsersummaryValue(
                        link.topic.title,
                      ),
                      // The link is in a post, and the post is where it goes.
                      onPressed: () =>
                          ShellScope.read(context).openSummaryTopic(
                            link.topic,
                            postNumber: link.postNumber,
                          ),
                    ),
                    [
                      if (showSource)
                        TopicTitle(
                          link.topic.title,
                          siteUrl: siteUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(_number(link.clicks)),
                    ],
                  ),
              ],
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
      : _SummaryTable(
          name: context.l10n.summaryPerson,
          columns: [
            (
              label: noun == CountNoun.reply
                  ? context.l10n.replies
                  : context.l10n.likes,
              width: 72,
            ),
          ],
          rows: [
            for (final user in users)
              (
                UserCardTarget(
                  username: user.username,
                  siteUrl: siteUrl,
                  semanticLabel: context.l10n.viewProfileForUsersummary(
                    user.displayName,
                    countLabel(user.count, noun),
                  ),
                  child: _RowName(
                    mark: _SummaryAvatar(
                      username: user.username,
                      avatarUrl: user.avatarUrl,
                      dimension: 21,
                    ),
                    title: user.displayName,
                    note: '@${user.username}',
                  ),
                ),
                [Text(_number(user.count))],
              ),
          ],
        );
}

class _SummaryAvatar extends StatelessWidget {
  const _SummaryAvatar({
    required this.username,
    required this.dimension,
    this.avatarUrl,
  });
  final String username;
  final String? avatarUrl;
  final double dimension;

  @override
  Widget build(BuildContext context) => DAvatar(
    dimension: dimension,
    decorative: true,
    child: AvatarImage(
      url: avatarUrl,
      size: dimension,
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
  Widget build(BuildContext context) => _SummaryTable(
    semanticLabel: context.l10n.topCategories,
    name: context.l10n.category,
    columns: [
      (label: context.l10n.topics, width: 64),
      (label: context.l10n.replies, width: 72),
    ],
    rows: [
      for (final category in categories)
        (
          _RowName(
            mark: _Tile(color: Color(category.colorValue), icon: DIcons.tag),
            title: category.name,
          ),
          [
            for (final topics in [true, false])
              (topics ? category.topicCount : category.postCount) <= 0
                  ? const Text('\u2014')
                  : DButton(
                      variant: DButtonVariant.inline,
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
          ],
        ),
    ],
  );
}

// Milestones as the Start page's rows across the whole width: packed to the
// start, so they read as a list of things rather than a rank of columns.
class _BadgeRows extends StatelessWidget {
  const _BadgeRows({required this.badges});
  final List<UserSummaryBadge> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return _EmptySection(message: context.l10n.noBadgesYet);
    final tokens = DTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, DSpacing.xs, 16, 16),
      child: Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          for (final badge in badges)
            Semantics(
              container: true,
              label: context.l10n.earnedUsersummary(
                badge.count,
                (badge.name).toString(),
              ),
              child: DTooltip(
                message: badge.description ?? badge.name,
                focusable: true,
                child: ExcludeSemantics(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: IntrinsicWidth(
                      child: DCard(
                        variant: DCardVariant.well,
                        size: DCardSize.small,
                        spacing: 0,
                        border: false,
                        borderRadius: BorderRadius.circular(9),
                        backgroundColor: tokens.footerBackground,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 37),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            child: Row(
                              children: [
                                _Tile(
                                  color: tokens.primary,
                                  icon:
                                      pluginIconNamed(context, badge.icon) ??
                                      DIcons.certificate,
                                ),
                                const SizedBox(width: 9),
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      text: badge.name,
                                      style: _reading(context).copyWith(
                                        fontSize: DiscourseTypography.control,
                                        height: 20 / 13,
                                        fontWeight: FontWeight.w500,
                                        color: tokens.foreground,
                                      ),
                                      children: [
                                        if (badge.count > 1) ...[
                                          const WidgetSpan(
                                            child: SizedBox(width: 7),
                                          ),
                                          TextSpan(
                                            text: '\u00d7${badge.count}',
                                            style: TextStyle(
                                              fontSize:
                                                  DiscourseTypography.metadata,
                                              fontWeight: FontWeight.w400,
                                              color: tokens.mutedForeground,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => DCard(
    variant: DCardVariant.well,
    borderColor: DTokens.of(context).footerBorder,
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
    padding: const EdgeInsets.fromLTRB(16, DSpacing.md, 16, DSpacing.lg),
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
          DSkeleton(height: 76),
          DSkeleton(height: 320),
          DSkeleton(height: 320),
        ],
      ),
    ),
  );
}

String _number(int value) => NumberFormat.decimalPattern().format(value);

String _host(String source) {
  final uri = Uri.tryParse(source);
  return uri == null || uri.host.isEmpty ? source : uri.host;
}
