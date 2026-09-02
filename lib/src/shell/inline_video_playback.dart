import 'dart:async';
import 'dart:convert' show htmlEscape;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_all/webview_all.dart';

import '../data/api_credentials.dart';
import '../data/http_transport.dart';
import '../data/site_lifecycle.dart';
import '../data/site_video_source.dart';
import '../diagnostics/diagnostics_controller.dart';
import 'external_link.dart';
import 'media_webview.dart';

@immutable
final class InlineVideoPlaybackRequest {
  const InlineVideoPlaybackRequest({
    required this.source,
    required this.title,
    required this.posterUrl,
    required this.aspectRatio,
    required this.siteUrl,
    required this.credentials,
    required this.lifecycle,
  });

  final Uri source;
  final String title;
  final String? posterUrl;
  final double aspectRatio;
  final String? siteUrl;
  final ApiCredentialReader? credentials;
  final SiteLifecycle? lifecycle;
}

enum InlineVideoPlaybackPhase { initializing, ready, failed }

@immutable
final class InlineVideoPlaybackState {
  const InlineVideoPlaybackState({
    required this.phase,
    required this.aspectRatio,
    this.playerBuilder,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.showAppControls = false,
    this.supportsFullscreen = false,
    this.error,
  });

  final InlineVideoPlaybackPhase phase;
  final double aspectRatio;
  final Widget Function()? playerBuilder;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool showAppControls;
  final bool supportsFullscreen;
  final Object? error;
}

/// App-owned playback boundary used by the inline-video presentation.
///
/// Platform controller types stay behind this interface. The view observes a
/// platform-neutral state snapshot and sends playback intents back to the
/// session, which makes lifecycle and race behavior deterministic in tests.
abstract interface class InlineVideoPlaybackSession implements Listenable {
  InlineVideoPlaybackState get state;

  Future<void> start();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  void dispose();
}

typedef InlineVideoPlaybackSessionFactory =
    InlineVideoPlaybackSession Function(InlineVideoPlaybackRequest request);

InlineVideoPlaybackSession createInlineVideoPlaybackSession(
  InlineVideoPlaybackRequest request, {
  TargetPlatform? platform,
}) {
  final selectedPlatform = platform ?? defaultTargetPlatform;
  switch (selectedPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _NativeInlineVideoPlaybackSession(request);
    case TargetPlatform.linux:
      return _WebViewInlineVideoPlaybackSession(request);
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.windows:
      return _UnsupportedInlineVideoPlaybackSession(request, selectedPlatform);
  }
}

