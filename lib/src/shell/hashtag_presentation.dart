import '../plugin_api/hashtag_kind.dart';
import '../theme/d_icons.dart';
import 'composer/autocomplete.dart';

HashtagPresentation resolveHashtagPresentation(
  HashtagPresentationRequest request, {
  PluginHashtagPresentationResolver? pluginPresentation,
}) {
  switch (request.type) {
    case 'category':
      return HashtagPresentation.fromRequest(
        request,
        fallbackIcon: DIcons.folder,
        colorPolicy: HashtagColorPolicy.category,
      );
    case 'tag':
      return HashtagPresentation.fromRequest(
        request,
        fallbackIcon: DIcons.tag,
        colorPolicy: HashtagColorPolicy.none,
      );
  }

  final contributed = pluginPresentation?.call(request);
  return (contributed?.type == request.type ? contributed : null) ??
      HashtagPresentation.fromRequest(
        request,
        fallbackIcon: DIcons.link,
        colorPolicy: HashtagColorPolicy.supplied,
      );
}

SuggestionArt hashtagSuggestionArt(
  HashtagPresentation presentation, {
  required String Function(String emoji) resolveEmoji,
}) {
  final emoji = presentation.emoji;
  if (presentation.style == HashtagStyle.emoji) {
    return emoji == null
        ? ArtIcon(presentation.icon, fallback: presentation.fallbackIcon)
        : ArtImage(resolveEmoji(emoji));
  }
  if (presentation.style == HashtagStyle.square &&
      drawsHashtagSquare(presentation)) {
    return ArtSquare(presentation.colorValues);
  }
  return ArtIcon(
    presentation.icon,
    colorValue: hashtagColorValue(presentation),
    fallback: presentation.fallbackIcon,
  );
}

bool drawsHashtagSquare(HashtagPresentation presentation) =>
    switch (presentation.colorPolicy) {
      HashtagColorPolicy.category => true,
      HashtagColorPolicy.supplied => presentation.colorValues.isNotEmpty,
      HashtagColorPolicy.none => false,
    };

int? hashtagColorValue(HashtagPresentation presentation) =>
    presentation.colorPolicy == HashtagColorPolicy.none ||
        presentation.colorValues.isEmpty
    ? null
    : presentation.colorValues.last;
