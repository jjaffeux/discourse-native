import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'site_image.dart';

const Set<String> _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtu.be',
};
final RegExp _youtubeId = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _youtubeTime = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$');

/// The YouTube fields Discourse preserves in cooked HTML.
///
/// This parser deliberately understands both the lazy-video plugin's `div`
/// and core Onebox's iframe fallback. The renderer never has to trust an
/// arbitrary cooked iframe: only exact YouTube hosts, paths and identifiers
/// reach [YoutubePlayerSurface].
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

  /// Claims a cooked lazy-video container or core YouTube iframe.
  static YoutubeVideoData? tryParse(dom.Element element) {
    if (_isLazyYoutube(element)) return _fromLazyContainer(element);
    if (_isCoreYoutubeIframe(element)) return _fromCoreIframe(element);
    return null;
  }

  /// Parses the URL forms accepted by Discourse's YouTube onebox engine.
  static YoutubeVideoData? tryParseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !_isSafeYoutubeUri(uri)) return null;

    String? videoId;
    String? listId = _sanitizeId(_firstQuery(uri, 'list'));
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();

    if (uri.host == 'youtu.be') {
      if (segments.isNotEmpty) videoId = _sanitizeId(segments.first);
    } else if (segments.length >= 2 && segments.first == 'embed') {
      if (segments[1] == 'videoseries') {
        // A playlist-only iframe has no video id.
      } else {
        videoId = _sanitizeId(segments[1]);
      }
    } else if (segments.length >= 2 &&
        const {'shorts', 'live'}.contains(segments.first)) {
      videoId = _sanitizeId(segments[1]);
    } else if (segments.length == 1 && segments.first == 'watch') {
      videoId = _sanitizeId(_firstQuery(uri, 'v'));
    }

    if (videoId == null && listId == null) return null;

    final start =
        _parseYoutubeTime(_firstQuery(uri, 'start')) ??
        _parseYoutubeTime(_firstQuery(uri, 't')) ??
        _fragmentStart(uri.fragment);
    final end = _parseYoutubeTime(_firstQuery(uri, 'end'));
    final title = videoId == null ? 'YouTube playlist' : 'YouTube video';

    return YoutubeVideoData(
      videoId: videoId,
      listId: listId,
      title: title,
      thumbnailUrl: videoId == null
          ? null
          : 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
      startSeconds: start,
      endSeconds: end,
      loop: uri.queryParametersAll.containsKey('loop'),
    );
  }

  static YoutubeVideoData? _fromLazyContainer(dom.Element element) {
    final link = element.querySelector('a[href]');
    final fromUrl = link == null
        ? null
        : YoutubeVideoData.tryParseUrl(link.attributes['href'] ?? '');
    final videoId =
        _sanitizeId(element.attributes['data-video-id']) ?? fromUrl?.videoId;
    final listId =
        _sanitizeId(element.attributes['data-video-list-id']) ??
        fromUrl?.listId;
    if (videoId == null && listId == null) return null;

    final image = element.querySelector('img.youtube-thumbnail');
    final title =
        element.attributes['data-video-title']?.trim().nullIfEmpty ??
        image?.attributes['title']?.trim().nullIfEmpty ??
        (videoId == null ? 'YouTube playlist' : 'YouTube video');

    return YoutubeVideoData(
      videoId: videoId,
      listId: listId,
      title: title,
      thumbnailUrl:
          image?.attributes['src']?.trim().nullIfEmpty ??
          (videoId == null
              ? null
              : 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg'),
      startSeconds:
          _parseYoutubeTime(element.attributes['data-video-start-time']) ??
          fromUrl?.startSeconds,
      endSeconds: fromUrl?.endSeconds,
      loop: fromUrl?.loop ?? false,
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

  static bool _isLazyYoutube(dom.Element element) =>
      element.localName == 'div' &&
      element.classes.contains('lazy-video-container') &&
      element.classes.contains('youtube-onebox') &&
      element.attributes['data-provider-name'] == 'youtube';

  static bool _isCoreYoutubeIframe(dom.Element element) =>
      element.localName == 'iframe' &&
      element.classes.contains('youtube-onebox');
}

/// Returns an empty replacement for core's hidden thumbnail, or the native
/// YouTube preview/player for markup this client recognises.
Widget? youtubeVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (_isHiddenCoreThumbnail(element)) return const SizedBox.shrink();
  final data = YoutubeVideoData.tryParse(element);
  if (data == null) return null;
  return YoutubeVideo(data: data, siteUrl: siteUrl);
}

bool _isHiddenCoreThumbnail(dom.Element element) {
  if (element.localName != 'img' ||
      !element.classes.contains('youtube-thumbnail') ||
      !element.classes.contains('onebox')) {
    return false;
  }
  final next = element.nextElementSibling;
  return next != null && YoutubeVideoData.tryParse(next) != null;
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

String? _sanitizeId(String? value) {
  final candidate = value?.trim();
  if (candidate == null ||
      candidate.isEmpty ||
      candidate.length > 256 ||
      !_youtubeId.hasMatch(candidate)) {
    return null;
  }
  return candidate;
}

String? _firstQuery(Uri uri, String key) =>
    uri.queryParametersAll[key]?.firstOrNull;

int? _fragmentStart(String fragment) {
  if (!fragment.startsWith('t=')) return null;
  return _parseYoutubeTime(fragment.substring(2));
}

int? _parseYoutubeTime(String? value) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) return null;
  final seconds = int.tryParse(candidate);
  if (seconds != null) return seconds >= 0 ? seconds : null;

  final match = _youtubeTime.firstMatch(candidate);
  if (match == null || match.group(0)!.isEmpty) return null;
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final remainingSeconds = int.tryParse(match.group(3) ?? '') ?? 0;
  if (hours == 0 && minutes == 0 && remainingSeconds == 0) return null;
  return hours * 3600 + minutes * 60 + remainingSeconds;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

typedef YoutubePlayerBuilder =
    Widget Function(YoutubeVideoData data, Uri? forumOrigin);

/// The native, lazy YouTube card used by both posts and chat messages.
class YoutubeVideo extends StatefulWidget {
  const YoutubeVideo({
    super.key,
    required this.data,
    required this.siteUrl,
    this.playerBuilder,
  });

  final YoutubeVideoData data;
  final String? siteUrl;

  /// A test seam; production always uses [YoutubePlayerSurface].
  final YoutubePlayerBuilder? playerBuilder;

  @override
  State<YoutubeVideo> createState() => _YoutubeVideoState();
}

class _YoutubeVideoState extends State<YoutubeVideo>
    with AutomaticKeepAliveClientMixin {
  bool _loaded = false;

  @override
  bool get wantKeepAlive => _loaded;

  @override
  void didUpdateWidget(YoutubeVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playbackIdentity != widget.data.playbackIdentity) {
      _loaded = false;
      updateKeepAlive();
    }
  }

  void _load() {
    if (_loaded) return;
    setState(() => _loaded = true);
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final origin = youtubeForumOrigin(widget.siteUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 480.0;
          final height = math.max(width * 9 / 16, 200.0);
          final player = widget.playerBuilder;
          final child = _loaded
              ? player?.call(widget.data, origin) ??
                    YoutubePlayerSurface(data: widget.data, forumOrigin: origin)
              : _YoutubePoster(
                  data: widget.data,
                  siteUrl: widget.siteUrl,
                  onPlay: _load,
                );

          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _YoutubePoster extends StatelessWidget {
  const _YoutubePoster({
    required this.data,
    required this.siteUrl,
    required this.onPlay,
  });

  final YoutubeVideoData data;
  final String? siteUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playLabel = 'Play video: ${data.title}';
    final openLabel = 'Open on YouTube: ${data.title}';
    void openOnYoutube() =>
        unawaited(openExternalLink(data.watchUri.toString()));

    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          button: true,
          label: playLabel,
          onTap: onPlay,
          child: ExcludeSemantics(
            child: Material(
              color: Colors.black,
              child: InkWell(
                onTap: onPlay,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (data.thumbnailUrl case final thumbnail?)
                      SiteImage(
                        url: thumbnail,
                        siteUrl: siteUrl,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x22000000),
                            Color(0x11000000),
                            Color(0xDD000000),
                          ],
                          stops: [0, 0.48, 1],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 68,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0033),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: DIcon(
                            DIcons.play,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 64,
                      bottom: 14,
                      child: Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Semantics(
            link: true,
            label: openLabel,
            onTap: openOnYoutube,
            child: ExcludeSemantics(
              child: Tooltip(
                message: 'Open on YouTube',
                child: IconButton.filled(
                  onPressed: openOnYoutube,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xBB000000),
                    foregroundColor: Colors.white,
                  ),
                  icon: const DIcon(
                    DIcons.upRightFromSquare,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sole platform-WebView boundary for YouTube playback.
class YoutubePlayerSurface extends StatefulWidget {
  const YoutubePlayerSurface({
    super.key,
    required this.data,
    required this.forumOrigin,
  });

  final YoutubeVideoData data;
  final Uri? forumOrigin;

  @override
  State<YoutubePlayerSurface> createState() => _YoutubePlayerSurfaceState();
}

class _YoutubePlayerSurfaceState extends State<YoutubePlayerSurface> {
  WebViewController? _controller;
  Object? _error;
  int _generation = 0;
  bool _loadingDocument = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(YoutubePlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playbackIdentity != widget.data.playbackIdentity ||
        oldWidget.forumOrigin != widget.forumOrigin) {
      _initialize();
    }
  }

  void _initialize() {
    final generation = ++_generation;
    _loadingDocument = true;
    _error = null;

    try {
      final controller = WebViewController.fromPlatformCreationParams(
        youtubeWebViewCreationParams(),
      );
      _controller = controller;
      final documentBase =
          widget.forumOrigin ?? Uri.parse('https://www.youtube.com');
      unawaited(
        _configure(controller, documentBase, generation).catchError((
          Object error,
          StackTrace stack,
        ) {
          if (!mounted || generation != _generation) return;
          _report(error, stack);
          setState(() => _error = error);
        }),
      );
    } on Object catch (error, stack) {
      _controller = null;
      _report(error, stack);
      _error = error;
    }
  }

  Future<void> _configure(
    WebViewController controller,
    Uri documentBase,
    int generation,
  ) async {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.black);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          if (_loadingDocument &&
              (isYoutubeDocumentNavigation(request.url, documentBase) ||
                  isYoutubeInitialEmbedNavigation(
                    request.url,
                    widget.data,
                    forumOrigin: widget.forumOrigin,
                  ))) {
            return NavigationDecision.navigate;
          }
          unawaited(openExternalLink(request.url));
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (generation == _generation) _loadingDocument = false;
        },
      ),
    );
    await controller.loadHtmlString(
      buildYoutubeEmbedHtml(widget.data, forumOrigin: widget.forumOrigin),
      baseUrl: documentBase.toString(),
    );
  }

  void _report(Object error, StackTrace stackTrace) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: 'youtube.player.initialize',
      source: 'platform',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null || controller == null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't load the YouTube player.",
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => unawaited(
                  openExternalLink(widget.data.watchUri.toString()),
                ),
                child: const Text('Open on YouTube'),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: 'YouTube player: ${widget.data.title}',
      child: WebViewWidget(controller: controller),
    );
  }
}

/// Opts into the playback behavior promised by the native Play action before
/// the platform WebView is created. In particular, WKWebView defaults inline
/// media to false even when the iframe itself uses `playsinline=1`.
PlatformWebViewControllerCreationParams youtubeWebViewCreationParams() {
  const base = PlatformWebViewControllerCreationParams();
  final platform = WebViewPlatform.instance;
  if (platform is WebKitWebViewPlatform) {
    return WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
      base,
      mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      allowsInlineMediaPlayback: true,
    );
  }
  if (platform is LinuxWebViewPlatform) {
    return const LinuxWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
      base,
      mediaPlaybackRequiresUserGesture: false,
      mediaPlaybackAllowsInline: true,
    );
  }
  return base;
}

