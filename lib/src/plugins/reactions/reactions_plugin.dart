import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../shell/post_action.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icons.dart';
import '../site_plugin.dart';
import 'reaction.dart';
import 'reaction_picker.dart';
import 'reactions_row.dart';

/// `discourse-reactions`, as this app knows it.
///
/// The plugin lets a site's readers give a post any of a set of emoji instead
/// of only a like. The two are the same thing underneath: one of the emoji is
/// the site's *main reaction*, and giving it writes an ordinary like — which is
/// why on a site that has this, the like affordance is replaced rather than
/// joined.
///
/// **Nothing on a reactions post is ever written through `/post_actions`.**
/// Reacting with a non-excluded emoji creates a shadow like alongside the
/// reaction, so an unliking `DELETE` there destroys the like and orphans the
/// reaction — a desync only a scheduled server job repairs. Every write goes
/// through the toggle route or does not happen.
class ReactionsPlugin implements SitePlugin<Reactions> {
  const ReactionsPlugin();

  @override
  String get name => 'discourse-reactions';

  @override
  Type get record => Reactions;

  @override
  Reactions? readPost(Map<String, dynamic> json, String siteUrl) =>
      Reactions.fromJson(json);

  @override
  Widget? postFooter(Post post) =>
      post.hasReactions ? ReactionsRow(post: post) : null;

  /// Replaces Like on a post that has reactions, and offers whichever of the
  /// three things a tap can mean here.
  ///
  /// | Held | Main reaction | Icon · label | Tap |
  /// |---|---|---|---|
  /// | one | any | that emoji · "Remove your … reaction" | takes it back |
  /// | none | known | outline heart · "Like this post" | gives the main one |
  /// | none | not known | face · "React" | opens the picker |
  ///
  /// Beside those, wherever the first row is not already opening it, a
  /// "Pick a reaction" entry opens the picker: the main reaction is not the
  /// only one the site allows, and the toggle above is the only other write
  /// this menu can make, so without it the rest of `offeredReactions` would
  /// be configured and unreachable.
  ///
  /// The label comes from what they *hold*, not from
  /// `usedMainReaction`. A reader who clapped has a shadow like, so
  /// [Post.canToggleLike] is true and the naive label reads "Like this post" —
  /// on a tap that would destroy their clap and replace it. Discourse's own
  /// client labels from the held reaction for exactly this reason.
  ///
  /// The third row is why `SiteConfig.mainReaction` is nullable: the setting
  /// behind it is enum-constrained to the reactions a site allows, and `heart`
  /// is not in the default enabled list — so guessing it on a site whose admin
  /// chose `+1` earns a 422 whose body says only "Sorry, an error has
  /// occurred." A slower first interaction is better than a wrong write.
  /// The plugin publishes here whenever anyone reacts to a post in the topic.
  @override
  List<String> topicChannels(int topicId) => ['/topic/$topicId/reactions'];

  /// `{post_id, reactions: [reaction, previous_reaction]}`.
  ///
  /// No counts and no actor, so there is nothing to apply — only a post worth
  /// reading again. Which is the better answer anyway: the topic route builds
  /// `reactions` from the preloaded query, and that is the one whose numbers
  /// agree with what the row is already drawing.
  @override
  List<int> stalePosts(String channel, Object? data) {
    if (data is! Map) return const [];
    return switch (data['post_id']) {
      final num id => [id.toInt()],
      _ => const [],
    };
  }

  @override
  PostMenuContribution postMenu(BuildContext context, Post post) {
    if (!post.hasReactions) return PostMenuContribution.none;
    // Replaced even where nothing can be offered — a post the reader may not
    // react to must not fall back to a Like that writes to the wrong table.
    if (!post.canReact) return const PostMenuContribution(replacesLike: true);

    final controller = ShellScope.of(context);
    final siteUrl = controller.currentInstance?.url ?? '';
    final config = controller.currentSiteConfig;
    final held = post.reactions!.mine;
    final target = held?.id ?? config.mainReaction;

    void report(Future<String?> work) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      work.then((error) {
        if (error != null) {
          messenger?.showSnackBar(SnackBar(content: Text(error)));
        }
      });
    }

    return PostMenuContribution(
      replacesLike: true,
      entries: [
        PostAction(
          icon: held == null ? DIcons.farHeart : DIcons.heart,
          emojiUrl: held == null
              ? null
              : controller.emojiUrlFor(siteUrl, held.id),
          label: switch ((held, target)) {
            (final mine?, _) => 'Remove your ${mine.id} reaction',
            (null, final _?) => 'Like',
            _ => 'React',
          },
          tooltip: switch ((held, target)) {
            (final mine?, _) => 'Remove your ${mine.id} reaction',
            (null, final _?) => 'Like this post',
            _ => 'React to this post',
          },
          tint: held == null ? null : discourseLove,
          onInvoke: () {
            if (target == null) {
              // Nothing known to send. The picker is where a reader chooses,
              // and this is the one path that does not need the setting.
              showReactionPicker(context, post);
              return;
            }
            report(controller.toggleReaction(post, target));
          },
        ),
        if (target != null && config.offeredReactions.isNotEmpty)
          PostAction(
            icon: DIcons.farFaceSmile,
            label: 'React',
            tooltip: 'Pick a reaction',
            onInvoke: () => showReactionPicker(context, post),
          ),
      ],
    );
  }
}
