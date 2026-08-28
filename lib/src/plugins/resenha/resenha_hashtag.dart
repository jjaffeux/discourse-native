import '../../plugin_api/hashtag_kind.dart';
import '../../theme/d_icons.dart';

/// Resenha's server-owned hashtag type and its native presentation policy.
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
