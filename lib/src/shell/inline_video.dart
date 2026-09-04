import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:html/dom.dart' as dom;

import '../data/api_credentials.dart';
import '../data/http_transport.dart';
import '../data/site_lifecycle.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'inline_video_playback.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'site_url.dart';

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
    this.maximumWidth,
    this.maximumHeight = 480,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  }) : assert(maximumWidth == null || maximumWidth > 0),
       assert(maximumHeight == null || maximumHeight > 0);

  final InlineVideoData data;
  final String? siteUrl;
  final InlineVideoPlayerBuilder? playerBuilder;
  final InlineVideoPlaybackSessionFactory? sessionFactory;
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
    return InlineVideoPlaybackSurface(
      data: widget.data,
      siteUrl: widget.siteUrl,
      credentials: shell?.authenticator,
      lifecycle: shell?.lifecycle,
      sessionFactory: widget.sessionFactory ?? createInlineVideoPlaybackSession,
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

class InlineVideoPlaybackSurface extends StatefulWidget {
  const InlineVideoPlaybackSurface({
    super.key,
    required this.data,
    required this.siteUrl,
    required this.credentials,
    required this.lifecycle,
    required this.sessionFactory,
  });

  final InlineVideoData data;
  final String? siteUrl;
  final ApiCredentialReader? credentials;
  final SiteLifecycle? lifecycle;
  final InlineVideoPlaybackSessionFactory sessionFactory;

  @override
  State<InlineVideoPlaybackSurface> createState() =>
      _InlineVideoPlaybackSurfaceState();
}

class _InlineVideoPlaybackSurfaceState extends State<InlineVideoPlaybackSurface>
    with WidgetsBindingObserver {
  InlineVideoPlaybackSession? _session;
  bool _fullscreenOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _replaceSession();
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
      previous.removeListener(_sessionChanged);
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
    session.addListener(_sessionChanged);
    if (mounted) setState(() {});
    unawaited(session.start());
  }

  void _sessionChanged() {
    final session = _session;
    if (!mounted || session == null) return;
    if (session.state.isPlaying) {
      _InlineVideoPlaybackCoordinator.activate(session, session.pause);
    }
    setState(() {});
  }

  void _retry() => _replaceSession();

  Future<void> _togglePlayback() async {
    final session = _session;
    if (session == null ||
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
    if (_fullscreenOpen ||
        session == null ||
        !session.state.supportsFullscreen) {
      return;
    }
    setState(() => _fullscreenOpen = true);
    try {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'inline-video-fullscreen'),
          fullscreenDialog: true,
          builder: (context) => _InlineVideoFullscreen(
            data: widget.data,
            session: session,
            onTogglePlayback: () => unawaited(_togglePlayback()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fullscreenOpen = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final session = _session;
      if (session != null) unawaited(session.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final state = session?.state;
    if (state?.phase == InlineVideoPlaybackPhase.failed) {
      return _VideoFailure(data: widget.data, onRetry: _retry);
    }
    final playerBuilder = state?.playerBuilder;
    if (session == null || playerBuilder == null) {
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
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: state!.aspectRatio,
                  child: _fullscreenOpen
                      ? const SizedBox.shrink()
                      : playerBuilder(),
                ),
              ),
              if (state.showAppControls)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PlaybackControls(
                    state: state,
                    onTogglePlayback: () => unawaited(_togglePlayback()),
                    onSeek: session.seekTo,
                    onEnterFullscreen: state.supportsFullscreen
                        ? () => unawaited(_openFullscreen())
                        : null,
                  ),
                ),
              if (state.isBuffering)
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
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
    _session = null;
    if (session != null) {
      session.removeListener(_sessionChanged);
      _InlineVideoPlaybackCoordinator.release(session);
      session.dispose();
    }
    super.dispose();
  }
}

class _InlineVideoFullscreen extends StatelessWidget {
  const _InlineVideoFullscreen({
    required this.data,
    required this.session,
    required this.onTogglePlayback,
  });

  final InlineVideoData data;
  final InlineVideoPlaybackSession session;
  final VoidCallback onTogglePlayback;

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
          child: AnimatedBuilder(
            animation: session,
            builder: (context, _) {
              final state = session.state;
              final playerBuilder = state.playerBuilder;
              if (playerBuilder == null) return const SizedBox.shrink();
              return Semantics(
                label: 'Full-screen video player: ${data.title}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: state.aspectRatio,
                        child: playerBuilder(),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PlaybackControls(
                        state: state,
                        onTogglePlayback: onTogglePlayback,
                        onSeek: session.seekTo,
                        onExitFullscreen: Navigator.of(context).pop,
                      ),
                    ),
                    if (state.isBuffering)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
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
    required this.state,
    required this.onTogglePlayback,
    required this.onSeek,
    this.onEnterFullscreen,
    this.onExitFullscreen,
  }) : assert(onEnterFullscreen == null || onExitFullscreen == null);

  final InlineVideoPlaybackState state;
  final VoidCallback onTogglePlayback;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final durationMilliseconds = state.duration.inMilliseconds;
    final positionMilliseconds = state.position.inMilliseconds.clamp(
      0,
      math.max(durationMilliseconds, 0),
    );
    final bufferedMilliseconds = state.buffered.inMilliseconds.clamp(
      positionMilliseconds,
      math.max(durationMilliseconds, positionMilliseconds),
    );
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
          IconButton(
            tooltip: state.isPlaying ? 'Pause' : 'Play',
            color: Colors.white,
            onPressed: onTogglePlayback,
            icon: DIcon(state.isPlaying ? DIcons.pause : DIcons.play),
          ),
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
            '${_duration(state.position)} / ${_duration(state.duration)}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white),
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
              icon: const DIcon(DIcons.discourseCompress),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
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
