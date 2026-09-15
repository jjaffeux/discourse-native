import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/topic.dart';
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
    this.onTagFilter,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicTagNavigationCallback onTagNavigate;
  final VoidCallback? onEdit;
  final ValueChanged<TopicTag>? onTagFilter;

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
        _TopicHeaderTag(
          key: ValueKey((siteUrl, topic.id, tag.name)),
          tag: tag,
          canEdit: topic.canEditTags,
          onEdit: edit,
          onNavigate: onTagNavigate,
          onFilter: tag.pmOnly ? null : onTagFilter,
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

class _TopicHeaderTag extends StatefulWidget {
  const _TopicHeaderTag({
    super.key,
    required this.tag,
    required this.canEdit,
    required this.onEdit,
    required this.onNavigate,
    required this.onFilter,
  });

  final TopicTag tag;
  final bool canEdit;
  final VoidCallback? onEdit;
  final TopicTagNavigationCallback onNavigate;
  final ValueChanged<TopicTag>? onFilter;

  @override
  State<_TopicHeaderTag> createState() => _TopicHeaderTagState();
}

class _TopicHeaderTagState extends State<_TopicHeaderTag> {
  final _trigger = DContextMenuTriggerController();

  @override
  Widget build(BuildContext context) => DContextMenu(
    content: DContextMenuContent(
      semanticLabel: 'Actions for tag ${widget.tag.name}',
      children: [
        DContextMenuItem(
          key: ValueKey(('topic-header-tag-open', widget.tag.name)),
          onPressed: () => widget.onNavigate(widget.tag),
          child: const Text('Open'),
        ),
        DContextMenuItem(
          key: ValueKey(('topic-header-tag-open-new-tab', widget.tag.name)),
          onPressed: () => widget.onNavigate(widget.tag, newTab: true),
          child: const Text('Open in new tab'),
        ),
        DContextMenuItem(
          key: ValueKey(('topic-header-tag-filter', widget.tag.name)),
          onPressed: widget.onFilter == null
              ? null
              : () => widget.onFilter!(widget.tag),
          child: const Text('Use as filter'),
        ),
      ],
    ),
    child: DContextMenuTrigger(
      controller: _trigger,
      focusable: false,
      child: GestureDetector(
        onTertiaryTapUp: (_) => widget.onNavigate(widget.tag, newTab: true),
        child: DBadge.action(
          key: ValueKey(('topic-header-tag', widget.tag.name)),
          variant: DBadgeVariant.ghost,
          foregroundColor: DTokens.of(context).mutedForeground,
          semanticLabel: widget.canEdit
              ? 'Edit tags: ${widget.tag.name}'
              : 'Actions for tag ${widget.tag.name}',
          onPressed: widget.canEdit ? widget.onEdit : _trigger.openFromKeyboard,
          child: Text('#${widget.tag.name}'),
        ),
      ),
    ),
  );
}
