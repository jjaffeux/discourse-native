import 'dart:async';

import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'choice_menu.dart';
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
    ChoiceMenuOption(
      value: CategoryNotificationLevel.watching,
      title: 'Watching',
      description: 'Every new post and unread count',
      icon: DIcons.discourseBellExclamation,
    ),
    ChoiceMenuOption(
      value: CategoryNotificationLevel.tracking,
      title: 'Tracking',
      description: 'Mentions, replies, and unread count',
      icon: DIcons.bell,
    ),
    ChoiceMenuOption(
      value: CategoryNotificationLevel.watchingFirstPost,
      title: 'Watching First Post',
      description: 'New topics only',
      icon: DIcons.discourseBellExclamation,
    ),
    ChoiceMenuOption(
      value: CategoryNotificationLevel.normal,
      title: 'Normal',
      description: 'Mentions and replies only',
      icon: DIcons.farBell,
    ),
    ChoiceMenuOption(
      value: CategoryNotificationLevel.muted,
      title: 'Muted',
      description: 'No notifications; hidden from Latest',
      icon: DIcons.discourseBellSlash,
    ),
  ];

  static DIconData _iconFor(CategoryNotificationLevel level) => switch (level) {
    CategoryNotificationLevel.watching => DIcons.discourseBellExclamation,
    CategoryNotificationLevel.tracking => DIcons.bell,
    CategoryNotificationLevel.watchingFirstPost =>
      DIcons.discourseBellExclamation,
    CategoryNotificationLevel.normal => DIcons.farBell,
    CategoryNotificationLevel.muted => DIcons.discourseBellSlash,
  };

  static String _labelFor(CategoryNotificationLevel level) => switch (level) {
    CategoryNotificationLevel.watching => 'Watching',
    CategoryNotificationLevel.tracking => 'Tracking',
    CategoryNotificationLevel.watchingFirstPost => 'Watching First Post',
    CategoryNotificationLevel.normal => 'Normal',
    CategoryNotificationLevel.muted => 'Muted',
  };

  static bool _isEmphasized(CategoryNotificationLevel level) => switch (level) {
    CategoryNotificationLevel.watching ||
    CategoryNotificationLevel.tracking ||
    CategoryNotificationLevel.watchingFirstPost => true,
    CategoryNotificationLevel.normal ||
    CategoryNotificationLevel.muted => false,
  };

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ValueListenableBuilder<TopicCategory?>(
      valueListenable: controller.categoryRef(siteUrl, categoryId),
      builder: (context, category, _) {
        if (category == null) return const SizedBox.shrink();
        final level = category.notificationLevel;
        return ChoiceMenuAnchor<CategoryNotificationLevel>(
          title: 'Category notifications',
          showPopoverTitle: false,
          value: level,
          options: _options,
          onSelected: (selected) => unawaited(
            controller.updateCategoryNotificationLevel(
              siteUrl,
              categoryId,
              selected,
            ),
          ),
          builder: (context, openMenu) => DButton.iconOnly(
            key: const ValueKey('category-notification-level-button'),
            tooltip: 'Category notifications: ${_labelFor(level)}',
            onPressed: openMenu,
            icon: DIcon(_iconFor(level), size: 18),
            variant: _isEmphasized(level)
                ? DButtonVariant.transparentPrimary
                : DButtonVariant.flat,
            size: DButtonSize.small,
          ),
        );
      },
    );
  }
}
