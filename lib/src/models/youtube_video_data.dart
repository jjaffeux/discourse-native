import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:html/dom.dart' as dom;

import '../foundation/uri_path.dart';

const Set<String> _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtu.be',
};
final RegExp _youtubeId = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _youtubeTime = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$');

@immutable
final class YoutubeVideoData {
  const YoutubeVideoData({
    required this.videoId,
    required this.listId,
    required this.title,
    required this.thumbnailUrl,
    required this.startSeconds,
    required this.endSeconds,
    required this.loop,
  });

  final String? videoId;
  final String? listId;
  final String title;
  final String? thumbnailUrl;
  final int? startSeconds;
  final int? endSeconds;
  final bool loop;

  Object get playbackIdentity =>
      (videoId, listId, startSeconds, endSeconds, loop);

  Uri get watchUri {
    final query = <String, String>{};
    String path;
    if (videoId case final id?) {
      path = '/watch';
      query['v'] = id;
    } else {
      path = '/playlist';
    }
    if (listId case final list?) query['list'] = list;
    if (startSeconds case final start?) query['t'] = '${start}s';
    if (endSeconds case final end?) query['end'] = '$end';
    if (loop) query['loop'] = '1';
    return Uri.https('www.youtube.com', path, query);
  }

  static YoutubeVideoData? tryParseCoreIframe(dom.Element element) =>
      _isCoreYoutubeIframe(element) ? _fromCoreIframe(element) : null;

  static YoutubeVideoData? tryParseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !_isSafeYoutubeUri(uri)) return null;
    final decoded = tryUriPathSegments(uri);
    if (decoded == null) return null;
    final Map<String, List<String>> query;
    try {
      query = uri.queryParametersAll;
    } on FormatException {
      return null;
    }

    String? videoId;
    String? listId = sanitizeYoutubeId(_firstQuery(query, 'list'));
    final segments = decoded.where((part) => part.isNotEmpty).toList();

    if (uri.host == 'youtu.be') {
      if (segments.isNotEmpty) videoId = sanitizeYoutubeId(segments.first);
    } else if (segments.length >= 2 && segments.first == 'embed') {
      if (segments[1] == 'videoseries') {
      } else {
        videoId = sanitizeYoutubeId(segments[1]);
      }
    } else if (segments.length >= 2 &&
        const {'shorts', 'live'}.contains(segments.first)) {
      videoId = sanitizeYoutubeId(segments[1]);
    } else if (segments.length == 1 && segments.first == 'watch') {
      videoId = sanitizeYoutubeId(_firstQuery(query, 'v'));
    }

    if (videoId == null && listId == null) return null;

    final start =
        parseYoutubeTime(_firstQuery(query, 'start')) ??
        parseYoutubeTime(_firstQuery(query, 't')) ??
        _fragmentStart(uri.fragment);
    final end = parseYoutubeTime(_firstQuery(query, 'end'));
    final title = videoId == null
        ? appL10n.youTubePlaylist
        : appL10n.youTubeVideo;

    return YoutubeVideoData(
      videoId: videoId,
      listId: listId,
      title: title,
      thumbnailUrl: videoId == null
          ? null
          : 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
      startSeconds: start,
      endSeconds: end,
      loop: _firstQuery(query, 'loop') == '1',
    );
  }

  static YoutubeVideoData? _fromCoreIframe(dom.Element element) {
    final parsed = YoutubeVideoData.tryParseUrl(
      element.attributes['src'] ?? '',
    );
    if (parsed == null) return null;

    final thumbnail = element.previousElementSibling;
    final isYoutubeThumbnail =
        thumbnail?.localName == 'img' &&
        thumbnail!.classes.contains('youtube-thumbnail');
    final thumbnailUrl = isYoutubeThumbnail
        ? thumbnail.attributes['src']?.trim().nullIfEmpty
        : null;
    final title =
        element.attributes['title']?.trim().nullIfEmpty ??
        (isYoutubeThumbnail
            ? thumbnail.attributes['title']?.trim().nullIfEmpty
            : null) ??
        parsed.title;

    return YoutubeVideoData(
      videoId: parsed.videoId,
      listId: parsed.listId,
      title: title,
      thumbnailUrl: thumbnailUrl ?? parsed.thumbnailUrl,
      startSeconds: parsed.startSeconds,
      endSeconds: parsed.endSeconds,
      loop: parsed.loop,
    );
  }

  static bool _isCoreYoutubeIframe(dom.Element element) =>
      element.localName == 'iframe' &&
      element.classes.contains('youtube-onebox');
}

bool _isSafeYoutubeUri(Uri uri) {
  if (!const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      !_youtubeHosts.contains(uri.host.toLowerCase())) {
    return false;
  }
  if (!uri.hasPort) return true;
  return (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
}

String? sanitizeYoutubeId(String? value) {
  final candidate = value?.trim();
  if (candidate == null ||
      candidate.isEmpty ||
      candidate.length > 256 ||
      !_youtubeId.hasMatch(candidate)) {
    return null;
  }
  return candidate;
}

String? _firstQuery(Map<String, List<String>> query, String key) =>
    query[key]?.firstOrNull;

int? _fragmentStart(String fragment) {
  if (!fragment.startsWith('t=')) return null;
  return parseYoutubeTime(fragment.substring(2));
}

int? parseYoutubeTime(String? value) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) return null;
  final seconds = int.tryParse(candidate);
  if (seconds != null) return seconds >= 0 ? seconds : null;

  final match = _youtubeTime.firstMatch(candidate);
  if (match == null || match.group(0)!.isEmpty) return null;
  final hours = int.tryParse(match.group(1) ?? '0');
  final minutes = int.tryParse(match.group(2) ?? '0');
  final remainingSeconds = int.tryParse(match.group(3) ?? '0');
  if (hours == null || minutes == null || remainingSeconds == null) return null;
  final total =
      BigInt.from(hours) * BigInt.from(3600) +
      BigInt.from(minutes) * BigInt.from(60) +
      BigInt.from(remainingSeconds);
  return total.isValidInt ? total.toInt() : null;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
