import 'package:flutter/material.dart';

import '../plugin_api/post_action.dart';
import '../theme/d_icon.dart';
import 'emoji.dart';

extension PostActionLeading on PostAction {
  Widget leading(BuildContext context, {required double size, Color? color}) {
    final url = emojiUrl;
    if (url == null) return DIcon(icon, size: size, color: color);
    return EmojiImage(
      url: url,
      size: size,
      alt: label,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
