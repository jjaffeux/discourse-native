import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:html/dom.dart' as dom;

import '../data/api_credentials.dart';
import '../data/http_transport.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/uri_path.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'inline_video_playback.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'site_url.dart';
import 'video_download.dart';

export 'inline_video_playback.dart'
    show
        InlineVideoPlaybackPhase,
        InlineVideoPlaybackRequest,
        InlineVideoPlaybackSession,
        InlineVideoPlaybackSessionFactory,
        InlineVideoPlaybackState,
        buildInlineVideoHtml,
        createInlineVideoPlaybackSession;

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

typedef InlineVideoPlayerBuilder =
    Widget Function(BuildContext context, InlineVideoData data);

/// A lazy, app-owned shell around the platform video implementation.
class InlineVideo extends StatefulWidget {
  const InlineVideo({
    super.key,
    required this.data,
    required this.siteUrl,
    this.playerBuilder,
    this.sessionFactory,
    this.videoDownloader,
    this.maximumWidth,
    this.maximumHeight = 480,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  }) : assert(maximumWidth == null || maximumWidth > 0),
       assert(maximumHeight == null || maximumHeight > 0);

  final InlineVideoData data;
  final String? siteUrl;
  final InlineVideoPlayerBuilder? playerBuilder;
  final InlineVideoPlaybackSessionFactory? sessionFactory;
  final VideoDownloader? videoDownloader;
  final double? maximumWidth;
  final double? maximumHeight;
  final EdgeInsetsGeometry padding;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  bool _loaded = false;
  final _downloading = ValueNotifier(false);

  Future<void> _download(BuildContext actionContext) async {
    if (_downloading.value) return;
    final data = widget.data;
    final shell = ShellScope.maybeIdentityOf(context);
    final messenger = ScaffoldMessenger.maybeOf(actionContext);
    final renderObject = actionContext.findRenderObject();
    final shareOrigin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    _downloading.value = true;
    try {
      final outcome = await (widget.videoDownloader ?? NativeVideoDownloader())
          .download(
            url: data.source,
            title: data.title,
            siteUrl: widget.siteUrl,
            credentials: shell?.authenticator,
            lifecycle: shell?.lifecycle,
            sharePositionOrigin: shareOrigin,
          );
      if (!mounted || messenger?.mounted != true) return;
      if (outcome == VideoDownloadOutcome.saved) {
        final filename = videoDownloadFilename(
          title: data.title,
          url: data.source,
        );
        messenger!
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Saved $filename.')));
      }
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'video.download',
        source: 'platform',
        severity: DiagnosticSeverity.warning,
        handled: true,
      );
      if (mounted && messenger?.mounted == true) {
        messenger!
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text("Couldn't download video. Try again."),
            ),
          );
      }
    } finally {
      if (mounted) _downloading.value = false;
    }
  }

  Widget _buildActions(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _downloading,
    builder: (context, downloading, _) => Positioned.fill(
      top: 8,
      left: 8,
      right: 8,
      bottom: 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final download = IconButton.filled(
            key: const ValueKey('inline-video-download'),
            tooltip: downloading ? 'Downloading video…' : 'Download video',
            onPressed: downloading ? null : () => unawaited(_download(context)),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xBB000000),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xBB000000),
            ),
            icon: downloading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const DIcon(DIcons.download, size: 18, color: Colors.white),
          );
          final open = _OpenVideoButton(data: widget.data);
          if (constraints.maxWidth < 100) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [open, download],
            );
          }
          return Align(
            alignment: Alignment.topRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [download, const SizedBox(width: 4), open],
            ),
          );
        },
      ),
    ),
  );

  @override
  void dispose() {
    _downloading.dispose();
    super.dispose();
  }

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
    if (custom != null) {
      return _ActiveVideoFrame(
        data: widget.data,
        actions: _buildActions(context),
        child: custom(context, widget.data),
      );
    }

    final shell = ShellScope.maybeIdentityOf(context);
    return InlineVideoPlaybackSurface(
      data: widget.data,
      siteUrl: widget.siteUrl,
      credentials: shell?.authenticator,
      lifecycle: shell?.lifecycle,
      sessionFactory: widget.sessionFactory ?? createInlineVideoPlaybackSession,
      actionsBuilder: _buildActions,
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
                        key: const ValueKey('inline-video-play'),
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
        _buildActions(context),
      ],
    );
  }
}

class InlineVideoPlaybackSurface extends StatefulWidget {
  const InlineVideoPlaybackSurface({
    super.key,
    required this.data,
    required this.siteUrl,
    required this.credentials,
    required this.lifecycle,
    required this.sessionFactory,
    this.actionsBuilder,
  });

