import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/draft_feed.dart';
import '../models/topic.dart';
import '../models/user_draft.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'adaptive_dialog_action.dart';
import 'external_link.dart';
import 'loading_skeleton.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

class DraftListView extends StatefulWidget {
  const DraftListView({super.key, required this.siteUrl});

  static const double compactRowMinimumHeight = 72;
  static const double wideRowMinimumHeight = 84;

  final String siteUrl;

  @override
  State<DraftListView> createState() => _DraftListViewState();
}

class _DraftListViewState extends State<DraftListView> {
  (ShellController, String)? _loadedIdentity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(DraftListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _request();
  }

  DiscourseInstance? _instance(ShellController controller) => controller
      .instances
      .where((instance) => instance.url == widget.siteUrl)
      .firstOrNull;

  void _request() {
    final controller = ShellScope.read(context);
    final identity = (controller, widget.siteUrl);
    if (_loadedIdentity == identity) return;
    final instance = _instance(controller);
    if (instance == null) return;
    _loadedIdentity = identity;
    unawaited(controller.draftList.load(instance));
  }

  Future<void> _refresh() async {
    final controller = ShellScope.read(context);
    final instance = _instance(controller);
    if (instance != null) {
      await controller.draftList.load(instance, refresh: true);
    }
  }

  Future<void> _remove(UserDraft draft) async {
    final confirmed = await showDiscourseDialog<bool>(
      context: context,
      builder: (context) => DiscourseAlertDialog(
        title: const Text('Remove draft?'),
        content: Text(
          '“${draft.displayTitle}” will be permanently removed from this '
          'account.',
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            kind: AdaptiveDialogActionKind.destructive,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = ShellScope.read(context);
    final instance = _instance(controller);
    if (instance != null) await controller.draftList.delete(instance, draft);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ListenableBuilder(
      listenable: controller.draftList,
      builder: (context, _) {
        final instance = _instance(controller);
        if (instance?.isConnected != true) {
          return const _DraftState(
            icon: DIcons.pencil,
            title: 'Connect this account to see its drafts',
          );
        }

        final feed = controller.draftList.feedFor(widget.siteUrl);
        if (!feed.loaded && feed.drafts.isEmpty) {
          return const _DraftListLoadingSkeleton(
            key: ValueKey('draft-list-loading-skeleton'),
          );
        }
        if (feed.isEmpty) {
          return const _DraftState(
            icon: DIcons.pencil,
            title: 'No drafts yet',
            body: 'Replies and topics you start writing will appear here.',
          );
        }
        if (feed.error != null && feed.drafts.isEmpty) {
          return _DraftState(
            icon: DIcons.triangleExclamation,
            title: feed.error!,
            actionLabel: 'Try again',
            onAction: _refresh,
          );
        }

        return _Drafts(
          siteUrl: widget.siteUrl,
          feed: feed,
          controller: controller,
          onRefresh: _refresh,
          onRemove: _remove,
          instance: instance!,
        );
      },
    );
  }
}

class _DraftListLoadingSkeleton extends StatelessWidget {
  const _DraftListLoadingSkeleton({super.key});

  static const _outerVerticalPadding = 36.0;
  static const _compactRowHeight = 101.0;
  static const _wideRowHeight = 113.0;
  static const _patternLength = 3;

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      semanticsLabel: 'Loading drafts',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth - 32 < 520;
          final rowHeight = compact ? _compactRowHeight : _wideRowHeight;
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight - _outerVerticalPadding
              : double.infinity;
          final visibleRowCount = constraints.hasBoundedHeight
              ? (availableHeight / rowHeight).ceil()
              : _patternLength;
          final rowCount = visibleRowCount < 1 ? 1 : visibleRowCount;

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        key: const ValueKey(
                          'draft-list-loading-skeleton-content',
                        ),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var index = 0; index < rowCount; index++) ...[
                            if (index > 0) const Divider(height: 1),
                            _rowAt(index),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rowAt(int index) => switch (index % _patternLength) {
    0 => const _DraftSkeletonRow(titleWidth: 0.42, excerptWidths: [0.88, 0.62]),
    1 => const _DraftSkeletonRow(titleWidth: 0.58, excerptWidths: [0.72, 0.46]),
    _ => const Opacity(
      opacity: 0.72,
      child: _DraftSkeletonRow(titleWidth: 0.34, excerptWidths: [0.82, 0.54]),
    ),
  };
}

class _DraftSkeletonRow extends StatelessWidget {
  const _DraftSkeletonRow({
    required this.titleWidth,
    required this.excerptWidths,
  });

  final double titleWidth;
  final List<double> excerptWidths;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final row = Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 16,
            compact ? 14 : 20,
            compact ? 8 : 12,
            compact ? 14 : 20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DraftSkeletonLine(widthFactor: titleWidth, height: 11),
                    const SizedBox(height: 8),
                    const LoadingSkeletonBlock(width: 112, height: 8),
                    const SizedBox(height: 18),
                    for (
                      var index = 0;
                      index < excerptWidths.length;
                      index++
                    ) ...[
                      _DraftSkeletonLine(
                        widthFactor: excerptWidths[index],
                        height: 10,
                      ),
                      if (index < excerptWidths.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 16),
              const LoadingSkeletonBlock(
                width: 44,
                height: 44,
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
              SizedBox(width: compact ? 6 : 10),
              const LoadingSkeletonBlock(
                width: 44,
                height: 44,
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
            ],
          ),
        );

        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: compact
                ? DraftListView.compactRowMinimumHeight
                : DraftListView.wideRowMinimumHeight,
          ),
          child: row,
        );
      },
    );
  }
}

