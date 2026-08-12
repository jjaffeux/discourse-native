import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../shell/shell_scope.dart';
import 'reaction.dart';
import 'reaction_pill.dart';
import 'reactions_controller.dart';

export 'reaction_pill.dart' show ReactionPill, ReactionPills;

/// What people gave a post, under the post itself.
///
/// Topic owns the post-reaction records and API callbacks. The row, pills,
/// hover panel, touch sheet and reactor rows are shared with chat through
/// [ReactionPills], [ReactionPill] and [ReactionUsersList].
class ReactionsRow extends StatelessWidget {
  const ReactionsRow({super.key, required this.siteUrl, required this.post});

  final String siteUrl;
  final Post post;

  @override
  Widget build(BuildContext context) {
    final reactions = post.reactions;
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

    final controller = ShellScope.identityOf(context);
    return ReactionPills(
      children: [
        for (final entry in reactions.entries)
          ReactionPill(
            siteUrl: siteUrl,
            reaction: entry.id,
            count: entry.count,
            selected: reactions.mine?.id == entry.id,
            onTapHint: _tapHint(entry.id),
            interactionOwner: controller,
            onToggle: post.canReact
                ? () => controller.toggleReaction(
                    post,
                    entry.id,
                    siteUrl: siteUrl,
                  )
                : null,
            loadReactors: () => controller.reactions.load(
              siteUrl: siteUrl,
              postId: post.id,
              filter: entry.id,
            ),
            reactorsBuilder: (_) =>
                ReactorList(siteUrl: siteUrl, post: post, filter: entry.id),
          ),
      ],
    );
  }

  String _tapHint(String reaction) {
    if (!post.canReact) return 'show who reacted';
    return switch (post.reactions?.mine?.id) {
      final id when id == reaction => 'remove your reaction',
      null => 'add this reaction',
      _ => 'change your reaction to $reaction',
    };
  }
}

/// Topic's adapter into the shared reactor-list presentation.
class ReactorList extends StatelessWidget {
  const ReactorList({
    super.key,
    required this.siteUrl,
    required this.post,
    this.filter,
  });

  final String siteUrl;
  final Post post;
  final String? filter;

  @override
  Widget build(BuildContext context) => ShellSelector<ReactionsController>(
    select: (controller) => controller.reactions,
    builder: (context, reactions, _) => ReactionUsersList(
      siteUrl: siteUrl,
      source: reactions,
      query: (siteUrl: siteUrl, postId: post.id, filter: filter),
      select: () => (
        reactors: reactions.reactors(siteUrl, post.id, filter: filter),
        error: reactions.error(siteUrl, post.id, filter: filter),
      ),
      load: () =>
          reactions.load(siteUrl: siteUrl, postId: post.id, filter: filter),
    ),
  );
}
