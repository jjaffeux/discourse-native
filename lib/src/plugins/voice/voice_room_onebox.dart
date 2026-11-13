import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'voice_models.dart';
import 'voice_room_onebox_data.dart';
import 'voice_services.dart';

export 'voice_room_onebox_data.dart';

final class VoiceRoomOnebox extends StatelessWidget {
  const VoiceRoomOnebox({super.key, required this.data, this.siteUrl});

  final VoiceRoomOneboxData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final controller = PluginUiScope.maybe(context, voiceControllerService);
    final site = siteUrl;
    if (controller == null || site == null || data.localSlug == null) {
      return VoiceRoomOneboxCard(data: data, siteUrl: siteUrl);
    }
    return ListenableBuilder(
      listenable: controller.roomListenable,
      builder: (context, _) {
        final room = controller
            .directory(site)
            ?.rooms
            .where((room) => room.slug == data.localSlug && !room.ephemeral)
            .firstOrNull;
        return VoiceRoomOneboxCard(
          data: data,
          siteUrl: siteUrl,
          participants: room?.participants ?? const [],
        );
      },
    );
  }
}

/// The native card composition shared by cooked content and the styleguide.
final class VoiceRoomOneboxCard extends StatelessWidget {
  const VoiceRoomOneboxCard({
    super.key,
    required this.data,
    this.siteUrl,
    this.participants = const [],
  });

  final VoiceRoomOneboxData data;
  final String? siteUrl;
  final List<VoiceParticipant> participants;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
    child: DCard(
      size: DCardSize.small,
      children: [
        DCardHeader(
          title: DButton(
            isLink: true,
            variant: DButtonVariant.link,
            alignment: AlignmentDirectional.centerStart,
            icon: DIcon(data.stage ? DIcons.earListen : DIcons.microphoneLines),
            label: Text(data.name),
            onPressed: () =>
                unawaited(openLink(context, data.url, siteUrl: siteUrl)),
          ),
          description: data.type.isEmpty
              ? null
              : DCardDescription(child: Text(data.type)),
        ),
        if (data.descriptionHtml.isNotEmpty)
          DCardContent(
            child: CookedHtml(html: data.descriptionHtml, siteUrl: siteUrl),
          ),
        if (participants.isNotEmpty)
          DCardContent(
            child: Wrap(
              spacing: DSpacing.sm,
              runSpacing: DSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DAvatarGroup(
                  size: DAvatarSize.sm,
                  children: [
                    for (final participant in participants.take(5))
                      DAvatar(
                        size: DAvatarSize.sm,
                        decorative: true,
                        child: AvatarImage(
                          url: siteUrl == null
                              ? null
                              : participant.avatarUrl(siteUrl!, size: 48),
                          size: DAvatarSize.sm.dimension,
                          fallback: DAvatarFallback(
                            child: Text(
                              participant.username.isEmpty
                                  ? '?'
                                  : participant.username.characters.first,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(context.l10n.voiceRoomHereNow(participants.length)),
              ],
            ),
          ),
      ],
    ),
  );
}
