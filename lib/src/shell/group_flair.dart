import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';

/// Shared rendering for group search results and user avatar badges.
class GroupFlair extends StatelessWidget {
  const GroupFlair({
    super.key,
    required this.url,
    this.color,
    this.backgroundColor,
    this.size = 24,
    this.iconSize = 16,
    this.borderRadius = 5,
    this.defaultColor,
  });

  final String? url;
  final String? color;
  final String? backgroundColor;
  final double size;
  final double iconSize;
  final double borderRadius;
  final Color? defaultColor;

  @override
  Widget build(BuildContext context) {
    final foreground = _hexColor(
      color,
      defaultColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final flair = url;
    final fallback = DIcon(DIcons.users, size: iconSize, color: foreground);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _hexColor(backgroundColor, Colors.transparent),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: flair == null
          ? null
          : flair.contains('/')
          ? AvatarImage(
              url: flair,
              size: size,
              fit: BoxFit.contain,
              fallback: fallback,
            )
          : DIcon(
              DIcons.byName[flair] ?? DIcons.users,
              size: iconSize,
              color: foreground,
            ),
    );
  }
}

Color _hexColor(String? value, Color fallback) {
  var normalized = value?.replaceFirst(RegExp(r'^#'), '');
  if (normalized == null ||
      !RegExp(r'^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(normalized)) {
    return fallback;
  }
  if (normalized.length == 3) {
    normalized = normalized.split('').map((digit) => '$digit$digit').join();
  }
  return Color(0xFF000000 | int.parse(normalized, radix: 16));
}
