import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_flag.dart';
import '../plugins/plugin_scope.dart';
import '../plugins/site_plugin.dart';
import 'post_likes.dart';
import 'shell_scope.dart';

/// What sits under a post: the record of what people did with it.
///
/// On plain core that is the likes, and on a site with an optional feature that
/// claims this spot it is whatever that feature draws instead. The choice is
/// made per post rather than per site, from the payload the post arrived in —
/// see [SitePlugin] for why that is the gate rather than a setting.
///
/// An ordered fallthrough with the core answer at the end, the same shape as
/// `cooked_html.dart`'s builder chain and `open_link.dart`'s dispatch.
class PostFooter extends StatelessWidget {
  const PostFooter({super.key, required this.siteUrl, required this.post});

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<List<PostFlagType>>(
      select: (controller) => controller.postFlagTypesFor(siteUrl),
      builder: (context, catalog, child) => _buildFooter(context, catalog),
    );
  }

  Widget _buildFooter(BuildContext context, List<PostFlagType> catalog) {
    final registry = PluginScope.maybeOf(context)?.registry ?? pluginRegistry;
    final engagement =
        registry.postFooter(siteUrl, post) ??
        PostLikes(siteUrl: siteUrl, post: post);
    final acted = post.actedFlagSummaries;
    if (acted.isEmpty) return engagement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        for (final summary in acted)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _actedDescription(summary, catalog),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        engagement,
      ],
    );
  }

  static String _actedDescription(
    PostActionSummary summary,
    List<PostFlagType> catalog,
  ) {
    PostFlagType? type;
    for (final candidate in catalog) {
      if (candidate.id == summary.id) {
        type = candidate;
        break;
      }
    }
    if (type == null) return 'You flagged this post';
    return switch (type.nameKey) {
      'off_topic' => 'You flagged this as off-topic',
      'spam' => 'You flagged this as spam',
      'inappropriate' => 'You flagged this as inappropriate',
      'illegal' => 'You flagged this as illegal',
      'notify_moderators' => 'You flagged this for moderation',
      'notify_user' => 'You sent a message to this user',
      _ => 'You flagged this as ${type.name}.',
    };
  }
}
