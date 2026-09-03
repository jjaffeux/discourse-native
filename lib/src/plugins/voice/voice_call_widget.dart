import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import 'voice_call_port.dart';

class VoiceCallWidget extends StatelessWidget {
  const VoiceCallWidget({super.key, required this.port});

  final VoiceCallPort port;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: port,
    builder: (context, _) {
      final state = port.state;
      final call = state.call;
      if (!state.supported || call == null) {
        return const SizedBox.shrink();
      }
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
                    if (call.localVideoPreview case final preview?) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: SizedBox(width: 56, height: 40, child: preview),
                      ),
                    ] else
                      const DIcon(DIcons.microphoneLines, size: 22),
                    const SizedBox(width: 10),
                    Flexible(
                      child: InkWell(
                        onTap: () => port.dispatch(VoiceCallAction.openRoom),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (call.recording) ...[
                                  Tooltip(
                                    message: 'Recording',
                                    child: DIcon(
                                      DIcons.circle,
                                      size: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(
                                    call.roomName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${call.siteName} · ${call.participantCount} present',
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
                      onPressed: () =>
                          port.dispatch(VoiceCallAction.toggleMuted),
                      icon: DIcon(
                        call.muted
                            ? DIcons.microphoneSlash
                            : DIcons.microphoneLines,
                        size: 18,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Leave room',
                      onPressed: () => port.dispatch(VoiceCallAction.leave),
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
