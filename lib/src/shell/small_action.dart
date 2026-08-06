import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/app_theme.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'relative_time.dart';

/// How a small action reads: an icon and the sentence it completes.
///
/// The wording follows Discourse's own `action_codes` strings, so a topic
/// reads the same here as it does on the web.
@immutable
class SmallActionDescription {
  const SmallActionDescription({required this.icon, required this.phrase});

  final IconData icon;

  /// The sentence after the actor's name, e.g. `closed this topic`.
  final String phrase;

  /// The description for [post], or null if it is not a small action.
  static SmallActionDescription? of(Post post) {
    if (!post.isSmallAction) return null;
    final code = post.actionCode;
    if (code == null) return null;
    return SmallActionDescription(
      icon: _icons[code] ?? Icons.info_outline,
      phrase: _phrase(code, post.actionCodeWho),
    );
  }

  static String _phrase(String code, String? who) {
    final subject = who ?? 'them';
    return switch (code) {
      'closed.enabled' || 'autoclosed.enabled' => 'closed this topic',
      'closed.disabled' || 'autoclosed.disabled' => 'opened this topic',
      'archived.enabled' => 'archived this topic',
      'archived.disabled' => 'unarchived this topic',
      'pinned.enabled' => 'pinned this topic',
      'pinned.disabled' => 'unpinned this topic',
      'pinned_globally.enabled' => 'pinned this topic globally',
      'pinned_globally.disabled' => 'unpinned this topic globally',
      'banner.enabled' => 'made this topic a banner',
      'banner.disabled' => 'removed this banner',
      'visible.enabled' => 'listed this topic',
      'visible.disabled' => 'unlisted this topic',
      'split_topic' => 'split this topic',
      'moved_post' => 'moved this post',
      'invited_user' || 'invited_group' => 'invited $subject',
      'removed_user' || 'removed_group' => 'removed $subject',
      'user_left' => 'removed themselves from this message',
      'autobumped' => 'automatically bumped this topic',
      'public_topic' => 'made this topic public',
      'private_topic' => 'made this topic a personal message',
      'open_topic' => 'converted this to a topic',
      'forwarded' => 'forwarded the above email',
      // Plugins add action codes of their own, and Discourse adds new ones
      // between releases. An unknown code still names what happened, so read
      // it out rather than dropping the notice.
      _ => code.replaceAll(RegExp(r'[._]'), ' '),
    };
  }

  static const Map<String, IconData> _icons = {
    'closed.enabled': Icons.lock_outline,
    'autoclosed.enabled': Icons.lock_outline,
    'closed.disabled': Icons.lock_open_outlined,
    'autoclosed.disabled': Icons.lock_open_outlined,
    'archived.enabled': Icons.archive_outlined,
    'archived.disabled': Icons.unarchive_outlined,
    'pinned.enabled': Icons.push_pin_outlined,
    'pinned.disabled': Icons.push_pin_outlined,
    'pinned_globally.enabled': Icons.push_pin_outlined,
    'pinned_globally.disabled': Icons.push_pin_outlined,
    'banner.enabled': Icons.campaign_outlined,
    'banner.disabled': Icons.campaign_outlined,
    'visible.enabled': Icons.visibility_outlined,
    'visible.disabled': Icons.visibility_off_outlined,
    'split_topic': Icons.call_split,
    'moved_post': Icons.call_split,
    'invited_user': Icons.person_add_outlined,
    'invited_group': Icons.group_add_outlined,
    'removed_user': Icons.person_remove_outlined,
    'removed_group': Icons.group_remove_outlined,
    'user_left': Icons.logout_outlined,
    'autobumped': Icons.arrow_upward,
    'public_topic': Icons.public,
    'private_topic': Icons.mail_outline,
    'open_topic': Icons.comment_outlined,
    'forwarded': Icons.forward_to_inbox_outlined,
  };
}

/// A moderator notice in the post stream — "Martin Brennan closed this topic".
///
/// Kept to one muted line so it reads as an aside next to the posts around it.
/// Some small actions carry a message of their own (a close reason, say); that
/// is drawn underneath.
class SmallActionTile extends StatelessWidget {
  const SmallActionTile({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final description = SmallActionDescription.of(post);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                description?.icon ?? Icons.info_outline,
                size: 16,
                color: muted,
              ),
              const SizedBox(width: 10),
              ClipOval(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: AvatarImage(
                    url: post.avatarUrl,
                    size: 20,
                    fallback: ColoredBox(color: theme.shell.floating),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: post.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (description != null)
                        TextSpan(text: ' ${description.phrase}'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              if (post.createdAt case final createdAt?) ...[
                const SizedBox(width: 8),
                Text(
                  relativeTime(createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
          if (post.cooked.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 6),
              child: CookedHtml(
                html: post.cooked,
                textStyle: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
