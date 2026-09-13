import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../models/user_summary.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
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
          return const _SummaryState(
            icon: DIcons.user,
            title: 'Connect this account to see its summary',
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
              actionLabel: 'Try again',
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
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: widget.onRefresh,
    child: _SummaryLayout(
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
              const DTabList<_SummaryTab>(
                variant: DTabListVariant.line,
                children: [
                  DTabTrigger(
                    value: _SummaryTab.highlights,
                    child: Text('Highlights'),
                  ),
                  DTabTrigger(
                    value: _SummaryTab.connections,
                    child: Text('Connections'),
                  ),
                  DTabTrigger(
                    value: _SummaryTab.reading,
                    child: Text('Reading'),
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
    final time = summaryDuration(summary.timeRead);
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
                      style: const TextStyle(fontSize: 12, height: 16 / 12),
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
                      label: 'Days visited',
                      value: _number(summary.daysVisited),
                      semantics: null,
                    ),
                    (
                      label: 'Time reading',
                      value: time.short,
                      semantics: 'read time: ${time.long}, all time',
                    ),
                    (
                      label: 'Likes given',
                      value: _number(summary.likesGiven),
                      semantics: null,
                    ),
                    if (summary.bookmarkCount > 0)
                      (
                        label: 'Bookmarks',
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
          const _EmptyCard(
            title: 'Your story starts with a conversation.',
            description:
                'As you read, reply and connect with people, your highlights will appear here.',
          )
        else ...[
          _PairedSections(
            left: _SummarySection(
              title: 'Top topics',
              child: _TopicRows(
                emptyMessage: 'No topics yet.',
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
              title: 'Top replies',
              description: 'Conversations you joined',
              child: _TopicRows(
                emptyMessage: 'No replies yet.',
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
              title: 'Your milestones',
              description: 'Badges earned in the community',
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
      return const _EmptyCard(
        title: 'No connections yet.',
        description:
            'The people you reply to and exchange likes with will appear here.',
      );
    }
    return _SectionStack(
      children: [
        _SummarySection(
          title: 'Most replied to',
          child: _UserRows(
            siteUrl: siteUrl,
            users: summary.mostRepliedToUsers,
            emptyMessage: 'No replies yet.',
            countLabel: 'replies',
          ),
        ),
        _PairedSections(
          left: _SummarySection(
            title: 'Most liked by',
            child: _UserRows(
              siteUrl: siteUrl,
              users: summary.mostLikedByUsers,
              emptyMessage: 'No likes yet.',
              countLabel: 'likes',
            ),
          ),
          right: _SummarySection(
            title: 'Most liked',
            child: _UserRows(
              siteUrl: siteUrl,
              users: summary.mostLikedUsers,
              emptyMessage: 'No likes yet.',
              countLabel: 'likes',
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
    final time = summaryDuration(summary.timeRead);
    final recent = summaryDuration(summary.recentTimeRead);
    return _SectionStack(
      children: [
        if (summary.canSeeSummaryStats)
          _SummarySection(
            title: 'Time well spent',
            description: 'Reading across the community',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(
                  time.short,
                  semanticsLabel: 'read time: ${time.long}, all time',
                  style: const TextStyle(
                    fontSize: DiscourseTypography.xxxl,
                    height: 36 / 30,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: DSpacing.xs),
                if (summary.showRecentTimeRead)
                  _Caption(
                    '${recent.short} in the last 60 days',
                    semantics:
                        'recent read time: ${recent.long}, in the last 60 days',
                  )
                else
                  const _Caption('All-time reading'),
                const SizedBox(height: DSpacing.sm),
                _DetailStats(
                  values: [
                    (
                      label: 'Topics viewed',
                      value: _number(summary.topicsEntered),
                      semantics: null,
                    ),
                    (
                      label: 'Posts read',
                      value: _number(summary.postsReadCount),
                      semantics: null,
                    ),
                    if (summary.bookmarkCount > 0)
                      (
                        label: 'Bookmarks',
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
            title: 'Top categories',
            child: _CategoryRows(
              siteUrl: instance.url,
              username: instance.user!.username,
              categories: summary.topCategories,
            ),
          ),
        _SummarySection(
          title: 'Top links',
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
                label: 'Likes received',
                value: _number(summary.likesReceived),
              ),
              _Stat(
                label: 'Replies written',
                value: _number(summary.postCount),
              ),
              _Stat(
                label: 'Topics started',
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
    style: const TextStyle(fontSize: 12, height: 16 / 12),
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
      style: const TextStyle(fontSize: 12, height: 16 / 12),
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
  const _SummarySection({
    required this.title,
    this.description,
    required this.child,
  });
  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) => DCard(
    children: [
      DCardHeader(
        title: DCardTitle(child: Text(title)),
        description: description == null
            ? null
            : DCardDescription(child: Text(description!)),
      ),
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

  @override
  Widget build(BuildContext context) {
    final date = createdAt == null ? null : relativeTime(createdAt!);
    final category = ShellScope.read(
      context,
    ).categoryFor(topic.categoryId, siteUrl: siteUrl);
    final label = [
      'Open ${topic.title}',
      ?date,
      if (likes > 0) '$likes likes',
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
      ? const _EmptySection(message: 'No links yet.')
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
    semanticLabel:
        'Open external link ${_shortUrl(link.url)}, ${link.clicks} clicks',
    link: true,
    onPressed: () => unawaited(openExternalLink(link.url)),
    footer: DItemFooter(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DButton(
          variant: DButtonVariant.link,
          semanticLabel: 'Open ${link.topic.title}',
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
      ExcludeSemantics(child: _Caption('${_number(link.clicks)} clicks')),
    ],
  );
}

class _UserRows extends StatelessWidget {
  const _UserRows({
    required this.siteUrl,
    required this.users,
    required this.emptyMessage,
    required this.countLabel,
  });
  final String siteUrl;
  final List<UserSummaryUser> users;
  final String emptyMessage;
  final String countLabel;

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
                semanticLabel:
                    'View profile for ${user.displayName}, ${user.count} $countLabel',
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
                        _Caption(countLabel),
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
    final search = ShellScope.read(context).search;
    search.requestFocus();
    search.setQuery('@$username #${category.slug}${topics ? ' in:first' : ''}');
    search.showTopics();
  }

  @override
  Widget build(BuildContext context) => DTable(
    semanticLabel: 'Top categories',
    columnWidths: const {
      0: IntrinsicColumnWidth(flex: 1),
      1: IntrinsicColumnWidth(),
      2: IntrinsicColumnWidth(),
    },
    header: const DTableHeader(
      rows: [
        DTableRow(
          cells: [
            DTableHead(child: Text('Category')),
            DTableHead(
              alignment: AlignmentDirectional.centerEnd,
              child: Text('Topics'),
            ),
            DTableHead(
              alignment: AlignmentDirectional.centerEnd,
              child: Text('Replies'),
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
                          semanticLabel:
                              'Search ${topics ? category.topicCount : category.postCount} ${topics ? 'topics' : 'replies'} by @$username in ${category.name}',
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
      ? const _EmptySection(message: 'No badges yet.')
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
                    semanticLabel:
                        '${badge.name}, earned ${badge.count} ${badge.count == 1 ? 'time' : 'times'}',
                    leading: DIcon(
                      DIcons.byName[badge.icon] ?? DIcons.certificate,
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
          label: const Text('Retry'),
          onPressed: () => unawaited(onRetry()),
          variant: DButtonVariant.link,
          loading: refreshing,
          loadingLabel: const Text('Refreshing…'),
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
  Widget build(BuildContext context) => const DSkeletonRegion(
    expand: true,
    semanticsLabel: 'Loading summary',
    child: _SummaryLayout(
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

typedef SummaryDuration = ({String short, String long});

SummaryDuration summaryDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = (safe / 60).round().clamp(1, 1 << 31);
  if (safe <= 59) {
    return (short: '<1m', long: 'less than 1 min');
  }
  if (minutes <= 44) {
    return (
      short: '${minutes}m',
      long: '$minutes ${minutes == 1 ? 'min' : 'mins'}',
    );
  }
  if (minutes <= 89) {
    return (short: '1h', long: 'about 1 hour');
  }
  if (minutes <= 1409) {
    final count = (minutes / 60).round();
    return (
      short: '${count}h',
      long: 'about $count ${count == 1 ? 'hour' : 'hours'}',
    );
  }
  if (minutes <= 2519) {
    return (short: '1d', long: '1 day');
  }
  if (minutes <= 129599) {
    final count = (minutes / 1440).round();
    return (short: '${count}d', long: '$count days');
  }
  if (minutes <= 525599) {
    final count = (minutes / 43200).round();
    return (
      short: '${count}mon',
      long: '$count ${count == 1 ? 'month' : 'months'}',
    );
  }

  final years = minutes / 525600;
  final remainder = years % 1;
  if (remainder < 0.25) {
    final count = years.floor();
    return (
      short: '${count}y',
      long: 'about $count ${count == 1 ? 'year' : 'years'}',
    );
  }
  if (remainder < 0.75) {
    final count = years.floor();
    return (
      short: '> ${count}y',
      long: 'over $count ${count == 1 ? 'year' : 'years'}',
    );
  }
  final count = years.floor() + 1;
  return (
    short: '${count}y',
    long: 'almost $count ${count == 1 ? 'year' : 'years'}',
  );
}

String _shortUrl(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.host.isEmpty) return source;
  final path = uri.path == '/' ? '' : uri.path;
  return '${uri.host}$path';
}
