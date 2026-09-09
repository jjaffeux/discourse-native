// Offline fixture mounts production controls; it never creates a media session
// connected to a platform player, credentials or a remote service.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const SliderReviewApp());
}

class SliderReviewApp extends StatefulWidget {
  const SliderReviewApp({super.key});
  @override
  State<SliderReviewApp> createState() => _SliderReviewAppState();
}

class _SliderReviewAppState extends State<SliderReviewApp> {
  bool _dark = false, _rtl = false, _disabled = false, _visible = true;
  double _scale = 1, _volume = 0.7;
  int _post = 30;
  late SliderReviewPlaybackSession _session;
  late final InlineVideoPlaybackSessionFactory _factory = _createSession;
  InlineVideoPlaybackSession _createSession(InlineVideoPlaybackRequest _) =>
      _session = SliderReviewPlaybackSession()..setReady(!_disabled);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Slider review — offline production widgets'),
        ),
        body: Directionality(
          textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(_scale)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DButton(
                        label: const Text('Styleguide'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ComponentStyleguidePage(),
                          ),
                        ),
                      ),
                      DButton(
                        label: const Text('Light / dark'),
                        onPressed: () => setState(() => _dark = !_dark),
                      ),
                      DButton(
                        label: const Text('RTL'),
                        onPressed: () => setState(() => _rtl = !_rtl),
                      ),
                      DButton(
                        label: const Text('Text 1× / 2×'),
                        onPressed: () =>
                            setState(() => _scale = _scale == 1 ? 2 : 1),
                      ),
                      DButton(
                        label: const Text('Disable / enable'),
                        onPressed: () => setState(() {
                          _disabled = !_disabled;
                          _session.setReady(!_disabled);
                        }),
                      ),
                      DButton(
                        label: const Text('Remove / restore'),
                        onPressed: () => setState(() => _visible = !_visible),
                      ),
                      DButton(
                        label: const Text('External playback tick'),
                        onPressed: () =>
                            _session.seekTo(const Duration(seconds: 70)),
                      ),
                    ],
                  ),
                  if (_visible) ...[
                    const SizedBox(height: 24),
                    Text('Topic jump editor: post $_post of 100'),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: TopicPositionSlider(
                        position: _post,
                        total: 100,
                        onChanged: _disabled
                            ? null
                            : (value) => setState(() => _post = value),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Participant volume: ${(_volume * 100).round()}%'),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: VoiceParticipantVolumeSlider(
                        value: _volume,
                        onChanged: _disabled
                            ? null
                            : (value) => setState(() => _volume = value),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Inline video: seek track, buffered value and playback state',
                    ),
                    SizedBox(
                      width: 560,
                      height: 315,
                      child: InlineVideoPlaybackSurface(
                        siteUrl: null,
                        credentials: null,
                        lifecycle: null,
                        data: InlineVideoData.fromUpload(
                          url: 'https://offline.invalid/slider.mp4',
                          siteUrl: 'https://offline.invalid',
                          title: 'Local slider fixture',
                        )!,
                        sessionFactory: _factory,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SliderReviewPlaybackSession extends ChangeNotifier
    implements InlineVideoPlaybackSession {
  bool _ready = true, _playing = false;
  Duration _position = const Duration(seconds: 30);
  @override
  InlineVideoPlaybackState get state => InlineVideoPlaybackState(
    phase: InlineVideoPlaybackPhase.ready,
    aspectRatio: 16 / 9,
    playerBuilder: () => const ColoredBox(
      color: Color(0xff202020),
      child: Center(
        child: Text(
          'Local playback fixture',
          style: TextStyle(color: Colors.white),
        ),
      ),
    ),
    isPlaying: _playing,
    position: _position,
    duration: _ready ? const Duration(seconds: 120) : Duration.zero,
    buffered: const Duration(seconds: 90),
    showAppControls: true,
  );
  void setReady(bool ready) {
    _ready = ready;
    notifyListeners();
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> play() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    _position = position;
    notifyListeners();
  }
}
