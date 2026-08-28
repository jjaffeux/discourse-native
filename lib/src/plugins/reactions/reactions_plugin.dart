import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/post_action.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icons.dart';
import 'reaction.dart';
import 'reaction_picker.dart';
import 'reactions_row.dart';
import 'reactions_settings.dart';
import 'reactions_shell_extension.dart';

export 'reactions_settings.dart';

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
class ReactionsPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<ReactionsSettings>,
        PostRecordPlugin<Reactions>,
        PostFooterPlugin,
        PostMenuPlugin,
        TopicLivePlugin {
  const ReactionsPlugin();

  @override
  String get name => 'discourse-reactions';

  @override
  PluginDataPersistenceCodec<ReactionsSettings> get siteSettingsCodec =>
      reactionsSettingsPersistenceCodec;

  @override
  ReactionsSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => ReactionsSettings.fromSiteSettings(json);

  @override
  PluginDataKey<Reactions> get record => reactionsDataKey;

  @override
  Reactions? readPost(Map<String, dynamic> json, String siteUrl) =>
      Reactions.fromJson(json);

  @override
  Reactions? mergeAfterPostEdit(Reactions? held, Reactions? incoming) =>
      held ?? incoming;

  @override
  Widget? postFooter(String siteUrl, Post post) =>
      post.hasReactions ? ReactionsRow(siteUrl: siteUrl, post: post) : null;

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
  /// The third row is why [ReactionsSettings.mainReaction] is nullable: the
  /// setting behind it is enum-constrained to the reactions a site allows, and
  /// `heart` is not in the default enabled list — so guessing it on a site
  /// whose admin chose `+1` earns a 422 whose body says only "Sorry, an error
  /// has occurred." A slower first interaction is better than a wrong write.
  static String _channelFor(int topicId) => '/topic/$topicId/reactions';

  /// The plugin publishes here whenever anyone reacts to a post in the topic.
  @override
  List<String> topicChannels(int topicId) => [_channelFor(topicId)];

  /// `{post_id, reactions: [reaction, previous_reaction]}`.
  ///
  /// No counts and no actor, so there is nothing to apply — only a post worth
  /// reading again. Which is the better answer anyway: the topic route builds
  /// `reactions` from the preloaded query, and that is the one whose numbers
  /// agree with what the row is already drawing.
  /// Only its own channel: every plugin's hook is asked about every message on
  /// every topic channel, and `post_id` is not a key one feature may read out
  /// of another's payload. Assign publishes one for a post-level assignment,
  /// which is nothing to do with a reaction.
  @override
  List<int> stalePosts(String channel, Object? data) {
    if (!channel.startsWith('/topic/') || !channel.endsWith('/reactions')) {
      return const [];
    }
    if (data is! Map) return const [];
    return switch (data['post_id']) {
      final num id => [id.toInt()],
      _ => const [],
    };
  }

  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final context = menu.buildContext;
    final siteUrl = menu.siteUrl;
    final post = menu.post;
    if (!post.hasReactions) return PostMenuContribution.none;
    // Replaced even where nothing can be offered — a post the reader may not
    // react to must not fall back to a Like that writes to the wrong table.
    if (!post.canReact) return const PostMenuContribution(replacesLike: true);

    final controller = ShellScope.read(context);
    final config = controller.siteConfigFor(siteUrl);
    final held = post.reactions!.mine;
    final settings = config.reactionsSettings;
    final target = held?.id ?? settings.mainReaction;
    final writeInFlight = controller.postWriteInFlight(
      post.id,
      siteUrl: siteUrl,
    );

    void report(Future<String?> work) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      unawaited(
        work.then((error) {
          if (error == null || messenger == null || !messenger.mounted) return;
          if (!identical(ShellScope.maybeRead(messenger.context), controller)) {
            return;
          }
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }),
      );
    }

    return PostMenuContribution(
      replacesLike: true,
      entries: [
        PostAction(
          icon: held == null ? DIcons.farHeart : DIcons.heart,
          placement: PostActionPlacement.toolbar,
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
          tint: held == null ? null : Theme.of(context).discourse.love,
          enabled: !writeInFlight,
          onInvoke: () {
            if (target == null) {
              // Nothing known to send. The picker is where a reader chooses,
              // and this is the one path that does not need the setting.
              unawaited(showPostReactionPicker(context, siteUrl, post));
              return;
            }
            report(controller.toggleReaction(post, target, siteUrl: siteUrl));
          },
        ),
        if (target != null && settings.offeredReactions.isNotEmpty)
          PostAction(
            icon: DIcons.farFaceSmile,
            placement: PostActionPlacement.toolbar,
            label: 'React',
            tooltip: 'Pick a reaction',
            enabled: !writeInFlight,
            onInvoke: () =>
                unawaited(showPostReactionPicker(context, siteUrl, post)),
          ),
      ],
    );
  }
}
