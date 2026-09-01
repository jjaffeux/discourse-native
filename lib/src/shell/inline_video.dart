import 'dart:async';
import 'dart:convert' show htmlEscape;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:video_player/video_player.dart';
import 'package:webview_all/webview_all.dart';

import '../data/api_credentials.dart';
import '../data/http_transport.dart';
import '../data/site_lifecycle.dart';
import '../data/site_video_source.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'media_webview.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'site_url.dart';

@immutable
final class InlineVideoData {
  const InlineVideoData._({
    required this.source,
    required this.title,
    required this.posterUrl,
    required this.aspectRatio,
  });

  final Uri source;
  final String title;
  final String? posterUrl;
  final double aspectRatio;

  Object get playbackIdentity => (source, posterUrl, aspectRatio);

  static InlineVideoData? fromUpload({
    required String url,
    required String title,
    required String siteUrl,
    String? posterUrl,
    double? aspectRatio,
  }) => _fromValues(
    source: url,
    title: title,
    posterUrl: posterUrl,
    aspectRatio: aspectRatio,
    siteUrl: siteUrl,
  );

  static InlineVideoData? tryParse(dom.Element element, {String? siteUrl}) {
    dom.Element? video;
    String? source;
    String? poster;
    String? title;
    double? aspectRatio;

    if (element.classes.contains('video-placeholder-container')) {
      source =
          element.attributes['data-video-src'] ??
          element.attributes['data-orig-src'];
      poster = element.attributes['data-thumbnail-src'];
      title =
          element.attributes['data-video-title'] ??
          element.attributes['title'] ??
          element.attributes['aria-label'];
      aspectRatio = _elementAspectRatio(element, dataPrefix: 'data-video-');
    } else if (element.localName == 'video') {
      video = element;
    } else if (element.classes.contains('video-onebox') ||
        element.classes.contains('video-container')) {
      video = element.querySelector('video');
      title =
          element.attributes['data-video-title'] ?? element.attributes['title'];
    } else {
      return null;
    }

    if (video != null) {
      source =
          video.attributes['src'] ??
          video.querySelector('source')?.attributes['src'];
      poster = video.attributes['poster'];
      title ??=
          video.attributes['title'] ??
          video.attributes['aria-label'] ??
          element.querySelector('a')?.text.trim();
      aspectRatio = _elementAspectRatio(video);
    }

    return _fromValues(
      source: source,
      title: title,
      posterUrl: poster,
      aspectRatio: aspectRatio,
      siteUrl: siteUrl,
    );
  }

  static InlineVideoData? _fromValues({
    required String? source,
    required String? title,
    required String? posterUrl,
    required double? aspectRatio,
    required String? siteUrl,
  }) {
    final safeSource = _safeAbsoluteUrl(source, siteUrl);
    if (safeSource == null || safeSource.path == '/404') return null;

    final trimmedTitle = title?.trim();
    return InlineVideoData._(
      source: safeSource,
      title: trimmedTitle == null || trimmedTitle.isEmpty
          ? _filename(safeSource)
          : trimmedTitle,
      posterUrl: _safeAbsoluteUrl(posterUrl, siteUrl)?.toString(),
      aspectRatio: _safeAspectRatio(aspectRatio),
    );
  }
}

Widget? inlineVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final data = InlineVideoData.tryParse(element, siteUrl: siteUrl);
  return data == null ? null : InlineVideo(data: data, siteUrl: siteUrl);
}

typedef InlineVideoPlayerBuilder = Widget Function(
  BuildContext context,
  InlineVideoData data,
);

@visibleForTesting
typedef InlineVideoControllerBuilder = VideoPlayerController Function(
  Uri source,
);

