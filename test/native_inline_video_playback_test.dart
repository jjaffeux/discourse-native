import 'dart:async';

import 'package:discourse_native/discourse_ui.dart' show DSlider, DSpinner;
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  late _VideoPlatform platform;

  setUp(() {
    final previous = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() async {
      await platform.close();
      VideoPlayerPlatform.instance = previous;
    });
  });

  for (final fullscreen in [false, true]) {
    testWidgets(
      'native ${fullscreen ? 'full-screen' : 'inline'} playback updates only the affected controls',
      (tester) async {
        var actionBuilds = 0;
        await tester.pumpWidget(
          _app(
            actionsBuilder: (context) {
              actionBuilds++;
              return const SizedBox.shrink();
            },
          ),
        );
        await tester.pumpAndSettle();
        if (fullscreen) {
          await tester.tap(find.byTooltip('Enter full screen'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(VideoPlayer, skipOffstage: false), findsOneWidget);
        final player = tester.widget<VideoPlayer>(find.byType(VideoPlayer));
        final pause = _button(tester, 'Pause');
        final fullscreenControl = _button(
          tester,
          fullscreen ? 'Exit full screen' : 'Enter full screen',
        );
        final initialViewBuilds = platform.viewBuilds;
        final initialActionBuilds = actionBuilds;

        for (var second = 1; second <= 20; second++) {
          platform.position = Duration(seconds: second);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump();
          expect(
            find.text('0:${second.toString().padLeft(2, '0')} / 2:00'),
            findsOneWidget,
          );
          expect(
            tester.widget<DSlider>(find.byType(DSlider)).value,
            second * 1000,
          );
        }
        expect(platform.viewBuilds - initialViewBuilds, 0);
        expect(actionBuilds - initialActionBuilds, 0);
        expect(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)),
          same(player),
        );
        expect(_button(tester, 'Pause'), same(pause));
        expect(
          _button(
            tester,
            fullscreen ? 'Exit full screen' : 'Enter full screen',
          ),
          same(fullscreenControl),
        );

        platform.events.single.add(
          VideoEvent(
            eventType: VideoEventType.bufferingUpdate,
            buffered: [
              DurationRange(Duration.zero, const Duration(seconds: 60)),
            ],
          ),
        );
        await tester.pump();
        expect(
          tester.widget<DSlider>(find.byType(DSlider)).secondaryTrackValue,
          60000,
        );
        expect(find.byType(DSpinner), findsNothing);

        platform.events.single.add(
          VideoEvent(eventType: VideoEventType.bufferingStart),
        );
        await tester.pump();
        expect(find.byType(DSpinner), findsOneWidget);
        platform.position = const Duration(seconds: 21);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(find.text('0:21 / 2:00'), findsOneWidget);
        expect(find.byType(DSpinner), findsOneWidget);
        platform.events.single.add(
          VideoEvent(eventType: VideoEventType.bufferingEnd),
        );
        await tester.pump();
        expect(find.byType(DSpinner), findsNothing);

        await tester.tap(find.byTooltip('Pause'));
        await tester.pump();
        expect(player.controller.value.isPlaying, isFalse);
        expect(find.byTooltip('Play'), findsOneWidget);
        await tester.tap(find.byTooltip('Play'));
        await tester.pump();
        expect(player.controller.value.isPlaying, isTrue);
        expect(find.byTooltip('Pause'), findsOneWidget);
        await tester.tapAt(tester.getCenter(find.byType(DSlider)));
        await tester.pump();
        expect(platform.seeks, hasLength(1));
        expect(
          tester.widget<DSlider>(find.byType(DSlider)).value,
          platform.seeks.single.inMilliseconds,
        );
        expect(platform.viewBuilds, initialViewBuilds);
        expect(actionBuilds, initialActionBuilds);

        if (fullscreen) {
          await tester.tap(find.byTooltip('Exit full screen'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
            same(player.controller),
          );
        }
        expect(find.byType(VideoPlayer, skipOffstage: false), findsOneWidget);
        expect(platform.events, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await platform.disposed(0);
        expect(platform.disposals, [0]);
      },
    );
  }

  testWidgets(
    'native presentation follows size and rotation changes on the same controller',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      final initialViewBuilds = platform.viewBuilds;
      controller.value = controller.value.copyWith(size: const Size(640, 480));
      await tester.pump();
      final size = tester.getSize(find.byType(VideoPlayer));
      expect(size.width / size.height, closeTo(4 / 3, 0.001));
      expect(platform.viewBuilds, initialViewBuilds + 1);

      controller.value = controller.value.copyWith(rotationCorrection: 90);
      await tester.pump();
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        1,
      );
      expect(platform.viewBuilds, initialViewBuilds + 2);
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(controller),
      );
      controller.value = controller.value.copyWith(
        duration: const Duration(seconds: 180),
      );
      await tester.pump();
      expect(find.text('0:00 / 3:00'), findsOneWidget);
      expect(tester.widget<DSlider>(find.byType(DSlider)).max, 180000);
      expect(platform.viewBuilds, initialViewBuilds + 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await platform.disposed(0);
    },
  );

  for (final initializing in [false, true]) {
    testWidgets(
      'native ${initializing ? 'initialization' : 'playback'} failure releases the player and retries',
      (tester) async {
        platform.failInitialization = initializing;
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        if (!initializing) {
          platform.events.single.addError(
            PlatformException(code: 'VideoError', message: 'Playback failed'),
          );
          await tester.pumpAndSettle();
        }
        await tester.pump();
        expect(find.text("Couldn't play this video."), findsOneWidget);
        expect(find.text('Open video'), findsOneWidget);
        expect(find.byType(VideoPlayer), findsNothing);
        await platform.disposed(0);
        expect(platform.disposals, [0]);
        platform.failInitialization = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.byType(VideoPlayer), findsOneWidget);
        expect(find.byTooltip('Pause'), findsOneWidget);
        expect(platform.events, hasLength(2));
        await tester.pumpWidget(const SizedBox.shrink());
        await platform.disposed(1);
        expect(platform.disposals, [0, 1]);
      },
    );
  }
  testWidgets('retained native playback pauses until manually resumed', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(_retainedApp(visible));
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    final initialPauses = platform.pauses.length;
    expect(controller.value.isPlaying, isTrue);

    visible.value = false;
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    expect(platform.pauses.length, initialPauses + 1);
    final positionReads = platform.positionReads;
    for (var tick = 0; tick < 20; tick++) {
      controller.value = controller.value.copyWith(
        position: Duration(seconds: tick),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(platform.positionReads, positionReads);
    expect(platform.pauses.length, initialPauses + 1);
    expect(platform.disposals, isEmpty);

    visible.value = true;
    await tester.pump();
    expect(_controller(tester), same(controller));
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(platform.plays, [0]);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(controller.value.isPlaying, isTrue);
    expect(platform.plays, [0, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
    await platform.disposed(0);
    expect(platform.disposals, [0]);
  });

  testWidgets('an initially hidden parent prevents native autoplay', (
    tester,
  ) async {
    final visible = ValueNotifier(false);
    addTearDown(visible.dispose);
    await tester.pumpWidget(_retainedApp(visible));
    await tester.pumpAndSettle();
    expect(_controller(tester).value.isInitialized, isTrue);
    expect(platform.plays, isEmpty);
    visible.value = true;
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(platform.plays, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await platform.disposed(0);
  });

  for (final restoreBeforeReady in [false, true]) {
    testWidgets(
      'initialization after hiding ${restoreBeforeReady ? 'and revealing' : 'a retained pane'} cannot interrupt a visible video',
      (tester) async {
        final gate = _completionGate();
        platform.nextInitialization = gate;
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await tester.pumpWidget(
          _retainedApp(visible, secondVideo: _surface('visible.mp4')),
        );
        await tester.pump();
        expect(platform.plays, [1]);
        visible.value = false;
        await tester.pump();
        if (restoreBeforeReady) {
          visible.value = true;
          await tester.pump();
        }
        gate.complete();
        await tester.pump();
        final controllers = tester
            .widgetList<VideoPlayer>(
              find.byType(VideoPlayer, skipOffstage: false),
            )
            .map((player) => player.controller)
            .toList();
        expect(controllers.first.value.isInitialized, isTrue);
        expect(controllers.first.value.isPlaying, isFalse);
        expect(controllers.last.value.isPlaying, isTrue);
        expect(platform.plays, [1]);
        expect(platform.pauses.where((id) => id == 1), [1]);
        await tester.pumpWidget(const SizedBox.shrink());
        await platform.disposed(0);
        await platform.disposed(1);
        expect(platform.disposals.toSet(), {0, 1});
      },
    );
  }

  testWidgets('hidden source replacement rejects late native initialization', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    final source = ValueNotifier('first.mp4');
    addTearDown(visible.dispose);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      _retainedApp(
        visible,
        video: ValueListenableBuilder<String>(
          valueListenable: source,
          builder: (context, source, _) => _surface(source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pump();
    final gate = _completionGate();
    platform.nextInitialization = gate;
    source.value = 'second.mp4';
    await tester.pump();
    await platform.disposed(0);
    source.value = 'third.mp4';
    await tester.pump();
    await platform.disposed(1);
    gate.complete();
    await tester.pump();
    expect(platform.sources.map((url) => Uri.parse(url).path), [
      '/first.mp4',
      '/second.mp4',
      '/third.mp4',
    ]);
    expect(platform.plays, [0]);
    expect(platform.disposals, [0, 1]);
    visible.value = true;
    await tester.pump();
    expect(_controller(tester).dataSource, 'https://cdn.example.com/third.mp4');
    expect(find.byTooltip('Play'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(platform.plays, [0, 2]);
    await tester.pumpWidget(const SizedBox.shrink());
    await platform.disposed(2);
    expect(platform.disposals, [0, 1, 2]);
  });

  testWidgets(
    'late hidden playback events coalesce pauses and keep the visible owner',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        _retainedApp(visible, secondVideo: _surface('visible.mp4')),
      );
      await tester.pumpAndSettle();
      final controllers = tester
          .widgetList<VideoPlayer>(find.byType(VideoPlayer))
          .map((player) => player.controller)
          .toList();
      final initialPauses = platform.pauses.where((id) => id == 0).length;
      final gate = _completionGate();
      platform.nextPause = gate;
      visible.value = false;
      await tester.pump();
      for (var event = 0; event < 10; event++) {
        platform.events.first.add(
          VideoEvent(
            eventType: VideoEventType.isPlayingStateUpdate,
            isPlaying: true,
          ),
        );
        await tester.pump();
      }
      expect(platform.pauses.where((id) => id == 0).length, initialPauses + 1);
      expect(controllers.last.value.isPlaying, isTrue);
      gate.complete();
      await tester.pump();
      expect(controllers.first.value.isPlaying, isFalse);
      expect(platform.pauses.where((id) => id == 0).length, initialPauses + 2);
      expect(controllers.last.value.isPlaying, isTrue);
      expect(platform.pauses.where((id) => id == 1), [1]);
      visible.value = true;
      await tester.pump();
      expect(controllers.first.value.isPlaying, isFalse);
      expect(platform.plays, [0, 1]);
      await tester.pumpWidget(const SizedBox.shrink());
      await platform.disposed(0);
      await platform.disposed(1);
    },
  );

  testWidgets(
    'disposing hidden native setup releases it before late completion',
    (tester) async {
      final gate = _completionGate();
      platform.nextInitialization = gate;
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      await tester.pumpWidget(_retainedApp(visible));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await platform.disposed(0);
      gate.complete();
      await tester.pump();
      expect(platform.disposals, [0]);
      expect(platform.plays, isEmpty);
      expect(find.byType(VideoPlayer, skipOffstage: false), findsNothing);
    },
  );

  for (final hiddenOnReturn in [false, true]) {
    testWidgets(
      'fullscreen preserves native playback and returns to a ${hiddenOnReturn ? 'hidden' : 'visible'} pane',
      (tester) async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await tester.pumpWidget(_retainedApp(visible));
        await tester.pumpAndSettle();
        final controller = _controller(tester);
        final initialPauses = platform.pauses.length;
        await tester.tap(find.byTooltip('Enter full screen'));
        await tester.pumpAndSettle();
        expect(
          TickerMode.valuesOf(
            tester.element(
              find.byType(InlineVideoPlaybackSurface, skipOffstage: false),
            ),
          ).enabled,
          isFalse,
        );
        expect(controller.value.isPlaying, isTrue);
        expect(platform.pauses.length, initialPauses);
        if (hiddenOnReturn) {
          visible.value = false;
          await tester.pump();
          expect(controller.value.isPlaying, isTrue);
          expect(platform.pauses.length, initialPauses);
        }
        await tester.tap(find.byTooltip('Exit full screen'));
        await tester.pumpAndSettle();
        expect(controller.value.isPlaying, !hiddenOnReturn);
        expect(platform.plays, [0]);
        expect(
          platform.pauses.length,
          initialPauses + (hiddenOnReturn ? 1 : 0),
        );
        if (hiddenOnReturn) {
          visible.value = true;
          await tester.pump();
          expect(find.byTooltip('Play'), findsOneWidget);
          expect(controller.value.isPlaying, isFalse);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await platform.disposed(0);
      },
    );
  }

  testWidgets(
    'source replacement cannot inherit the previous fullscreen exemption',
    (tester) async {
      final visible = ValueNotifier(true);
      final source = ValueNotifier('first.mp4');
      addTearDown(visible.dispose);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        _retainedApp(
          visible,
          video: ValueListenableBuilder<String>(
            valueListenable: source,
            builder: (context, source, _) => _surface(source),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Enter full screen'));
      await tester.pumpAndSettle();
      source.value = 'replacement.mp4';
      await tester.pump();
      await platform.disposed(0);
      expect(platform.plays, [0]);
      await tester.tap(find.byTooltip('Exit full screen'));
      await tester.pumpAndSettle();
      expect(
        _controller(tester).dataSource,
        'https://cdn.example.com/replacement.mp4',
      );
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(platform.plays, [0]);
      await tester.pumpWidget(const SizedBox.shrink());
      await platform.disposed(1);
      expect(platform.disposals, [0, 1]);
    },
  );

  testWidgets('covered fullscreen playback stays paused when revealed', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(_retainedApp(visible, navigatorKey: navigator));
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    await tester.tap(find.byTooltip('Enter full screen'));
    await tester.pumpAndSettle();
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (context) => const Scaffold(body: Text('Covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(platform.plays, [0]);
    await tester.pumpWidget(const SizedBox.shrink());
    await platform.disposed(0);
  });

  for (final phase in ['initializing', 'inline', 'fullscreen']) {
    testWidgets('app lifecycle loss pauses $phase native playback until Play', (
      tester,
    ) async {
      final gate = phase == 'initializing' ? _completionGate() : null;
      platform.nextInitialization = gate;
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(_retainedApp(visible));
      await tester.pump();
      if (phase == 'fullscreen') {
        await tester.tap(find.byTooltip('Enter full screen'));
        await tester.pumpAndSettle();
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      gate?.complete();
      await tester.pump();
      if (gate == null) expect(_controller(tester).value.isPlaying, isFalse);
      final plays = platform.plays.toList();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(_controller(tester).value.isPlaying, isFalse);
      expect(platform.plays, plays);
      if (gate != null) expect(platform.plays, isEmpty);
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(_controller(tester).value.isPlaying, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await platform.disposed(0);
    });
  }

  testWidgets('pause before session startup cancels native autoplay', (
    tester,
  ) async {
    final session = _nativeSession(
      InlineVideoPlaybackRequest(
        source: Uri.parse('https://cdn.example.com/demo.mp4'),
        title: 'Demo',
        posterUrl: null,
        aspectRatio: 16 / 9,
        siteUrl: null,
        credentials: null,
        lifecycle: null,
      ),
    );
    addTearDown(session.dispose);
    await session.pause();
    await session.start();
    expect(session.state.phase, InlineVideoPlaybackPhase.ready);
    expect(session.state.isPlaying, isFalse);
    expect(platform.plays, isEmpty);
    await session.play();
    expect(session.state.isPlaying, isTrue);
    session.dispose();
    await platform.disposed(0);
  });
}

IconButton _button(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

Widget _app({WidgetBuilder? actionsBuilder}) => MaterialApp(
  home: Scaffold(
    body: InlineVideoPlaybackSurface(
      data: InlineVideoData.fromUpload(
        url: 'https://cdn.example.com/demo.mp4',
        title: 'Demo',
        siteUrl: 'https://example.com',
      )!,
      siteUrl: null,
      credentials: null,
      lifecycle: null,
      sessionFactory: (request) => createInlineVideoPlaybackSession(
        request,
        platform: TargetPlatform.macOS,
      ),
      actionsBuilder: actionsBuilder,
    ),
  ),
);

Completer<void> _completionGate() {
  final gate = Completer<void>();
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

VideoPlayerController _controller(WidgetTester tester) => tester
    .widget<VideoPlayer>(find.byType(VideoPlayer, skipOffstage: false))
    .controller;

InlineVideoPlaybackSession _nativeSession(InlineVideoPlaybackRequest request) =>
    createInlineVideoPlaybackSession(request, platform: TargetPlatform.macOS);

Widget _surface(String source) => InlineVideoPlaybackSurface(
  data: InlineVideoData.fromUpload(
    url: 'https://cdn.example.com/$source',
    title: source,
    siteUrl: 'https://example.com',
  )!,
  siteUrl: null,
  credentials: null,
  lifecycle: null,
  sessionFactory: _nativeSession,
);

Widget _retainedApp(
  ValueNotifier<bool> visible, {
  Widget? video,
  Widget? secondVideo,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  home: Scaffold(
    body: Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, visible, child) => Offstage(
              offstage: !visible,
              child: TickerMode(enabled: visible, child: child!),
            ),
            child: TickerMode(
              enabled: true,
              child: video ?? _surface('demo.mp4'),
            ),
          ),
        ),
        if (secondVideo != null) Expanded(child: secondVideo),
      ],
    ),
  ),
);

class _VideoPlatform extends VideoPlayerPlatform {
  final events = <StreamController<VideoEvent>>[];
  final _disposed = <Completer<void>>[];
  final disposals = <int>[];
  final seeks = <Duration>[];
  final plays = <int>[];
  final pauses = <int>[];
  final sources = <String>[];
  Completer<void>? nextInitialization;
  Completer<void>? nextPause;
  int positionReads = 0;
  Duration position = Duration.zero;
  int viewBuilds = 0;
  bool failInitialization = false;

  @override
  Future<void> init() async {}

  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    final gate = nextInitialization;
    nextInitialization = null;
    sources.add(options.dataSource.uri!);
    final id = events.length;
    final stream = StreamController<VideoEvent>(
      sync: true,
      // Keep cancellation completion in the widget test's async zone.
      onCancel: () async {},
    );
    events.add(stream);
    _disposed.add(Completer<void>());
    if (failInitialization) {
      stream.addError(
        PlatformException(code: 'VideoError', message: 'Initialization failed'),
      );
    } else {
      void initialize() => stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(1920, 1080),
          duration: const Duration(seconds: 120),
        ),
      );
      if (gate == null) {
        initialize();
      } else {
        unawaited(gate.future.then((_) => initialize()));
      }
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId].stream;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    viewBuilds++;
    return Texture(textureId: options.playerId);
  }

  @override
  Future<void> dispose(int playerId) async {
    disposals.add(playerId);
    _disposed[playerId].complete();
  }

  Future<void> disposed(int playerId) => _disposed[playerId].future;

  @override
  Future<Duration> getPosition(int playerId) async {
    positionReads++;
    return position;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    this.position = position;
  }

  @override
  Future<void> play(int playerId) async {
    plays.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    pauses.add(playerId);
    final gate = nextPause;
    nextPause = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  Future<void> close() async {
    for (final stream in events) {
      await stream.close();
    }
  }
}
