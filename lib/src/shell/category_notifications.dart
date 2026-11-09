import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../foundation/icons/d_native_icons.dart';
import '../models/tag_notification.dart';
import '../models/topic.dart';
import 'shell_scope.dart';

List<DNotificationLevelOption<CategoryNotificationLevel>> get _levelOptions => [
  DNotificationLevelOption(
    value: CategoryNotificationLevel.watching,
    emphasized: true,
    label: appL10n.watching,
    description: appL10n.everyNewPostAndUnreadCount,
    icon: const DIcon(DNativeIcons.bellRing),
  ),
  DNotificationLevelOption(
    value: CategoryNotificationLevel.tracking,
    emphasized: true,
    label: appL10n.tracking,
    description: appL10n.mentionsRepliesAndUnreadCount,
    icon: const DIcon(DIcons.bell),
  ),
  DNotificationLevelOption(
    value: CategoryNotificationLevel.watchingFirstPost,
    emphasized: true,
    label: appL10n.watchingFirstPost,
    description: appL10n.newTopicsOnly,
    icon: const DIcon(DNativeIcons.bellRing),
  ),
  DNotificationLevelOption(
    value: CategoryNotificationLevel.normal,
    label: appL10n.normal,
    description: appL10n.mentionsAndRepliesOnly,
    icon: const DIcon(DIcons.bell),
  ),
  DNotificationLevelOption(
    value: CategoryNotificationLevel.muted,
    label: appL10n.muted,
    description: appL10n.noNotificationsHiddenFromLatest,
    icon: const DIcon(DNativeIcons.bellOff),
  ),
];

class CategoryNotificationLevelButton extends StatelessWidget {
  const CategoryNotificationLevelButton({
    super.key,
    required this.siteUrl,
    required this.categoryId,
    this.showLabel = false,
    this.showChevron = false,
    this.size = DButtonSize.chip,
    this.quiet = false,
  });

  final String siteUrl;
  final int categoryId;
  final bool showLabel;
  final bool showChevron;
  final DButtonSize size;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<Object>(
      select: (controller) => controller.lifecycle.capture(siteUrl).session,
      builder: (context, _, _) {
        final controller = ShellScope.read(context);
        return ValueListenableBuilder<TopicCategory?>(
          valueListenable: controller.categoryRef(siteUrl, categoryId),
          builder: (context, category, _) {
            if (category == null) return const SizedBox.shrink();
            final level = category.notificationLevel;
            final lease = controller.lifecycle.capture(siteUrl);
            return DNotificationLevelMenu<CategoryNotificationLevel>(
              key: ValueKey((controller, siteUrl, categoryId, lease.session)),
              semanticLabel: context.l10n.categoryNotifications,
              buttonKey: const ValueKey('category-notification-level-button'),
              size: size,
              variant: quiet ? DButtonVariant.quiet : DButtonVariant.outline,
              showLabel: showLabel,
              showChevron: showChevron,
              value: level,
              options: _levelOptions,
              onChanged: (selected) {
                // Account replacement can precede the anchor's next rebuild.
                if (!lease.isCurrent) return;
                unawaited(
                  controller.updateCategoryNotificationLevel(
                    siteUrl,
                    categoryId,
                    selected,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class TagNotificationLevelButton extends StatelessWidget {
  const TagNotificationLevelButton({
    super.key,
    required this.siteUrl,
    required this.tag,
    this.size = DButtonSize.chip,
    this.quiet = false,
    this.showChevron = false,
  });

  final String siteUrl;
  final String tag;
  final DButtonSize size;
  final bool quiet;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<Object>(
      select: (controller) => controller.lifecycle.capture(siteUrl).session,
      builder: (context, session, _) {
        final controller = ShellScope.read(context);
        return _TagNotificationMenu(
          // A new account or tag starts over with its own read of the level.
          key: ValueKey((controller, siteUrl, tag, session)),
          siteUrl: siteUrl,
          tag: tag,
          size: size,
          quiet: quiet,
          showChevron: showChevron,
        );
      },
    );
  }
}

class _TagNotificationMenu extends StatefulWidget {
  const _TagNotificationMenu({
    super.key,
    required this.siteUrl,
    required this.tag,
    required this.size,
    required this.quiet,
    required this.showChevron,
  });

  final String siteUrl;
  final String tag;
  final DButtonSize size;
  final bool quiet;
  final bool showChevron;

  @override
  State<_TagNotificationMenu> createState() => _TagNotificationMenuState();
}

class _TagNotificationMenuState extends State<_TagNotificationMenu> {
  late final _controller = ShellScope.read(context);
  late final _lease = _controller.lifecycle.capture(widget.siteUrl);

  @override
  void initState() {
    super.initState();
    unawaited(
      _controller.refreshTagNotificationLevel(widget.siteUrl, widget.tag),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TagNotificationPreference?>(
      valueListenable: _controller.tagNotificationRef(
        widget.siteUrl,
        widget.tag,
      ),
      builder: (context, preference, _) {
        if (preference == null) return const SizedBox.shrink();
        return DNotificationLevelMenu<TagNotificationLevel>(
          semanticLabel: context.l10n.tagNotifications,
          buttonKey: const ValueKey('tag-notification-level-button'),
          size: widget.size,
          variant: widget.quiet ? DButtonVariant.quiet : DButtonVariant.outline,
          showChevron: widget.showChevron,
          value: preference.level,
          options: _levelOptions,
          onChanged: (selected) {
            // Account replacement can precede the anchor's next rebuild.
            if (!_lease.isCurrent) return;
            unawaited(
              _controller.updateTagNotificationLevel(
                widget.siteUrl,
                widget.tag,
                selected,
              ),
            );
          },
        );
      },
    );
  }
}
