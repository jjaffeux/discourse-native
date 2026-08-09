import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import 'emoji.dart';

/// One thing that can be done with a post, in whichever surface is offering it.
///
/// The hover menu and the long-press sheet draw the same list rather than each
/// deciding for itself what a post allows — two answers to that question is one
/// too many.
///
/// Public, and in a file of its own, because an optional site feature can
/// contribute one. See `PostMenuPlugin.postMenu`.
@immutable
class PostAction {
  const PostAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onInvoke,
    this.destructive = false,
    this.tint,
    this.emojiUrl,
  });

  final DIconData icon;

  /// An emoji to draw in place of [icon], for a feature whose action is an
  /// emoji rather than a glyph. Falls back to [icon] until it has loaded, and
  /// wherever the site will not serve it.
  final String? emojiUrl;

  /// For the sheet, which has room for words.
  final String label;

  /// For the menu, which does not.
  final String tooltip;

  final bool destructive;

  /// Overrides the icon's color where the state of the post is worth saying in
  /// the icon itself — a heart already given, rather than one on offer.
  final Color? tint;

  final VoidCallback onInvoke;

  /// The entry's glyph at [size], which is an emoji where the action *is* one.
  ///
  /// [EmojiImage] holds the space and falls back to text of its own, so the
  /// menu keeps its width whether or not the site serves the artwork.
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