  final InlineVideoData data;
  final String? siteUrl;
  final ApiCredentialReader? credentials;
  final SiteLifecycle? lifecycle;
  final InlineVideoPlaybackSessionFactory sessionFactory;
  final WidgetBuilder? actionsBuilder;

  @override
  State<InlineVideoPlaybackSurface> createState() =>
      _InlineVideoPlaybackSurfaceState();
}

class _InlineVideoPlaybackSurfaceState extends State<InlineVideoPlaybackSurface>
    with WidgetsBindingObserver {
  InlineVideoPlaybackSession? _session;
  InlineVideoPlaybackSession? _fullscreenSession;
  InlineVideoPlaybackSession? _pausingSession;
  bool _tickerEnabled = true;
  bool _fullscreenTickerEnabled = false;
  bool _appResumed = true;
  bool? _playbackVisible;

  bool get _fullscreenOpen => _fullscreenSession != null;

  bool get _canPlay =>
      _appResumed &&
      (_tickerEnabled ||
          (identical(_fullscreenSession, _session) &&
              _fullscreenTickerEnabled));

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appResumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_session == null) {
      _replaceSession();
    } else {
      _syncPlaybackVisibility();
    }
  }

  @override
  void didUpdateWidget(InlineVideoPlaybackSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playbackIdentity != widget.data.playbackIdentity ||
        oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.credentials, widget.credentials) ||
        !identical(oldWidget.lifecycle, widget.lifecycle) ||
        !identical(oldWidget.sessionFactory, widget.sessionFactory)) {
      _replaceSession();
    }
  }

  void _replaceSession() {
    final previous = _session;
    _session = null;
    if (previous != null) {
      previous.removeListener(_syncPlaybackVisibility);
      _InlineVideoPlaybackCoordinator.release(previous);
      previous.dispose();
    }

    final session = widget.sessionFactory(
      InlineVideoPlaybackRequest(
        source: widget.data.source,
        title: widget.data.title,
        posterUrl: widget.data.posterUrl,
        aspectRatio: widget.data.aspectRatio,
        siteUrl: widget.siteUrl,
        credentials: widget.credentials,
        lifecycle: widget.lifecycle,
      ),
    );
    _session = session;
    _playbackVisible = null;
    session.addListener(_syncPlaybackVisibility);
    _syncPlaybackVisibility();
    if (mounted) setState(() {});
    unawaited(session.start());
  }

  void _syncPlaybackVisibility() {
    final session = _session;
    if (!mounted || session == null) return;
    final visible = _canPlay;
    final changed = _playbackVisible != visible;
    _playbackVisible = visible;
    if (!visible) {
      _InlineVideoPlaybackCoordinator.release(session);
      if (changed || session.state.isPlaying) unawaited(_pauseHidden(session));
    } else if (session.state.isPlaying) {
      _InlineVideoPlaybackCoordinator.activate(session, session.pause);
    }
  }

  Future<void> _pauseHidden(InlineVideoPlaybackSession session) async {
    if (identical(_pausingSession, session)) return;
    _pausingSession = session;
    try {
      await session.pause();
    } on Object {
      // A replaced platform view may already be detached.
      return;
    } finally {
      if (identical(_pausingSession, session)) _pausingSession = null;
    }
    if (mounted && identical(_session, session) && !_canPlay) {
      _syncPlaybackVisibility();
    }
  }

  void _retry() => _replaceSession();

  Future<void> _togglePlayback() async {
    final session = _session;
    if (!_canPlay ||
        session == null ||
        session.state.phase != InlineVideoPlaybackPhase.ready) {
      return;
    }
    if (session.state.isPlaying) {
      await session.pause();
    } else {
      _InlineVideoPlaybackCoordinator.activate(session, session.pause);
      await session.play();
    }
  }

  Future<void> _openFullscreen() async {
    final session = _session;
    if (!_canPlay ||
        _fullscreenOpen ||
        session == null ||
        !session.state.supportsFullscreen) {
      return;
    }
    setState(() {
      _fullscreenSession = session;
      _fullscreenTickerEnabled = true;
    });
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'inline-video-fullscreen'),
          fullscreenDialog: true,
          builder: (context) => _InlineVideoFullscreen(
            data: widget.data,
            session: session,
            onVisibilityChanged: (visible) {
              if (!mounted || !identical(_fullscreenSession, session)) return;
              _fullscreenTickerEnabled = visible;
              // Inline and fullscreen controls listen from different routes.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && identical(_fullscreenSession, session)) {
                  _syncPlaybackVisibility();
                }
              });
            },
            onTogglePlayback: () => unawaited(_togglePlayback()),
            actionsBuilder: widget.actionsBuilder,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _fullscreenSession = null;
          _fullscreenTickerEnabled = false;
        });
        // The source route receives its restored TickerMode during this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncPlaybackVisibility();
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncPlaybackVisibility();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    return _ActiveVideoFrame(
      data: widget.data,
      actions: widget.actionsBuilder?.call(context),
      child: _PlaybackStateBuilder(
        session: session,
        select: _selectPresentation,
        builder: (context, presentation) {
          if (presentation.phase == InlineVideoPlaybackPhase.failed) {
            return _VideoFailure(data: widget.data, onRetry: _retry);
          }
          final playerBuilder = presentation.playerBuilder;
          if (playerBuilder == null) {
            return const ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
          }
          return Semantics(
            label: 'Video player: ${widget.data.title}',
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: presentation.aspectRatio,
                      child: _fullscreenOpen
                          ? const SizedBox.shrink()
                          : playerBuilder(),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _PlaybackControls(
                      session: session,
                      onTogglePlayback: () => unawaited(_togglePlayback()),
                      onSeek: session.seekTo,
                      onEnterFullscreen: () => unawaited(_openFullscreen()),
                    ),
                  ),
                  _PlaybackBuffering(session: session),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
    _session = null;
    if (session != null) {
      session.removeListener(_syncPlaybackVisibility);
      _InlineVideoPlaybackCoordinator.release(session);
      session.dispose();
    }
    super.dispose();
  }
}

typedef _PlaybackPresentation = ({
  InlineVideoPlaybackPhase phase,
  double aspectRatio,
  Widget Function()? playerBuilder,
});

_PlaybackPresentation _selectPresentation(InlineVideoPlaybackState state) => (
  phase: state.phase,
  aspectRatio: state.aspectRatio,
  playerBuilder: state.playerBuilder,
);

/// Selects playback values without caching widgets that depend on inherited
/// context. Parent and environment changes still rebuild normally.
class _PlaybackStateBuilder<T> extends StatefulWidget {
  const _PlaybackStateBuilder({
    required this.session,
    required this.select,
    required this.builder,
  });

  final InlineVideoPlaybackSession session;
  final T Function(InlineVideoPlaybackState state) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_PlaybackStateBuilder<T>> createState() =>
      _PlaybackStateBuilderState<T>();
}

class _PlaybackStateBuilderState<T> extends State<_PlaybackStateBuilder<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.session.state);
    widget.session.addListener(_select);
  }

  @override
  void didUpdateWidget(_PlaybackStateBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeListener(_select);
      widget.session.addListener(_select);
    }
    _value = widget.select(widget.session.state);
  }

  void _select() {
    final next = widget.select(widget.session.state);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);

  @override
  void dispose() {
    widget.session.removeListener(_select);
    super.dispose();
  }
}