/// Keeps the source forum as the iframe's referrer/client identity while
/// discarding paths, credentials and fragments.
Uri? youtubeForumOrigin(String? siteUrl) {
  final uri = siteUrl == null ? null : Uri.tryParse(siteUrl);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final defaultPort =
      (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort && !defaultPort ? uri.port : null,
  );
}

Uri youtubeEmbedUri(YoutubeVideoData data, {Uri? forumOrigin}) {
  final query = <String, String>{
    'autoplay': '1',
    'playsinline': '1',
    'rel': '0',
  };
  if (data.listId case final list?) query['list'] = list;
  if (data.startSeconds case final start?) query['start'] = '$start';
  if (data.endSeconds case final end?) query['end'] = '$end';
  if (data.loop) {
    query['loop'] = '1';
    if (data.videoId case final id?) query['playlist'] = id;
  }
  if (forumOrigin != null) query['origin'] = forumOrigin.toString();

  final videoId = data.videoId;
  final path = videoId == null ? '/embed/videoseries' : '/embed/$videoId';
  return Uri.https('www.youtube.com', path, query);
}

String buildYoutubeEmbedHtml(YoutubeVideoData data, {Uri? forumOrigin}) {
  final source = const HtmlEscape(
    HtmlEscapeMode.attribute,
  ).convert(youtubeEmbedUri(data, forumOrigin: forumOrigin).toString());
  final title = const HtmlEscape(HtmlEscapeMode.attribute).convert(data.title);
  return '''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="origin">
  <style>
    html, body { width: 100%; height: 100%; margin: 0; background: #000; overflow: hidden; }
    iframe { width: 100%; height: 100%; border: 0; display: block; }
  </style>
</head>
<body>
  <iframe src="$source" title="$title" referrerpolicy="origin"
    allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share"
    allowfullscreen></iframe>
</body>
</html>''';
}

bool isYoutubeDocumentNavigation(String value, Uri documentBase) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (uri.scheme == 'about' && uri.path == 'blank') return true;
  if (uri.scheme == 'data' && uri.path.startsWith('text/html')) return true;
  return uri == documentBase || uri == documentBase.replace(path: '/');
}

/// Linux's WebKitGTK adapter currently marks iframe policy requests as main
/// frame requests. Permit only our exact initial player URL while the app-owned
/// document is loading; subsequent main-frame requests still leave the app.
bool isYoutubeInitialEmbedNavigation(
  String value,
  YoutubeVideoData data, {
  Uri? forumOrigin,
}) {
  final uri = Uri.tryParse(value);
  return uri == youtubeEmbedUri(data, forumOrigin: forumOrigin);
}
