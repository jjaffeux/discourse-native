import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'open_link.dart';
import 'topic_tag_picker.dart';

/// A topic's category, tags and [tools] on one line, the tools at its end.
/// Tags past the line wait behind their count; opening it shows them all
/// and lets the run wrap, the tools still at the end of its last line.
class TopicHeaderTags extends StatelessWidget {
  const TopicHeaderTags({
    super.key,
    required this.siteUrl,
    required this.topic,
    required this.onTagNavigate,
    this.path = const [],
    this.tools,
    this.editOnTap = false,
  });

  final String siteUrl;
  final TopicDetail topic;
  final TopicTagNavigationCallback onTagNavigate;
  final List<DHeaderStep> path;
  final Widget? tools;
  final bool editOnTap;

  @override
  Widget build(BuildContext context) {
    return TopicTagMenuAnchor(
      siteUrl: siteUrl,
      topicId: topic.id,
      categoryId: topic.categoryId,
      tags: topic.tags,
      enabled: topic.canEditTags,
      onTagNavigate: onTagNavigate,
      builder: (context, edit, saving) {
        final tags = topic.tags;
        final muted = DTokens.of(context).mutedForeground;
        Widget tagChip(TopicTag tag) {
          final editing = editOnTap && topic.canEditTags;
          final chip = GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onLongPress: topic.canEditTags ? edit : null,
            onTertiaryTapUp: (_) => onTagNavigate(tag, newTab: true),
            child: DButton(
              key: ValueKey(('topic-header-tag', tag.name)),
              variant: DButtonVariant.tool,
              size: DButtonSize.filter,
              isLink: !editing,
              loading: editing && saving,
              semanticLabel: editing
                  ? context.l10n.editTopicTags(tag.name)
                  : context.l10n.openTagTopicheadertags(tag.name),
              onPressed: editing ? edit : () => onTagNavigate(tag),
              label: Text.rich(
                TextSpan(
                  children: [
                    // The hash stands where the other buttons keep an icon.
                    TextSpan(
                      text: '#',
                      style: TextStyle(color: muted),
                    ),
                    const WidgetSpan(
                      child: SizedBox(width: DSpacing.controlGap),
                    ),
                    TextSpan(text: tag.name),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          );
          return editing
              ? chip
              : LinkTarget.action(
                  action: ({required newTab, panel}) =>
                      onTagNavigate(tag, newTab: newTab, panel: panel),
                  child: chip,
                );
        }

        final editTags = topic.canEditTags
            ? DPopoverTrigger(
                builder: (context, trigger) {
                  final onPressed = edit == null
                      ? null
                      : trigger.open
                      ? trigger.closePopover
                      : edit;
                  return tags.isEmpty
                      ? DButton(
                          key: const ValueKey('topic-header-edit-tags'),
                          label: Text(context.l10n.addTag),
                          icon: const DIcon(DIcons.tag),
                          tooltip: context.l10n.addTag,
                          variant: DButtonVariant.tool,
                          size: DButtonSize.filter,
                          focusNode: trigger.focusNode,
                          hasPopup: true,
                          expanded: trigger.open,
                          loading: saving,
                          loadingSemanticLabel: context.l10n.savingTags,
                          onPressed: onPressed,
                        )
                      : DButton.iconOnly(
                          key: const ValueKey('topic-header-edit-tags'),
                          icon: const DIcon(DIcons.pencil),
                          tooltip: context.l10n.addOrRemoveTopicTags,
                          variant: DButtonVariant.tool,
                          size: DButtonSize.filter,
                          focusNode: trigger.focusNode,
                          hasPopup: true,
                          expanded: trigger.open,
                          loading: saving,
                          loadingSemanticLabel: context.l10n.savingTags,
                          onPressed: onPressed,
                        );
                },
              )
            : null;

        return DHeaderTags(
          identity: ('topic-head-all-tags', topic.id),
          tags: [
            for (final tag in tags)
              DHeaderTag(name: tag.name, child: tagChip(tag)),
          ],
          path: path,
          expandSemanticLabel: context.l10n.viewAllTopicTags(
            tags.length.toString(),
          ),
          moreKey: const ValueKey('topic-header-more-tags'),
          emptyAction: editTags,
          expandedAction: editOnTap ? null : editTags,
          tools: tools,
        );
      },
    );
  }
}
