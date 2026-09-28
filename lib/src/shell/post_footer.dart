import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/post_flag.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import 'post_actions.dart';
import 'post_likes.dart';
import 'shell_scope.dart';

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
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final engagement = PostActionsFooter(
      child:
          registry.postFooter(siteUrl, post) ??
          PostLikes(siteUrl: siteUrl, post: post),
    );
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
    if (type == null) return appL10n.youFlaggedThisPost;
    return switch (type.nameKey) {
      'off_topic' => appL10n.youFlaggedThisAsOffTopic,
      'spam' => appL10n.youFlaggedThisAsSpam,
      'inappropriate' => appL10n.youFlaggedThisAsInappropriate,
      'illegal' => appL10n.youFlaggedThisAsIllegal,
      'notify_moderators' => appL10n.youFlaggedThisForModeration,
      'notify_user' => appL10n.youSentAMessageToThisUser,
      _ => appL10n.youFlaggedThisAs((type.name).toString()),
    };
  }
}
