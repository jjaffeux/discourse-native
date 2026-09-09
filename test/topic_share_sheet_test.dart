import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_share.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Weekly engineering manager meeting notes';
const _url =
    'https://dev.discourse.org/t/weekly-engineering-manager-meeting-notes/92860?u=reader';
const _copyKey = ValueKey('topic-share-copy');
const _shareKey = ValueKey('topic-share-system');
const _replyKey = ValueKey('topic-share-reply-as-new-topic');

void main() {
  testWidgets('copies the full single-line link and resets inline feedback', (
    tester,
  ) async {
    final copied = <String>[];
    _mockClipboard(tester, (call) async {
      copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final semantics = tester.ensureSemantics();
    try {
      await _openShare(tester);

      final copy = find.byKey(_copyKey);
      final link = find.byType(SelectableText);
      expect(tester.getCenter(copy).dy, closeTo(tester.getCenter(link).dy, 1));
      expect(find.byKey(_replyKey), findsNothing);

      await tester.tap(copy);
      await tester.pump();

      expect(copied, [_url]);
      expect(find.text('Copied!'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Copied!')),
        isSemantics(
          label: 'Copied!',
          isButton: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          isLiveRegion: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Copied!'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('clipboard failures keep copy available and show an error', (
    tester,
  ) async {
    _mockClipboard(tester, (_) async {
      throw PlatformException(code: 'clipboard-unavailable');
    });
    await _openShare(tester);

    await tester.tap(find.byKey(_copyKey));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't copy link."), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Copied!'), findsNothing);
  });

  testWidgets('closing before the clipboard responds is safe', (tester) async {
    final pending = Completer<void>();
    _mockClipboard(tester, (_) async {
      await pending.future;
      return null;
    });
    await _openShare(tester);

    await tester.tap(find.byKey(_copyKey));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(_copyKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing after copying cancels its feedback timer', (
    tester,
  ) async {
    _mockClipboard(tester, (_) async => null);
    await _openShare(tester);

    await tester.tap(find.byKey(_copyKey));
    await tester.pump();
    expect(find.text('Copied!'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(_copyKey), findsNothing);
  });

  for (final postNumber in <int?>[null, 2]) {
    testWidgets(
      'the reply footer closes ${postNumber == null ? 'topic' : 'post'} sharing before continuing',
      (tester) async {
        var replies = 0;
        await _openShare(
          tester,
          postNumber: postNumber,
          onReplyAsNewTopic: () async => replies++,
        );

        expect(
          find.text(postNumber == null ? 'Share this topic' : 'Share post #2'),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byKey(_replyKey)).top,
          greaterThan(tester.getRect(find.byKey(_shareKey)).bottom),
        );

        await tester.tap(find.byKey(_replyKey));
        await tester.pumpAndSettle();

        expect(replies, 1);
        expect(find.byKey(_shareKey), findsNothing);
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'long links fit at 320px on ${platform.name} with text scale $textScale',
        (tester) async {
          await _openShare(
            tester,
            platform: platform,
            size: const Size(320, 700),
            textScale: textScale,
            onReplyAsNewTopic: () async {},
          );

          expect(tester.takeException(), isNull);
          for (final key in [_copyKey, _shareKey, _replyKey]) {
            final button = find.byKey(key);
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
            expect(button.hitTestable(), findsOneWidget);
            if (platform == TargetPlatform.iOS) {
              expect(rect.height, greaterThanOrEqualTo(44));
            }
          }
        },
      );
    }
  }
}

void _mockClipboard(
  WidgetTester tester,
  Future<Object?> Function(MethodCall) handler,
) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') return handler(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

Future<void> _openShare(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.macOS,
  Size size = const Size(800, 600),
  double textScale = 1,
  int? postNumber,
  Future<void> Function()? onReplyAsNewTopic,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: platform),
      builder: (context, child) => DToaster(
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              postNumber == null
                  ? showTopicShareSheet(
                      context: context,
                      title: _title,
                      url: _url,
                      onReplyAsNewTopic: onReplyAsNewTopic,
                    )
                  : showPostShareSheet(
                      context: context,
                      topicTitle: _title,
                      url: _url,
                      postNumber: postNumber,
                      onReplyAsNewTopic: onReplyAsNewTopic,
                    ),
            ),
            child: const Text('Open share'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open share'));
  await tester.pumpAndSettle();
}
