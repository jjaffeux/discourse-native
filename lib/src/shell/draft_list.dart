import 'dart:async';

import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/draft_feed.dart';
import '../models/user_draft.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'relative_time.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

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
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove draft?'),
        content: Text(
          '“${draft.displayTitle}” will be permanently removed from this '
          'account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
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
          return const Center(child: CircularProgressIndicator());
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
              constraints: const BoxConstraints(maxWidth: 760),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < feed.drafts.length;
                      index++
                    ) ...[
                      if (index > 0) const Divider(height: 1),
                      _DraftRow(
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
                    ],
                  ],
                ),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
    required this.draft,
    required this.deleting,
    required this.onResume,
    required this.onOpenForum,
    required this.onRemove,
  });

  final UserDraft draft;
  final bool deleting;
  final VoidCallback? onResume;
  final VoidCallback onOpenForum;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = draft.createdAt;
    return InkWell(
      onTap: onResume,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: DIcon(
                DIcons.pencil,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      draft.kindLabel,
                      if (createdAt != null) relativeTime(createdAt),
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (draft.excerpt.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      draft.excerpt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: onResume ?? onOpenForum,
              child: Text(onResume == null ? 'Open on forum' : 'Resume'),
            ),
            IconButton(
              tooltip: 'Remove draft',
              onPressed: deleting ? null : onRemove,
              icon: deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const DIcon(DIcons.trashCan, size: 17),
            ),
          ],
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
