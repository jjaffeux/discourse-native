import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/reviewable.dart';
import '../theme/app_theme.dart';
import '../utils/pagination.dart';
import 'adaptive_dialog_action.dart';
import 'cooked_html.dart';
import 'relative_time.dart';
import 'review_controller.dart';

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

Widget _notice(ReviewNotice notice) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: DAlert(
    variant: notice is ReviewPerformed
        ? DAlertVariant.normal
        : DAlertVariant.destructive,
    description: DAlertDescription(
      child: Text(switch (notice) {
        ReviewPerformed(:final message) => message ?? appL10n.reviewPerformed,
        ReviewConflict() => appL10n.reviewConflict,
        ReviewActionFailed(:final message) => message,
      }),
    ),
  ),
);

Widget _alert(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: DAlert(
    variant: DAlertVariant.destructive,
    description: DAlertDescription(child: Text(text)),
  ),
);

Widget _empty(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 24),
  child: DEmpty(children: [DEmptyDescription(text)]),
);

typedef ReviewCategoryOption = ({int id, String name});

/// The filterable queue. State and every effect belong to the caller.
class ReviewQueuePage extends StatefulWidget {
  const ReviewQueuePage({
    super.key,
    required this.state,
    required this.permitted,
    required this.onRefresh,
    required this.onFilters,
    required this.onLoadMore,
    required this.onOpen,
    this.categories = const [],
  });

  final ReviewState state;
  final bool permitted;
  final Future<void> Function() onRefresh;
  final ValueChanged<ReviewFilters> onFilters;
  final VoidCallback onLoadMore;
  final ValueChanged<Reviewable> onOpen;
  final List<ReviewCategoryOption> categories;

  @override
  State<ReviewQueuePage> createState() => _ReviewQueuePageState();
}

class _ReviewQueuePageState extends State<ReviewQueuePage> {
  late final _username = TextEditingController(
    text: widget.state.filters.username,
  );

  ReviewState get state => widget.state;
  ReviewFilters get filters => state.filters;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  DSelect<T> _select<T>({
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T> onChanged,
  }) => DSelect<T>(
    value: value,
    semanticLabel: label,
    entries: [
      for (final (option, text) in options)
        DSelectItem(value: option, textValue: text, child: Text(text)),
    ],
    onChanged: (selected) {
      if (selected != null && selected != value) onChanged(selected);
    },
  );

