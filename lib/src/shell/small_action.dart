import 'package:flutter/material.dart';

import '../models/post.dart';
import '../plugins/plugin_scope.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
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

  final DIconData icon;

  /// The sentence after the actor's name, e.g. `closed this topic`.
  final String phrase;

  /// The description for [post], or null if it is not a small action.
  static SmallActionDescription? of(Post post, {PluginRegistry? registry}) {
    if ((registry ?? pluginRegistry).smallAction(post)
        case final contribution?) {
      return SmallActionDescription(
        icon: contribution.icon,
        phrase: contribution.phrase,
      );
    }
    if (post.postType != Post.smallActionPostType) return null;
    final code = post.actionCode;
    if (code == null) return null;
    return SmallActionDescription(
      icon: _icons[code] ?? fallbackIcon,
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

  /// What Discourse falls back to for an action code it has no icon for.
  static const DIconData fallbackIcon = DIcons.exclamation;

  /// Straight from `ICONS` in Discourse's `components/post/small-action.gjs`,
  /// so a notice carries the same icon here as it does on the web. `forwarded`
  /// is ours: Discourse has no entry for it and would fall back.
  static const Map<String, DIconData> _icons = {
    'closed.enabled': DIcons.lock,
    'autoclosed.enabled': DIcons.lock,
    'closed.disabled': DIcons.unlock,
    'autoclosed.disabled': DIcons.unlock,
    'archived.enabled': DIcons.folder,
    'archived.disabled': DIcons.folderOpen,
    'pinned.enabled': DIcons.thumbtack,
    'pinned.disabled': DIcons.thumbtack,
    'pinned_globally.enabled': DIcons.thumbtack,
    'pinned_globally.disabled': DIcons.thumbtack,
    'banner.enabled': DIcons.thumbtack,
    'banner.disabled': DIcons.thumbtack,
    'visible.enabled': DIcons.farEye,
    'visible.disabled': DIcons.farEyeSlash,
    'split_topic': DIcons.rightFromBracket,
    'moved_post': DIcons.rightFromBracket,
    'invited_user': DIcons.circlePlus,
    'invited_group': DIcons.circlePlus,
    'removed_user': DIcons.circleMinus,
    'removed_group': DIcons.circleMinus,
    'user_left': DIcons.circleMinus,
    'autobumped': DIcons.handPointRight,
    'public_topic': DIcons.comment,
    'private_topic': DIcons.envelope,
    'open_topic': DIcons.comment,
    'forwarded': DIcons.envelope,
  };
}

/// A moderator notice in the post stream — "Martin Brennan closed this topic".
///
/// Kept to one muted line so it reads as an aside next to the posts around it.
/// Some small actions carry a message of their own (a close reason, say); that
/// is drawn underneath.
class SmallActionTile extends StatelessWidget {
  const SmallActionTile({super.key, required this.post, this.siteUrl});

  final Post post;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final description = SmallActionDescription.of(
      post,
      registry: PluginScope.maybeOf(context)?.registry,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DIcon(
                description?.icon ?? SmallActionDescription.fallbackIcon,
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
                siteUrl: siteUrl,
              ),
            ),
        ],
      ),
    );
  }
}