class _DraftSkeletonLine extends StatelessWidget {
  const _DraftSkeletonLine({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FractionallySizedBox(
      widthFactor: widthFactor,
      child: LoadingSkeletonBlock(height: height),
    ),
  );
}

class _Drafts extends StatelessWidget {
  const _Drafts({
    required this.siteUrl,
    required this.feed,
    required this.controller,
    required this.onRefresh,
    required this.onRemove,
    required this.instance,
  });

  final String siteUrl;
  final DraftFeed feed;
  final ShellController controller;
  final Future<void> Function() onRefresh;
  final ValueChanged<UserDraft> onRemove;
  final DiscourseInstance instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (feed.error case final error?)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                    onPressed: () => unawaited(onRefresh()),
                    variant: DButtonVariant.link,
                  ),
                ],
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                children: [
                  for (var index = 0; index < feed.drafts.length; index++) ...[
                    _DraftRow(
                      siteUrl: siteUrl,
                      draft: feed.drafts[index],
                      deleting: controller.draftList.deleting(
                        siteUrl,
                        feed.drafts[index].key,
                      ),
                      onResume: feed.drafts[index].canResume
                          ? () => unawaited(
                              controller.resumeDraft(
                                siteUrl,
                                feed.drafts[index],
                              ),
                            )
                          : null,
                      onOpenForum: () => unawaited(
                        openExternalLink(
                          '$siteUrl/u/'
                          '${Uri.encodeComponent(instance.user!.username)}'
                          '/activity/drafts',
                        ),
                      ),
                      onRemove: () => onRemove(feed.drafts[index]),
                    ),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          if (feed.hasMore)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: DButton(
                  label: const Text('Load more'),
                  onPressed: () =>
                      unawaited(controller.draftList.load(instance)),
                  loading: feed.loading,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.siteUrl,
    required this.draft,
    required this.deleting,
    required this.onResume,
    required this.onOpenForum,
    required this.onRemove,
  });

  final String siteUrl;
  final UserDraft draft;
  final bool deleting;
  final VoidCallback? onResume;
  final VoidCallback onOpenForum;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<TopicCategory?>(
      select: (controller) =>
          controller.categoryFor(draft.displayCategoryId, siteUrl: siteUrl),
      builder: (context, category, _) => LayoutBuilder(
        builder: (context, constraints) => _DraftRowContent(
          siteUrl: siteUrl,
          draft: draft,
          category: category,
          deleting: deleting,
          onResume: onResume,
          onOpenForum: onOpenForum,
          onRemove: onRemove,
          compact: constraints.maxWidth < 520,
        ),
      ),
    );
  }
}

class _DraftRowContent extends StatelessWidget {
  const _DraftRowContent({
    required this.siteUrl,
    required this.draft,
    required this.category,
    required this.deleting,
    required this.onResume,
    required this.onOpenForum,
    required this.onRemove,
    required this.compact,
  });

  final String siteUrl;
  final UserDraft draft;
  final TopicCategory? category;
  final bool deleting;
  final VoidCallback? onResume;
  final VoidCallback onOpenForum;
  final VoidCallback onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = draft.createdAt;
    final action = onResume ?? onOpenForum;
    final title = draft.displayTitle == 'Untitled draft'
        ? null
        : draft.displayTitle;
    const actionSize = 44.0;

    final row = InkWell(
      onTap: action,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 16,
          compact ? 14 : 20,
          compact ? 8 : 12,
          compact ? 14 : 20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    TopicTitle(
                      title,
                      siteUrl: siteUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (title != null && (category != null || createdAt != null))
                    const SizedBox(height: 5),
                  if (category != null || createdAt != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (category case final category?)
                          _DraftCategory(category: category),
                        if (category != null && createdAt != null)
                          Text(
                            '•',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (createdAt != null)
                          Text(
                            relativeTime(createdAt),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  if (draft.excerpt.isNotEmpty) ...[
                    SizedBox(height: title == null ? 10 : 18),
                    TopicTitle(
                      draft.excerpt,
                      siteUrl: siteUrl,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: compact ? 8 : 16),
            _DraftAction(
              tooltip: onResume == null ? 'Open draft on forum' : 'Edit draft',
              onPressed: action,
              icon: DIcons.pencil,
              size: actionSize,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: compact ? 6 : 10),
            _DraftAction(
              tooltip: 'Remove draft',
              onPressed: deleting ? null : onRemove,
              icon: DIcons.trashCan,
              size: actionSize,
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
              loading: deleting,
            ),
          ],
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: compact
            ? DraftListView.compactRowMinimumHeight
            : DraftListView.wideRowMinimumHeight,
      ),
      child: row,
    );
  }
}

class _DraftCategory extends StatelessWidget {
  const _DraftCategory({required this.category});

  final TopicCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Color(category.colorValue),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          category.name,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DraftAction extends StatelessWidget {
  const _DraftAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.size,
    required this.backgroundColor,
    required this.foregroundColor,
    this.loading = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final DIconData icon;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onPressed == null
            ? backgroundColor.withValues(alpha: 0.5)
            : backgroundColor,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: AdaptiveActivityIndicator(
                        color: foregroundColor,
                        cupertinoRadius: 9,
                        materialStrokeWidth: 2,
                      ),
                    )
                  : DIcon(icon, size: 18, color: foregroundColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftState extends StatelessWidget {
  const _DraftState({
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
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (body case final body?) ...[
                const SizedBox(height: 6),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (actionLabel case final label?) ...[
                const SizedBox(height: 18),
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
