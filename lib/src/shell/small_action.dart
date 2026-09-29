import 'package:discourse_native/discourse_ui.dart' show DAvatar;
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'relative_time.dart';

@immutable
class SmallActionDescription {
  const SmallActionDescription({required this.icon, required this.phrase});

  final DIconData icon;

  final String phrase;

  static SmallActionDescription? of(Post post, {PluginRegistry? registry}) {
    if ((registry ?? PluginRegistry.empty).smallAction(post)
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
      'closed.enabled' || 'autoclosed.enabled' => appL10n.closedThisTopic,
      'closed.disabled' || 'autoclosed.disabled' => appL10n.openedThisTopic,
      'archived.enabled' => appL10n.archivedThisTopic,
      'archived.disabled' => appL10n.unarchivedThisTopic,
      'pinned.enabled' => appL10n.pinnedThisTopic,
      'pinned.disabled' => appL10n.unpinnedThisTopic,
      'pinned_globally.enabled' => appL10n.pinnedThisTopicGlobally,
      'pinned_globally.disabled' => appL10n.unpinnedThisTopicGlobally,
      'banner.enabled' => appL10n.madeThisTopicABanner,
      'banner.disabled' => appL10n.removedThisBanner,
      'visible.enabled' => appL10n.listedThisTopic,
      'visible.disabled' => appL10n.unlistedThisTopic,
      'split_topic' => appL10n.splitThisTopic,
      'moved_post' => appL10n.movedThisPost,
      'invited_user' ||
      'invited_group' => appL10n.invitedSmallaction((subject).toString()),
      'removed_user' ||
      'removed_group' => appL10n.removed((subject).toString()),
      'user_left' => appL10n.removedThemselvesFromThisMessage,
      'autobumped' => appL10n.automaticallyBumpedThisTopic,
      'public_topic' => appL10n.madeThisTopicPublic,
      'private_topic' => appL10n.madeThisTopicAPersonalMessage,
      'open_topic' => appL10n.convertedThisToATopic,
      'forwarded' => appL10n.forwardedTheAboveEmail,
      // Plugins add action codes of their own, and Discourse adds new ones
      // between releases. An unknown code still names what happened, so read
      // it out rather than dropping the notice.
      _ => code.replaceAll(RegExp(r'[._]'), ' '),
    };
  }

  static const DIconData fallbackIcon = DIcons.exclamation;

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
              DAvatar.frame(
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
                RelativeTimeText(
                  createdAt,
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
