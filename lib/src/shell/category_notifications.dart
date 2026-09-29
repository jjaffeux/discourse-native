import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'shell_scope.dart';

class CategoryNotificationLevelButton extends StatelessWidget {
  const CategoryNotificationLevelButton({
    super.key,
    required this.siteUrl,
    required this.categoryId,
    this.showLabel = false,
    this.showChevron = false,
  });

  final String siteUrl;
  final int categoryId;
  final bool showLabel;
  final bool showChevron;

  static List<DNotificationLevelOption<CategoryNotificationLevel>>
  get _options => [
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
              size: DButtonSize.chip,
              variant: DButtonVariant.outline,
              showLabel: showLabel,
              showChevron: showChevron,
              value: level,
              options: _options,
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
