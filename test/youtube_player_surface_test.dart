import 'dart:async';

import 'package:discourse_native/src/shell/topic_post_retention.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'support/fake_media_webview.dart';

const _video = YoutubeVideoData(
  videoId: 'first_video',
  listId: null,
  title: 'First video',
  thumbnailUrl: null,
  startSeconds: null,
  endSeconds: null,
  loop: false,
);
const _replacementVideo = YoutubeVideoData(
  videoId: 'second_video',
  listId: null,
  title: 'Second video',
  thumbnailUrl: null,
  startSeconds: null,
  endSeconds: null,
  loop: false,
);
final _forum = Uri.parse('https://first.example');
final _replacementForum = Uri.parse('https://second.example');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeMediaWebViewPlatform platform;
  late WebViewPlatform previousPlatform;
  late List<String> launched;

  setUp(() {
    previousPlatform = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
    launched = [];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
  });

  tearDown(() {
    WebViewPlatform.instance = previousPlatform;
    messenger.setMockMethodCallHandler(launcher, null);
  });

  for (final stage in MediaWebViewConfigurationStage.values) {
    testWidgets('closing the player during ${stage.name} stops native setup', (
      tester,
    ) async {
      final gate = Completer<void>();
      platform.nextGate = (stage, gate.future);
      await tester.pumpWidget(_player());
      final controller = platform.controllers.single;
      final admitted = List.of(controller.operations);
      expect(admitted.last, stage);

      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pump();

      expect(controller.operations, admitted);
      expect(controller.documents, isNotEmpty);
      expect(
        controller.documents.every((d) => !d.html.contains('<iframe')),
        isTrue,
      );
      expect(controller.channels, isEmpty);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('replacing the player during ${stage.name} retires old setup', (
      tester,
    ) async {
      final gate = Completer<void>();
      platform.nextGate = (stage, gate.future);
      await tester.pumpWidget(_player());
      final oldController = platform.controllers.single;
      final admitted = List.of(oldController.operations);

      await tester.pumpWidget(
        _player(data: _replacementVideo, forum: _replacementForum),
      );
      final replacement = platform.controllers.last;
      expect(replacement, isNot(same(oldController)));
      expect(
        replacement.documents.single.html,
        contains('/embed/second_video'),
      );
      expect(
        replacement.documents.single.baseUrl,
        _replacementForum.toString(),
      );
      gate.complete();
      await tester.pump();

      expect(oldController.operations, admitted);
      expect(oldController.documents, isNotEmpty);
      expect(
        oldController.documents.every((d) => !d.html.contains('<iframe')),
        isTrue,
      );
      expect(oldController.channels, isEmpty);
      expect(find.byType(YoutubePlayerSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets(
    'macOS registers hover support inside the iframe before loading',
    (tester) async {
      final gate = Completer<void>();
      platform.nextGate = (
        MediaWebViewConfigurationStage.userScript,
        gate.future,
      );
      await tester.pumpWidget(_player());
      final controller = platform.controllers.single;

      expect(controller.documents, isEmpty);
      final script = controller.userScripts.single;
      expect(script.forMainFrameOnly, isFalse);
      expect(script.source, youtubePlayerHoverScript);

      gate.complete();
      await tester.pump();
      expect(controller.documents.single.html, contains('/embed/first_video'));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final replace in [false, true]) {
    testWidgets(
      '${replace ? 'replaced' : 'closed'} players cannot open external links',
      (tester) async {
        await tester.pumpWidget(_player());
        final delegate = platform.controllers.single.delegate!;
        if (replace) {
          await tester.pumpWidget(
            _player(data: _replacementVideo, forum: _replacementForum),
          );
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
        }

        expect(
          await delegate.navigate(
            'https://www.youtube.com/watch?v=first_video',
          ),
          NavigationDecision.prevent,
        );
        await tester.pump();
        expect(launched, isEmpty);
        expect(
          await delegate.navigate(
            'https://www.youtube.com/embed/first_video',
            isMainFrame: false,
          ),
          NavigationDecision.prevent,
        );
      },
    );
  }

  testWidgets(
    'a failed player cannot open external links from its retired view',
    (tester) async {
      final gate = Completer<void>();
      platform.nextGate = (
        MediaWebViewConfigurationStage.navigation,
        gate.future,
      );
      await tester.pumpWidget(_player());
      final delegate = platform.controllers.single.delegate!;
      gate.completeError(StateError('Native player configuration failed'));
      await tester.pump();
      expect(find.text("Couldn't load the YouTube player."), findsOneWidget);

      expect(
        await delegate.navigate('https://www.youtube.com/watch?v=first_video'),
        NavigationDecision.prevent,
      );
      await tester.pump();
      expect(launched, isEmpty);
    },
  );

  testWidgets('the current player loads its document and opens chosen links', (
    tester,
  ) async {
    await tester.pumpWidget(_player());
    final controller = platform.controllers.single;
    final delegate = controller.delegate!;
    expect(controller.documents.single.html, contains('/embed/first_video'));
    expect(controller.documents.single.baseUrl, _forum.toString());
    expect(
      await delegate.navigate(_forum.toString()),
      NavigationDecision.navigate,
    );
    expect(
      await delegate.navigate(
        'https://www.youtube.com/embed/first_video',
        isMainFrame: false,
      ),
      NavigationDecision.navigate,
    );
    delegate.onPageFinished!(_forum.toString());
    const link = 'https://www.youtube.com/watch?v=first_video';
    expect(await delegate.navigate(link), NavigationDecision.prevent);
    await tester.pump();
    expect(launched, [link]);
  });

  testWidgets(
    'a retired page completion cannot finish the replacement document',
    (tester) async {
      await tester.pumpWidget(_player());
      final retired = platform.controllers.single.delegate!;
      await tester.pumpWidget(
        _player(data: _replacementVideo, forum: _replacementForum),
      );
      retired.onPageFinished!(_forum.toString());

      expect(
        await platform.controllers.last.delegate!.navigate(
          _replacementForum.toString(),
        ),
        NavigationDecision.navigate,
      );
      expect(launched, isEmpty);
    },
  );

  testWidgets('hidden players pause without replacing their document', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, enabled, _) => TickerMode(
            enabled: enabled,
            child: YoutubePlayerSurface(data: _video, forumOrigin: _forum),
          ),
        ),
      ),
    );
    final controller = platform.controllers.single;
    visible.value = false;
    await tester.pumpAndSettle();
    expect(controller.scripts.last, contains('false'));
    expect(controller.documents, hasLength(1));
    visible.value = true;
    await tester.pumpAndSettle();
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
    expect(controller.scripts.where((s) => s.contains('playVideo')), isEmpty);
  });

  testWidgets('backgrounding pauses but losing focus preserves playback', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_player());
    final controller = platform.controllers.single;
    final before = controller.scripts.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller.scripts, hasLength(before));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(controller.scripts.last, contains('false'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
    expect(controller.scripts.where((s) => s.contains('playVideo')), isEmpty);
  });

  testWidgets('closing and replacing initialized players unloads the iframe', (
    tester,
  ) async {
    await tester.pumpWidget(_player());
    final old = platform.controllers.single;
    await tester.pumpWidget(_player(data: _replacementVideo));
    await tester.pumpAndSettle();
    expect(old.documents.last.html, isNot(contains('<iframe')));
    final current = platform.controllers.last;
    expect(current.documents.single.html, contains('/embed/second_video'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(current.documents.last.html, isNot(contains('<iframe')));
    expect(launched, isEmpty);
  });

  testWidgets(
    'document readiness reapplies hidden state and ignores retired views',
    (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, enabled, _) => TickerMode(
              enabled: enabled,
              child: YoutubePlayerSurface(data: _video, forumOrigin: _forum),
            ),
          ),
        ),
      );
      final controller = platform.controllers.single;
      final ready = controller.channels['NativeYoutube']!;
      visible.value = false;
      await tester.pumpAndSettle();
      controller.scripts.clear();
      ready.onMessageReceived(const JavaScriptMessage(message: 'ready'));
      await tester.pump();
      expect(controller.scripts.single, contains('false'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(controller.channels, isEmpty);
      controller.scripts.clear();
      ready.onMessageReceived(const JavaScriptMessage(message: 'ready'));
      await tester.pump();
      expect(controller.scripts, isEmpty);
    },
  );

  testWidgets(
    'scrolling a retained player pauses it and preserves its document',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                YoutubeVideo(data: _video, siteUrl: _forum.toString()),
                const SizedBox(height: 2500),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Play video: First video'));
      await tester.pumpAndSettle();
      final controller = platform.controllers.single;
      scroll.jumpTo(1500);
      await tester.pumpAndSettle();
      expect(controller.scripts.last, contains('false'));
      expect(controller.documents, hasLength(1));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(platform.controllers.single, same(controller));
      expect(controller.documents, hasLength(1));
      expect(controller.scripts.last, contains('true'));
      expect(controller.scripts.where((s) => s.contains('playVideo')), isEmpty);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'a retained lazy row pauses before its player is evicted',
    (tester) async {
      final scroll = ScrollController();
      final retention = TopicPostRetention(maxPosts: 8);
      addTearDown(scroll.dispose);
      addTearDown(retention.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            controller: scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemExtent: 500,
            itemCount: 40,
            itemBuilder: (_, index) =>
                _RetainedPlayerRow(key: ValueKey(index), retention: retention),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Play video: First video').first);
      await tester.pumpAndSettle();
      final controller = platform.controllers.single;
      scroll.jumpTo(1500);
      await tester.pumpAndSettle();
      expect(controller.documents, hasLength(1));
      expect(controller.scripts.last, contains('false'));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(platform.controllers.single, same(controller));
      expect(controller.documents, hasLength(1));
      expect(controller.scripts.last, contains('true'));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'activated players obey the outer post retention budget',
    (tester) async {
      final scroll = ScrollController();
      final retention = TopicPostRetention(maxPosts: 2);
      addTearDown(scroll.dispose);
      addTearDown(retention.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            controller: scroll,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemExtent: 500,
            itemCount: 40,
            itemBuilder: (_, index) =>
                _RetainedPlayerRow(key: ValueKey(index), retention: retention),
          ),
        ),
      );
      for (var index = 0; index < 30; index += 3) {
        scroll.jumpTo(index * 500);
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsLabel('Play video: First video').first,
        );
        await tester.pumpAndSettle();
        final livePlayers = platform.controllers.where(
          (c) =>
              c.documents.isNotEmpty &&
              c.documents.last.html.contains('<iframe'),
        );
        expect(livePlayers.length, lessThanOrEqualTo(2));
      }
      expect(platform.controllers, hasLength(10));
      expect(
        platform.controllers.first.documents.last.html,
        isNot(contains('<iframe')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(
        platform.controllers.every(
          (c) => !c.documents.last.html.contains('<iframe'),
        ),
        isTrue,
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );
}

class _RetainedPlayerRow extends StatefulWidget {
  const _RetainedPlayerRow({super.key, required this.retention});
  final TopicPostRetention retention;

  @override
  State<_RetainedPlayerRow> createState() => _RetainedPlayerRowState();
}

class _RetainedPlayerRowState extends State<_RetainedPlayerRow>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.retention.contains(this);

  @override
  void initState() {
    super.initState();
    widget.retention.retain(this, 100);
    widget.retention.addListener(updateKeepAlive);
  }

  @override
  void dispose() {
    widget.retention.removeListener(updateKeepAlive);
    widget.retention.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return YoutubeVideo(data: _video, siteUrl: _forum.toString());
  }
}

Widget _player({YoutubeVideoData data = _video, Uri? forum}) => MaterialApp(
  home: Scaffold(
    body: YoutubePlayerSurface(data: data, forumOrigin: forum ?? _forum),
  ),
);
