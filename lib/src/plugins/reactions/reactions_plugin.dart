import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/live_refresh_id.dart';
import '../../models/post.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/post_action.dart';
import '../../theme/d_icons.dart';
import 'reaction.dart';
import 'reaction_picker.dart';
import 'reactions_notifications.dart';
import 'reactions_row.dart';
import 'reactions_services.dart';
import 'reactions_settings.dart';

export 'reactions_settings.dart';

/// Reactions posts must use the plugin toggle route, never `/post_actions`;
/// the latter can orphan the reaction while removing its shadow like.
class ReactionsPlugin
    implements
        SitePlugin,
        SiteSettingsPlugin<ReactionsSettings>,
        PostRecordPlugin<Reactions>,
        PostFooterPlugin,
        PostMenuPlugin,
        NotificationTypePlugin,
        TopicLivePlugin {
  const ReactionsPlugin();

  @override
  String get name => 'discourse-reactions';

  @override
  List<PluginNotificationType> get notificationTypes =>
      reactionsNotificationTypes;

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

  static String _channelFor(int topicId) => '/topic/$topicId/reactions';

  @override
  List<String> topicChannels(int topicId) => [_channelFor(topicId)];

  // Events omit counts, and every plugin hook receives every topic channel.
  @override
  List<int> stalePosts(String channel, Object? data) {
    if (!channel.startsWith('/topic/') || !channel.endsWith('/reactions')) {
      return const [];
    }
    if (data is! Map) return const [];
    final postId = liveRefreshId(data['post_id']);
    return postId == null ? const [] : [postId];
  }

  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final context = menu.buildContext;
    final siteUrl = menu.siteUrl;
    final post = menu.post;
    if (!post.hasReactions) return PostMenuContribution.none;
    // Never fall back to a Like write against the wrong table.
    if (!post.canReact) return const PostMenuContribution(replacesLike: true);

    final controller = PluginUiScope.require(
      context,
      reactionsControllerService,
    );
    final emoji = PluginUiScope.require(context, reactionsEmojiHostService);
    final writeInFlight = controller.writeInFlight(siteUrl, post.id);

    return PostMenuContribution(
      replacesLike: true,
      entries: [
        PostAction(
          icon: DIcons.farFaceSmile,
          placement: PostActionPlacement.toolbar,
          label: 'React',
          tooltip: 'React to this post',
          enabled: !writeInFlight,
          onInvoke: () => unawaited(
            showPostReactionPicker(context, controller, emoji, siteUrl, post),
          ),
          onInvokeAnchored: (anchor) => unawaited(
            showPostReactionPicker(
              context,
              controller,
              emoji,
              siteUrl,
              post,
              anchor: anchor,
            ),
          ),
        ),
      ],
      rebuildOn: controller,
    );
  }
}
