import 'package:html/dom.dart' as dom;

/// Baked room metadata. Presence always comes from the viewer's live directory.
final class VoiceRoomOneboxData {
  const VoiceRoomOneboxData({
    required this.url,
    required this.name,
    required this.type,
    required this.descriptionHtml,
    required this.localSlug,
    required this.stage,
  });

  final String url;
  final String name;
  final String type;
  final String descriptionHtml;
  final String? localSlug;
  final bool stage;

  static VoiceRoomOneboxData? read(dom.Element element, String? siteUrl) {
    if (element.localName != 'aside' ||
        !element.classes.contains('onebox') ||
        !element.classes.contains('live-room-onebox')) {
      return null;
    }
    final title = element.querySelector('.live-room-onebox__title a');
    final url = title?.attributes['href'];
    if (title == null || url == null || title.text.trim().isEmpty) return null;
    final site = Uri.tryParse(siteUrl ?? '');
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final resolved = site?.resolveUri(uri) ?? uri;
    if (!const {'http', 'https'}.contains(resolved.scheme) ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty) {
      return null;
    }
    String? slug;
    if (site != null && site.hasAuthority && site.origin == resolved.origin) {
      try {
        final sitePath = site.pathSegments
            .where((part) => part.isNotEmpty)
            .toList();
        final path = resolved.pathSegments
            .where((part) => part.isNotEmpty)
            .toList();
        if (path.length == sitePath.length + 3 &&
            List.generate(
              sitePath.length,
              (i) => path[i] == sitePath[i],
            ).every((same) => same) &&
            const {'live', 'voice'}.contains(path[sitePath.length]) &&
            path[sitePath.length + 1] == 'r') {
          slug = path.last;
        }
      } on FormatException {
        return null;
      }
    }
    return VoiceRoomOneboxData(
      url: resolved.toString(),
      name: title.text.trim(),
      type: element.querySelector('.live-room-onebox__type')?.text.trim() ?? '',
      descriptionHtml:
          element.querySelector('.live-room-onebox__description')?.innerHtml ??
          '',
      localSlug: slug,
      stage: title.querySelector('.d-icon-ear-listen') != null,
    );
  }
}
