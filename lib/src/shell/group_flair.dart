import 'package:flutter/material.dart';

import '../models/group.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'site_url.dart';

class GroupFlair extends StatelessWidget {
  const GroupFlair({
    super.key,
    required this.siteUrl,
    required this.group,
    required this.size,
  });

  final String siteUrl;
  final Group group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flair = group.flairUrl?.trim();
    final imageUrl = flair != null && flair.contains('/')
        ? resolveSitePath(siteUrl, flair)
        : null;
    final icon = DIcons.byName[group.flairIcon?.trim()] ?? DIcons.byName[flair];
    if (imageUrl == null && icon == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Container(
        key: const ValueKey('group-flair'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _flairColor(group.flairBackgroundColor),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: imageUrl != null
            ? AvatarImage(
                url: imageUrl,
                size: size,
                fit: BoxFit.contain,
                fallback: const SizedBox.shrink(),
              )
            : DIcon(
                icon!,
                size: size * .7,
                color: _flairColor(group.flairColor),
              ),
      ),
    );
  }

  Color? _flairColor(String? value) {
    var hex = value?.trim().replaceFirst('#', '');
    if (hex == null) return null;
    if (hex.length == 3) {
      hex = hex.split('').map((digit) => '$digit$digit').join();
    }
    if (hex.length != 6) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }
}

/// Shared rendering for group search results and user avatar badges.
class GroupFlairBadge extends StatelessWidget {
  const GroupFlairBadge({
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