/// A lazy, app-owned shell around the platform video implementation.
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.data,
    required this.siteUrl,
    this.playerBuilder,
    this.maximumWidth,
    this.maximumHeight = 480,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  }) : assert(maximumWidth == null || maximumWidth > 0),
       assert(maximumHeight == null || maximumHeight > 0);

  final InlineVideoData data;
  final String? siteUrl;
  final InlineVideoPlayerBuilder? playerBuilder;
  final double? maximumWidth;
  final double? maximumHeight;
  final EdgeInsetsGeometry padding;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  bool _loaded = false;

  @override
  void didUpdateWidget(InlineVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playbackIdentity != widget.data.playbackIdentity ||
        oldWidget.siteUrl != widget.siteUrl) {
      _loaded = false;
    }
  }

  void _load() {
    if (_loaded) return;
    setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 720.0;
          var width = math.min(
            availableWidth,
            widget.maximumWidth ?? availableWidth,
          );
          var height = width / widget.data.aspectRatio;
          height = math.min(height, widget.maximumHeight ?? height);
          width = math.min(width, height * widget.data.aspectRatio);
          final surface = SizedBox(
            width: width,
            height: height,
            child: _loaded ? _buildPlayer(context) : _buildPoster(context),
          );
          return Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: surface,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final custom = widget.playerBuilder;
    if (custom != null) return custom(context, widget.data);

    final shell = ShellScope.maybeIdentityOf(context);
    final common = (
      data: widget.data,
      siteUrl: widget.siteUrl,
      credentials: shell?.authenticator,
      lifecycle: shell?.lifecycle,
    );
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return InlineVideoWebViewSurface(
        data: common.data,
        siteUrl: common.siteUrl,
        credentials: common.credentials,
        lifecycle: common.lifecycle,
      );
    }
    return InlineVideoNativeSurface(
      data: common.data,
      siteUrl: common.siteUrl,
      credentials: common.credentials,
      lifecycle: common.lifecycle,
    );
  }

  Widget _buildPoster(BuildContext context) {
    final theme = Theme.of(context);
    final playLabel = 'Play video: ${widget.data.title}';

    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          button: true,
          label: playLabel,
          onTap: _load,
          child: ExcludeSemantics(
            child: Material(
              color: Colors.black,
              child: InkWell(
                onTap: _load,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.data.posterUrl case final poster?)
                      SiteImage(
                        url: poster,
                        siteUrl: widget.siteUrl,
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
                            Color(0x11000000),
                            Color(0x22000000),
                            Color(0xDD000000),
                          ],
                          stops: [0, 0.5, 1],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          color: Color(0xDDFFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: DIcon(
                            DIcons.play,
                            size: 23,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 58,
                      bottom: 12,
                      child: Text(
                        widget.data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
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
        _OpenVideoButton(data: widget.data),
      ],
    );
  }
}

class InlineVideoNativeSurface extends StatefulWidget {
  const InlineVideoNativeSurface({
    super.key,
    required this.data,
    required this.siteUrl,
    required this.credentials,
    required this.lifecycle,
    this.controllerBuilder,
  });

  final InlineVideoData data;
  final String? siteUrl;
  final ApiCredentialReader? credentials;
  final SiteLifecycle? lifecycle;

  @visibleForTesting
  final InlineVideoControllerBuilder? controllerBuilder;

  @override
  State<InlineVideoNativeSurface> createState() =>
      _InlineVideoNativeSurfaceState();
}

class _InlineVideoNativeSurfaceState extends State<InlineVideoNativeSurface>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  _VideoSourceResolution? _sourceResolution;
  Object? _error;
  int _generation = 0;
  bool _fullscreenOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(InlineVideoNativeSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playbackIdentity != widget.data.playbackIdentity ||
        oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.credentials, widget.credentials) ||
        !identical(oldWidget.lifecycle, widget.lifecycle) ||
        !identical(oldWidget.controllerBuilder, widget.controllerBuilder)) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    _InlineVideoPlaybackCoordinator.release(this);
    _sourceResolution?.cancel();
    _sourceResolution = null;
    final previous = _controller;
    _controller = null;
    _error = null;
    if (mounted) setState(() {});
    if (previous != null) {
      previous.removeListener(_playerChanged);
      await _disposeNativeController(previous);
    }
    if (!mounted || generation != _generation) return;

    try {
      final resolution = _VideoSourceResolution(
        data: widget.data,
        siteUrl: widget.siteUrl,
        credentials: widget.credentials,
        lifecycle: widget.lifecycle,
      );
      _sourceResolution = resolution;
      late final SiteVideoSource source;
      try {
        source = await resolution.resolve();
      } finally {
        if (identical(_sourceResolution, resolution)) {
          _sourceResolution = null;
        }
        resolution.cancel();
      }
      if (!mounted || generation != _generation) return;
      final controller =
          widget.controllerBuilder?.call(source.url) ??
          VideoPlayerController.networkUrl(source.url);
      _controller = controller;
      controller.addListener(_playerChanged);
      await controller.initialize();
      if (!mounted || generation != _generation || _error != null) {
        controller.removeListener(_playerChanged);
        if (_error == null && !identical(_controller, controller)) {
          await _disposeNativeController(controller);
        }
        return;
      }
      await _play(controller);
      if (mounted && generation == _generation) setState(() {});
    } on Object catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      if (_error != null) return;
      _reportVideoError(error, stackTrace, 'video.native.initialize');
      final controller = _controller;
      _controller = null;
      if (controller != null) {
        controller.removeListener(_playerChanged);
        await _disposeNativeController(controller);
      }
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    }
  }

  void _playerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError && _error == null) {
      _failNative(
        controller,
        StateError(
          value.errorDescription ?? 'The platform video player failed.',
        ),
        StackTrace.current,
        'video.native.playback',
      );
      return;
    }
    if (value.isPlaying) {
      _InlineVideoPlaybackCoordinator.activate(this, controller.pause);
    }
    setState(() {});
  }

  Future<void> _play(VideoPlayerController controller) async {
    _InlineVideoPlaybackCoordinator.activate(this, controller.pause);
    await controller.play();
  }

  Future<void> _togglePlayback(VideoPlayerController controller) async {
    if (!identical(_controller, controller) || _error != null) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        await _play(controller);
      }
    } on Object catch (error, stackTrace) {
      _failNative(controller, error, stackTrace, 'video.native.controls');
    }
  }

  Future<void> _openFullscreen(VideoPlayerController controller) async {
    if (_fullscreenOpen || !identical(_controller, controller)) return;
    setState(() => _fullscreenOpen = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'inline-video-fullscreen'),
          fullscreenDialog: true,
          builder: (context) => _InlineVideoFullscreen(
            data: widget.data,
            controller: controller,
            onTogglePlayback: () => unawaited(_togglePlayback(controller)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fullscreenOpen = false);
    }
  }

  void _failNative(
    VideoPlayerController controller,
    Object error,
    StackTrace stackTrace,
    String operation,
  ) {
    if (!mounted || !identical(_controller, controller) || _error != null) {
      return;
    }
    controller.removeListener(_playerChanged);
    _controller = null;
    _InlineVideoPlaybackCoordinator.release(this);
    _reportVideoError(error, stackTrace, operation);
    unawaited(_disposeNativeController(controller));
    setState(() => _error = error);
  }

  Future<void> _disposeNativeController(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.pause();
    } on Object {
      // An errored platform controller may reject pause during teardown.
    }
    try {
      await controller.dispose();
    } on Object {
      // Disposal is best-effort after the platform reports playback failure.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final controller = _controller;
      if (controller != null) {
        unawaited(_pauseNativeIgnoringErrors(controller));
      }
    }
  }

  Future<void> _pauseNativeIgnoringErrors(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.pause();
    } on Object {
      // The player may be concurrently replaced while the app backgrounds.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return _VideoFailure(data: widget.data);
    }
    if (controller == null || !controller.value.isInitialized) {
      return _ActiveVideoFrame(
        data: widget.data,
        child: const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    final value = controller.value;
    final playerRatio = value.aspectRatio.isFinite && value.aspectRatio > 0
        ? value.aspectRatio
        : widget.data.aspectRatio;
    return _ActiveVideoFrame(
      data: widget.data,
      child: Semantics(
        label: 'Video player: ${widget.data.title}',
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: playerRatio,
                  child: _fullscreenOpen
                      ? const SizedBox.shrink()
                      : VideoPlayer(controller),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xDD000000)],
                    ),
                  ),
                  child: _NativeVideoControls(
                    controller: controller,
                    value: value,
                    onTogglePlayback: () =>
                        unawaited(_togglePlayback(controller)),
                    onEnterFullscreen: () =>
                        unawaited(_openFullscreen(controller)),
                  ),
                ),
              ),
              if (value.isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _InlineVideoPlaybackCoordinator.release(this);
    _sourceResolution?.cancel();
    _sourceResolution = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_playerChanged);
      unawaited(_disposeNativeController(controller));
    }
    super.dispose();
  }
}

