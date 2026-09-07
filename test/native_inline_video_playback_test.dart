import 'dart:async';

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
            tester.widget<Slider>(find.byType(Slider)).value,
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
          tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue,
          60000,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        platform.events.single.add(
          VideoEvent(eventType: VideoEventType.bufferingStart),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        platform.position = const Duration(seconds: 21);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(find.text('0:21 / 2:00'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        platform.events.single.add(
          VideoEvent(eventType: VideoEventType.bufferingEnd),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.tap(find.byTooltip('Pause'));
        await tester.pump();
        expect(player.controller.value.isPlaying, isFalse);
        expect(find.byTooltip('Play'), findsOneWidget);
        await tester.tap(find.byTooltip('Play'));
        await tester.pump();
        expect(player.controller.value.isPlaying, isTrue);
        expect(find.byTooltip('Pause'), findsOneWidget);
        await tester.tapAt(tester.getCenter(find.byType(Slider)));
        await tester.pump();
        expect(platform.seeks, hasLength(1));
        expect(
          tester.widget<Slider>(find.byType(Slider)).value,
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
      expect(tester.widget<Slider>(find.byType(Slider)).max, 180000);
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
}

IconButton _button(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
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

class _VideoPlatform extends VideoPlayerPlatform {
  final events = <StreamController<VideoEvent>>[];
  final _disposed = <Completer<void>>[];
  final disposals = <int>[];
  final seeks = <Duration>[];
  Duration position = Duration.zero;
  int viewBuilds = 0;
  bool failInitialization = false;

  @override
  Future<void> init() async {}

  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
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
      stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(1920, 1080),
          duration: const Duration(seconds: 120),
        ),
      );
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
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    this.position = position;
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

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
