import 'package:discourse_native/discourse_plugin_sdk.dart';

const resenhaRoomHashtagKind = PluginHashtagKind(
  'room',
  _presentResenhaRoomHashtag,
);

HashtagPresentation _presentResenhaRoomHashtag(
  HashtagPresentationRequest request,
) => HashtagPresentation(
  type: request.type,
  style: request.style,
  icon: request.icon,
  emoji: request.emoji,
  fallbackIcon: DIcons.microphoneLines,
  colorPolicy: HashtagColorPolicy.none,
);
