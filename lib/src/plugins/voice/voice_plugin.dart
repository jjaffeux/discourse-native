import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import 'voice_call_widget.dart';
import 'voice_hashtag.dart';
import 'voice_models.dart';
import 'voice_room_view.dart';
import 'voice_services.dart';
import 'voice_settings.dart';
import 'voice_shell_service.dart';

final class VoicePlugin
    implements
        SitePlugin,
        SidebarPlugin,
        ContentPlugin,
        ShellOverlayPlugin,
        SiteSettingsPlugin<VoiceClientConfig>,
        HashtagKindPlugin,
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
                await controller.join(
                  siteUrl: instance.url,
                  siteName: instance.title,
                  room: room,
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
  List<Widget> shellOverlays(BuildContext context) => const [
    Positioned.fill(
      child: IgnorePointer(ignoring: false, child: VoiceCallWidget()),
    ),
  ];
}
