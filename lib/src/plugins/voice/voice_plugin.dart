import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import '../../models/user_card.dart';

import 'voice_call_widget.dart';
import 'voice_hashtag.dart';
import 'voice_incoming_call.dart';
import 'voice_join.dart';
import 'voice_models.dart';
import 'voice_notices.dart';
import 'voice_notifications.dart';
import 'voice_room_view.dart';
import 'voice_services.dart';
import 'voice_settings.dart';
import 'voice_shell_service.dart';
import 'voice_user_card.dart';

final class VoicePlugin
    implements
        SitePlugin,
        SidebarPlugin,
        ContentPlugin,
        ShellOverlayPlugin,
        NotificationTypePlugin,
        SiteSettingsPlugin<VoiceClientConfig>,
        HashtagKindPlugin,
        UserCardRecordPlugin<VoiceUserCardData>,
        UserCardActionPlugin,
        PluginSiteFeature {
  const VoicePlugin();

  static String routeId(int roomId) => 'voice-room-$roomId';

  static int? roomIdIn(String routeId) {
    const prefix = 'voice-room-';
    return routeId.startsWith(prefix)
        ? int.tryParse(routeId.substring(prefix.length))
        : null;
  }

  @override
  String get name => 'voice';

  @override
  List<PluginNotificationType> get notificationTypes => voiceNotificationTypes;

  @override
  List<PluginHashtagKind> get hashtagKinds => const [voiceRoomHashtagKind];

  @override
  PluginDataPersistenceCodec<VoiceClientConfig> get siteSettingsCodec =>
      voiceSettingsPersistenceCodec;

  @override
  VoiceClientConfig readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => VoiceClientConfig.fromSettings(json);

  @override
  bool siteFeatureEnabled(PluginData siteSettings) =>
      siteSettings.voiceSettings.enabled;

  @override
  PluginDataKey<VoiceUserCardData> get record => voiceUserCardKey;

  /// Serializer presence is the gate: the site only writes `voice_can_call`
  /// for viewers allowed to start calls, and it already folds in whether
  /// this particular user may be rung.
  @override
  VoiceUserCardData? readUserCard(Map<String, dynamic> json, String siteUrl) =>
      json.containsKey('voice_can_call')
      ? VoiceUserCardData(canCall: json['voice_can_call'] == true)
      : null;

  @override
  List<Widget> userCardActions(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) {
    if (user.plugins.get(voiceUserCardKey)?.canCall != true) return const [];
    final controller = PluginUiScope.require(context, voiceControllerService);
    if (!controller.supportedPlatform) return const [];
    return [
      VoiceUserCardCallButton(siteUrl: siteUrl, user: user, close: close),
    ];
  }

  @override
  List<SidebarSection> sidebarSections(BuildContext context) {
    final controller = PluginUiScope.require(context, voiceControllerService);
    final shell = PluginUiScope.require(context, voiceShellService);
    if (!controller.supportedPlatform) return const [];
    final instance = shell.currentInstance;
    if (instance == null || !instance.isConnected) return const [];
    final directory = controller.directory(instance.url);
    if (directory == null || directory.rooms.isEmpty) return const [];

    return [
      SidebarSection(
        id: 'voice-rooms',
        title: 'Voice rooms',
        actionIcon: DIcons.plus,
        actionLabel: 'Create voice room',
        onAction: directory.canCreateRoom
            ? () => showVoiceRoomEditor(context, siteUrl: instance.url)
            : null,
        destinations: [
          for (final room in directory.rooms) ...[
            SidebarDestination(
              id: routeId(room.id),
              label: room.name,
              icon: room.type == VoiceRoomType.stage
                  ? DIcons.earListen
                  : DIcons.microphoneLines,
              trailingLabel: room.participants.isEmpty
                  ? null
                  : '${room.participants.length}',
              onTap: () async {
                final replaceRoomPage =
                    roomIdIn(shell.currentContent?.id ?? '') != null;
                await joinVoiceRoom(
                  context,
                  controller: controller,
                  siteUrl: instance.url,
                  siteName: instance.title,
                  room: room,
                  meshPrivacyWarningEnabled: shell.meshPrivacyWarningEnabledFor(
                    instance.url,
                  ),
                );
                final call = controller.call;
                if (replaceRoomPage &&
                    call?.siteUrl == instance.url &&
                    call?.room.id == room.id) {
                  shell.openRoom(
                    siteUrl: instance.url,
                    route: ContentRoute(
                      id: routeId(room.id),
                      title: room.name,
                      icon: DIcons.microphoneLines,
                    ),
                    replaceCurrent: true,
                  );
                }
              },
              onSecondaryTap: () => shell.openRoom(
                siteUrl: instance.url,
                route: ContentRoute(
                  id: routeId(room.id),
                  title: room.name,
                  icon: DIcons.microphoneLines,
                ),
              ),
            ),
            for (final participant in room.participants)
              SidebarDestination(
                id: 'voice-room-${room.id}-user-${participant.id}',
                label: participant.name ?? participant.username,
                icon: DIcons.user,
                avatarUrl: participant.avatarUrl(instance.url),
                trailingLabel: participant.handRaisedAt != null
                    ? '✋'
                    : participant.muted
                    ? 'muted'
                    : null,
                indent: 1,
                enabled: false,
              ),
          ],
        ],
      ),
    ];
  }

  @override
  Listenable sidebarListenable(BuildContext context) =>
      PluginUiScope.require(context, voiceControllerService);

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final roomId = roomIdIn(route.id);
    if (roomId == null) return null;
    return VoiceRoomView(roomId: roomId);
  }

  @override
  List<Widget> shellOverlays(BuildContext context) => [
    Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: VoiceCallWidget(
          port: PluginUiScope.require(context, voiceCallPortService),
        ),
      ),
    ),
    Positioned.fill(
      child: VoiceIncomingCallBanner(
        controller: PluginUiScope.require(context, voiceControllerService),
        shell: PluginUiScope.require(context, voiceShellService),
      ),
    ),
    Positioned.fill(
      child: IgnorePointer(
        child: VoiceNoticeHost(
          notices: PluginUiScope.require(
            context,
            voiceControllerService,
          ).notices,
        ),
      ),
    ),
  ];
}
