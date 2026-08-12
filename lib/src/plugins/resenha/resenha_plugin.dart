import 'package:flutter/material.dart';

import '../../models/content_route.dart';
import '../../models/sidebar.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../site_plugin_api.dart';
import 'resenha_models.dart';
import 'resenha_room_view.dart';

final class ResenhaPlugin implements SitePlugin, SidebarPlugin, ContentPlugin {
  const ResenhaPlugin();

  static String routeId(int roomId) => 'resenha-room-$roomId';

  static int? roomIdIn(String routeId) {
    const prefix = 'resenha-room-';
    return routeId.startsWith(prefix)
        ? int.tryParse(routeId.substring(prefix.length))
        : null;
  }

  @override
  String get name => 'resenha';

  @override
  List<SidebarSection> sidebarSections(BuildContext context) {
    final shell = ShellScope.read(context);
    if (!shell.resenha.supportedPlatform) return const [];
    final instance = shell.currentInstance;
    if (instance == null || !instance.isConnected) return const [];
    final controller = shell.resenha;
    final directory = controller.directory(instance.url);
    if (directory == null || directory.rooms.isEmpty) return const [];

    return [
      SidebarSection(
        id: 'voice-rooms',
        title: 'Voice rooms',
        actionIcon: DIcons.plus,
        actionLabel: 'Create voice room',
        onAction: directory.canCreateRoom
            ? () => showResenhaRoomEditor(context, siteUrl: instance.url)
            : null,
        destinations: [
          for (final room in directory.rooms)
            SidebarDestination(
              id: routeId(room.id),
              label: room.name,
              icon: room.type == ResenhaRoomType.stage
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
                  shell.openResenhaRoom(
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
              onSecondaryTap: () => shell.openResenhaRoom(
                siteUrl: instance.url,
                route: ContentRoute(
                  id: routeId(room.id),
                  title: room.name,
                  icon: DIcons.microphoneLines,
                ),
              ),
              children: [
                for (final participant in room.participants)
                  SidebarDestination(
                    id: 'resenha-room-${room.id}-user-${participant.id}',
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
            ),
        ],
      ),
    ];
  }

  @override
  Listenable sidebarListenable(BuildContext context) =>
      ShellScope.read(context).resenha;

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final roomId = roomIdIn(route.id);
    if (roomId == null) return null;
    return ResenhaRoomView(roomId: roomId);
  }
}
