import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/badge.dart';
import '../models/badge_route.dart';
import '../models/content_route.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'badges_controller.dart';
import 'content_reading_lane.dart';
import 'cooked_html.dart';
import 'directory_skeleton.dart';
import 'open_link.dart';
import 'site_image.dart';

class BadgesPage extends StatelessWidget {
  const BadgesPage({
    super.key,
    required this.siteUrl,
    required this.route,
    required this.state,
    required this.onRefresh,
    required this.onOpenBadge,
    required this.onLoadMore,
    required this.onOpenUrl,
    this.currentUsername,
  });

  final String siteUrl;
  final BadgeRoute route;
  final BadgesState state;
  final String? currentUsername;
  final Future<void> Function() onRefresh;
  final ValueChanged<DiscourseBadge> onOpenBadge;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) => ContentReadingLane(
    basePadding: route.isDirectory
        ? const EdgeInsets.symmetric(vertical: 16)
        : const EdgeInsets.all(16),
    builder: (context, lane) => CustomScrollView(
      key: PageStorageKey('badges-$siteUrl-${route.id}'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: lane.padding,
          sliver: SliverMainAxisGroup(
            slivers: [
              if (state.error != null)
                SliverToBoxAdapter(
                  child: _BadgeError(message: state.error!, onRetry: onRefresh),
                ),
              if (state.loading && state.catalog == null && state.badge == null)
                const SliverDirectorySkeleton(
                  key: ValueKey('badges-loading'),
                  kind: DirectorySkeletonKind.badges,
                )
              else if (route.isDirectory && state.catalog != null)
                _BadgeDirectory(
                  key: ValueKey((siteUrl, currentUsername)),
                  catalog: state.catalog!,
                  siteUrl: siteUrl,
                  onOpenBadge: onOpenBadge,
                )
              else if (state.badge != null)
                ..._detail(context, state.badge!),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _detail(BuildContext context, DiscourseBadge badge) {
    final theme = Theme.of(context);
    final ownAwardsUrl = currentUsername == null
        ? null
        : '$siteUrl${BadgeRoute.detail(badge.id, slug: badge.slug, username: currentUsername).path}';
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinkTarget(
              url: '$siteUrl/badges',
              siteUrl: siteUrl,
              child: DButton(
                label: Text(context.l10n.allBadges),
                icon: const DIcon(DIcons.arrowLeft),
                variant: DButtonVariant.link,
                onPressed: () => onOpenUrl('$siteUrl/badges'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BadgeSymbol(badge: badge, siteUrl: siteUrl, size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          badge.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _BadgeTierLabel(tier: badge.tier),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CookedHtml(
              html: badge.longDescription.isEmpty
                  ? badge.description
                  : badge.longDescription,
              siteUrl: siteUrl,
              compactParagraphs: true,
            ),
            const SizedBox(height: 20),
            if (badge.hasBadge == true) ...[
              Row(
                children: [
                  const _EarnedBadge(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l10n.youEarnedThisBadge,
                      style: TextStyle(color: theme.discourse.success),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(_awarded(badge.grantCount)),
                if (badge.multipleGrant)
                  Text(context.l10n.canBeEarnedMultipleTimes),
                if (badge.allowTitle) Text(context.l10n.canBeUsedAsATitle),
              ],
            ),
            const SizedBox(height: 24),
            DSeparator(color: theme.shell.divider),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                route.username == null
                    ? context.l10n.recentlyAwarded
                    : context.l10n.awardedTo((route.username).toString()),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            if (route.username != null)
              LinkTarget(
                url: '$siteUrl${badge.route.path}',
                siteUrl: siteUrl,
                child: DButton(
                  label: Text(context.l10n.showAllRecipients),
                  variant: DButtonVariant.link,
                  onPressed: () => onOpenUrl('$siteUrl${badge.route.path}'),
                ),
              )
            else if (badge.hasBadge == true && ownAwardsUrl != null)
              LinkTarget(
                url: ownAwardsUrl,
                siteUrl: siteUrl,
                child: DButton(
                  label: Text(context.l10n.showYourAwards),
                  variant: DButtonVariant.link,
                  onPressed: () => onOpenUrl(ownAwardsUrl),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      SliverList.builder(
        itemCount: state.grants.length,
        itemBuilder: (context, index) => _BadgeRecipient(
          key: ValueKey('badge-grant-${state.grants[index].id}'),
          grant: state.grants[index],
          siteUrl: siteUrl,
          onOpenUrl: onOpenUrl,
        ),
      ),
      if (state.recipientsError != null)
        SliverToBoxAdapter(
          child: _BadgeError(
            message: state.recipientsError!,
            onRetry: onLoadMore,
          ),
        )
      else if (!state.loading && !state.loadingMore && state.grants.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(context.l10n.noAwardsToDisplay),
          ),
        ),
      if (state.loadingMore)
        const SliverToBoxAdapter(child: SizedBox.shrink())
      else if (state.hasMore && state.recipientsError == null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: DButton(
                key: const ValueKey('badge-load-more'),
                label: Text(context.l10n.loadMore),
                onPressed: onLoadMore,
              ),
            ),
          ),
        ),
    ];
  }
}

enum _BadgeFilter {
  all(),
  earned(),
  unearned(),
  bronze(),
  silver(),
  gold();

  const _BadgeFilter();
  String get label => switch (this) {
    all => appL10n.allBadges,
    earned => appL10n.earned,
    unearned => appL10n.notEarned,
    bronze => appL10n.bronze,
    silver => appL10n.silver,
    gold => appL10n.gold,
  };

  bool get personal => this == earned || this == unearned;

  bool includes(DiscourseBadge badge) => switch (this) {
    all => true,
    earned => badge.hasBadge == true,
    unearned => badge.hasBadge == false,
    bronze => badge.tier == BadgeTier.bronze,
    silver => badge.tier == BadgeTier.silver,
    gold => badge.tier == BadgeTier.gold,
  };
}

class _BadgeDirectory extends StatefulWidget {
  const _BadgeDirectory({
    super.key,
    required this.catalog,
    required this.siteUrl,
    required this.onOpenBadge,
  });

  final BadgeCatalog catalog;
  final String siteUrl;
  final ValueChanged<DiscourseBadge> onOpenBadge;

  @override
  State<_BadgeDirectory> createState() => _BadgeDirectoryState();
}

class _BadgeDirectoryState extends State<_BadgeDirectory> {
  _BadgeFilter _filter = _BadgeFilter.all;

  @override
  void didUpdateWidget(_BadgeDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.catalog.hasPersonalState && _filter.personal) {
      _filter = _BadgeFilter.all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = widget.catalog;
    final groups = [
      for (final group in catalog.groups)
        (
          name: group.name,
          badges: group.badges.where(_filter.includes).toList(),
        ),
    ].where((group) => group.badges.isNotEmpty).toList();
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    context.l10n.badges,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale =
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(DiscourseTypography.sm) /
                        DiscourseTypography.sm;
                    final stacked = constraints.maxWidth / scale < 300;
                    final filter = DSelect<_BadgeFilter>.controlled(
                      size: DControlSize.filter,
                      key: const ValueKey('badge-filter'),
                      value: _filter,
                      semanticLabel: context.l10n.filterBadges,
                      width: 128,
                      isExpanded: stacked,
                      entries: [
                        for (final filter in _BadgeFilter.values)
                          if (!filter.personal || catalog.hasPersonalState)
                            DSelectItem(
                              value: filter,
                              textValue: filter.label,
                              child: Text(filter.label),
                            ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _filter = value);
                      },
                    );
                    final summary = Text(
                      context.l10n.messageBadgespage(
                        catalog.total,
                        (catalog.hasPersonalState).toString(),
                        (_number(catalog.total)).toString(),
                        ((catalog.hasPersonalState)
                                ? (_number(catalog.earned))
                                : '')
                            .toString(),
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.shell.marker,
                      ),
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [filter, const SizedBox(height: 8), summary],
                      );
                    }
                    return Row(
                      children: [
                        filter,
                        const SizedBox(width: 16),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: summary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                DSeparator(color: theme.shell.divider),
              ],
            ),
          ),
        ),
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SingleChildScrollView(
                child: DEmpty(
                  children: [
                    DEmptyHeader(
                      children: [
                        DEmptyTitle(
                          catalog.total == 0
                              ? context.l10n.noBadgesToDisplay
                              : context.l10n.noBadgesMatchThisFilter,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Semantics(
                header: true,
                child: Text(
                  group.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: group.badges.length,
            separatorBuilder: (context, index) =>
                DSeparator(color: theme.shell.divider),
            itemBuilder: (context, index) {
              final badge = group.badges[index];
              return LinkTarget.content(
                content: ContentRoute.badges(badge.route, title: badge.name),
                siteUrl: widget.siteUrl,
                child: BadgeRow(
                  key: ValueKey('badge-row-${badge.id}'),
                  badge: badge,
                  siteUrl: widget.siteUrl,
                  onTap: () => widget.onOpenBadge(badge),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class BadgeRow extends StatelessWidget {
  const BadgeRow({
    super.key,
    required this.badge,
    required this.siteUrl,
    required this.onTap,
  });

  final DiscourseBadge badge;
  final String siteUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DItem(
      shape: DItemShape.fullWidth,
      link: true,
      onPressed: onTap,
      footer: badge.description.isEmpty
          ? null
          : DItemFooter(
              child: CookedHtml(
                html: badge.description,
                siteUrl: siteUrl,
                compactParagraphs: true,
                textStyle: theme.textTheme.bodyLarge?.copyWith(
                  height: theme.textTheme.bodyMedium?.height,
                  color: theme.shell.marker,
                ),
              ),
            ),
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: DAvatar(
            size: DAvatarSize.lg,
            decorative: true,
            fallback: DAvatarFallback(
              backgroundColor: _tierColor(
                context,
                badge.tier,
              ).withValues(alpha: .22),
              child: BadgeSymbol(badge: badge, siteUrl: siteUrl, size: 20),
            ),
          ),
        ),
        DItemContent(
          spacing: 0,
          children: [
            Text(
              badge.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                _BadgeTierLabel(tier: badge.tier),
                Text(
                  '· ${_awarded(badge.grantCount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.shell.marker,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (badge.hasBadge == true) const _EarnedBadge(),
      ],
    );
  }
}

class BadgeSymbol extends StatelessWidget {
  const BadgeSymbol({
    super.key,
    required this.badge,
    required this.siteUrl,
    required this.size,
  });
  final DiscourseBadge badge;
  final String siteUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = DIcon(
      pluginIconNamed(context, badge.icon) ?? DIcons.certificate,
      size: size,
      color: _tierColor(context, badge.tier),
    );
    return ExcludeSemantics(
      child: badge.imageUrl == null
          ? fallback
          : SiteImage(
              url: badge.imageUrl!,
              siteUrl: siteUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }
}

class _EarnedBadge extends StatelessWidget {
  const _EarnedBadge();

  @override
  Widget build(BuildContext context) => DTooltip(
    message: context.l10n.earned,
    excludeFromSemantics: true,
    child: Semantics(
      label: context.l10n.earned,
      child: ExcludeSemantics(
        child: DIcon(
          DIcons.circleCheck,
          size: 18,
          color: Theme.of(context).discourse.success,
        ),
      ),
    ),
  );
}

class _BadgeTierLabel extends StatelessWidget {
  const _BadgeTierLabel({required this.tier});
  final BadgeTier tier;

  @override
  Widget build(BuildContext context) => Text(
    tier.label,
    style: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: _tierColor(context, tier)),
  );
}

class _BadgeError extends StatelessWidget {
  const _BadgeError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: DAlert(
      variant: DAlertVariant.destructive,
      icon: const DIcon(DIcons.triangleExclamation),
      description: DAlertDescription(child: Text(message)),
      action: DAlertAction(
        child: DButton(
          label: Text(context.l10n.retry),
          onPressed: onRetry,
          variant: DButtonVariant.link,
        ),
      ),
    ),
  );
}

class _BadgeRecipient extends StatelessWidget {
  const _BadgeRecipient({
    super.key,
    required this.grant,
    required this.siteUrl,
    required this.onOpenUrl,
  });
  final BadgeGrant grant;
  final String siteUrl;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Theme.of(context).shell.divider),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DAvatar.frame(
          child: AvatarImage(
            url: grant.avatarUrl,
            size: 36,
            fallback: const DAvatarFallback(
              child: DIcon(DIcons.user, size: 24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DButton(
                    label: Text(grant.username),
                    variant: DButtonVariant.link,
                    onPressed: () => onOpenUrl(
                      '$siteUrl/u/${Uri.encodeComponent(grant.username)}',
                    ),
                  ),
                  if (grant.grantedAt != null)
                    Text(
                      DateFormat.yMMMd().format(grant.grantedAt!.toLocal()),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).shell.marker,
                      ),
                    ),
                ],
              ),
              if (grant.postPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinkTarget(
                    url: '$siteUrl${grant.postPath}',
                    title: grant.topicTitle,
                    siteUrl: siteUrl,
                    child: DButton(
                      label: Text(
                        grant.topicTitle ?? context.l10n.viewAwardedPost,
                      ),
                      variant: DButtonVariant.link,
                      onPressed: () => onOpenUrl('$siteUrl${grant.postPath}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

Color _tierColor(BuildContext context, BadgeTier tier) =>
    switch ((Theme.of(context).brightness, tier)) {
      (Brightness.dark, BadgeTier.bronze) => const Color(0xffedc48d),
      (Brightness.dark, BadgeTier.silver) => const Color(0xffc0c0c0),
      (Brightness.dark, BadgeTier.gold) => const Color(0xffe7c300),
      (Brightness.light, BadgeTier.bronze) => const Color(0xffa9601f),
      (Brightness.light, BadgeTier.silver) => const Color(0xff68727e),
      (Brightness.light, BadgeTier.gold) => const Color(0xff8c7400),
    };

String _number(int value) => NumberFormat.decimalPattern().format(value);
String _awarded(int count) => appL10n.awarded((_number(count)).toString());