abstract base class _InlineVideoPlaybackSessionBase extends ChangeNotifier
    implements InlineVideoPlaybackSession {
  _InlineVideoPlaybackSessionBase(this.request)
    : _state = InlineVideoPlaybackState(
        phase: InlineVideoPlaybackPhase.initializing,
        aspectRatio: request.aspectRatio,
      );

  final InlineVideoPlaybackRequest request;
  InlineVideoPlaybackState _state;
  bool _disposed = false;
  bool _started = false;

  bool get isDisposed => _disposed;

  @override
  InlineVideoPlaybackState get state => _state;

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      await initialize();
    } on Object catch (error, stackTrace) {
      if (_disposed) return;
      reportFailure(error, stackTrace, initializeOperation);
    }
  }

  @protected
  Future<void> initialize();

  @protected
  String get initializeOperation;

  @protected
  void replaceState(InlineVideoPlaybackState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @protected
  void reportFailure(Object error, StackTrace stackTrace, String operation) {
    if (_disposed || _state.phase == InlineVideoPlaybackPhase.failed) return;
    releasePlatformResources();
    _reportVideoError(error, stackTrace, operation);
    replaceState(
      InlineVideoPlaybackState(
        phase: InlineVideoPlaybackPhase.failed,
        aspectRatio: request.aspectRatio,
        error: error,
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releasePlatformResources();
    super.dispose();
  }

  @protected
  void releasePlatformResources();
}

final class _NativeInlineVideoPlaybackSession
    extends _InlineVideoPlaybackSessionBase {
  _NativeInlineVideoPlaybackSession(super.request);

  _VideoSourceResolution? _sourceResolution;
  _NativeControllerLease? _controllerLease;

  VideoPlayerController? get _controller => _controllerLease?.controller;

  @override
  String get initializeOperation => 'video.native.initialize';

  @override
  Future<void> initialize() async {
    final resolution = _VideoSourceResolution(request);
    _sourceResolution = resolution;
    late final SiteVideoSource source;
    try {
      source = await resolution.resolve();
    } finally {
      if (identical(_sourceResolution, resolution)) {
        _sourceResolution = null;
        resolution.cancel();
      }
    }
    if (isDisposed) return;

    final controller = VideoPlayerController.networkUrl(source.url);
    final lease = _NativeControllerLease(controller, _playerChanged);
    _controllerLease = lease;
    controller.addListener(_playerChanged);
    await controller.initialize();
    if (isDisposed || !identical(_controllerLease, lease)) return;
    _publishControllerState(controller);
    await play();
  }

  void _playerChanged() {
    final controller = _controller;
    if (isDisposed || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      final error = StateError(
        value.errorDescription ?? 'The platform video player failed.',
      );
      _releaseController();
      reportFailure(error, StackTrace.current, 'video.native.playback');
      return;
    }
    _publishControllerState(controller);
  }

  void _publishControllerState(VideoPlayerController controller) {
    if (isDisposed || !identical(controller, _controller)) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    final ratio = value.aspectRatio.isFinite && value.aspectRatio > 0
        ? value.aspectRatio
        : request.aspectRatio;
    final buffered = value.buffered.fold(
      Duration.zero,
      (latest, range) => range.end > latest ? range.end : latest,
    );
    replaceState(
      InlineVideoPlaybackState(
        phase: InlineVideoPlaybackPhase.ready,
        aspectRatio: ratio,
        playerBuilder: () => VideoPlayer(controller),
        isPlaying: value.isPlaying,
        isBuffering: value.isBuffering,
        position: value.position,
        duration: value.duration,
        buffered: buffered,
        showAppControls: true,
        supportsFullscreen: true,
      ),
    );
  }

  @override
  Future<void> play() =>
      _runControl((controller) => controller.play(), 'video.native.controls');

  @override
  Future<void> pause() =>
      _runControl((controller) => controller.pause(), 'video.native.controls');

  @override
  Future<void> seekTo(Duration position) => _runControl(
    (controller) => controller.seekTo(position),
    'video.native.controls',
  );

  Future<void> _runControl(
    Future<void> Function(VideoPlayerController controller) action,
    String operation,
  ) async {
    final controller = _controller;
    if (isDisposed ||
        controller == null ||
        state.phase == InlineVideoPlaybackPhase.failed) {
      return;
    }
    try {
      await action(controller);
      _publishControllerState(controller);
    } on Object catch (error, stackTrace) {
      if (isDisposed || !identical(controller, _controller)) return;
      _releaseController();
      reportFailure(error, stackTrace, operation);
    }
  }

  void _releaseController() {
    final lease = _controllerLease;
    _controllerLease = null;
    lease?.release();
  }

  @override
  void releasePlatformResources() {
    _sourceResolution?.cancel();
    _sourceResolution = null;
    _releaseController();
  }
}

final class _NativeControllerLease {
  _NativeControllerLease(this.controller, this.listener);

  final VideoPlayerController controller;
  final VoidCallback listener;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    controller.removeListener(listener);
    unawaited(_dispose());
  }

  Future<void> _dispose() async {
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
}

final class _WebViewInlineVideoPlaybackSession
    extends _InlineVideoPlaybackSessionBase {
  _WebViewInlineVideoPlaybackSession(super.request);

  _VideoSourceResolution? _sourceResolution;
  WebViewController? _controller;
  bool _loadingDocument = true;
  bool _released = false;

  @override
  String get initializeOperation => 'video.webview.initialize';

  @override
  Future<void> initialize() async {
    final resolution = _VideoSourceResolution(request);
    _sourceResolution = resolution;
    late final SiteVideoSource source;
    try {
      source = await resolution.resolve();
    } finally {
      if (identical(_sourceResolution, resolution)) {
        _sourceResolution = null;
        resolution.cancel();
      }
    }
    if (isDisposed) return;

    final controller = WebViewController.fromPlatformCreationParams(
      mediaWebViewCreationParams(),
    );
    _controller = controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (!_isCurrent(controller)) return;
    await controller.addJavaScriptChannel(
      _videoBridgeName,
      onMessageReceived: (message) {
        if (!_isCurrent(controller)) return;
        switch (message.message) {
          case 'play':
            _publishReady(isPlaying: true);
          case 'error':
            _fail(
              StateError('The WebKit media element could not play the video.'),
              StackTrace.current,
              'video.webview.playback',
            );
        }
      },
    );
    if (!_isCurrent(controller)) return;
    await controller.setBackgroundColor(Colors.black);
    if (!_isCurrent(controller)) return;
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!_isCurrent(controller)) return NavigationDecision.prevent;
          if (!request.isMainFrame || _loadingDocument) {
            return NavigationDecision.navigate;
          }
          unawaited(openExternalLink(request.url));
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (!_isCurrent(controller) || !_loadingDocument) return;
          _loadingDocument = false;
          _publishReady(isPlaying: false);
          unawaited(play());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false || !_isCurrent(controller)) return;
          _fail(error, StackTrace.current, 'video.webview.playback');
        },
      ),
    );
    if (isDisposed) return;
    _publishReady(isPlaying: false);
    await controller.loadHtmlString(
      buildInlineVideoHtml(source.url, posterUrl: request.posterUrl),
      baseUrl: _originOf(source.url).toString(),
    );
    if (!_isCurrent(controller)) unawaited(_pauseIgnoringErrors(controller));
  }

  bool _isCurrent(WebViewController controller) =>
      !isDisposed && identical(_controller, controller);

  void _publishReady({required bool isPlaying}) {
    final controller = _controller;
    if (controller == null || !_isCurrent(controller)) return;
    replaceState(
      InlineVideoPlaybackState(
        phase: InlineVideoPlaybackPhase.ready,
        aspectRatio: request.aspectRatio,
        playerBuilder: () => WebViewWidget(
          controller: controller,
          gestureRecognizers: mediaPlayerGestureRecognizers,
        ),
        isPlaying: isPlaying,
        isBuffering: _loadingDocument,
      ),
    );
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller == null || !_isCurrent(controller)) return;
    try {
      await controller.runJavaScript(_playVideoScript);
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace, 'video.webview.controls');
    }
  }

  @override
  Future<void> pause() async {
    final controller = _controller;
    if (controller == null || !_isCurrent(controller)) return;
    await _pauseIgnoringErrors(controller);
    if (_isCurrent(controller)) _publishReady(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {}

  void _fail(Object error, StackTrace stackTrace, String operation) {
    if (isDisposed || state.phase == InlineVideoPlaybackPhase.failed) return;
    final controller = _controller;
    if (controller != null) unawaited(_pauseIgnoringErrors(controller));
    reportFailure(error, stackTrace, operation);
  }

  Future<void> _pauseIgnoringErrors(WebViewController controller) async {
    try {
      await controller.runJavaScript(_pauseVideoScript);
    } on Object {
      // The owned document may not exist yet during replacement or teardown.
    }
  }

  @override
  void releasePlatformResources() {
    if (_released) return;
    _released = true;
    _sourceResolution?.cancel();
    _sourceResolution = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_pauseIgnoringErrors(controller));
  }
}