class _InlineVideoFullscreen extends StatelessWidget {
  const _InlineVideoFullscreen({
    required this.data,
    required this.controller,
    required this.onTogglePlayback,
  });

  final InlineVideoData data;
  final VideoPlayerController controller;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('inline-video-fullscreen-view'),
    backgroundColor: Colors.black,
    body: SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final value = controller.value;
          final ratio = value.aspectRatio.isFinite && value.aspectRatio > 0
              ? value.aspectRatio
              : data.aspectRatio;
          return Semantics(
            label: 'Full-screen video player: ${data.title}',
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: ratio,
                    child: VideoPlayer(controller),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xDD000000)],
                      ),
                    ),
                    child: _NativeVideoControls(
                      controller: controller,
                      value: value,
                      onTogglePlayback: onTogglePlayback,
                      onExitFullscreen: Navigator.of(context).pop,
                    ),
                  ),
                ),
                if (value.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _NativeVideoControls extends StatelessWidget {
  const _NativeVideoControls({
    required this.controller,
    required this.value,
    required this.onTogglePlayback,
    this.onEnterFullscreen,
    this.onExitFullscreen,
  }) : assert(onEnterFullscreen == null || onExitFullscreen == null);

  final VideoPlayerController controller;
  final VideoPlayerValue value;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: value.isPlaying ? 'Pause' : 'Play',
        color: Colors.white,
        onPressed: onTogglePlayback,
        icon: Icon(
          value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        ),
      ),
      Expanded(
        child: VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 16),
          colors: const VideoProgressColors(
            playedColor: Colors.white,
            bufferedColor: Color(0x88FFFFFF),
            backgroundColor: Color(0x55FFFFFF),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        '${_duration(value.position)} / ${_duration(value.duration)}',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Colors.white),
      ),
      if (onEnterFullscreen case final enter?)
        IconButton(
          key: const ValueKey('inline-video-fullscreen'),
          tooltip: 'Enter full screen',
          color: Colors.white,
          onPressed: enter,
          icon: const DIcon(DIcons.expand, size: 18, color: Colors.white),
        )
      else if (onExitFullscreen case final exit?)
        IconButton(
          key: const ValueKey('inline-video-fullscreen-close'),
          tooltip: 'Exit full screen',
          color: Colors.white,
          onPressed: exit,
          icon: const Icon(Icons.fullscreen_exit_rounded),
        )
      else
        const SizedBox(width: 12),
    ],
  );
}

