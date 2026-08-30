import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sidebar_tag.dart';
import '../models/tag_directory_feed.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';

/// The site's browsable tags, loaded from Discourse's native tag directory.
class TagsPage extends StatefulWidget {
  const TagsPage({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  (Object, String)? _requestedIdentity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(TagsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.siteUrl != oldWidget.siteUrl) _request();
  }

  void _request({bool force = false}) {
    final controller = ShellScope.identityOf(context);
    final identity = (controller as Object, widget.siteUrl);
    if (!force && identity == _requestedIdentity) return;
    _requestedIdentity = identity;
    unawaited(controller.loadTags(widget.siteUrl, force: force));
  }

  @override
  Widget build(BuildContext context) => ShellSelector<TagDirectoryFeed>(
    select: (controller) => controller.tagDirectoryFeedFor(widget.siteUrl),
    builder: (context, feed, _) {
      if (feed.error != null && feed.tags.isEmpty) {
        return _TagPageState(
          icon: DIcons.triangleExclamation,
          title: feed.error!,
          actionLabel: 'Try again',
          onAction: () => _request(force: true),
        );
      }
      if (!feed.loaded && feed.tags.isEmpty) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      if (feed.isEmpty) {
        return const _TagPageState(icon: DIcons.tag, title: 'No tags yet');
      }

      return RefreshIndicator.adaptive(
        onRefresh: () =>
            ShellScope.read(context).loadTags(widget.siteUrl, force: true),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount:
              feed.tags.length +
              (feed.loading ? 1 : 0) +
              (feed.error == null ? 0 : 1),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            var tagIndex = index;
            if (feed.loading) {
              if (tagIndex == 0) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              tagIndex--;
            }
            if (feed.error case final message?) {
              if (tagIndex == 0) {
                return _TagErrorBanner(
                  message: message,
                  onRetry: () => _request(force: true),
                );
              }
              tagIndex--;
            }
            final tag = feed.tags[tagIndex];
            return _TagRow(
              tag: tag,
              onTap: () => ShellScope.read(context).openTag(tag),
            );
          },
        ),
      );
    },
  );
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, required this.onTap});

  final SidebarTag tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = tag.description;
    final countNoun = tag.pmOnly ? 'message' : 'topic';
    final countLabel =
        '${tag.count} '
        '${tag.count == 1 ? countNoun : '${countNoun}s'}';

    return Semantics(
      button: true,
      label: '${tag.name}, $countLabel',
      child: Material(
        key: ValueKey('tag-directory-tag-${tag.id}'),
        color: theme.shell.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: theme.shell.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  DIcon(
                    DIcons.tag,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tag.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 2),
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
                  const SizedBox(width: 12),
                  Text(
                    '${tag.count}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _TagErrorBanner extends StatelessWidget {
  const _TagErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          DIcon(
            DIcons.triangleExclamation,
            size: 17,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _TagPageState extends StatelessWidget {
  const _TagPageState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(icon, size: 26, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center),
            if (actionLabel case final label?) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onAction, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}
