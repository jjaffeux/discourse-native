import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../../foundation/foreground_lifecycle.dart';
import '../inline_video_playback.dart';
import '../open_link.dart';
import '../shell_scope.dart';
import 'embedded.dart';

class AudioOneboxData {
  const AudioOneboxData({required this.source, required this.title});
  final Uri source;
  final String title;

  static AudioOneboxData? from(dom.Element element, {String? siteUrl}) {
    if (element.localName != 'audio') return null;
    final source = oneboxHttpUri(
      element.attributes['src'] ??
          element.querySelector('source[src]')?.attributes['src'],
      siteUrl: siteUrl,
    );
    if (source == null) return null;
    final label =
        element.attributes['title'] ?? element.attributes['aria-label'];
    String filename;
    try {
      filename = source.pathSegments.lastWhere(
        (part) => part.isNotEmpty,
        orElse: () => 'Audio',
      );
    } on FormatException {
      filename = 'Audio';
    }
    return AudioOneboxData(
      source: source,
      title: label?.trim().isNotEmpty == true ? label!.trim() : filename,
    );
  }
}

Widget? audioOneboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final data = AudioOneboxData.from(element, siteUrl: siteUrl);
  return data == null ? null : AudioOnebox(data: data, siteUrl: siteUrl);
}

class AudioOnebox extends StatefulWidget {
  const AudioOnebox({
    super.key,
    required this.data,
    this.siteUrl,
    this.sessionFactory = createInlineVideoPlaybackSession,
  });
  final AudioOneboxData data;
  final String? siteUrl;
  final InlineVideoPlaybackSessionFactory sessionFactory;

  @override
  State<AudioOnebox> createState() => _AudioOneboxState();
}

class _AudioOneboxState extends State<AudioOnebox> with WidgetsBindingObserver {
  InlineVideoPlaybackSession? _session;
  bool _visible = true;
  bool _foreground = true;
  InlineVideoPlaybackSession? _pausing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = isForegroundLifecycle(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    if (!_visible) unawaited(_session?.pause());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = isForegroundLifecycle(state);
    if (!_foreground) unawaited(_session?.pause());
  }

  @override
  void didUpdateWidget(AudioOnebox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.source != widget.data.source ||
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.sessionFactory != widget.sessionFactory) {
      _retire();
    }
  }

  void _retire() {
    _session?.removeListener(_changed);
    _session?.dispose();
    _session = null;
  }

  void _changed() {
    final session = _session;
    if ((!_visible || !_foreground) &&
        session != null &&
        session.state.isPlaying &&
        !identical(_pausing, session)) {
      _pausing = session;
      unawaited(
        session.pause().whenComplete(() {
          if (identical(_pausing, session)) _pausing = null;
        }),
      );
    }
    if (mounted) setState(() {});
  }

  void _start() {
    if (!_foreground || !_visible) return;
    _retire();
    final shell = ShellScope.maybeIdentityOf(context);
    final session = widget.sessionFactory(
      InlineVideoPlaybackRequest(
        source: widget.data.source,
        title: widget.data.title,
        posterUrl: null,
        aspectRatio: 1,
        siteUrl: widget.siteUrl,
        credentials: shell?.credentials,
        lifecycle: shell?.lifecycle,
        audioOnly: true,
      ),
    );
    _session = session;
    session.addListener(_changed);
    setState(() {});
    unawaited(session.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _session?.state;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
      child: Stack(
        children: [
          // Linux's audio transport needs an attached WebView, with no visual
          // controls. Playback UI and semantics belong to DAudioPlayer.
          if (state?.playerBuilder != null && state!.showAppControls)
            ExcludeSemantics(
              child: IgnorePointer(
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: state.playerBuilder!(),
                ),
              ),
            ),
          DAudioPlayer(
            title: widget.data.title,
            loading: state?.phase == InlineVideoPlaybackPhase.initializing,
            failed: state?.phase == InlineVideoPlaybackPhase.failed,
            playing: state?.isPlaying ?? false,
            position: state?.position ?? Duration.zero,
            duration: state?.duration ?? Duration.zero,
            onPlayPause: () {
              final session = _session;
              if (session == null) {
                _start();
                return;
              }
              if (session.state.isPlaying) {
                unawaited(session.pause());
              } else if (_foreground && _visible) {
                unawaited(session.play());
              }
            },
            onSeek: (position) => unawaited(_session?.seekTo(position)),
            onRetry: _start,
            onOpen: () => unawaited(
              openLink(
                context,
                widget.data.source.toString(),
                siteUrl: widget.siteUrl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