class InlineVideoWebViewSurface extends StatefulWidget {
  const InlineVideoWebViewSurface({
    super.key,
    required this.data,
    required this.siteUrl,
    required this.credentials,
    required this.lifecycle,
  });

  final InlineVideoData data;
  final String? siteUrl;
  final ApiCredentialReader? credentials;
  final SiteLifecycle? lifecycle;

  @override
  State<InlineVideoWebViewSurface> createState() =>
      _InlineVideoWebViewSurfaceState();
}

class _InlineVideoWebViewSurfaceState extends State<InlineVideoWebViewSurface>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  _VideoSourceResolution? _sourceResolution;
  Object? _error;
  int _generation = 0;
  bool _loadingDocument = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(InlineVideoWebViewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playbackIdentity != widget.data.playbackIdentity ||
        oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.credentials, widget.credentials) ||
        !identical(oldWidget.lifecycle, widget.lifecycle)) {
      _initialize();
    }
  }

  void _initialize() {
    final generation = ++_generation;
    _InlineVideoPlaybackCoordinator.release(this);
    _sourceResolution?.cancel();
    _sourceResolution = null;
    final previous = _controller;
    if (previous != null) _pause(previous);
    _controller = null;
    _error = null;
    _loadingDocument = true;
    if (mounted) setState(() {});

    unawaited(
      _configure(generation).catchError((Object error, StackTrace stackTrace) {
        if (!mounted || generation != _generation) return;
        _reportVideoError(error, stackTrace, 'video.webview.initialize');
        setState(() => _error = error);
      }),
    );
  }

  Future<void> _configure(int generation) async {
    final resolution = _VideoSourceResolution(
      data: widget.data,
      siteUrl: widget.siteUrl,
      credentials: widget.credentials,
      lifecycle: widget.lifecycle,
    );
    _sourceResolution = resolution;
    late final SiteVideoSource source;
    try {
      source = await resolution.resolve();
    } finally {
      if (identical(_sourceResolution, resolution)) {
        _sourceResolution = null;
      }
      resolution.cancel();
    }
    if (!mounted || generation != _generation) return;

    final controller = WebViewController.fromPlatformCreationParams(
      mediaWebViewCreationParams(),
    );
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (!_isCurrent(generation)) return;
    await controller.addJavaScriptChannel(
      _videoBridgeName,
      onMessageReceived: (message) {
        if (!_isCurrent(generation, controller)) return;
        switch (message.message) {
          case 'play':
            _InlineVideoPlaybackCoordinator.activate(
              this,
              () => _pauseIgnoringErrors(controller),
            );
          case 'error':
            _failWebView(
              StateError('The WebKit media element could not play the video.'),
              StackTrace.current,
              generation,
              controller,
            );
        }
      },
    );
    if (!_isCurrent(generation)) return;
    await controller.setBackgroundColor(Colors.black);
    if (!_isCurrent(generation)) return;
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!_isCurrent(generation, controller)) {
            return NavigationDecision.prevent;
          }
          if (!request.isMainFrame || _loadingDocument) {
            return NavigationDecision.navigate;
          }
          unawaited(openExternalLink(request.url));
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (_isCurrent(generation, controller) && _loadingDocument) {
            setState(() => _loadingDocument = false);
            unawaited(_play(controller, generation));
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false ||
              !_isCurrent(generation, controller)) {
            return;
          }
          _failWebView(error, StackTrace.current, generation, controller);
        },
      ),
    );
    if (!_isCurrent(generation)) return;
    setState(() => _controller = controller);
    await controller.loadHtmlString(
      buildInlineVideoHtml(source.url, posterUrl: widget.data.posterUrl),
      baseUrl: _originOf(source.url).toString(),
    );
    if (!_isCurrent(generation, controller)) _pause(controller);
  }

  bool _isCurrent(int generation, [WebViewController? controller]) =>
      mounted &&
      generation == _generation &&
      (controller == null || identical(_controller, controller));

  Future<void> _play(WebViewController controller, int generation) async {
    try {
      _InlineVideoPlaybackCoordinator.activate(
        this,
        () => _pauseIgnoringErrors(controller),
      );
      await controller.runJavaScript(_playVideoScript);
    } on Object catch (error, stackTrace) {
      _failWebView(error, stackTrace, generation, controller);
    }
  }

  void _failWebView(
    Object error,
    StackTrace stackTrace,
    int generation,
    WebViewController controller,
  ) {
    if (!_isCurrent(generation, controller) || _error != null) return;
    _InlineVideoPlaybackCoordinator.release(this);
    _pause(controller);
    _reportVideoError(error, stackTrace, 'video.webview.playback');
    setState(() => _error = error);
  }

  void _pause(WebViewController controller) {
    unawaited(_pauseIgnoringErrors(controller));
  }

  Future<void> _pauseIgnoringErrors(WebViewController controller) async {
    try {
      await controller.runJavaScript(_pauseVideoScript);
    } on Object {
      // The owned document may not exist yet during replacement or teardown.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final controller = _controller;
      if (controller != null) _pause(controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) return _VideoFailure(data: widget.data);
    if (controller == null) {
      return _ActiveVideoFrame(
        data: widget.data,
        child: const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }
    return _ActiveVideoFrame(
      data: widget.data,
      child: Semantics(
        label: 'Video player: ${widget.data.title}',
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(
              controller: controller,
              gestureRecognizers: mediaPlayerGestureRecognizers,
            ),
            if (_loadingDocument)
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _InlineVideoPlaybackCoordinator.release(this);
    _sourceResolution?.cancel();
    _sourceResolution = null;
    final controller = _controller;
    if (controller != null) _pause(controller);
    super.dispose();
  }
}

String buildInlineVideoHtml(Uri source, {String? posterUrl}) {
  final safeSource = requireSafeHttpUrl(source);
  final safePoster = _safeAbsoluteUrl(posterUrl, null);
  final escapedSource = htmlEscape.convert(safeSource.toString());
  final poster = safePoster == null
      ? ''
      : ' poster="${htmlEscape.convert(safePoster.toString())}"';
  final mediaSources = [
    'https:',
    if (safeSource.scheme == 'http') safeSource.origin,
  ].join(' ');
  final imageSources = [
    'https:',
    'data:',
    if (safePoster?.scheme == 'http') safePoster!.origin,
  ].join(' ');
  return '''<!doctype html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src $mediaSources; img-src $imageSources; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}video{width:100%;height:100%;object-fit:contain}</style>
</head><body>
<video src="$escapedSource"$poster controls playsinline preload="metadata"></video>
<script>
const video = document.querySelector('video');
const notify = (event) => {
  if (window.$_videoBridgeName) window.$_videoBridgeName.postMessage(event);
};
video.addEventListener('play', () => notify('play'));
video.addEventListener('error', () => notify('error'));
</script>
</body></html>''';
}

const _videoBridgeName = 'DiscourseVideo';
const _pauseVideoScript = "document.querySelector('video')?.pause();";
const _playVideoScript = "document.querySelector('video')?.play();";

final class _InlineVideoPlaybackCoordinator {
  static Object? _owner;
  static Future<void> Function()? _pauseCurrent;

  static void activate(Object owner, Future<void> Function() pause) {
    if (identical(_owner, owner)) return;
    final previous = _pauseCurrent;
    _owner = owner;
    _pauseCurrent = pause;
    if (previous != null) unawaited(_pauseIgnoringFailure(previous));
  }

  static void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _pauseCurrent = null;
  }

  static Future<void> _pauseIgnoringFailure(
    Future<void> Function() pause,
  ) async {
    try {
      await pause();
    } on Object {
      // A replaced platform view may already be detached.
    }
  }
}

class _ActiveVideoFrame extends StatelessWidget {
  const _ActiveVideoFrame({required this.data, required this.child});

  final InlineVideoData data;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      _OpenVideoButton(data: data),
    ],
  );
}

