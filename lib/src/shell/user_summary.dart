import 'dart:async';

import 'package:flutter/material.dart';

import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../models/user_summary.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'external_link.dart';
import 'inline_action.dart';
import 'loading_skeleton.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';
import 'user_card.dart';

/// The connected account's native equivalent of Discourse's user Summary.
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
          siteUrl: widget.siteUrl,
          username: instance!.user!.username,
          badgesEnabled: instance.config.badgesEnabled,
          summary: summary,
          error: state.error,
          refreshing: state.loading,
          onRefresh: _refresh,
        );
      },
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({
    required this.siteUrl,
    required this.username,
    required this.badgesEnabled,
    required this.summary,
    required this.error,
    required this.refreshing,
    required this.onRefresh,
  });

  final String siteUrl;
  final String username;
  final bool badgesEnabled;
  final UserSummary summary;
  final String? error;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('user-summary-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error case final error?)
                    _SummaryErrorBanner(
                      error: error,
                      refreshing: refreshing,
                      onRetry: onRefresh,
                    ),
                  if (summary.canSeeSummaryStats) ...[
                    _Stats(summary: summary),
                    const SizedBox(height: 28),
                  ],
                  _PairedSections(
                    left: _SummarySection(
                      title: 'Top Replies',
                      child: _TopicRows(
                        emptyMessage: 'No replies yet.',
                        rows: [
                          for (final reply in summary.replies)
                            _SummaryTopicRow(
                              siteUrl: siteUrl,
                              topic: reply.topic,
                              postNumber: reply.postNumber,
                              createdAt: reply.createdAt,
                              likes: reply.likeCount,
                            ),
                        ],
                      ),
                    ),
                    right: _SummarySection(
                      title: 'Top Topics',
                      child: _TopicRows(
                        emptyMessage: 'No topics yet.',
                        rows: [
                          for (final topic in summary.topics)
                            _SummaryTopicRow(
                              siteUrl: siteUrl,
                              topic: topic,
                              createdAt: topic.createdAt,
                              likes: topic.likeCount,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _PairedSections(
                    left: _SummarySection(
                      title: 'Top Links',
                      child: _LinkRows(siteUrl: siteUrl, links: summary.links),
                    ),
                    right: _SummarySection(
                      title: 'Most Replied To',
                      child: _UserRows(
                        siteUrl: siteUrl,
                        users: summary.mostRepliedToUsers,
                        emptyMessage: 'No replies yet.',
                        icon: DIcons.reply,
                        countLabel: 'replies',
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _PairedSections(
                    left: _SummarySection(
                      title: 'Most Liked By',
                      child: _UserRows(
                        siteUrl: siteUrl,
                        users: summary.mostLikedByUsers,
                        emptyMessage: 'No likes yet.',
                        icon: DIcons.heart,
                        countLabel: 'likes',
                      ),
                    ),
                    right: _SummarySection(
                      title: 'Most Liked',
                      child: _UserRows(
                        siteUrl: siteUrl,
                        users: summary.mostLikedUsers,
                        emptyMessage: 'No likes yet.',
                        icon: DIcons.heart,
                        countLabel: 'likes',
                      ),
                    ),
                  ),
                  if (summary.topCategories.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _SummarySection(
                      title: 'Top Categories',
                      child: _CategoryRows(
                        username: username,
                        categories: summary.topCategories,
                      ),
                    ),
                  ],
                  if (badgesEnabled) ...[
                    const SizedBox(height: 28),
                    _SummarySection(
                      title: 'Top Badges',
                      child: _BadgeRows(badges: summary.badges),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary});

  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final timeRead = summaryDuration(summary.timeRead);
    final recentTimeRead = summaryDuration(summary.recentTimeRead);
    return _SummarySection(
      title: 'Stats',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Stat(value: '${summary.daysVisited}', label: 'days visited'),
          _Stat(
            value: timeRead.short,
            semanticValue: '${timeRead.long}, all time',
            label: 'read time',
          ),
          if (summary.showRecentTimeRead)
            _Stat(
              value: recentTimeRead.short,
              semanticValue: '${recentTimeRead.long}, in the last 60 days',
              label: 'recent read time',
            ),
          _Stat(value: '${summary.topicsEntered}', label: 'topics viewed'),
          _Stat(value: '${summary.postsReadCount}', label: 'posts read'),
          _Stat(
            value: '${summary.likesGiven}',
            label: 'given',
            icon: DIcons.heart,
          ),
          _Stat(
            value: '${summary.likesReceived}',
            label: 'received',
            icon: DIcons.heart,
          ),
          if (summary.bookmarkCount > 0)
            _Stat(
              value: '${summary.bookmarkCount}',
              label: summary.bookmarkCount == 1 ? 'bookmark' : 'bookmarks',
              icon: DIcons.bookmark,
            ),
          _Stat(
            value: '${summary.topicCount}',
            label: summary.topicCount == 1 ? 'topic created' : 'topics created',
          ),
          _Stat(
            value: '${summary.postCount}',
            label: summary.postCount == 1 ? 'post created' : 'posts created',
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.semanticValue,
    this.icon,
  });

  final String value;
  final String label;
  final String? semanticValue;
  final DIconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: ${semanticValue ?? value}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 112),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon case final icon?) ...[
                    DIcon(icon, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairedSections extends StatelessWidget {
  const _PairedSections({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <= 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 28), right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 28),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _TopicRows extends StatelessWidget {
  const _TopicRows({required this.emptyMessage, required this.rows});

  final String emptyMessage;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? _EmptySection(message: emptyMessage)
      : Column(children: rows);
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
    final theme = Theme.of(context);
    final date = createdAt == null ? null : relativeTime(createdAt!);
    final details = [?date, if (likes > 0) '$likes likes'];
    return Semantics(
      button: true,
      label: [
        'Open ${topic.title}',
        ?date,
        if (likes > 0) '$likes likes',
      ].join(', '),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => ShellScope.read(
            context,
          ).openSummaryTopic(topic, postNumber: postNumber),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: theme.shell.divider, width: 2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (details.isNotEmpty) ...[
                  Text(
                    details.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                TopicTitle(
                  topic.title,
                  siteUrl: siteUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      : Column(
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final externalLabel = _shortUrl(link.url);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 7, 8, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.shell.divider, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InlineAction.link(
            onTap: () => unawaited(openExternalLink(link.url)),
            semanticLabel:
                'Open external link $externalLabel, ${link.clicks} clicks',
            excludeChildSemantics: true,
            child: Text(
              externalLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 4),
          InlineAction.link(
            onTap: () => ShellScope.read(
              context,
            ).openSummaryTopic(link.topic, postNumber: link.postNumber),
            semanticLabel: 'Open ${link.topic.title}',
            excludeChildSemantics: true,
            child: TopicTitle(
              link.topic.title,
              siteUrl: siteUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRows extends StatelessWidget {
  const _UserRows({
    required this.siteUrl,
    required this.users,
    required this.emptyMessage,
    required this.icon,
    required this.countLabel,
  });

  final String siteUrl;
  final List<UserSummaryUser> users;
  final String emptyMessage;
  final DIconData icon;
  final String countLabel;

  @override
  Widget build(BuildContext context) => users.isEmpty
      ? _EmptySection(message: emptyMessage)
      : Column(
          children: [
            for (final user in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: UserCardTarget(
                  username: user.username,
                  siteUrl: siteUrl,
                  semanticLabel:
                      'View profile for ${user.displayName}, '
                      '${user.count} $countLabel',
                  child: _SummaryUserRow(
                    user: user,
                    icon: icon,
                    countLabel: countLabel,
                  ),
                ),
              ),
          ],
        );
}

class _SummaryUserRow extends StatelessWidget {
  const _SummaryUserRow({
    required this.user,
    required this.icon,
    required this.countLabel,
  });

  final UserSummaryUser user;
  final DIconData icon;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = user.username.characters.firstOrNull?.toUpperCase() ?? '?';
    return Semantics(
      label: '${user.displayName}, ${user.count} $countLabel',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox.square(
                  dimension: 36,
                  child: AvatarImage(
                    url: user.avatarUrl,
                    size: 36,
                    fallback: ColoredBox(
                      color: theme.colorScheme.primaryContainer,
                      child: Center(
                        child: Text(
                          initial,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (user.name != null)
                      Text(
                        '@${user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              DIcon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text('${user.count}', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRows extends StatelessWidget {
  const _CategoryRows({required this.username, required this.categories});

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: SizedBox()),
            SizedBox(
              width: 76,
              child: Text(
                'Topics',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                'Replies',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ),
        for (final category in categories)
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.shell.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(category.colorValue),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          category.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (category.readRestricted) ...[
                        const SizedBox(width: 5),
                        const DIcon(DIcons.lock, size: 12),
                      ],
                    ],
                  ),
                ),
                _CategoryCount(
                  count: category.topicCount,
                  semanticLabel:
                      'Search ${category.topicCount} topics by @$username '
                      'in ${category.name}',
                  onTap: () => _search(context, category, topics: true),
                ),
                _CategoryCount(
                  count: category.postCount,
                  semanticLabel:
                      'Search ${category.postCount} replies by @$username '
                      'in ${category.name}',
                  onTap: () => _search(context, category, topics: false),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryCount extends StatelessWidget {
  const _CategoryCount({
    required this.count,
    required this.semanticLabel,
    required this.onTap,
  });

  final int count;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: count <= 0
        ? const Text('—', textAlign: TextAlign.center)
        : Semantics(
            button: true,
            label: semanticLabel,
            child: TextButton(
              onPressed: onTap,
              child: ExcludeSemantics(child: Text('$count')),
            ),
          ),
  );
}

class _BadgeRows extends StatelessWidget {
  const _BadgeRows({required this.badges});

  final List<UserSummaryBadge> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const _EmptySection(message: 'No badges yet.');
    final theme = Theme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final badge in badges)
          Semantics(
            container: true,
            label:
                '${badge.name}, earned ${badge.count} '
                '${badge.count == 1 ? 'time' : 'times'}',
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border.all(color: theme.shell.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DIcon(
                      DIcons.byName[badge.icon] ?? DIcons.certificate,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badge.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (badge.description case final description?) ...[
                            const SizedBox(height: 3),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (badge.count > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        '×${badge.count}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            DIcon(
              DIcons.triangleExclamation,
              size: 18,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(error)),
            DButton(
              label: const Text('Retry'),
              onPressed: () => unawaited(onRetry()),
              variant: DButtonVariant.link,
              loading: refreshing,
              loadingLabel: const Text('Refreshing…'),
            ),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: icon == DIcons.triangleExclamation,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (actionLabel case final label?) ...[
                const SizedBox(height: 20),
                DButton(
                  label: Text(label),
                  onPressed: onAction == null
                      ? null
                      : () => unawaited(onAction!()),
                  variant: DButtonVariant.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLoadingSkeleton extends StatelessWidget {
  const _SummaryLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    semanticsLabel: 'Loading summary',
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LoadingSkeletonBlock(width: 70, height: 11),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var index = 0; index < 8; index++)
                    const LoadingSkeletonBlock(
                      width: 116,
                      height: 62,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                ],
              ),
              const SizedBox(height: 30),
              const LoadingSkeletonBlock(width: 110, height: 11),
              const SizedBox(height: 12),
              for (final width in [0.72, 0.9, 0.61]) ...[
                FractionallySizedBox(
                  widthFactor: width,
                  child: const LoadingSkeletonBlock(height: 44),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 22),
              const LoadingSkeletonBlock(width: 90, height: 11),
              const SizedBox(height: 12),
              for (final width in [0.86, 0.66]) ...[
                FractionallySizedBox(
                  widthFactor: width,
                  child: const LoadingSkeletonBlock(height: 52),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

typedef SummaryDuration = ({String short, String long});

/// Core's tiny/medium duration pair used by Summary read-time stats.
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
