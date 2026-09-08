import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import 'avatar_image.dart';

class ForumIcon extends StatelessWidget {
  const ForumIcon({super.key, required this.forum, this.size = 28});

  final DiscourseInstance forum;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: forum.title,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: AvatarImage(
          url: forum.iconUrl,
          size: size,
          fit: BoxFit.contain,
          fallback: ColoredBox(
            color: forum.accentColor.withValues(alpha: 0.16),
            child: SizedBox.square(
              dimension: size,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    forum.monogram,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
