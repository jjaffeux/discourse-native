import '../../models/json.dart';
import '../../models/notification.dart';
import '../../plugin_api/notification_types.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../theme/d_icons.dart';
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
  DiscourseNotification notification,
) {
  if (notification.typeId.value != VoiceNotificationTypes.invitation.wireId) {
    return null;
  }

  final data = notification.data;
  final actor = jsonText(data['display_username']) ?? 'Someone';
  final roomName = jsonText(data['room_name']) ?? 'a voice room';
  final isCall = data['call'] == true;
  return ResolvedNotification(
    presentation: NotificationPresentation(
      icon: isCall ? VoiceIcons.phone : DIcons.microphoneLines,
      actor: actor,
      phrase: isCall ? 'is calling you' : 'invited you to join $roomName',
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
