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
