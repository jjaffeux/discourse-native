import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/foundation/count_label.dart';
import 'package:flutter/material.dart';

import '../models/sidebar_tag.dart';
import '../models/tag_directory_feed.dart';
import '../theme/d_icons.dart';
import 'content_reading_lane.dart';
import 'directory_skeleton.dart';
import 'search_words.dart';
import 'shell_scope.dart';

typedef _TagPageSnapshot = (Object, TagDirectoryFeed);

class TagsPage extends StatefulWidget {
  const TagsPage({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  (Object, String, Object)? _requestedIdentity;
  bool _requestScheduled = false;

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
    final identity = (
      controller as Object,
      widget.siteUrl,
      controller.lifecycle.capture(widget.siteUrl).session,
    );
    if (!force && identity == _requestedIdentity) return;
    _requestedIdentity = identity;
    unawaited(controller.loadTags(widget.siteUrl, force: force));
  }

  void _scheduleRequest(Object session) {
    if (_requestedIdentity?.$3 == session || _requestScheduled) return;
    _requestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScheduled = false;
      if (mounted) _request();
    });
  }

  @override
  Widget build(BuildContext context) => DPageSurface.headed(
    identity: widget.siteUrl,
    title: Text(context.l10n.tags),
    foldTitleAtTop: true,
    child: ShellSelector<_TagPageSnapshot>(
      select: (controller) => (
        controller.lifecycle.capture(widget.siteUrl).session,
        controller.tagDirectoryFeedFor(widget.siteUrl),
      ),
      builder: (context, data, _) {
        final (session, feed) = data;
        final tags =
            feed.tags
                .where(
                  (tag) =>
                      searchWordsMatch(SearchWords.of(context), [tag.name]),
                )
                .toList()
              ..sort((a, b) {
                final count = b.count.compareTo(a.count);
                return count != 0
                    ? count
                    : a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });
        _scheduleRequest(session);
        if (feed.error != null && feed.tags.isEmpty) {
          return _TagPageState(
            icon: DIcons.triangleExclamation,
            title: feed.error!,
            actionLabel: context.l10n.tryAgain,
            onAction: () => _request(force: true),
          );
        }
        if (!feed.loaded && feed.tags.isEmpty) {
          return ContentReadingLane(
            basePadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            builder: (context, lane) => Padding(
              padding: lane.padding,
              child: const DirectorySkeleton(kind: DirectorySkeletonKind.tags),
            ),
          );
        }
        if (feed.isEmpty) {
          return _TagPageState(icon: DIcons.tag, title: context.l10n.noTagsYet);
        }

        return ContentReadingLane(
          basePadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          builder: (context, lane) {
            final columns = math.max(
              1,
              (lane.width / MediaQuery.textScalerOf(context).scale(300))
                  .floor(),
            );
            final rows = (tags.length / columns).ceil();
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: lane.padding.add(
                EdgeInsets.only(bottom: DScrollChrome.bottomInsetOf(context)),
              ),
              itemCount: rows + (feed.error == null ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: DSpacing.md),
              itemBuilder: (context, index) {
                if (feed.error != null) {
                  if (index == 0) {
                    return _TagErrorBanner(
                      message: feed.error!,
                      onRetry: () => _request(force: true),
                    );
                  }
                  index--;
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.md,
                  children: [
                    for (var column = 0; column < columns; column++)
                      Expanded(
                        child: index * columns + column < tags.length
                            ? TagDirectoryRow(
                                tag: tags[index * columns + column],
                                onTap: () => ShellScope.read(
                                  context,
                                ).openTag(tags[index * columns + column]),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    ),
  );
}

class TagDirectoryRow extends StatelessWidget {
  const TagDirectoryRow({super.key, required this.tag, required this.onTap});

  final SidebarTag tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = tag.description;
    final noun = tag.pmOnly ? CountNoun.message : CountNoun.topic;
    final countText = countLabel(tag.count, noun);

    return DCard(
      key: ValueKey('tag-directory-tag-${tag.id}'),
      variant: DCardVariant.well,
      border: false,
      spacing: 0,
      child: DItem(
        shape: DItemShape.card,
        link: true,
        onPressed: onTap,
        children: [
          DItemMedia(
            variant: DItemMediaVariant.icon,
            child: DIcon(DIcons.tag, color: theme.colorScheme.primary),
          ),
          DItemContent(
            children: [
              DItemTitle(child: Text(tag.name)),
              if (description != null)
                DItemDescription(child: Text(description)),
              DItemDescription(child: Text(countText)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagErrorBanner extends StatelessWidget {
  const _TagErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => DAlert(
    variant: DAlertVariant.destructive,
    icon: const Icon(Icons.error_outline),
    description: DAlertDescription(child: Text(message)),
    action: DAlertAction(
      child: DButton(
        label: Text(context.l10n.retry),
        onPressed: onRetry,
        variant: DButtonVariant.link,
      ),
    ),
  );
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
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(title),
            ],
          ),
          if (actionLabel case final label?)
            DEmptyContent(
              children: [DButton(label: Text(label), onPressed: onAction)],
            ),
        ],
      ),
    ),
  );
}
