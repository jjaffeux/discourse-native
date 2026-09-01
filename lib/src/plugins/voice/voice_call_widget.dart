import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import 'voice_plugin.dart';
import 'voice_room_view.dart';
import 'voice_services.dart';
import 'voice_shell_service.dart';

class VoiceCallWidget extends StatelessWidget {
  const VoiceCallWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PluginUiScope.require(context, voiceControllerService);
    final shell = PluginUiScope.require(context, voiceShellService);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final call = controller.call;
        if (call == null) return const SizedBox.shrink();
        return SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.bottomRight,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (call.media.localVideoTrack case final track?) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: SizedBox(
                            width: 56,
                            height: 40,
                            child: VoiceVideoSurface(track: track),
                          ),
                        ),
                      ] else
                        const DIcon(DIcons.microphoneLines, size: 22),
                      const SizedBox(width: 10),
                      Flexible(
                        child: InkWell(
                          onTap: () => shell.openRoom(
                            siteUrl: call.siteUrl,
                            route: ContentRoute(
                              id: VoicePlugin.routeId(call.room.id),
                              title: call.room.name,
                              icon: DIcons.microphoneLines,
                              subtitle: call.siteName,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                call.room.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${call.siteName} · ${call.room.participants.length} present',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: call.muted ? 'Unmute' : 'Mute',
                        onPressed: () => controller.setMuted(!call.muted),
                        icon: DIcon(
                          call.muted
                              ? DIcons.microphoneSlash
                              : DIcons.microphoneLines,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Leave room',
                        onPressed: controller.leave,
                        icon: DIcon(
                          DIcons.phoneSlash,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
