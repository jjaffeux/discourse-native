import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_video_playback.dart';
import 'package:discourse_native/src/shell/oneboxes/audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  test('core audio markup resolves uploads and rejects unsafe URLs', () {
    final data = AudioOneboxData.from(
      html
          .parseFragment('<audio><source src="/uploads/recording.mp3"></audio>')
          .children
          .single,
      siteUrl: 'https://forum.test',
    );
    expect(data!.source.toString(), 'https://forum.test/uploads/recording.mp3');
    expect(data.title, 'recording.mp3');
    for (final url in [
      'javascript:alert(1)',
      'file:///recording.mp3',
      'https://user:secret@forum.test/file.mp3',
    ]) {
      expect(
        AudioOneboxData.from(
          html.parseFragment('<audio src="$url"></audio>').children.single,
        ),
        isNull,
      );
    }
  });

  testWidgets('cooked audio mounts Native controls without starting playback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CookedHtml(
            buildAsync: false,
            html:
                '<audio controls><source src="https://example.com/recording.mp3"></audio>',
          ),
        ),
      ),
    );
    expect(find.byType(DAudioPlayer), findsOneWidget);
    expect(find.text('Play audio'), findsOneWidget);
  });

  testWidgets(
    'play, pause, seek, failure, retry and replacement own the session',
    (tester) async {
      final sessions = <_Session>[];
      Widget host(String source) => MaterialApp(
        home: Scaffold(
          body: AudioOnebox(
            data: AudioOneboxData(
              source: Uri.parse(source),
              title: 'Recording',
            ),
            sessionFactory: (request) {
              expect(request.audioOnly, isTrue);
              final session = _Session();
              sessions.add(session);
              return session;
            },
          ),
        ),
      );
      await tester.pumpWidget(host('https://example.com/a.mp3'));
      expect(sessions, isEmpty);
      await tester.tap(find.text('Play audio'));
      await tester.pump();
      final session = sessions.single;
      expect(session.started, isTrue);
      session.update(playing: true);
      await tester.pump();
      await tester.tap(find.text('Pause audio'));
      await tester.pump();
      expect(session.pauses, 1);
      tester.widget<DSlider>(find.byType(DSlider)).onChanged!(15000);
      expect(session.position, const Duration(seconds: 15));
      session.update(failed: true);
      await tester.pump();
      expect(find.text('Could not play this audio.'), findsOneWidget);
      await tester.tap(find.text('Retry audio'));
      await tester.pump();
      expect(session.disposed, isTrue);
      expect(sessions.length, 2);
      await tester.pumpWidget(host('https://example.com/b.mp3'));
      expect(sessions.last.disposed, isTrue);
      expect(find.text('Play audio'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hidden or background audio pauses pending playback', (
    tester,
  ) async {
    final session = _Session();
    Widget host(bool enabled) => MaterialApp(
      home: TickerMode(
        enabled: enabled,
        child: AudioOnebox(
          data: AudioOneboxData(
            source: Uri.parse('https://example.com/a.mp3'),
            title: 'Audio',
          ),
          sessionFactory: (_) => session,
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    await tester.tap(find.text('Play audio'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(session.pauses, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(host(false));
    expect(session.pauses, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    expect(session.disposed, isTrue);
  });

  testWidgets('an unfocused window keeps audio playing until it is hidden', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final session = _Session();
    // macOS and Linux report a visible window that lost focus as inactive.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(
      MaterialApp(
        home: AudioOnebox(
          data: AudioOneboxData(
            source: Uri.parse('https://example.com/a.mp3'),
            title: 'Audio',
          ),
          sessionFactory: (_) => session,
        ),
      ),
    );
    await tester.tap(find.text('Play audio'));
    await tester.pump();
    expect(session.started, isTrue);
    session.update(playing: true);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    session.update(playing: true);
    await tester.pump();
    expect(session.pauses, 0);
    expect(find.text('Pause audio'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(session.pauses, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Native audio layout wraps at large text in both directions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: direction,
              child: DAudioPlayer(
                title: 'Long audio recording title',
                onPlayPause: () {},
                onOpen: () {},
                duration: const Duration(minutes: 5),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

class _Session extends ChangeNotifier implements InlineVideoPlaybackSession {
  @override
  InlineVideoPlaybackState state = const InlineVideoPlaybackState(
    phase: InlineVideoPlaybackPhase.initializing,
    aspectRatio: 1,
  );
  bool started = false;
  bool disposed = false;
  int pauses = 0;
  Duration? position;
  void update({bool playing = false, bool failed = false}) {
    state = InlineVideoPlaybackState(
      phase: failed
          ? InlineVideoPlaybackPhase.failed
          : InlineVideoPlaybackPhase.ready,
      aspectRatio: 1,
      isPlaying: playing,
      duration: const Duration(seconds: 60),
      showAppControls: true,
    );
    notifyListeners();
  }

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> play() async {
    update(playing: true);
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> seekTo(Duration value) async {
    position = value;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
