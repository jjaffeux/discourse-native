import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show Factory, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../theme/d_button.dart';
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

    String? videoId;
    String? listId = sanitizeYoutubeId(_firstQuery(uri, 'list'));
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();

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
      videoId = sanitizeYoutubeId(_firstQuery(uri, 'v'));
    }

    if (videoId == null && listId == null) return null;

    final start =
        parseYoutubeTime(_firstQuery(uri, 'start')) ??
        parseYoutubeTime(_firstQuery(uri, 't')) ??
        _fragmentStart(uri.fragment);
    final end = parseYoutubeTime(_firstQuery(uri, 'end'));
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

Widget? youtubeVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (_isHiddenCoreThumbnail(element)) return const SizedBox.shrink();
  final data = YoutubeVideoData.tryParseCoreIframe(element);
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
  return next != null && YoutubeVideoData.tryParseCoreIframe(next) != null;
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

String? _firstQuery(Uri uri, String key) =>
    uri.queryParametersAll[key]?.firstOrNull;

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

class YoutubeVideo extends StatefulWidget {
  const YoutubeVideo({
    super.key,
    required this.data,
    required this.siteUrl,
    this.playerBuilder,
  });

  final YoutubeVideoData data;
  final String? siteUrl;

  final YoutubePlayerBuilder? playerBuilder;

  @override
  State<YoutubeVideo> createState() => _YoutubeVideoState();
}

class _YoutubeVideoState extends State<YoutubeVideo>
    with AutomaticKeepAliveClientMixin {
  final LayerLink _playerLink = LayerLink();
  final GlobalKey _playerAnchorKey = GlobalKey();

  bool _loaded = false;
  OverlayEntry? _playerEntry;
  Size _playerSize = Size.zero;
  Rect? _playerViewport;
  Object? _geometrySyncToken;

  bool get _usesRootPlayerOverlay =>
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  bool get wantKeepAlive => _loaded;

  @override
  void didUpdateWidget(YoutubeVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.data.playbackIdentity != widget.data.playbackIdentity ||
        youtubeForumOrigin(oldWidget.siteUrl) !=
            youtubeForumOrigin(widget.siteUrl);
    if (sourceChanged) {
      _removePlayer();
      _loaded = false;
      updateKeepAlive();
    } else {
      _playerEntry?.markNeedsBuild();
    }
  }

  void _load() {
    if (_loaded) return;
    setState(() => _loaded = true);
    updateKeepAlive();
    if (_usesRootPlayerOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _insertPlayer());
    }
  }

  void _insertPlayer() {
    if (!mounted || !_loaded || !_usesRootPlayerOverlay) return;
    if (_playerEntry != null) return;
    _syncPlayerGeometry();
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: ClipRect(
          clipper: _PlayerViewportClipper(_playerViewport),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _playerLink,
                  showWhenUnlinked: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.fromSize(
                      size: _playerSize,
                      child: _buildPlayer(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _playerEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _MacOSYoutubeScrollBridge.register(this, _handleMacOSScroll);
  }

  Widget _buildPlayer() =>
      widget.playerBuilder?.call(
        widget.data,
        youtubeForumOrigin(widget.siteUrl),
      ) ??
      YoutubePlayerSurface(
        data: widget.data,
        forumOrigin: youtubeForumOrigin(widget.siteUrl),
      );

  void _schedulePlayerGeometrySync({bool rebuildPlayer = false}) {
    if (!_loaded || !_usesRootPlayerOverlay) return;
    final token = Object();
    _geometrySyncToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_geometrySyncToken, token)) return;
      _geometrySyncToken = null;
      _syncPlayerGeometry(rebuildPlayer: rebuildPlayer);
    });
  }

  void _syncPlayerGeometry({bool rebuildPlayer = false}) {
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    final viewportBox =
        Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    Rect? nextViewport;
    if (overlayBox != null &&
        overlayBox.hasSize &&
        viewportBox != null &&
        viewportBox.hasSize) {
      final origin = viewportBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      nextViewport = origin & viewportBox.size;
    }
    if (_playerViewport != nextViewport) {
      _playerViewport = nextViewport;
      rebuildPlayer = true;
    }
    if (rebuildPlayer) _playerEntry?.markNeedsBuild();
  }

  bool _handleMacOSScroll(Offset globalPosition, double delta) {
    if (!mounted || !_loaded) return false;
    final playerBox =
        _playerAnchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (playerBox == null || !playerBox.attached || !playerBox.hasSize) {
      return false;
    }

    var visibleBounds = playerBox.localToGlobal(Offset.zero) & playerBox.size;
    final viewportBox =
        Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (viewportBox != null && viewportBox.attached && viewportBox.hasSize) {
      final viewportBounds =
          viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
      if (!visibleBounds.overlaps(viewportBounds)) return false;
      visibleBounds = visibleBounds.intersect(viewportBounds);
    }
    if (!visibleBounds.contains(globalPosition)) return false;

    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || !position.hasContentDimensions) return true;
    position.pointerScroll(delta);
    return true;
  }

  void _removePlayer() {
    _geometrySyncToken = null;
    _MacOSYoutubeScrollBridge.unregister(this);
    _playerEntry?.remove();
    _playerEntry = null;
    _playerViewport = null;
  }

  @override
  void dispose() {
    _removePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 480.0;
          final height = math.max(width * 9 / 16, 200.0);
          final nextSize = Size(width, height);
          final sizeChanged = _playerSize != nextSize;
          if (sizeChanged) _playerSize = nextSize;
          _schedulePlayerGeometrySync(rebuildPlayer: sizeChanged);

          final child = _loaded && _usesRootPlayerOverlay
              ? CompositedTransformTarget(
                  key: _playerAnchorKey,
                  link: _playerLink,
                  child: const ColoredBox(color: Colors.black),
                )
              : _loaded
              ? _buildPlayer()
              : _YoutubePoster(
                  data: widget.data,
                  siteUrl: widget.siteUrl,
                  onPlay: _load,
                );

          final surface = SizedBox(
            width: double.infinity,
            height: height,
            child: child,
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: surface,
          );
        },
      ),
    );
  }
}

