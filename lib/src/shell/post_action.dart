import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import 'emoji.dart';

/// Where a post action belongs on pointer-driven layouts.
///
/// Touch surfaces always show the complete, labelled list. The distinction is
/// only for the compact hover surface, where frequent reading actions deserve
/// one-click access and everything else belongs behind progressive disclosure.
enum PostActionPlacement {
  /// Shown before Core's expansion ellipsis.
  toolbar,

  /// Hidden in the labelled More actions menu when at least two such actions
  /// are available. A lone collapsed action is promoted, as it is on web.
  overflow,

  /// Kept after the expansion ellipsis. Core uses this position for Reply.
  trailing,
}

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
    this.onInvokeAnchored,
    this.enabled = true,
    this.destructive = false,
    this.tint,
    this.emojiUrl,
    this.placement = PostActionPlacement.toolbar,
  });

  final DIconData icon;

  /// An emoji to draw in place of [icon], for a feature whose action is an
  /// emoji rather than a glyph. Falls back to [icon] until it has loaded, and
  /// wherever the site will not serve it.
  final String? emojiUrl;

  /// For the sheet, which has room for words.
  final String label;

  /// For icon-only buttons in the compact hover toolbar.
  final String tooltip;

  /// False while another write owns the same target.
  final bool enabled;

  final bool destructive;

  /// Plugin actions are visible by default, matching Core's post-menu DAG.
  /// Actions which correspond to Core's `post_menu_hidden_items` opt into
  /// [PostActionPlacement.overflow].
  final PostActionPlacement placement;

  /// Overrides the icon's color where the state of the post is worth saying in
  /// the icon itself — a heart already given, rather than one on offer.
  final Color? tint;

  /// Invoked instead of [onInvoke] on pointer-driven post toolbars when the
  /// action opens a popover that belongs beside its button.
  ///
  /// The rectangle is captured before the toolbar overlay closes and uses the
  /// root navigator overlay's coordinates. Touch sheets and a button that can
  /// no longer be measured fall back to [onInvoke].
  final ValueChanged<Rect>? onInvokeAnchored;

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