class _OpenVideoButton extends StatelessWidget {
  const _OpenVideoButton({required this.data});

  final InlineVideoData data;

  @override
  Widget build(BuildContext context) {
    final label = 'Open video: ${data.title}';
    void open() => unawaited(openExternalLink(data.source.toString()));
    return Positioned(
      top: 8,
      right: 8,
      child: Semantics(
        link: true,
        label: label,
        onTap: open,
        child: ExcludeSemantics(
          child: Tooltip(
            message: 'Open video',
            child: IconButton.filled(
              onPressed: open,
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
    );
  }
}

class _VideoFailure extends StatelessWidget {
  const _VideoFailure({required this.data});

  final InlineVideoData data;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Couldn't play this video.",
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          DButton(
            label: const Text('Open video'),
            onPressed: () =>
                unawaited(openExternalLink(data.source.toString())),
            variant: DButtonVariant.link,
          ),
        ],
      ),
    ),
  );
}

final class _VideoSourceResolution {
  _VideoSourceResolution({
    required this.data,
    required this.siteUrl,
    required ApiCredentialReader? credentials,
    required SiteLifecycle? lifecycle,
  }) : _resolver = siteUrl == null || credentials == null || lifecycle == null
           ? null
           : SiteVideoSourceResolver(
               credentials: credentials,
               lifecycle: lifecycle,
             );

