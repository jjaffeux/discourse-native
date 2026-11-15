import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/json.dart';
import '../models/reviewable.dart';
import '../theme/discourse_typography.dart';
import '../utils/pagination.dart';
import 'account_activity_paging_skeleton.dart';
import 'adaptive_dialog_action.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'relative_time.dart';
import 'review_controller.dart';
import 'skeleton_fill.dart';

part 'review_filter_menu.dart';
part 'review_item_page.dart';

/// The site's name for a reviewable class. Classes this app has no wording
/// for, which any plugin can add, are read out of the class name itself.
String reviewTypeLabel(String type, {bool newTopic = false}) => switch (type) {
  'ReviewableFlaggedPost' => appL10n.reviewTypeFlaggedPost,
  'ReviewableQueuedPost' =>
    newTopic ? appL10n.reviewTypeQueuedTopic : appL10n.reviewTypeQueuedPost,
  'ReviewableUser' => appL10n.reviewTypeUser,
  'ReviewablePost' => appL10n.reviewTypePost,
  'ReviewableChatMessage' ||
  'Chat::ReviewableMessage' => appL10n.reviewTypeChatMessage,
  _ => _classWords(type),
};

String _classWords(String type) {
  final name = type.split('::').last.replaceFirst(RegExp('^Reviewable'), '');
  final words = name
      .replaceAllMapped(RegExp('(?<=[a-z0-9])(?=[A-Z])'), (match) => ' ')
      .trim();
  return words.isEmpty ? appL10n.reviewTitle : words;
}

String reviewStatusLabel(ReviewableStatus status) => switch (status) {
  ReviewableStatus.pending => appL10n.reviewStatusPending,
  ReviewableStatus.approved => appL10n.reviewStatusApproved,
  ReviewableStatus.rejected => appL10n.reviewStatusRejected,
  ReviewableStatus.ignored => appL10n.reviewStatusIgnored,
  ReviewableStatus.deleted => appL10n.reviewStatusDeleted,
  ReviewableStatus.unknown => appL10n.reviewStatusHandled,
};

String _statusFilterLabel(ReviewStatusFilter status) => switch (status) {
  ReviewStatusFilter.pending => appL10n.reviewStatusPending,
  ReviewStatusFilter.reviewed => appL10n.reviewStatusReviewed,
  ReviewStatusFilter.approved => appL10n.reviewStatusApproved,
  ReviewStatusFilter.rejected => appL10n.reviewStatusRejected,
  ReviewStatusFilter.ignored => appL10n.reviewStatusIgnored,
  ReviewStatusFilter.deleted => appL10n.reviewStatusDeleted,
  ReviewStatusFilter.all => appL10n.reviewStatusAll,
};

String _priorityLabel(ReviewPriorityFilter priority) => switch (priority) {
  ReviewPriorityFilter.any => appL10n.reviewPriorityAny,
  ReviewPriorityFilter.low => appL10n.reviewPriorityLow,
  ReviewPriorityFilter.medium => appL10n.reviewPriorityMedium,
  ReviewPriorityFilter.high => appL10n.reviewPriorityHigh,
};

String _orderLabel(ReviewSortOrder order) => switch (order) {
  ReviewSortOrder.score => appL10n.reviewOrderScore,
  ReviewSortOrder.scoreAscending => appL10n.reviewOrderScoreAscending,
  ReviewSortOrder.newest => appL10n.reviewOrderNewest,
  ReviewSortOrder.oldest => appL10n.reviewOrderOldest,
};

String _scoreStatusLabel(ReviewableScoreStatus status) => switch (status) {
  ReviewableScoreStatus.pending => appL10n.reviewStatusPending,
  ReviewableScoreStatus.agreed => appL10n.reviewScoreAgreed,
  ReviewableScoreStatus.disagreed => appL10n.reviewScoreDisagreed,
  ReviewableScoreStatus.ignored => appL10n.reviewStatusIgnored,
  ReviewableScoreStatus.unknown => '',
};

String _itemTypeLabel(Reviewable item) => reviewTypeLabel(
  item.type,
  newTopic: item.kind == ReviewableKind.queuedPost && item.title != null,
);

/// What a row is about, in one line.
String reviewItemSummary(Reviewable item) =>
    item.title ??
    item.topicTitle ??
    switch (item.accountUsername ?? item.targetCreatedBy?.username) {
      final username? => '@$username',
      null => _itemTypeLabel(item),
    };

