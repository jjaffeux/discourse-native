import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/user_draft.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

/// Core's New Topic combo button: the primary action opens the composer and,
/// when the account has drafts, the attached action opens the four newest.
class TopicCreateButton extends StatefulWidget {
  const TopicCreateButton({
    super.key,
    required this.showLabel,
    required this.onPressed,
  });

  static const Key buttonKey = ValueKey('new-topic-button');
  static const Key draftsButtonKey = ValueKey('new-topic-drafts-button');

  final bool showLabel;
  final VoidCallback onPressed;

  @override
  State<TopicCreateButton> createState() => _TopicCreateButtonState();
}

class _TopicCreateButtonState extends State<TopicCreateButton> {
  final MenuController _menu = MenuController();

  void _toggleDraftsMenu(
    ShellController controller,
    DiscourseInstance instance,
  ) {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }

    _menu.open();
    unawaited(controller.draftList.load(instance, refresh: true));
  }

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

        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 6),
          style: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            shadowColor: WidgetStatePropertyAll(Colors.transparent),
            elevation: WidgetStatePropertyAll(0),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
          ),
          menuChildren: [
            if (instance != null)
              _RecentDraftsMenu(
                siteUrl: instance.url,
                menu: _menu,
                controller: controller,
              ),
          ],
          builder: (context, menu, child) => _TopicCreateControl(
            showLabel: widget.showLabel,
            showDraftsButton: hasDrafts,
            onPressed: widget.onPressed,
            onDraftsPressed: instance == null
                ? null
                : () => _toggleDraftsMenu(controller, instance),
          ),
        );
      },
    );
  }
}

class _TopicCreateControl extends StatelessWidget {
  const _TopicCreateControl({
    required this.showLabel,
    required this.showDraftsButton,
    required this.onPressed,
    required this.onDraftsPressed,
  });

  final bool showLabel;
  final bool showDraftsButton;
  final VoidCallback onPressed;
  final VoidCallback? onDraftsPressed;

  ButtonStyle _style(
    BuildContext context, {
    required BorderRadius borderRadius,
    required EdgeInsetsGeometry padding,
  }) {
    final theme = Theme.of(context);
    return FilledButton.styleFrom(
      minimumSize: const Size(40, 40),
      padding: padding,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      foregroundColor: theme.colorScheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
    );
  }

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(8);
    final mainRadius = showDraftsButton
        ? const BorderRadius.horizontal(left: radius)
        : const BorderRadius.all(radius);
    final mainStyle = _style(
      context,
      borderRadius: mainRadius,
      padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 10),
    );

    final mainButton = Tooltip(
      message: 'New topic',
      child: showLabel
          ? FilledButton.icon(
              key: TopicCreateButton.buttonKey,
              style: mainStyle,
              onPressed: onPressed,
              icon: const DIcon(DIcons.farPenToSquare, size: 20),
              label: const Text('New topic'),
            )
          : FilledButton(
              key: TopicCreateButton.buttonKey,
              style: mainStyle,
              onPressed: onPressed,
              child: const DIcon(DIcons.farPenToSquare, size: 20),
            ),
    );

    if (!showDraftsButton) return mainButton;

    return Semantics(
      label: 'New topic',
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mainButton,
          const SizedBox(width: 2),
          Tooltip(
            message: 'Open the latest drafts menu',
            child: FilledButton(
              key: TopicCreateButton.draftsButtonKey,
              style: _style(
                context,
                borderRadius: const BorderRadius.horizontal(right: radius),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: onDraftsPressed,
              child: const DIcon(DIcons.chevronDown, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentDraftsMenu extends StatelessWidget {
  const _RecentDraftsMenu({
    required this.siteUrl,
    required this.menu,
    required this.controller,
  });

  static const int _draftLimit = 4;

  final String siteUrl;
  final MenuController menu;
  final ShellController controller;

  void _resume(UserDraft draft) {
    menu.close();
    if (draft.canResume) {
      unawaited(controller.resumeDraft(siteUrl, draft));
    } else {
      controller.openDrafts(siteUrl);
    }
  }

  void _viewAll() {
    menu.close();
    controller.openDrafts(siteUrl);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = math.min(350.0, math.max(240.0, screenWidth - 24));

    return SizedBox(
      width: width,
      child: Material(
        color: Theme.of(context).shell.floating,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).shell.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListenableBuilder(
          listenable: controller.draftList,
          builder: (context, _) {
            final theme = Theme.of(context);
            final feed = controller.draftList.feedFor(siteUrl);
            final drafts = feed.drafts.take(_draftLimit).toList();
            final draftCount = controller.draftCountFor(siteUrl);
            final otherDraftCount = math.max(0, draftCount - _draftLimit);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (feed.loading && drafts.isEmpty)
                  const SizedBox(
                    height: 72,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else if (feed.error != null && drafts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Couldn't load drafts.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final draft in drafts)
                    _RecentDraftRow(
                      key: ValueKey('recent-draft-${draft.key}'),
                      siteUrl: siteUrl,
                      draft: draft,
                      onTap: () => _resume(draft),
                    ),
                if (otherDraftCount > 0) ...[
                  Divider(height: 1, color: theme.shell.divider),
                  _ViewAllDraftsRow(
                    otherDraftCount: otherDraftCount,
                    onTap: _viewAll,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecentDraftRow extends StatelessWidget {
  const _RecentDraftRow({
    super.key,
    required this.siteUrl,
    required this.draft,
    required this.onTap,
  });

  final String siteUrl;
  final UserDraft draft;
  final VoidCallback onTap;

  DIconData get _icon {
    if (draft.isNewTopic) return DIcons.layerGroup;
    if (draft.key.startsWith('new_private_message')) return DIcons.envelope;
    return DIcons.reply;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              DIcon(_icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: TopicTitle(
                  draft.displayTitle,
                  siteUrl: siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewAllDraftsRow extends StatelessWidget {
  const _ViewAllDraftsRow({required this.otherDraftCount, required this.onTap});

  final int otherDraftCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noun = otherDraftCount == 1 ? 'draft' : 'drafts';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '+$otherDraftCount other $noun',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'view all drafts',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
