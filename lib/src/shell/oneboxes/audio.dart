import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../inline_video_playback.dart';
import '../open_link.dart';
import '../reader_media_host.dart';
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
        orElse: () => appL10n.audio,
      );
    } on FormatException {
      filename = appL10n.audio;
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

class _AudioOneboxState extends State<AudioOnebox>
    with ReaderMediaHost<AudioOnebox> {
  InlineVideoPlaybackSession? _session;

  Object get _mediaSource => (
    widget.data.source,
    widget.siteUrl,
    widget.sessionFactory,
    mediaAccountFor(widget.siteUrl)?.session,
  );

  @override
  void mediaAccountRetired() {
    _retire();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AudioOnebox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_session != null && mediaActivity.attachment?.source != _mediaSource) {
      _retire();
    }
  }

  void _retire() {
    _session?.removeListener(_changed);
    mediaActivity.retire();
    _session = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _start() {
    if (!mediaActivity.mayStart) return;
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
    final account = mediaAccountFor(widget.siteUrl);
    mediaActivity.attachPlayback(
      source: _mediaSource,
      session: session,
      account: account,
    );
    session.addListener(_changed);
    setState(() {});
    unawaited(session.start());
  }

  @override
  void dispose() {
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
              } else if (mediaActivity.claimPlay(mediaActivity.attachment!)) {
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