  final InlineVideoData data;
  final String? siteUrl;
  final SiteVideoSourceResolver? _resolver;

  Future<SiteVideoSource> resolve() {
    final resolver = _resolver;
    final connectedSite = siteUrl;
    if (resolver == null || connectedSite == null) {
      return Future.value(SiteVideoSource(data.source));
    }
    return resolver.resolve(siteUrl: connectedSite, url: data.source);
  }

  void cancel() => _resolver?.close();
}

Uri? _safeAbsoluteUrl(String? value, String? siteUrl) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) return null;
  final resolved = Uri.tryParse(resolveSiteUrl(candidate, siteUrl));
  if (resolved == null) return null;
  try {
    return requireSafeHttpUrl(resolved);
  } on UnsafeHttpTransportException {
    return null;
  }
}

double? _elementAspectRatio(dom.Element element, {String dataPrefix = ''}) {
  final width = double.tryParse(
    element.attributes['${dataPrefix}width'] ??
        element.attributes['width'] ??
        '',
  );
  final height = double.tryParse(
    element.attributes['${dataPrefix}height'] ??
        element.attributes['height'] ??
        '',
  );
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return width / height;
}

double _safeAspectRatio(double? value) {
  if (value == null || !value.isFinite || value <= 0) return 16 / 9;
  return value.clamp(1 / 4, 4).toDouble();
}

String _filename(Uri source) {
  final segments = source.pathSegments.where((part) => part.isNotEmpty);
  return segments.isEmpty ? 'Video' : segments.last;
}

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

Uri _originOf(Uri url) => Uri(
  scheme: url.scheme,
  host: url.host,
  port: url.hasPort ? url.port : null,
  path: '/',
);

void _reportVideoError(Object error, StackTrace stackTrace, String operation) {
  DiagnosticsSink.current.reportError(
    error,
    stackTrace,
    operation: operation,
    source: 'platform',
    severity: DiagnosticSeverity.warning,
    handled: true,
    degraded: true,
  );
}
