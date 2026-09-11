import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/discourse_instance.dart';
import '../models/user_draft.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

class TopicCreateButton extends StatelessWidget {
  const TopicCreateButton({
    super.key,
    required this.showLabel,
    required this.onPressed,
    this.compact = false,
  });

  static const Key buttonKey = ValueKey('new-topic-button');
  static const Key draftsButtonKey = ValueKey('new-topic-drafts-button');

  final bool showLabel;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);

    return ListenableBuilder(
      listenable: controller.draftList,
      builder: (context, _) {
        final instance = controller.currentInstance;
        final hasDrafts =
            instance?.isConnected == true &&
            controller.draftCountFor(instance!.url) > 0;

        return _TopicCreateControl(
          showLabel: showLabel,
          compact: compact,
          onPressed: onPressed,
          draftsInstance: hasDrafts ? instance : null,
          controller: controller,
        );
      },
    );
  }
}

class _TopicCreateControl extends StatelessWidget {
  const _TopicCreateControl({
    required this.showLabel,
    required this.compact,
    required this.onPressed,
    required this.draftsInstance,
    required this.controller,
  });

  final bool showLabel;
  final bool compact;
  final VoidCallback onPressed;
  final DiscourseInstance? draftsInstance;
  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(DiscourseTypography.sm) *
        DiscourseTypography.lineHeightSmall;
    final insetIcons = compact && !showLabel && draftsInstance == null;
    final dimension = compact && showLabel
        ? math.max(28.0, labelHeight + 10)
        : compact
        ? DButton.iconOnlyDimensionFor(DButtonSize.small) -
              DButton.flatSurfacePadding * 2
        : DButton.iconOnlyDimensionFor(DButtonSize.small);
    final mainButton = showLabel
        ? DButton(
            key: TopicCreateButton.buttonKey,
            label: Text(
              'New topic',
              style: compact
                  ? const TextStyle(fontWeight: FontWeight.w500)
                  : null,
            ),
            icon: DIcon(DIcons.farPenToSquare, size: compact ? 14 : 18),
            tooltip: 'New topic',
            shortcut: const DShortcut(newTopicShortcut),
            semanticLabel: 'New topic',
            onPressed: onPressed,
            variant: DButtonVariant.primary,
            size: DButtonSize.small,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
                : null,
          )
        : DButton.iconOnly(
            key: TopicCreateButton.buttonKey,
            icon: const DIcon(DIcons.farPenToSquare, size: 18),
            tooltip: 'New topic',
            shortcut: const DShortcut(newTopicShortcut),
            semanticLabel: 'New topic',
            onPressed: onPressed,
            variant: DButtonVariant.primary,
            size: DButtonSize.small,
            insetSurface: insetIcons,
          );
    final sizedMainButton = insetIcons
        ? mainButton
        : SizedBox(
            height: dimension,
            width: showLabel ? null : dimension,
            child: mainButton,
          );

    final instance = draftsInstance;
    if (instance == null) return sizedMainButton;

    return DButtonGroup(
      semanticLabel: 'Topic creation actions',
      children: [
        sizedMainButton,
        if (!insetIcons) const DButtonGroupSeparator(),
        DDropdownMenu(
          key: ValueKey((instance.url, instance.user?.id)),
          onOpenChange: (open, _) {
            if (open) {
              unawaited(controller.draftList.load(instance, refresh: true));
            }
          },
          content: _draftsContent(context, instance),
          child: DDropdownMenuTrigger(
            builder: (context, state) {
              final button = DButton.iconOnly(
                key: TopicCreateButton.draftsButtonKey,
                icon: DIcon(
                  DIcons.chevronDown,
                  size: compact && showLabel ? 12 : 16,
                ),
                tooltip: 'Open the latest drafts menu',
                semanticLabel: 'Open the latest drafts menu',
                onPressed: state.toggle,
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                variant: DButtonVariant.primary,
                size: DButtonSize.small,
                insetSurface: insetIcons,
              );
              return insetIcons
                  ? button
                  : SizedBox(
                      height: dimension,
                      width: compact && showLabel ? 28 : dimension,
                      child: button,
                    );
            },
          ),
        ),
      ],
    );
  }

  static const int _draftLimit = 4;

  void _resume(String siteUrl, UserDraft draft) {
    if (draft.canResume) {
      unawaited(controller.resumeDraft(siteUrl, draft));
    } else {
      controller.openDrafts(siteUrl);
    }
  }

  DIconData _draftIcon(UserDraft draft) {
    if (draft.isVoiceTranscript) return DIcons.closedCaptioning;
    if (draft.isNewTopic) return DIcons.layerGroup;
    if (draft.key.startsWith('new_private_message')) return DIcons.envelope;
    return DIcons.reply;
  }

  DDropdownMenuContent _draftsContent(
    BuildContext context,
    DiscourseInstance instance,
  ) {
    final siteUrl = instance.url;
    final feed = controller.draftList.feedFor(siteUrl);
    final drafts = feed.drafts.take(_draftLimit);
    final otherDraftCount = math.max(
      0,
      controller.draftCountFor(siteUrl) - _draftLimit,
    );
    final noun = otherDraftCount == 1 ? 'draft' : 'drafts';

    return DDropdownMenuContent(
      semanticLabel: 'Recent drafts',
      align: DPopoverAlign.end,
      width: math.min(350, MediaQuery.sizeOf(context).width - 24),
      children: [
        if (feed.loading && drafts.isEmpty)
          const DDropdownMenuLabel(
            child: Row(
              children: [
                DSpinner(size: 16, semanticLabel: null),
                SizedBox(width: DSpacing.sm),
                Expanded(child: Text('Loading drafts…')),
              ],
            ),
          )
        else if (feed.error != null && drafts.isEmpty)
          const DDropdownMenuLabel(child: Text("Couldn't load drafts."))
        else
          for (final draft in drafts)
            DDropdownMenuItem(
              key: ValueKey('recent-draft-${draft.key}'),
              semanticLabel: draft.displayTitle,
              leading: DIcon(_draftIcon(draft), size: 16),
              onPressed: () => _resume(siteUrl, draft),
              child: TopicTitle(
                draft.displayTitle,
                siteUrl: siteUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        if (otherDraftCount > 0 && !feed.loading) ...[
          const DDropdownMenuSeparator(),
          DDropdownMenuItem(
            semanticLabel: 'View all drafts, $otherDraftCount other $noun',
            onPressed: () => controller.openDrafts(siteUrl),
            child: Wrap(
              spacing: DSpacing.md,
              children: [
                Text('+$otherDraftCount other $noun'),
                const Text('view all drafts'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