  Widget _controls(AppLocalizations l10n) {
    // The site lists its own types once a page has loaded; until then the
    // three every site has are offered.
    final types = {
      ...state.types.isEmpty
          ? const [
              'ReviewableFlaggedPost',
              'ReviewableQueuedPost',
              'ReviewableUser',
            ]
          : state.types,
      ?filters.type,
    };
    return DControlWrap(
      children: [
        _select<ReviewStatusFilter>(
          label: l10n.reviewFilterStatus,
          value: filters.status,
          options: [
            for (final status in ReviewStatusFilter.values)
              (status, _statusFilterLabel(status)),
          ],
          onChanged: (status) =>
              widget.onFilters(filters.copyWith(status: status)),
        ),
        _select<String>(
          label: l10n.reviewFilterType,
          value: filters.type ?? '',
          options: [
            ('', l10n.reviewAllTypes),
            for (final type in types) (type, reviewTypeLabel(type)),
          ],
          onChanged: (type) => widget.onFilters(
            type.isEmpty
                ? filters.copyWith(clearType: true)
                : filters.copyWith(type: type),
          ),
        ),
        _select<ReviewPriorityFilter>(
          label: l10n.reviewFilterPriority,
          value: filters.priority,
          options: [
            for (final priority in ReviewPriorityFilter.values)
              (priority, _priorityLabel(priority)),
          ],
          onChanged: (priority) =>
              widget.onFilters(filters.copyWith(priority: priority)),
        ),
        if (widget.categories.isNotEmpty)
          _select<int>(
            label: l10n.reviewFilterCategory,
            value: filters.categoryId ?? 0,
            options: [
              (0, l10n.reviewAllCategories),
              for (final category in widget.categories)
                (category.id, category.name),
            ],
            onChanged: (id) => widget.onFilters(
              id == 0
                  ? filters.copyWith(clearCategory: true)
                  : filters.copyWith(categoryId: id),
            ),
          ),
        _select<ReviewSortOrder>(
          label: l10n.reviewFilterOrder,
          value: filters.sortOrder,
          options: [
            for (final order in ReviewSortOrder.values)
              (order, _orderLabel(order)),
          ],
          onChanged: (order) =>
              widget.onFilters(filters.copyWith(sortOrder: order)),
        ),
        SizedBox(
          width: 180,
          child: DInput(
            controller: _username,
            semanticLabel: l10n.reviewFilterUsername,
            hintText: l10n.reviewFilterUsername,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) =>
                widget.onFilters(filters.copyWith(username: value.trim())),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failure = state.failure;
    return DPageSurface.headed(
      title: Text(l10n.reviewTitle),
      controls: widget.permitted ? _controls(l10n) : null,
      bodyBuilder: (context, header) => DPullToRefresh(
        onRefresh: widget.permitted && !state.loading ? widget.onRefresh : null,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
          children: [
            header.spacer,
            if (!widget.permitted)
              _empty(l10n.reviewNotPermitted)
            else ...[
              if (state.notice case final notice?) _notice(notice),
              if (failure != null) ...[
                _alert(_failureText(failure, item: false)),
                if (failure != ReviewFailure.forbidden)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DButton(
                      variant: DButtonVariant.outline,
                      label: Text(l10n.tryAgain),
                      onPressed: state.loading ? null : widget.onRefresh,
                    ),
                  ),
              ],
              // The host starts the first read after the first frame, so an
              // unloaded queue with no failure is one that is loading.
              if (!state.loaded && failure == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: DSpinner(semanticLabel: l10n.reviewLoading),
                  ),
                ),
              if (state.loaded && state.items.isEmpty && failure == null)
                _empty(l10n.reviewEmpty),
              for (final item in state.items)
                _ReviewRow(
                  key: ValueKey('review-row-${item.id}'),
                  item: item,
                  onOpen: () => widget.onOpen(item),
                ),
              if (state.hasMore)
                ScrollPageTrigger(
                  enabled: !state.loadingMore && failure == null,
                  onLoad: widget.onLoadMore,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: DButton(
                        variant: DButtonVariant.outline,
                        label: Text(l10n.loadMore),
                        loading: state.loadingMore,
                        onPressed: state.loadingMore ? null : widget.onLoadMore,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({super.key, required this.item, required this.onOpen});

  final Reviewable item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final summary = reviewItemSummary(item);
    final author = item.targetCreatedBy?.username;
    final reasons = {
      for (final score in item.scores)
        if (score.title.isNotEmpty) score.title,
    };
    final details = [
      _itemTypeLabel(item),
      reviewStatusLabel(item.status),
      if (author != null) l10n.reviewWrittenBy(author),
      if (item.createdAt case final created?) relativeTime(created),
    ].join(' · ');
    final excerpt = item.raw?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Semantics(
      container: true,
      button: true,
      label: l10n.reviewItemLabel([summary, details, ...reasons].join(', ')),
      child: ExcludeSemantics(
        child: DItem(
          shape: DItemShape.fullWidth,
          link: true,
          onPressed: onOpen,
          children: [
            DItemContent(
              children: [
                DItemTitle(child: Text(summary)),
                Text(
                  details,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.shell.marker,
                  ),
                ),
                if (excerpt != null && excerpt.isNotEmpty)
                  DItemDescription(child: Text(excerpt)),
                if (reasons.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final reason in reasons)
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text(reason),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One item: what it is about, why it is queued, and what can be done.
class ReviewItemPage extends StatelessWidget {
  const ReviewItemPage({
    super.key,
    required this.state,
    required this.siteUrl,
    required this.onBack,
    required this.onPerform,
    required this.onOpenInBrowser,
    this.onViewInContext,
  });

  final ReviewState state;
  final String siteUrl;
  final VoidCallback onBack;
  final void Function(Reviewable item, ReviewableAction action) onPerform;

  /// Opens this item on the site, where the actions this app cannot carry
  /// out are performed.
  final VoidCallback onOpenInBrowser;
  final ValueChanged<String>? onViewInContext;

  Future<void> _press(
    BuildContext context,
    Reviewable item,
    ReviewableAction action,
  ) async {
    final l10n = context.l10n;
    switch (item.routeFor(action)) {
      case ReviewableActionRoute.browser:
        onOpenInBrowser();
      case ReviewableActionRoute.perform:
        onPerform(item, action);
      case ReviewableActionRoute.confirm ||
          ReviewableActionRoute.confirmDestructive:
        final destructive =
            item.routeFor(action) == ReviewableActionRoute.confirmDestructive;
        final confirmed = await showDiscourseAlertDialog<bool>(
          context: context,
          title: Text(action.label),
          description: Text(
            action.confirmMessage ??
                action.description ??
                l10n.reviewConfirmDestructive,
          ),
          cancelLabel: Text(l10n.cancel),
          actionLabel: Text(action.label),
          cancelResult: false,
          actionResult: true,
          actionVariant: destructive
              ? DButtonVariant.destructive
              : DButtonVariant.primary,
          actionKey: const ValueKey('review-confirm-action'),
        );
        if (confirmed == true) onPerform(item, action);
    }
  }

  Widget _card(BuildContext context, String? title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: DCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                if (title != null)
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _field(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.shell.marker,
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, Reviewable item) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.shell.marker,
    );
    final author = item.targetCreatedBy?.username;
    final heading = item.title ?? item.topicTitle;
    return [
      if (heading != null) Text(heading, style: theme.textTheme.titleMedium),
      Text(
        [
          reviewStatusLabel(item.status),
          if (author != null && item.kind != ReviewableKind.user)
            l10n.reviewWrittenBy(author),
          if (item.createdAt case final created?) relativeTime(created),
        ].join(' · '),
        style: muted,
      ),
      if (item.kind == ReviewableKind.other)
        Text(l10n.reviewUnsupportedType, style: muted),
      if (item.targetDeleted) Text(l10n.reviewContentDeleted, style: muted),
      if (item.kind == ReviewableKind.user) ...[
        if (item.accountUsername ?? author case final username?)
          _field(context, l10n.reviewFilterUsername, '@$username'),
        if (item.accountName case final name?)
          _field(context, l10n.reviewAccountName, name),
        if (item.accountEmail case final email?)
          _field(context, l10n.reviewAccountEmail, email),
        if (item.rejectReason case final reason?)
          _field(context, l10n.reviewRejectReason, reason),
      ],
      if (item.cooked case final cooked?)
        CookedHtml(html: cooked, siteUrl: siteUrl)
      else if (item.raw case final raw?)
        Text(raw),
    ];
  }

  Widget _score(BuildContext context, ReviewableScore score) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = _scoreStatusLabel(score.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        MergeSemantics(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (score.title.isNotEmpty)
                DBadge(
                  variant: DBadgeVariant.secondary,
                  child: Text(score.title),
                ),
              Text(
                [
                  if (score.user case final user?)
                    l10n.reviewFlaggedBy(user.username),
                  if (status.isNotEmpty) status,
                  if (score.createdAt case final created?)
                    relativeTime(created),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.shell.marker,
                ),
              ),
            ],
          ),
        ),
        if (score.reasonHtml case final reason?)
          CookedHtml(html: reason, siteUrl: siteUrl, compactParagraphs: true),
      ],
    );
  }

  Widget _action(
    BuildContext context,
    Reviewable item,
    ReviewableAction action,
  ) {
    final browser = item.routeFor(action) == ReviewableActionRoute.browser;
    final sending = state.performing == action.id;
    return DButton(
      key: ValueKey('review-action-${action.id}'),
      variant: action.isDestructive
          ? DButtonVariant.destructive
          : DButtonVariant.outline,
      label: Text(action.label),
      icon: browser ? const DIcon(DIcons.upRightFromSquare) : null,
      tooltip: action.description,
      semanticLabel: browser
          ? context.l10n.reviewActionInBrowser(action.label)
          : null,
      loading: sending,
      onPressed: state.performing != null
          ? null
          : () => _press(context, item, action),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = state.selected;
    final failure = state.selectedFailure;
    final target = item?.targetUrl;
    return DPageSurface.headed(
      title: Text(item == null ? l10n.reviewTitle : _itemTypeLabel(item)),
      controls: DControlWrap(
        children: [
          DButton(
            variant: DButtonVariant.ghost,
            icon: const DIcon(DIcons.arrowLeft),
            label: Text(l10n.reviewBackToQueue),
            onPressed: onBack,
          ),
          if (target != null && onViewInContext != null)
            DButton(
              variant: DButtonVariant.outline,
              label: Text(l10n.reviewViewInContext),
              onPressed: () => onViewInContext!(target),
            ),
          DButton(
            variant: DButtonVariant.outline,
            icon: const DIcon(DIcons.upRightFromSquare),
            label: Text(l10n.reviewOpenInBrowser),
            onPressed: onOpenInBrowser,
          ),
        ],
      ),
      bodyBuilder: (context, header) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
        children: [
          header.spacer,
          if (state.notice case final notice?) _notice(notice),
          if (failure != null) _alert(_failureText(failure, item: true)),
          if (item == null && failure == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: DSpinner(semanticLabel: l10n.reviewLoading)),
            ),
          if (item != null) ...[
            _card(context, null, _content(context, item)),
            _card(context, l10n.reviewReasons, [
              if (item.scores.isEmpty)
                Text(l10n.reviewNoReasons)
              else
                for (final score in item.scores) _score(context, score),
            ]),
            _card(context, l10n.reviewActions, [
              if (item.bundles.every((bundle) => bundle.actions.isEmpty))
                Text(l10n.reviewNoActions),
              for (final bundle in item.bundles)
                if (bundle.actions.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      if (bundle.label case final label?
                          when bundle.actions.length > 1)
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final action in bundle.actions)
                            _action(context, item, action),
                        ],
                      ),
                    ],
                  ),
            ]),
          ],
        ],
      ),
    );
  }
}
