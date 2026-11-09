import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_comments.dart';
import 'post_voting_data.dart';
import 'post_voting_reader.dart';
import 'post_voting_services.dart';

final class PostVotingPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        SiteSettingsPlugin<PostVotingSettings>,
        PluginSiteFeature,
        TopicRecordPlugin<PostVotingTopicData>,
        TopicReaderPlugin,
        TopicListMetadataPlugin,
        TopicMenuPlugin,
        NotificationTypePlugin {
  const PostVotingPlugin();
  @override
  String get name => postVotingPluginId.value;
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory => PostVotingPlugin.new;
  @override
  PluginDataKey<PostVotingTopicData> get record => postVotingTopicKey;
  @override
  PluginDataPersistenceCodec<PostVotingSettings> get siteSettingsCodec =>
      const PostVotingSettingsCodec();
  @override
  PostVotingSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => PostVotingSettings.fromJson(json);
  @override
  bool siteFeatureEnabled(PluginData siteSettings) =>
      siteSettings.get(postVotingSettingsKey)?.enabled == true;
  @override
  PostVotingTopicData? readTopic(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) => PostVotingTopicData.fromContext(json, context);
  @override
  bool readsTopic(TopicReaderProbe probe) =>
      (probe.config.plugins.get(postVotingSettingsKey) ??
              const PostVotingSettings())
          .allowsTopic(
            probe.topic.plugins.get(postVotingTopicKey),
            privateMessage: probe.topic.privateMessage,
          );
  PostVotingServices _service(BuildContext context) =>
      PluginUiScope.require(context, postVotingServicesKey);
  @override
  Widget buildTopicReader(BuildContext context, PluginTopicReader reader) {
    final service = _service(context);
    service.activatePluginSite(reader.siteUrl, connected: reader.isConnected);
    return PostVotingReader(
      key: ValueKey((reader, service.actions.epochFor(reader.siteUrl))),
      reader: reader,
      services: service,
    );
  }

  @override
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  ) {
    final service = _service(context),
        data = topic.plugins.get(postVotingTopicKey);
    if (!service
        .settingsFor(siteUrl)
        .allowsTopic(data, privateMessage: topic.privateMessage)) {
      return const [];
    }
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          const DIcon(DIcons.chevronDown, size: 12),
          Text(
            data?.answerCount == null
                ? context.l10n.postVotingTitle
                : context.l10n.postVotingAnswerCount(data!.answerCount!),
          ),
          if (data?.lastAnswerer?.username case final name?) Text(name),
        ],
      ),
    ];
  }

  @override
  List<TopicMenuAction> topicMenuActions(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) {
    final service = _service(context);
    if (service.settingsFor(siteUrl).enabled != true ||
        service.siteState.currentUserFor(siteUrl) == null ||
        topic.privateMessage) {
      return const [];
    }
    return [
      if (service.siteState.currentUserFor(siteUrl)?.admin == true)
        TopicMenuAction(
          label: context.l10n.postVotingSiteSettings,
          icon: DIcons.gear,
          onSelected: (_) => unawaited(
            openExternalLink(
              '$siteUrl/admin/site_settings/category/plugins?filter=post_voting',
            ),
          ),
        ),
    ];
  }

  @override
  List<PluginNotificationType> get notificationTypes => const [
    PluginNotificationType(
      id: PluginNotificationTypeId(owner: postVotingPluginId, name: 'comment'),
      wireType: NotificationWireType(35, 'question_answer_user_commented'),
      decode: _notification,
    ),
  ];
  static ResolvedNotification? _notification(
    String site,
    DiscourseNotification notification,
  ) {
    final comment = notification.data['post_voting_comment_id'];
    final path = notificationTopicPath(notification);
    if (comment is! int || comment <= 0 || path == null) return null;
    final actor = notification.data['display_username'];
    return ResolvedNotification(
      presentation: NotificationPresentation(
        icon: DIcons.comment,
        actor: actor is String ? actor : appL10n.someone,
        phrase: appL10n
            .postVotingCommentNotification('', notification.title)
            .trimLeft(),
      ),
      path: Uri.parse(
        path,
      ).replace(fragment: 'post-voting-comment-$comment').toString(),
    );
  }
}

