import 'dart:async';

import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:flutter/material.dart';
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
      expect(controller.documents, isEmpty);
      expect(tester.takeException(), isNull);
    });

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
      expect(oldController.documents, isEmpty);
      expect(find.byType(YoutubePlayerSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
}

Widget _player({YoutubeVideoData data = _video, Uri? forum}) => MaterialApp(
  home: Scaffold(
    body: YoutubePlayerSurface(data: data, forumOrigin: forum ?? _forum),
  ),
);
