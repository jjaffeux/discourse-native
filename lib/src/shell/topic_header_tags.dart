import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/d_icons.dart';
import 'topic_tag_picker.dart';

/// Every tag remains visible. The containing header grows when tags wrap.
class TopicHeaderTags extends StatelessWidget {
  const TopicHeaderTags({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.onTagNavigate,
    this.onEdit,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicTagNavigationCallback onTagNavigate;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (onEdit != null || !topic.canEditTags) {
      return _tags(context, onEdit, false);
    }
    return TopicTagMenuAnchor(
      siteUrl: siteUrl,
      topicId: topic.id,
      categoryId: topic.categoryId,
      tags: topic.tags,
      enabled: topic.canEditTags,
      onTagNavigate: onTagNavigate,
      builder: _tags,
    );
  }

  Widget _tags(BuildContext context, VoidCallback? edit, bool saving) => Wrap(
    spacing: DSpacing.xs,
    runSpacing: DSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final tag in topic.tags)
        GestureDetector(
          onTertiaryTapUp: (_) => onTagNavigate(tag, newTab: true),
          child: DBadge.link(
            key: ValueKey(('topic-header-tag', tag.name)),
            variant: DBadgeVariant.ghost,
            foregroundColor: DTokens.of(context).mutedForeground,
            semanticLabel: 'Browse tag ${tag.name}',
            onPressed: () => onTagNavigate(tag),
            child: Text('#${tag.name}'),
          ),
        ),
      if (topic.canEditTags)
        DButton.iconOnly(
          key: const ValueKey('topic-header-edit-tags'),
          icon: DIcon(DIcons.plus, color: DTokens.of(context).mutedForeground),
          tooltip: topic.tags.isEmpty ? 'Add tag' : 'Edit tags',
          variant: DButtonVariant.ghost,
          size: DButtonSize.small,
          loading: saving,
          onPressed: edit,
        ),
    ],
  );
}
