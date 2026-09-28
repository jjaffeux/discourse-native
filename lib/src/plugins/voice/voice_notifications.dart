import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'voice_icons.dart';

abstract final class VoiceNotificationTypes {
  static const invitation = NotificationWireType(1000, 'voice_invitation');
}

const voiceNotificationTypes = <PluginNotificationType>[
  PluginNotificationType(
    id: PluginNotificationTypeId(owner: PluginId('voice'), name: 'invitation'),
    wireType: VoiceNotificationTypes.invitation,
    decode: _decodeVoiceInvitation,
  ),
];

ResolvedNotification? _decodeVoiceInvitation(
  String _,
  DiscourseNotification notification,
) {
  if (notification.typeId.value != VoiceNotificationTypes.invitation.wireId) {
    return null;
  }

  final data = notification.data;
  final actor = jsonText(data['display_username']) ?? appL10n.someone;
  final roomName = jsonText(data['room_name']) ?? appL10n.aVoiceRoom;
  final isCall = data['call'] == true;
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: isCall ? VoiceIcons.phone : DIcons.microphoneLines,
      actor: actor,
      phrase: isCall
          ? appL10n.isCallingYou
          : appL10n.invitedYouToJoin((roomName).toString()),
    ),
    path: _voiceInvitationPath(data),
  );
}

String? _voiceInvitationPath(Map<String, dynamic> data) {
  final roomSlug = jsonText(data['room_slug']);
  final inviter = jsonText(data['display_username']);
  if (roomSlug == null || inviter == null) return null;
  return '/voice/r/${Uri.encodeComponent(roomSlug)}/invited-by/'
      '${Uri.encodeComponent(inviter.toLowerCase())}';
}