String _failureText(ReviewFailure failure, {required bool item}) =>
    switch (failure) {
      ReviewFailure.forbidden => appL10n.reviewNotPermitted,
      ReviewFailure.missing => appL10n.reviewItemMissing,
      ReviewFailure.unavailable =>
        item ? appL10n.reviewItemLoadError : appL10n.reviewLoadError,
    };

DIconData _typeIcon(Reviewable item) => switch (item.kind) {
  ReviewableKind.flaggedPost => DIcons.flag,
  ReviewableKind.queuedPost => DIcons.inbox,
  ReviewableKind.user => DIcons.userPlus,
  _ => item.type.contains('Chat') ? DIcons.comment : DIcons.fileLines,
};

TextStyle _metaStyle(BuildContext context) => TextStyle(
  fontSize: DiscourseTypography.preview,
  height: DiscourseTypography.lineHeightSmall,
  color: DTokens.of(context).mutedForeground,
);

DBadgeVariant _statusVariant(ReviewableStatus status) => switch (status) {
  ReviewableStatus.rejected ||
  ReviewableStatus.deleted => DBadgeVariant.destructive,
  ReviewableStatus.approved => DBadgeVariant.primary,
  _ => DBadgeVariant.outline,
};

/// Each distinct reason on an item, with how many times it was raised.
List<String> _reasonLabels(Reviewable item) {
  final counts = <String, int>{};
  for (final score in item.scores) {
    if (score.title.isEmpty) continue;
    counts[score.title] = (counts[score.title] ?? 0) + 1;
  }
  return [
    for (final MapEntry(key: reason, value: count) in counts.entries)
      count > 1 ? appL10n.reviewReasonCount(reason, count) : reason,
  ];
}

class _ReviewAvatar extends StatelessWidget {
  const _ReviewAvatar({
    required this.person,
    required this.siteUrl,
    required this.size,
    this.username,
  });

  final ReviewablePerson? person;
  final String siteUrl;
  final double size;

  /// The name to draw an initial from when the site sent no person.
  final String? username;

  @override
  Widget build(BuildContext context) {
    final name = person?.username ?? username ?? '';
    final fallback = DAvatarFallback(
      child: name.isEmpty
          ? DIcon(DIcons.user, size: size * .45)
          : Text(name.characters.first.toUpperCase()),
    );
    return DAvatar(
      dimension: size,
      border: false,
      decorative: true,
      fallback: fallback,
      child: AvatarImage(
        url: resolveAvatarUrl(person?.avatarTemplate, siteUrl),
        size: size,
        fallback: fallback,
      ),
    );
  }
}