final class PostVotingPostPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        PostRecordPlugin<PostVotingPostData>,
        PostMenuPlugin,
        PostDecorationPlugin {
  const PostVotingPostPlugin();
  @override
  String get name => postVotingPluginId.value;
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      PostVotingPostPlugin.new;
  @override
  PluginDataKey<PostVotingPostData> get record => postVotingPostKey;
  @override
  PostVotingPostData? readPost(Map<String, dynamic> json, String siteUrl) {
    final value = PostVotingPostData.fromJson(json);
    return value.hasData ? value : null;
  }

  @override
  PostVotingPostData? mergeAfterPostEdit(
    PostVotingPostData? held,
    PostVotingPostData? incoming,
  ) => incoming == null ? held : held?.merge(incoming) ?? incoming;
  @override
  PostMenuContribution postMenu(PostMenuContext menu) {
    final service = PluginUiScope.require(
          menu.buildContext,
          postVotingServicesKey,
        ),
        topic = menu.topic;
    if (topic == null ||
        !service
            .settingsFor(menu.siteUrl)
            .allowsTopic(
              topic.plugins.get(postVotingTopicKey),
              privateMessage: topic.privateMessage,
            )) {
      return PostMenuContribution.none;
    }
    final answer = menu.post.postNumber != 1,
        noLikes =
            answer && !service.settingsFor(menu.siteUrl).answerLikesEnabled;
    return PostMenuContribution(
      rebuildOn: service,
      replacesReply: true,
      replacesLike: noLikes,
      suppressesReactions: noLikes,
      entries: [
        if (!answer && topic.canCreatePost)
          PostAction(
            icon: DIcons.reply,
            label: appL10n.answer,
            tooltip: appL10n.answer,
            enabled: !topic.closed && !topic.archived,
            onInvoke: () {
              final reader = service.readers.forVisibleTopic(
                menu.siteUrl,
                topic.id,
              );
              if (reader == null) return;
              try {
                reader.reply();
              } finally {
                reader.close();
              }
            },
          ),
      ],
    );
  }

  @override
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) {
    final service = PluginUiScope.require(context, postVotingServicesKey);
    if (!service
            .settingsFor(siteUrl)
            .allowsTopic(
              topic.plugins.get(postVotingTopicKey),
              privateMessage: topic.privateMessage,
            ) ||
        !service.settingsFor(siteUrl).commentsEnabled ||
        post.plugins.get(postVotingPostKey)?.canHaveComments == false ||
        post.isSmallAction ||
        post.contentRedacted ||
        post.isDeleted) {
      return const [];
    }
    return [
      PostVotingComments(
        key: ValueKey((
          'post-voting-comments',
          siteUrl,
          topic.id,
          post.id,
          service.actions.epochFor(siteUrl),
        )),
        services: service,
        siteUrl: siteUrl,
        topicId: topic.id,
        postId: post.id,
      ),
    ];
  }
}

final class PostVotingCategoryPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        CategoryRecordPlugin<PostVotingCategoryData> {
  const PostVotingCategoryPlugin();
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory =>
      PostVotingCategoryPlugin.new;
  @override
  String get name => postVotingPluginId.value;
  @override
  PluginDataKey<PostVotingCategoryData> get record => postVotingCategoryKey;
  @override
  PostVotingCategoryData? readCategory(
    Map<String, dynamic> json,
    String siteUrl, {
    TopicRecordDecodeContext context = const TopicRecordDecodeContext.partial(),
  }) {
    final fields = json['custom_fields'];
    return json.containsKey('create_as_post_voting_default') ||
            json.containsKey('only_post_voting_in_this_category') ||
            fields is Map &&
                (fields.containsKey('create_as_post_voting_default') ||
                    fields.containsKey('only_post_voting_in_this_category'))
        ? PostVotingCategoryData.fromJson(json)
        : null;
  }
}

final class PostVotingActorCodec
    extends PluginDataPersistenceCodec<PostVotingActor> {
  const PostVotingActorCodec();
  @override
  PluginDataKey<PostVotingActor> get key => postVotingCurrentUserKey;
  @override
  PostVotingActor? decode(Object? value) => value is Map
      ? PostVotingActor.fromJson(Map<String, dynamic>.from(value))
      : null;
  @override
  Object encode(PostVotingActor value) => {
    'can_flag_post_voting_comments': value.canFlagComments,
  };
}

final class PostVotingUserPlugin
    implements
        SitePlugin,
        CurrentUserPlugin<PostVotingActor>,
        UserCardRecordPlugin<PostVotingUserScore>,
        UserCardMetadataPlugin {
  const PostVotingUserPlugin();
  @override
  String get name => postVotingPluginId.value;
  @override
  PluginDataKey<PostVotingUserScore> get record => postVotingUserCardKey;
  @override
  PluginDataPersistenceCodec<PostVotingActor> get currentUserCodec =>
      const PostVotingActorCodec();
  @override
  PostVotingActor? readCurrentUser(Map<String, dynamic> json, String siteUrl) =>
      json.containsKey('can_flag_post_voting_comments')
      ? PostVotingActor.fromJson(json)
      : null;
  @override
  PostVotingUserScore? readUserCard(
    Map<String, dynamic> json,
    String siteUrl,
  ) => PostVotingUserScore.fromJson(json);
  @override
  List<Widget> userCardMetadata(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) {
    final score = user.plugins.get(postVotingUserCardKey);
    return score == null ||
            PluginUiScope.require(
                  context,
                  postVotingServicesKey,
                ).settingsFor(siteUrl).enabled ==
                false
        ? const []
        : [Text(context.l10n.postVotingReceivedScore(score.receivedNetScore))];
  }
}
