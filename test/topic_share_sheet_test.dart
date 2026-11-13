import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/shell/topic_share.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

const _title = 'Weekly engineering manager meeting notes';
const _url =
    'https://dev.discourse.org/t/weekly-engineering-manager-meeting-notes/92860?u=reader';
const _copyKey = ValueKey('topic-share-copy');
const _shareKey = ValueKey('topic-share-system');
const _replyKey = ValueKey('topic-share-reply-as-new-topic');
const _inviteKey = ValueKey('topic-share-invite');
const _cardKey = ValueKey('topic-share-url');
const _anchor = Rect.fromLTWH(300, 100, 36, 32);

void main() {
  testWidgets('shares the topic URL, subject and button origin', (
    tester,
  ) async {
    final previous = SharePlatform.instance;
    final sharing = _RecordingSharePlatform();
    SharePlatform.instance = sharing;
    addTearDown(() => SharePlatform.instance = previous);

    await _openShare(tester);
    final shareButton = find.byKey(_shareKey);
    final origin = tester.getRect(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    final request = sharing.requests.single;
    expect(request.text, _url);
    expect(request.subject, _title);
    expect(request.sharePositionOrigin, origin);
    expect(find.text(appL10n.couldnTOpenSharing), findsNothing);
  });

  testWidgets('copies the link and resets inline feedback', (tester) async {
    final copied = <String>[];
    _mockClipboard(tester, (call) async {
      copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final semantics = tester.ensureSemantics();
    try {
      await _openShare(tester);

      final copy = find.byKey(_copyKey);
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

  testWidgets('a phone sheet previews the whole link above equal buttons', (
    tester,
  ) async {
    await _openShare(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
    );

    final card = tester.getRect(find.byKey(_cardKey));
    final copy = tester.getRect(find.byKey(_copyKey));
    final share = tester.getRect(find.byKey(_shareKey));
    expect(find.text(_title), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(card.bottom, lessThan(copy.top));
    expect(copy.width, closeTo(share.width, .01));
    expect(copy.top, closeTo(share.top, .01));
    expect(share.left, greaterThan(copy.right));

    final link = tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byKey(_cardKey),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable;
    expect(link.plainText, _url);
    expect(link.maxLines, isNull);
    expect(link.size.height, greaterThan(link.preferredLineHeight * 1.5));
    expect(
      tester.getRect(find.byType(EditableText)).bottom,
      lessThan(card.bottom),
    );
    expect(
      tester.getRect(find.byType(EditableText)).left,
      greaterThanOrEqualTo(card.left),
    );
    expect(
      tester.getRect(find.byType(EditableText)).right,
      lessThanOrEqualTo(card.right),
    );
  });

  testWidgets('a phone sheet offers the reply row below the buttons', (
    tester,
  ) async {
    var replies = 0;
    await _openShare(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
      onReplyAsNewTopic: () async => replies++,
    );

    final reply = tester.getRect(find.byKey(_replyKey));
    expect(
      reply.top,
      greaterThan(tester.getRect(find.byKey(_shareKey)).bottom),
    );
    expect(reply.left, closeTo(tester.getRect(find.byKey(_cardKey)).left, .01));

    await tester.tap(find.byKey(_replyKey));
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(find.byKey(_replyKey), findsNothing);
  });

  testWidgets('a phone sheet offers invite above the reply row, only when '
      'given a callback', (tester) async {
    await _openShare(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
      onReplyAsNewTopic: () async {},
    );
    expect(find.byKey(_inviteKey), findsNothing);
    expect(find.text('Invite people'), findsNothing);

    var invites = 0;
    await tester.pumpWidget(const SizedBox());
    await _openShare(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
      onReplyAsNewTopic: () async {},
      onInvite: () async => invites++,
    );

    final invite = tester.getRect(find.byKey(_inviteKey));
    expect(find.text('Invite people'), findsOneWidget);
    expect(
      invite.top,
      greaterThan(tester.getRect(find.byKey(_shareKey)).bottom),
    );
    expect(invite.bottom, lessThan(tester.getRect(find.byKey(_replyKey)).top));
    expect(
      invite.left,
      closeTo(tester.getRect(find.byKey(_cardKey)).left, .01),
    );

    await tester.tap(find.byKey(_inviteKey));
    await tester.pumpAndSettle();

    expect(invites, 1);
    expect(find.byKey(_inviteKey), findsNothing);
    expect(find.byKey(_copyKey), findsNothing);
  });

  group('anchored desktop menu', () {
    testWidgets('lists invite after system share and before the reply '
        'separator, only when given a callback', (tester) async {
      await _openShare(tester, anchor: _anchor, onReplyAsNewTopic: () async {});
      expect(find.byKey(_inviteKey), findsNothing);

      await tester.pumpWidget(const SizedBox());
      var invites = 0;
      await _openShare(
        tester,
        anchor: _anchor,
        onReplyAsNewTopic: () async {},
        onInvite: () async => invites++,
      );

      final system = tester.getRect(find.byKey(_shareKey));
      final invite = tester.getRect(find.byKey(_inviteKey));
      final reply = tester.getRect(find.byKey(_replyKey));
      expect(find.text('Invite people'), findsOneWidget);
      expect(invite.top, greaterThanOrEqualTo(system.bottom));
      expect(invite.bottom, lessThan(reply.top));
      expect(find.byType(DDropdownMenuSeparator), findsOneWidget);
      expect(
        tester.getRect(find.byType(DDropdownMenuSeparator)).top,
        greaterThanOrEqualTo(invite.bottom),
      );

      await tester.tap(find.byKey(_inviteKey));
      await tester.pumpAndSettle();

      expect(invites, 1);
      expect(find.byKey(_inviteKey), findsNothing);
    });

    testWidgets('lists copy with the full link, system share and reply', (
      tester,
    ) async {
      await _openShare(
        tester,
        anchor: _anchor,
        postNumber: 2,
        onReplyAsNewTopic: () async {},
      );

      expect(find.text('Share post #2'), findsOneWidget);
      expect(find.byKey(_copyKey), findsOneWidget);
      expect(find.byKey(_shareKey), findsOneWidget);
      expect(find.byKey(_replyKey), findsOneWidget);
      expect(find.text('Share to another app'), findsOneWidget);
      final url = find.text(_url);
      expect(url, findsOneWidget);
      expect(tester.widget<Text>(url).maxLines, 1);
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    });

    testWidgets('omits the reply row when there is nothing to continue', (
      tester,
    ) async {
      await _openShare(tester, anchor: _anchor);

      expect(find.byKey(_copyKey), findsOneWidget);
      expect(find.byKey(_replyKey), findsNothing);
    });

    testWidgets('copying writes the link, closes the menu and confirms', (
      tester,
    ) async {
      final copied = <String>[];
      _mockClipboard(tester, (call) async {
        copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      await _openShare(tester, anchor: _anchor);

      await tester.tap(find.byKey(_copyKey));
      await tester.pumpAndSettle();

      expect(copied, [_url]);
      expect(find.byKey(_copyKey), findsNothing);
      expect(find.text('Link copied!'), findsOneWidget);
    });

    testWidgets('a clipboard failure is reported as an error', (tester) async {
      _mockClipboard(tester, (_) async {
        throw PlatformException(code: 'clipboard-unavailable');
      });
      await _openShare(tester, anchor: _anchor);

      await tester.tap(find.byKey(_copyKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_copyKey), findsNothing);
      expect(find.text("Couldn't copy link."), findsOneWidget);
      expect(find.text('Link copied!'), findsNothing);
    });

    for (final privateMessage in [false, true]) {
      testWidgets(
        'reply closes the menu and continues ${privateMessage ? 'a message' : 'a topic'} once',
        (tester) async {
          var replies = 0;
          await _openShare(
            tester,
            anchor: _anchor,
            privateMessage: privateMessage,
            onReplyAsNewTopic: () async => replies++,
          );

          expect(
            find.text(
              privateMessage ? 'Reply as new message' : 'Reply as new topic',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(_replyKey));
          await tester.pumpAndSettle();

          expect(replies, 1);
          expect(find.byKey(_replyKey), findsNothing);
        },
      );
    }

    testWidgets('a phone with an anchor still gets the sheet', (tester) async {
      await _openShare(
        tester,
        platform: TargetPlatform.iOS,
        size: const Size(390, 844),
        anchor: _anchor,
      );

      expect(find.byKey(_cardKey), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });
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

    testWidgets(
      '${postNumber == null ? 'topic' : 'post'} sharing continues a message as a message, never a topic',
      (tester) async {
        for (final privateMessage in [false, true]) {
          await _openShare(
            tester,
            postNumber: postNumber,
            privateMessage: privateMessage,
            onReplyAsNewTopic: () async {},
          );

          expect(
            find.descendant(
              of: find.byKey(_replyKey),
              matching: find.text(
                privateMessage ? 'Reply as new message' : 'Reply as new topic',
              ),
            ),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
        }
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
          if (platform == TargetPlatform.iOS) {
            // A phone sheet taller than its lower height opens there and is
            // pulled up to reach its foot.
            await tester.drag(
              find.byKey(const ValueKey('sheet-drag-handle')),
              const Offset(0, -600),
            );
            await tester.pumpAndSettle();
          }
          for (final key in [_copyKey, _shareKey, _replyKey]) {
            final button = find.byKey(key);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
            expect(button.hitTestable(), findsOneWidget);
            if (platform == TargetPlatform.iOS && key != _replyKey) {
              final surface = find.descendant(
                of: button,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is DecoratedBox &&
                      widget.decoration is DButtonDecoration,
                ),
              );
              expect(rect, tester.getRect(surface));
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
  bool privateMessage = false,
  Rect? anchor,
  Future<void> Function()? onReplyAsNewTopic,
  Future<void> Function()? onInvite,
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
                      onInvite: onInvite,
                      privateMessage: privateMessage,
                      anchor: anchor,
                    )
                  : showPostShareSheet(
                      context: context,
                      topicTitle: _title,
                      url: _url,
                      postNumber: postNumber,
                      onReplyAsNewTopic: onReplyAsNewTopic,
                      privateMessage: privateMessage,
                      anchor: anchor,
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

final class _RecordingSharePlatform extends SharePlatform {
  final requests = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    requests.add(params);
    return const ShareResult('', ShareResultStatus.dismissed);
  }
}