/// A whole-page message: nothing to show, nothing allowed, or nothing loaded.
class _ReviewStatePane extends StatelessWidget {
  const _ReviewStatePane({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Center(
            child: DEmpty(
              children: [
                DEmptyHeader(
                  children: [
                    DEmptyMedia(
                      variant: DEmptyMediaVariant.icon,
                      child: DIcon(icon),
                    ),
                    DEmptyTitle(title),
                    if (body case final body?) DEmptyDescription(body),
                  ],
                ),
                if (actionLabel case final label?)
                  DEmptyContent(
                    children: [
                      DButton(
                        label: Text(label),
                        variant: DButtonVariant.outline,
                        onPressed: onAction,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _retryAlert(String text, VoidCallback? onRetry) => DAlert(
  variant: DAlertVariant.destructive,
  icon: const DIcon(DIcons.triangleExclamation),
  description: DAlertDescription(child: Text(text)),
  action: onRetry == null
      ? null
      : DAlertAction(
          child: DButton(
            label: Text(appL10n.tryAgain),
            variant: DButtonVariant.link,
            onPressed: onRetry,
          ),
        ),
);

typedef ReviewCategoryOption = ({int id, String name});

/// The filterable queue. State and every effect belong to the caller.
class ReviewQueuePage extends StatelessWidget {
  const ReviewQueuePage({
    super.key,
    required this.state,
    required this.permitted,
    required this.siteUrl,
    required this.onRefresh,
    required this.onFilters,
    required this.onLoadMore,
    required this.onOpen,
    this.categories = const [],
  });

  final ReviewState state;
  final bool permitted;
  final String siteUrl;
  final Future<void> Function() onRefresh;
  final ValueChanged<ReviewFilters> onFilters;
  final VoidCallback onLoadMore;
  final ValueChanged<Reviewable> onOpen;
  final List<ReviewCategoryOption> categories;

  ReviewFilters get filters => state.filters;

  Widget _controls(AppLocalizations l10n) => DReferenceTextScale(
    child: DControlWrap(
      children: [
        DSelect<ReviewStatusFilter>.controlled(
          size: DControlSize.filter,
          semanticLabel: l10n.reviewFilterStatus,
          value: filters.status,
          entries: [
            for (final status in ReviewStatusFilter.values)
              DSelectOption(
                value: status,
                label: _statusFilterLabel(status),
                child: Text(_statusFilterLabel(status)),
              ),
          ],
          onChanged: (status) {
            if (status != null && status != filters.status) {
              onFilters(filters.copyWith(status: status));
            }
          },
        ),
        _ReviewFilterMenu(
          filters: filters,
          types: state.types,
          categories: categories,
          onFilters: onFilters,
        ),
      ],
    ),
  );

  Widget _state(AppLocalizations l10n) {
    final failure = state.failure;
    if (failure != null) {
      return _ReviewStatePane(
        icon: failure == ReviewFailure.forbidden
            ? DIcons.lock
            : DIcons.triangleExclamation,
        title: _failureText(failure, item: false),
        actionLabel: failure == ReviewFailure.forbidden ? null : l10n.tryAgain,
        onAction: state.loading ? null : onRefresh,
      );
    }
    final narrowed = filters.narrowing > 0;
    return _ReviewStatePane(
      icon: DIcons.circleCheck,
      title: l10n.reviewEmptyTitle,
      body: narrowed ? l10n.reviewEmptyFiltered : l10n.reviewEmpty,
      actionLabel: narrowed ? l10n.reviewClearFilters : null,
      onAction: () => onFilters(filters.cleared),
    );
  }

  Widget _list(BuildContext context, DPageHeaderGeometry header) {
    final l10n = context.l10n;
    final failure = state.failure;
    final items = state.items;
    return DPageReadingLane(
      builder: (context, lane) => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header.spacer),
          SliverPadding(
            padding: EdgeInsets.only(
              left: lane.leftInset + DSpacing.lg,
              right: lane.rightInset + DSpacing.lg,
              bottom: DSpacing.xl + DScrollChrome.bottomInsetOf(context),
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                if (failure != null && !state.hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: DSpacing.sm),
                      child: _retryAlert(
                        _failureText(failure, item: false),
                        state.loading ? null : onRefresh,
                      ),
                    ),
                  ),
                SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const DSeparator(space: 1),
                  itemBuilder: (context, index) => _ReviewRow(
                    key: ValueKey('review-row-${items[index].id}'),
                    item: items[index],
                    siteUrl: siteUrl,
                    showStatus: filters.status != ReviewStatusFilter.pending,
                    onOpen: () => onOpen(items[index]),
                  ),
                ),
                if (state.hasMore)
                  SliverToBoxAdapter(
                    child: failure != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: DSpacing.sm),
                            child: _retryAlert(
                              _failureText(failure, item: false),
                              onLoadMore,
                            ),
                          )
                        : state.loadingMore
                        ? AccountActivityPagingSkeleton(
                            semanticsLabel: l10n.reviewLoadingMore,
                          )
                        : ScrollPageTrigger(
                            enabled: true,
                            onLoad: onLoadMore,
                            child: const SizedBox(height: 1),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!permitted) {
      return DPageSurface.headed(
        title: Text(l10n.reviewTitle),
        child: _ReviewStatePane(
          icon: DIcons.lock,
          title: l10n.reviewNotPermittedTitle,
          body: l10n.reviewNotPermitted,
        ),
      );
    }
    // The host starts the first read after the first frame, so an unloaded
    // queue with no failure is one that is loading.
    final loading = !state.loaded && state.failure == null;
    if (loading) {
      return DPageSurface.headed(
        title: Text(l10n.reviewTitle),
        controls: _controls(l10n),
        child: const _ReviewQueueSkeleton(),
      );
    }
    if (state.items.isEmpty) {
      return DPageSurface.headed(
        title: Text(l10n.reviewTitle),
        controls: _controls(l10n),
        child: DPullToRefresh(
          onRefresh: state.loading ? null : onRefresh,
          child: _state(l10n),
        ),
      );
    }
    return DScrollChromePagination(
      hasMore: state.hasMore,
      loading: state.loadingMore,
      child: DPageSurface.headed(
        title: Text(l10n.reviewTitle),
        controls: _controls(l10n),
        bodyBuilder: (context, header) => DPullToRefresh(
          onRefresh: state.loading ? null : onRefresh,
          child: _list(context, header),
        ),
      ),
    );
  }
}

class _ReviewQueueSkeleton extends StatelessWidget {
  const _ReviewQueueSkeleton();

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    expand: true,
    semanticsLabel: context.l10n.reviewLoading,
    color: skeletonFill(context),
    child: DPageReadingLane(
      basePadding: const EdgeInsets.symmetric(horizontal: DSpacing.lg),
      builder: (context, lane) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: lane.padding,
        itemCount: 6,
        separatorBuilder: (_, _) => const DSeparator(space: 1),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: DSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.md,
            children: [
              const DSkeleton.circle(diameter: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.sm,
                  children: [
                    const DSkeleton(width: 120, height: 8),
                    FractionallySizedBox(
                      widthFactor: index.isEven ? .5 : .68,
                      child: const DSkeleton(height: 12),
                    ),
                    FractionallySizedBox(
                      widthFactor: index.isEven ? .82 : .6,
                      child: const DSkeleton(height: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    super.key,
    required this.item,
    required this.siteUrl,
    required this.showStatus,
    required this.onOpen,
  });

  final Reviewable item;
  final String siteUrl;

  /// A pending queue is all one status, so naming it on every row is noise.
  final bool showStatus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final created = item.createdAt;
    return created == null
        ? _row(context, null)
        : RelativeTimeBuilder(when: created, builder: _row);
  }

  Widget _row(BuildContext context, String? age) {
    final l10n = context.l10n;
    final tokens = DTokens.of(context);
    final summary = reviewItemSummary(item);
    final author = item.accountUsername ?? item.targetCreatedBy?.username;
    final type = _itemTypeLabel(item);
    final reasons = _reasonLabels(item);
    final excerpt = item.raw?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final named = author != null && summary != '@$author';
    final meta = _metaStyle(context);
    return DItem(
      shape: DItemShape.fullWidth,
      gap: DSpacing.md,
      padding: const EdgeInsets.symmetric(
        horizontal: DSpacing.xs,
        vertical: DSpacing.md,
      ),
      onPressed: onOpen,
      semanticLabel: l10n.reviewItemLabel(
        [
          summary,
          type,
          if (showStatus) reviewStatusLabel(item.status),
          if (named) l10n.reviewWrittenBy(author),
          ?age,
          ...reasons,
        ].join(', '),
      ),
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: _ReviewAvatar(
            person: item.targetCreatedBy,
            username: author,
            siteUrl: siteUrl,
            size: DAvatarSize.lg.dimension,
          ),
        ),
        DItemContent(
          spacing: 3,
          children: [
            ExcludeSemantics(
              child: Row(
                spacing: DSpacing.controlGap,
                children: [
                  DIcon(
                    _typeIcon(item),
                    size: 11,
                    color: tokens.mutedForeground,
                  ),
                  Expanded(
                    child: Text(
                      named ? '$type · $author' : type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta.copyWith(
                        fontSize: DiscourseTypography.metadata,
                      ),
                    ),
                  ),
                  if (age != null)
                    Text(
                      age,
                      style: meta.copyWith(
                        fontSize: DiscourseTypography.metadata,
                      ),
                    ),
                ],
              ),
            ),
            DItemTitle(
              maxLines: 2,
              child: ExcludeSemantics(
                child: Text(
                  summary,
                  style: const TextStyle(
                    fontSize: DiscourseTypography.rowTitle,
                    height: DiscourseTypography.lineHeightRowTitle,
                  ),
                ),
              ),
            ),
            if (excerpt != null && excerpt.isNotEmpty)
              DItemDescription(
                child: ExcludeSemantics(
                  child: Text(
                    excerpt,
                    style: meta.copyWith(
                      height: DiscourseTypography.lineHeightPreview,
                    ),
                  ),
                ),
              ),
            if (showStatus || reasons.isNotEmpty)
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: DSpacing.xs),
                  child: Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: DSpacing.xs,
                    children: [
                      if (showStatus)
                        DBadge(
                          variant: _statusVariant(item.status),
                          child: Text(reviewStatusLabel(item.status)),
                        ),
                      for (final reason in reasons)
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text(reason),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
