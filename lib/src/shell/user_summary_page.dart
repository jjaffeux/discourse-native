import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/user_summary.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'topic_title.dart';
import 'user_card.dart';
import 'user_status.dart';

/// The native counterpart of Discourse's connected-user Summary route.
class UserSummaryPage extends StatefulWidget {
  const UserSummaryPage({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<UserSummaryPage> createState() => _UserSummaryPageState();
}

class _UserSummaryPageState extends State<UserSummaryPage> {
  (ShellController, String, String)? _requestedIdentity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(UserSummaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _request();
  }

  DiscourseInstance? _instance(ShellController controller) => controller
      .instances
      .where((instance) => instance.url == widget.siteUrl)
      .firstOrNull;

  void _request() {
    // A replacement controller owns a different account/session cache even
    // when the site URL and username happen to be unchanged.
    final controller = ShellScope.identityOf(context);
    final instance = _instance(controller);
    final username = instance?.user?.username;
    if (instance == null || username == null) return;
    final identity = (controller, widget.siteUrl, username.toLowerCase());
    if (_requestedIdentity == identity) return;
    _requestedIdentity = identity;
    unawaited(controller.userSummaries.load(instance));
  }

  Future<void> _refresh() async {
    final controller = ShellScope.read(context);
    final instance = _instance(controller);
    if (instance != null) {
      await controller.userSummaries.load(instance, refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ListenableBuilder(
      listenable: controller.userSummaries,
      builder: (context, _) {
        final instance = _instance(controller);
        final user = instance?.user;
        if (instance == null || user == null) {
          return const _SummaryState(
            icon: DIcons.user,
            title: 'Connect this account to view its summary',
          );
        }

        final state = controller.userSummaries.stateFor(
          widget.siteUrl,
          user.username,
        );
        final summary = state.summary;
        if (!state.loaded && summary == null) {
          return const _SummaryLoading();
        }
        if (summary == null) {
          return _SummaryState(
            icon: DIcons.triangleExclamation,
            title: state.error ?? "Couldn't load your summary.",
            actionLabel: 'Try again',
            onAction: _refresh,
          );
        }

        return _SummaryContent(
          siteUrl: widget.siteUrl,
          instance: instance,
          user: user,
          summary: summary,
          loading: state.loading,
          error: state.error,
          onRefresh: _refresh,
        );
      },
    );
  }
}

class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Loading summary',
    child: const Center(child: CircularProgressIndicator.adaptive()),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (actionLabel case final label?) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onAction == null
                      ? null
                      : () => unawaited(onAction!()),
                  child: Text(label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({
    required this.siteUrl,
    required this.instance,
    required this.user,
    required this.summary,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final String siteUrl;
  final DiscourseInstance instance;
  final DiscourseUser user;
  final UserSummary summary;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      _ProfileIdentity(user: user, siteUrl: siteUrl, onRefresh: onRefresh),
      if (summary.canSeeSummaryStats) _StatsSection(summary: summary),
      _SummaryPair(
        first: _TopicsSection(
          title: 'Top Replies',
          emptyMessage: 'No replies yet.',
          rows: [
            for (final reply in summary.replies)
              _SummaryTopicRow(
                siteUrl: siteUrl,
                topic: reply.topic,
                createdAt: reply.createdAt,
                likes: reply.likeCount,
                postNumber: reply.postNumber,
              ),
          ],
        ),
        second: _TopicsSection(
          title: 'Top Topics',
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
      _SummaryPair(
        first: _LinksSection(siteUrl: siteUrl, links: summary.links),
        second: _UsersSection(
          siteUrl: siteUrl,
          title: 'Most Replied To',
          emptyMessage: 'No replies yet.',
          users: summary.mostRepliedToUsers,
          icon: DIcons.reply,
          countLabel: 'replies',
        ),
      ),
      _SummaryPair(
        first: _UsersSection(
          siteUrl: siteUrl,
          title: 'Most Liked By',
          emptyMessage: 'No likes yet.',
          users: summary.mostLikedByUsers,
          icon: DIcons.heart,
          countLabel: 'likes',
        ),
        second: _UsersSection(
          siteUrl: siteUrl,
          title: 'Most Liked',
          emptyMessage: 'No likes yet.',
          users: summary.mostLikedUsers,
          icon: DIcons.heart,
          countLabel: 'likes',
        ),
      ),
      if (summary.topCategories.isNotEmpty)
        _CategoriesSection(
          username: user.username,
          categories: summary.topCategories,
        ),
      if (instance.config.badgesEnabled)
        _BadgesSection(siteUrl: siteUrl, badges: summary.badges),
    ];

    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('user-summary-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (error case final message?)
            _SummaryErrorBanner(message: message, onRetry: onRefresh),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < sections.length; index++) ...[
                    if (index > 0) const SizedBox(height: 16),
                    sections[index],
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

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({
    required this.user,
    required this.siteUrl,
    required this.onRefresh,
  });

  final DiscourseUser user;
  final String siteUrl;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const avatarSize = 56.0;
    return _Surface(
      child: Row(
        children: [
          Semantics(
            image: true,
            label: 'Profile picture for @${user.username}',
            child: ExcludeSemantics(
              child: ClipOval(
                child: SizedBox.square(
                  dimension: avatarSize,
                  child: AvatarImage(
                    url: user.avatarUrl,
                    size: avatarSize,
                    fallback: ColoredBox(
                      color: theme.colorScheme.primary,
                      child: Center(
                        child: Text(
                          user.username.characters.first.toUpperCase(),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '@${user.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                UserStatusMessage(
                  siteUrl: siteUrl,
                  userId: user.id,
                  status: user.status,
                  showDescription: true,
                  size: 16,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('user-summary-refresh'),
            tooltip: 'Refresh summary',
            onPressed: () => unawaited(onRefresh()),
            icon: const DIcon(DIcons.arrowsRotate, size: 19),
          ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.summary});

  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final stats = <Widget>[
      _Stat(
        value: '${summary.daysVisited}',
        label: _plural(summary.daysVisited, 'day visited', 'days visited'),
      ),
      _Stat(
        value: _readTime(summary.timeRead),
        label: 'read time',
        semanticsValue:
            '${_readTimeLong(summary.timeRead)} read time, all time',
      ),
      if (summary.showRecentTimeRead)
        _Stat(
          value: _readTime(summary.recentTimeRead),
          label: 'recent read time',
          semanticsValue:
              '${_readTimeLong(summary.recentTimeRead)} read time in the last 60 days',
        ),
      _Stat(
        value: '${summary.topicsEntered}',
        label: _plural(summary.topicsEntered, 'topic viewed', 'topics viewed'),
      ),
      _Stat(
        value: '${summary.postsRead}',
        label: _plural(summary.postsRead, 'post read', 'posts read'),
      ),
      _Stat(
        value: '${summary.likesGiven}',
        label: 'given',
        icon: DIcons.heart,
        semanticsValue: '${summary.likesGiven} likes given',
      ),
      _Stat(
        value: '${summary.likesReceived}',
        label: 'received',
        icon: DIcons.heart,
        semanticsValue: '${summary.likesReceived} likes received',
      ),
      if (summary.bookmarkCount > 0)
        _Stat(
          value: '${summary.bookmarkCount}',
          label: _plural(summary.bookmarkCount, 'bookmark', 'bookmarks'),
        ),
      _Stat(
        value: '${summary.topicCount}',
        label: _plural(summary.topicCount, 'topic created', 'topics created'),
      ),
      _Stat(
        value: '${summary.postCount}',
        label: _plural(summary.postCount, 'post created', 'posts created'),
      ),
    ];
    return _Section(
      title: 'Stats',
      child: Wrap(spacing: 12, runSpacing: 12, children: stats),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.icon,
    this.semanticsValue,
  });

  final String value;
  final String label;
  final DIconData? icon;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticsValue ?? '$value $label',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 116),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon case final icon?) ...[
                    DIcon(icon, size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
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

class _SummaryPair extends StatelessWidget {
  const _SummaryPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 700) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 16), second],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        ),
      );
    },
  );
}

class _TopicsSection extends StatelessWidget {
  const _TopicsSection({
    required this.title,
    required this.emptyMessage,
    required this.rows,
  });

  final String title;
  final String emptyMessage;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    child: rows.isEmpty
        ? _EmptyMessage(emptyMessage)
        : Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                rows[index],
              ],
            ],
          ),
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
    final theme = Theme.of(context);
    final metadata = [
      if (createdAt case final createdAt?) relativeTime(createdAt),
      if (likes > 0) '$likes ${_plural(likes, 'like', 'likes')}',
    ];
    final label = [
      postNumber == null
          ? 'Open topic ${topic.title}'
          : 'Open reply in ${topic.title}',
      ...metadata,
    ].join(', ');

    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('user-summary-topic-${topic.id}-${postNumber ?? 0}'),
          onTap: () => ShellScope.read(
            context,
          ).openUserSummaryTopic(topic, postNumber: postNumber),
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (metadata.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          metadata.first,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (metadata.length > 1) ...[
                          const SizedBox(width: 6),
                          DIcon(
                            DIcons.heart,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$likes',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  TopicTitle(
                    topic.title,
                    siteUrl: siteUrl,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinksSection extends StatelessWidget {
  const _LinksSection({required this.siteUrl, required this.links});

  final String siteUrl;
  final List<UserSummaryLink> links;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Top Links',
    child: links.isEmpty
        ? const _EmptyMessage('No links yet.')
        : Column(
            children: [
              for (var index = 0; index < links.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _SummaryLinkRow(siteUrl: siteUrl, link: links[index]),
              ],
            ],
          ),
  );
}

class _SummaryLinkRow extends StatelessWidget {
  const _SummaryLinkRow({required this.siteUrl, required this.link});

  final String siteUrl;
  final UserSummaryLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domain = _linkLabel(link.url);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            link: true,
            label: 'Open external link $domain, ${link.clicks} clicks',
            child: ExcludeSemantics(
              child: InkWell(
                key: ValueKey('user-summary-external-${link.topic.id}'),
                onTap: () => unawaited(openExternalLink(link.url)),
                borderRadius: BorderRadius.circular(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      domain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Semantics(
            link: true,
            label: 'Open post in ${link.topic.title}',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => ShellScope.read(
                  context,
                ).openUserSummaryTopic(link.topic, postNumber: link.postNumber),
                borderRadius: BorderRadius.circular(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TopicTitle(
                      link.topic.title,
                      siteUrl: siteUrl,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
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

class _UsersSection extends StatelessWidget {
  const _UsersSection({
    required this.siteUrl,
    required this.title,
    required this.emptyMessage,
    required this.users,
    required this.icon,
    required this.countLabel,
  });

  final String siteUrl;
  final String title;
  final String emptyMessage;
  final List<UserSummaryUser> users;
  final DIconData icon;
  final String countLabel;

  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    child: users.isEmpty
        ? _EmptyMessage(emptyMessage)
        : Column(
            children: [
              for (var index = 0; index < users.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _SummaryUserRow(
                  siteUrl: siteUrl,
                  user: users[index],
                  icon: icon,
                  countLabel: countLabel,
                ),
              ],
            ],
          ),
  );
}

class _SummaryUserRow extends StatelessWidget {
  const _SummaryUserRow({
    required this.siteUrl,
    required this.user,
    required this.icon,
    required this.countLabel,
  });

  final String siteUrl;
  final UserSummaryUser user;
  final DIconData icon;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return UserCardTarget(
      username: user.username,
      siteUrl: siteUrl,
      semanticsLabel:
          'View profile for @${user.username}, ${user.count} $countLabel',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: 36,
                child: AvatarImage(
                  url: user.avatarUrl,
                  size: 36,
                  fallback: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: Text(
                        user.username.characters.first.toUpperCase(),
                        style: theme.textTheme.labelLarge,
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
    );
  }
}

class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({required this.username, required this.categories});

  final String username;
  final List<UserSummaryCategory> categories;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Top Categories',
    child: Column(
      children: [
        const _CategoryHeader(),
        for (var index = 0; index < categories.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          _CategoryRow(username: username, category: categories[index]),
        ],
      ],
    ),
  );
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Expanded(child: SizedBox()),
          SizedBox(
            width: 72,
            child: Text('Topics', textAlign: TextAlign.center, style: style),
          ),
          SizedBox(
            width: 72,
            child: Text('Replies', textAlign: TextAlign.center, style: style),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.username, required this.category});

  final String username;
  final UserSummaryCategory category;

  void _search(BuildContext context, {required bool topics}) {
    final search = ShellScope.read(context).search;
    search.requestFocus();
    search.setQuery('@$username #${category.slug}${topics ? ' in:first' : ''}');
    search.showTopics();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Open category ${category.name}',
              child: ExcludeSemantics(
                child: InkWell(
                  key: ValueKey('user-summary-category-${category.id}'),
                  onTap: () =>
                      ShellScope.read(context).openCategory(category.category),
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(category.category.colorValue),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _CategoryCount(
            count: category.topicCount,
            label: 'topics by @$username in ${category.name}',
            onTap: () => _search(context, topics: true),
          ),
          _CategoryCount(
            count: category.postCount,
            label: 'replies by @$username in ${category.name}',
            onTap: () => _search(context, topics: false),
          ),
        ],
      ),
    );
  }
}

class _CategoryCount extends StatelessWidget {
  const _CategoryCount({
    required this.count,
    required this.label,
    required this.onTap,
  });

  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox(
        width: 72,
        child: Text('–', textAlign: TextAlign.center),
      );
    }
    return SizedBox(
      width: 72,
      child: Semantics(
        button: true,
        label: 'Search $count $label',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgesSection extends StatelessWidget {
  const _BadgesSection({required this.siteUrl, required this.badges});

  final String siteUrl;
  final List<UserSummaryBadge> badges;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Top Badges',
    child: badges.isEmpty
        ? const _EmptyMessage('No badges yet.')
        : LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final width = wide
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final badge in badges)
                    SizedBox(
                      width: width,
                      child: _BadgeCard(siteUrl: siteUrl, badge: badge),
                    ),
                ],
              );
            },
          ),
  );
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.siteUrl, required this.badge});

  final String siteUrl;
  final UserSummaryBadge badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final namedIcon = badge.icon == null ? null : DIcons.byName[badge.icon];
    final fallback = DIcon(
      namedIcon ?? DIcons.certificate,
      size: 26,
      color: theme.colorScheme.primary,
    );
    return Semantics(
      container: true,
      label: [
        badge.name,
        if (badge.count > 1) 'earned ${badge.count} times',
        ?badge.description,
      ].join(', '),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 36,
                child: switch (badge.imageUrl) {
                  final image? => SiteImage(
                    url: image,
                    siteUrl: siteUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    loadingBuilder: (_) => fallback,
                    errorBuilder: (_, _, _) => fallback,
                  ),
                  null => Center(child: fallback),
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.count > 1
                          ? '${badge.name} ×${badge.count}'
                          : badge.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badge.description case final description?)
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => _Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
            ),
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.shell.panel,
        border: Border.all(color: theme.shell.divider),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _SummaryErrorBanner extends StatelessWidget {
  const _SummaryErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(onRetry()),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _plural(int count, String one, String other) => count == 1 ? one : other;

String _readTime(int seconds) {
  if (seconds >= Duration.secondsPerDay) {
    return '${seconds ~/ Duration.secondsPerDay}d';
  }
  if (seconds >= Duration.secondsPerHour) {
    return '${seconds ~/ Duration.secondsPerHour}h';
  }
  return '${seconds ~/ Duration.secondsPerMinute}m';
}

String _readTimeLong(int seconds) {
  if (seconds >= Duration.secondsPerDay) {
    final value = seconds ~/ Duration.secondsPerDay;
    return '$value ${_plural(value, 'day', 'days')}';
  }
  if (seconds >= Duration.secondsPerHour) {
    final value = seconds ~/ Duration.secondsPerHour;
    return '$value ${_plural(value, 'hour', 'hours')}';
  }
  final value = seconds ~/ Duration.secondsPerMinute;
  return '$value ${_plural(value, 'minute', 'minutes')}';
}

String _linkLabel(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (host.isEmpty) return url;
  final visibleHost = host.startsWith('www.') ? host.substring(4) : host;
  final path = uri!.path == '/' ? '' : uri.path;
  return '$visibleHost$path';
}