class _PlayerViewportClipper extends CustomClipper<Rect> {
  const _PlayerViewportClipper(this.viewport);

  final Rect? viewport;

  @override
  Rect getClip(Size size) {
    final bounds = Offset.zero & size;
    final candidate = viewport;
    if (candidate == null) return bounds;
    return candidate.overlaps(bounds) ? candidate.intersect(bounds) : Rect.zero;
  }

  @override
  bool shouldReclip(_PlayerViewportClipper oldClipper) =>
      oldClipper.viewport != viewport;
}

typedef _MacOSYoutubeScrollTarget =
    bool Function(Offset globalPosition, double delta);

final class _MacOSYoutubeScrollBridge {
  static const _channel = MethodChannel('org.discourse.native/youtube_scroll');
  static final Map<Object, _MacOSYoutubeScrollTarget> _targets = {};
  static bool _listening = false;

  static void register(Object owner, _MacOSYoutubeScrollTarget target) {
    if (!_listening) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _listening = true;
    }
    _targets[owner] = target;
  }

  static void unregister(Object owner) => _targets.remove(owner);

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'scroll' || call.arguments is! Map) return;
    final arguments = call.arguments as Map;
    final x = arguments['x'];
    final y = arguments['y'];
    final deltaY = arguments['deltaY'];
    if (x is! num || y is! num || deltaY is! num) return;
    final position = Offset(x.toDouble(), y.toDouble());
    final delta = deltaY.toDouble();
    if (!position.dx.isFinite || !position.dy.isFinite || !delta.isFinite) {
      return;
    }

    for (final target in _targets.values.toList().reversed) {
      if (target(position, delta)) return;
    }
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
              DButton(
                label: const Text('Open on YouTube'),
                onPressed: () => unawaited(
                  openExternalLink(widget.data.watchUri.toString()),
                ),
                variant: DButtonVariant.link,
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: 'YouTube player: ${widget.data.title}',
      child: WebViewWidget(
        controller: controller,
        gestureRecognizers: youtubePlayerGestureRecognizers,
      ),
    );
  }
}

const Set<Factory<OneSequenceGestureRecognizer>>
youtubePlayerGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
  Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
};

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

bool isYoutubeInitialEmbedNavigation(
  String value,
  YoutubeVideoData data, {
  Uri? forumOrigin,
}) {
  final uri = Uri.tryParse(value);
  return uri == youtubeEmbedUri(data, forumOrigin: forumOrigin);
}
