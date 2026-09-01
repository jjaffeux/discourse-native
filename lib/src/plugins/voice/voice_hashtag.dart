import 'package:discourse_native/discourse_plugin_sdk.dart';

const voiceRoomHashtagKind = PluginHashtagKind(
  'room',
  _presentVoiceRoomHashtag,
);

HashtagPresentation _presentVoiceRoomHashtag(
  HashtagPresentationRequest request,
) => HashtagPresentation(
  type: request.type,
  style: request.style,
  icon: request.icon,
  emoji: request.emoji,
  fallbackIcon: DIcons.microphoneLines,
  colorPolicy: HashtagColorPolicy.none,
);