class _PlaybackBuffering extends StatelessWidget {
  const _PlaybackBuffering({required this.session});

  final InlineVideoPlaybackSession session;

  @override
  Widget build(BuildContext context) => _PlaybackStateBuilder(
    session: session,
    select: (state) => state.isBuffering,
    builder: (context, isBuffering) => isBuffering
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : const SizedBox.shrink(),
  );
}

class _InlineVideoFullscreen extends StatefulWidget {
  const _InlineVideoFullscreen({
    required this.data,
    required this.session,
    required this.onTogglePlayback,
    required this.onVisibilityChanged,
    this.actionsBuilder,
  });

  final InlineVideoData data;
  final InlineVideoPlaybackSession session;
  final VoidCallback onTogglePlayback;
  final ValueChanged<bool> onVisibilityChanged;
  final WidgetBuilder? actionsBuilder;

  @override
  State<_InlineVideoFullscreen> createState() => _InlineVideoFullscreenState();
}

class _InlineVideoFullscreenState extends State<_InlineVideoFullscreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onVisibilityChanged(TickerMode.valuesOf(context).enabled);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).pop(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        key: const ValueKey('inline-video-fullscreen-view'),
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _PlaybackStateBuilder(
            session: widget.session,
            select: _selectPresentation,
            builder: (context, presentation) {
              final playerBuilder = presentation.playerBuilder;
              if (playerBuilder == null) return const SizedBox.shrink();
              return Semantics(
                label: 'Full-screen video player: ${widget.data.title}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: presentation.aspectRatio,
                        child: playerBuilder(),
                      ),
                    ),
                    if (widget.actionsBuilder case final buildActions?)
                      buildActions(context),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PlaybackControls(
                        session: widget.session,
                        onTogglePlayback: widget.onTogglePlayback,
                        onSeek: widget.session.seekTo,
                        onExitFullscreen: Navigator.of(context).pop,
                      ),
                    ),
                    _PlaybackBuffering(session: widget.session),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.session,
    required this.onTogglePlayback,
    required this.onSeek,
    this.onEnterFullscreen,
    this.onExitFullscreen,
  }) : assert(onEnterFullscreen == null || onExitFullscreen == null);

  final InlineVideoPlaybackSession session;
  final VoidCallback onTogglePlayback;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;

  @override
  Widget build(BuildContext context) => _PlaybackStateBuilder(
    session: session,
    select: (state) => (
      showControls: state.showAppControls,
      supportsFullscreen: state.supportsFullscreen,
    ),
    builder: (context, controls) {
      if (!controls.showControls) return const SizedBox.shrink();
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xDD000000)],
          ),
        ),
        child: Row(
          children: [
            _PlaybackStateBuilder(
              session: session,
              select: (state) => state.isPlaying,
              builder: (context, isPlaying) => IconButton(
                tooltip: isPlaying ? 'Pause' : 'Play',
                color: Colors.white,
                onPressed: onTogglePlayback,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ),
            Expanded(
              child: _PlaybackTimeline(session: session, onSeek: onSeek),
            ),
            if (onExitFullscreen case final exit?)
              IconButton(
                key: const ValueKey('inline-video-fullscreen-close'),
                tooltip: 'Exit full screen',
                color: Colors.white,
                onPressed: exit,
                icon: const Icon(Icons.fullscreen_exit_rounded),
              )
            else if (onEnterFullscreen != null && controls.supportsFullscreen)
              IconButton(
                key: const ValueKey('inline-video-fullscreen'),
                tooltip: 'Enter full screen',
                color: Colors.white,
                onPressed: onEnterFullscreen,
                icon: const DIcon(DIcons.expand, size: 18, color: Colors.white),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      );
    },
  );
}

