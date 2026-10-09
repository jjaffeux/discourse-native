import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import 'emoji.dart';

enum PostActionGroup { share, change, report, staff }

enum PostActionPlacement { toolbar, overflow, trailing }

@immutable
class PostAction {
  const PostAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onInvoke,
    this.onInvokeAnchored,
    this.enabled = true,
    this.group = PostActionGroup.change,
    this.destructive = false,
    this.tint,
    this.emojiUrl,
    this.placement = PostActionPlacement.toolbar,
    this.showLabelInFooter = true,
    this.showInMenu = true,
  });

  final DIconData icon;

  final String? emojiUrl;

  final String label;

  final String tooltip;

  final bool enabled;

  final PostActionGroup group;

  final bool destructive;

  final PostActionPlacement placement;

  final bool showLabelInFooter;

  /// Footer engagement can retain its toolbar action without duplicating menus.
  final bool showInMenu;

  final Color? tint;

  final ValueChanged<Rect>? onInvokeAnchored;

  final VoidCallback onInvoke;

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