final class _UnsupportedInlineVideoPlaybackSession
    extends _InlineVideoPlaybackSessionBase {
  _UnsupportedInlineVideoPlaybackSession(super.request, this.platform);

  final TargetPlatform platform;

  @override
  String get initializeOperation => 'video.unsupported.initialize';

  @override
  Future<void> initialize() async {
    throw UnsupportedError(
      'Inline video playback is unavailable on $platform.',
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  void releasePlatformResources() {}
}

String buildInlineVideoHtml(Uri source, {String? posterUrl}) {
  final safeSource = requireSafeHttpUrl(source);
  final safePoster = _safeAbsoluteUrl(posterUrl);
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

final class _VideoSourceResolution {
  _VideoSourceResolution(InlineVideoPlaybackRequest request)
    : data = request,
      _resolver =
          request.siteUrl == null ||
              request.credentials == null ||
              request.lifecycle == null
          ? null
          : SiteVideoSourceResolver(
              credentials: request.credentials!,
              lifecycle: request.lifecycle!,
            );

  final InlineVideoPlaybackRequest data;
  final SiteVideoSourceResolver? _resolver;

  Future<SiteVideoSource> resolve() {
    final resolver = _resolver;
    final connectedSite = data.siteUrl;
    if (resolver == null || connectedSite == null) {
      return Future.value(SiteVideoSource(data.source));
    }
    return resolver.resolve(siteUrl: connectedSite, url: data.source);
  }

  void cancel() => _resolver?.close();
}

Uri? _safeAbsoluteUrl(String? value) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) return null;
  final resolved = Uri.tryParse(candidate);
  if (resolved == null || !resolved.hasScheme || resolved.host.isEmpty) {
    return null;
  }
  try {
    return requireSafeHttpUrl(resolved);
  } on UnsafeHttpTransportException {
    return null;
  }
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
