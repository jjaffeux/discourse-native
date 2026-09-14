import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_native_icons.dart';
import 'shell_scope.dart';

class CategoryNotificationLevelButton extends StatelessWidget {
  const CategoryNotificationLevelButton({
    super.key,
    required this.siteUrl,
    required this.categoryId,
  });

  final String siteUrl;
  final int categoryId;

  static const _options = [
    DNotificationLevelOption(
      value: CategoryNotificationLevel.watching,
      emphasized: true,
      label: 'Watching',
      description: 'Every new post and unread count',
      icon: DIcon(DNativeIcons.bellRing),
    ),
    DNotificationLevelOption(
      value: CategoryNotificationLevel.tracking,
      emphasized: true,
      label: 'Tracking',
      description: 'Mentions, replies, and unread count',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: CategoryNotificationLevel.watchingFirstPost,
      emphasized: true,
      label: 'Watching First Post',
      description: 'New topics only',
      icon: DIcon(DNativeIcons.bellRing),
    ),
    DNotificationLevelOption(
      value: CategoryNotificationLevel.normal,
      label: 'Normal',
      description: 'Mentions and replies only',
      icon: DIcon(DNativeIcons.bell),
    ),
    DNotificationLevelOption(
      value: CategoryNotificationLevel.muted,
      label: 'Muted',
      description: 'No notifications; hidden from Latest',
      icon: DIcon(DNativeIcons.bellOff),
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
              semanticLabel: 'Category notifications',
              buttonKey: const ValueKey('category-notification-level-button'),
              size: DButtonSize.regular,
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
