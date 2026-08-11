import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/draft_feed.dart';
import '../models/topic.dart';
import '../models/user_draft.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'adaptive_dialog_action.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

/// The full-page list of server-side drafts for one connected account.
class DraftListView extends StatefulWidget {
  const DraftListView({super.key, required this.siteUrl});

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
          return const Center(child: CircularProgressIndicator.adaptive());
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
                  TextButton(
                    onPressed: () => unawaited(onRefresh()),
                    child: const Text('Retry'),
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
                child: OutlinedButton(
                  onPressed: feed.loading
                      ? null
                      : () => unawaited(controller.draftList.load(instance)),
                  child: feed.loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Load more'),
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
    final actionSize = compact ? 38.0 : 44.0;

    return InkWell(
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