class _PlaybackTimeline extends StatelessWidget {
  const _PlaybackTimeline({required this.session, required this.onSeek});

  final InlineVideoPlaybackSession session;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) => _PlaybackStateBuilder(
    session: session,
    select: (state) => (
      position: state.position,
      duration: state.duration,
      buffered: state.buffered,
    ),
    builder: (context, timeline) {
      final durationMilliseconds = timeline.duration.inMilliseconds;
      final positionMilliseconds = timeline.position.inMilliseconds.clamp(
        0,
        math.max(durationMilliseconds, 0),
      );
      final bufferedMilliseconds = timeline.buffered.inMilliseconds.clamp(
        positionMilliseconds,
        math.max(durationMilliseconds, positionMilliseconds),
      );
      return Row(
        children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: const Color(0x55FFFFFF),
                secondaryActiveTrackColor: const Color(0x88FFFFFF),
                thumbColor: Colors.white,
                overlayColor: const Color(0x33FFFFFF),
                trackHeight: 2,
              ),
              child: Slider(
                value: durationMilliseconds > 0
                    ? positionMilliseconds.toDouble()
                    : 0,
                max: math.max(durationMilliseconds, 1).toDouble(),
                secondaryTrackValue: durationMilliseconds > 0
                    ? bufferedMilliseconds.toDouble()
                    : null,
                onChanged: durationMilliseconds > 0
                    ? (value) => onSeek(Duration(milliseconds: value.round()))
                    : null,
              ),
            ),
          ),
          Text(
            '${_duration(timeline.position)} / ${_duration(timeline.duration)}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white),
          ),
        ],
      );
    },
  );
}

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
  const _ActiveVideoFrame({
    required this.data,
    required this.child,
    this.actions,
  });

  final InlineVideoData data;
  final Widget child;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      actions ??
          Positioned(top: 8, right: 8, child: _OpenVideoButton(data: data)),
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
    return Semantics(
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
    );
  }
}

class _VideoFailure extends StatelessWidget {
  const _VideoFailure({required this.data, required this.onRetry});

  final InlineVideoData data;
  final VoidCallback onRetry;

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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DButton(
                label: const Text('Try again'),
                onPressed: onRetry,
                variant: DButtonVariant.link,
              ),
              DButton(
                label: const Text('Open video'),
                onPressed: () =>
                    unawaited(openExternalLink(data.source.toString())),
                variant: DButtonVariant.link,
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
  final segments = tryUriPathSegments(source)?.where((part) => part.isNotEmpty);
  return segments == null || segments.isEmpty ? 'Video' : segments.last;
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
