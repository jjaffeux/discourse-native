import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'user_notes_controller.dart';
import 'user_notes_data.dart';
import 'user_notes_entry.dart';
import 'user_notes_sheet.dart';

final class UserNotesPlugin
    implements
        SitePlugin,
        IsolateTopicDecoderPlugin,
        SiteSettingsPlugin<UserNotesSettings>,
        PluginSiteFeature,
        PostRecordPlugin<UserNotesCount>,
        UserCardRecordPlugin<UserNotesCount>,
        UserCardIdentityDecorationPlugin,
        PostAuthorDecorationPlugin,
        PostMenuPlugin {
  const UserNotesPlugin();
  @override
  String get name => userNotesPluginId.value;
  @override
  SitePlugin Function()? get isolateTopicDecoderFactory => UserNotesPlugin.new;
  @override
  PluginDataKey<UserNotesCount> get record => userNotesCountKey;
  @override
  PluginDataPersistenceCodec<UserNotesSettings> get siteSettingsCodec =>
      const UserNotesSettingsCodec();
  @override
  UserNotesSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => UserNotesSettings.read(json);
  @override
  bool siteFeatureEnabled(PluginData siteSettings) =>
      siteSettings.get(userNotesSettingsKey)?.enabled == true;
  @override
  UserNotesCount? readPost(Map<String, dynamic> json, String siteUrl) =>
      UserNotesCount.read(json, post: true);
  @override
  UserNotesCount? readUserCard(Map<String, dynamic> json, String siteUrl) =>
      UserNotesCount.read(json);
  @override
  UserNotesCount? mergeAfterPostEdit(
    UserNotesCount? held,
    UserNotesCount? incoming,
  ) => incoming ?? held;
  UserNotesController? _observe(BuildContext context, String siteUrl) {
    final controller = PluginUiScope.maybe(context, userNotesControllerService);
    controller?.observe(siteUrl);
    return controller;
  }

  @override
  Listenable? postAuthorDecorationsListenable(
    BuildContext context,
    String siteUrl,
    Post post,
  ) => _observe(context, siteUrl);

  @override
  Listenable? userCardIdentityDecorationsListenable(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => _observe(context, siteUrl);

  @override
  List<Widget> userCardIdentityDecorations(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) {
    final controller = PluginUiScope.maybe(context, userNotesControllerService),
        userId = user.id;
    if (controller == null ||
        userId == null ||
        userId == 0 ||
        !controller.canOpen(siteUrl)) {
      return const [];
    }
    final count = controller.count(
      siteUrl,
      userId,
      fallback: user.plugins.get(userNotesCountKey)?.value,
    );
    if (count == null || count <= 0) return const [];
    return [
      UserNotesEntry(
        controller: controller,
        siteUrl: siteUrl,
        userId: userId,
        username: user.username,
        count: user.plugins.get(userNotesCountKey)?.value,
      ),
    ];
  }

  @override
  List<PostAuthorDecoration> postAuthorDecorations(
    BuildContext context,
    String siteUrl,
    Post post,
  ) {
    final controller = PluginUiScope.maybe(context, userNotesControllerService),
        userId = post.userId;
    if (controller == null ||
        userId == null ||
        userId == 0 ||
        !controller.canOpen(siteUrl)) {
      return const [];
    }
    final count = controller.count(
      siteUrl,
      userId,
      fallback: post.plugins.get(userNotesCountKey)?.value,
    );
    if (count == null || count <= 0) return const [];
    final placement =
        controller.settings(siteUrl).placement == UserNotesPlacement.avatar
        ? PostAuthorDecorationPlacement.afterAvatar
        : context.isTouch
        ? PostAuthorDecorationPlacement.beforeName
        : PostAuthorDecorationPlacement.afterName;
    return [
      PostAuthorDecoration(
        placement: placement,
        child: UserNotesEntry(
          controller: controller,
          siteUrl: siteUrl,
          userId: userId,
          username: post.username,
          postId: post.id,
          count: count,
          placement: placement,
        ),
      ),
    ];
  }

  @override
  PostMenuContribution postMenu(PostMenuContext context) {
    final controller = PluginUiScope.maybe(
          context.buildContext,
          userNotesControllerService,
        ),
        userId = context.post.userId;
    if (controller == null ||
        userId == null ||
        userId == 0 ||
        !controller.canOpen(context.siteUrl)) {
      return PostMenuContribution.none;
    }
    return PostMenuContribution(
      rebuildOn: controller,
      entries: [
        PostAction(
          icon: DIcons.penToSquare,
          label: appL10n.userNotesAdd,
          tooltip: appL10n.userNotesPrivate,
          group: PostActionGroup.staff,
          placement: PostActionPlacement.overflow,
          onInvoke: () => unawaited(
            showUserNotes(
              context: context.buildContext,
              controller: controller,
              siteUrl: context.siteUrl,
              userId: userId,
              username: context.post.username,
              postId: context.post.id,
            ),
          ),
        ),
      ],
    );
  }
}
