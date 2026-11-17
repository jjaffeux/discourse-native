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
const _titleKey = ValueKey('topic-share-title');

void main() {
  testWidgets('shares the topic URL, subject and button origin, then closes', (
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
    expect(find.byKey(_shareKey), findsNothing);
  });

  testWidgets('copying writes the link, closes the sheet and confirms', (
    tester,
  ) async {
    final copied = <String>[];
    _mockClipboard(tester, (call) async {
      copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    await _openShare(tester);

    await tester.tap(find.byKey(_copyKey));
    await tester.pumpAndSettle();

    expect(copied, [_url]);
    expect(find.byKey(_copyKey), findsNothing);
    expect(find.text('Link copied!'), findsOneWidget);
  });

  testWidgets('a clipboard failure keeps the sheet and says so', (
    tester,
  ) async {
    _mockClipboard(tester, (_) async {
      throw PlatformException(code: 'clipboard-unavailable');
    });
    await _openShare(tester);

    await tester.tap(find.byKey(_copyKey));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't copy link."), findsOneWidget);
    expect(find.byKey(_copyKey), findsOneWidget);
    expect(find.text('Link copied!'), findsNothing);
  });

  testWidgets('a desktop opens the same sheet as a dialog, not a menu', (
    tester,
  ) async {
    await _openShare(tester, postNumber: 2, onReplyAsNewTopic: () async {});

    expect(find.byType(DDropdownMenuContent), findsNothing);
    expect(find.text('Share post #2'), findsOneWidget);
    expect(find.byKey(_titleKey), findsOneWidget);
    expect(find.byKey(_cardKey), findsOneWidget);
    expect(find.byKey(_replyKey), findsOneWidget);
  });

  testWidgets('the title heads the sheet, then the whole link, then equal '
      'buttons', (tester) async {
    await _openShare(tester, size: const Size(800, 900));

    expect(find.text('Share topic'), findsOneWidget);
    final title = find.byKey(_titleKey);
    expect(tester.widget<Text>(title).data, _title);
    final titleStyle = tester.widget<Text>(title).style!;
    expect(titleStyle.fontSize, 17);
    expect(titleStyle.fontWeight, FontWeight.w700);
    final card = tester.getRect(find.byKey(_cardKey));
    final copy = tester.getRect(find.byKey(_copyKey));
    final share = tester.getRect(find.byKey(_shareKey));
    expect(
      find.descendant(of: find.byKey(_cardKey), matching: find.text(_title)),
      findsNothing,
    );
    expect(tester.getRect(title).bottom + 10, closeTo(card.top, .01));
    final copySurface = tester.getRect(
      find.descendant(
        of: find.byKey(_copyKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is DButtonDecoration,
        ),
      ),
    );
    expect(card.bottom + 12, closeTo(copySurface.top, .01));
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
    final linkRect = tester.getRect(find.byType(EditableText));
    expect(linkRect.top - card.top, closeTo(10, .01));
    expect(linkRect.left - card.left, closeTo(12, .01));
  });

  testWidgets('a topic offers neither a reply as a new topic nor, without a '
      'callback, an invite', (tester) async {
    await _openShare(tester, onReplyAsNewTopic: () async {});

    expect(find.byKey(_replyKey), findsNothing);
    expect(find.byKey(_inviteKey), findsNothing);
  });

  testWidgets('a topic offers invite under the buttons when given one', (
    tester,
  ) async {
    var invites = 0;
    await _openShare(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
      onInvite: () async => invites++,
    );

    final invite = tester.getRect(find.byKey(_inviteKey));
    expect(find.text('Invite people'), findsOneWidget);
    expect(
      invite.top,
      greaterThan(tester.getRect(find.byKey(_shareKey)).bottom),
    );
    expect(
      invite.left,
      closeTo(tester.getRect(find.byKey(_cardKey)).left, .01),
    );
    expect(
      invite.width,
      closeTo(tester.getRect(find.byKey(_cardKey)).width, .01),
    );

    await tester.tap(find.byKey(_inviteKey));
    await tester.pumpAndSettle();

    expect(invites, 1);
    expect(find.byKey(_copyKey), findsNothing);
  });

  testWidgets('the opening post is shared as the topic', (tester) async {
    await _openShare(tester, postNumber: 1, onReplyAsNewTopic: () async {});

    expect(find.text('Share topic'), findsOneWidget);
    expect(find.text('Share post #1'), findsNothing);
    expect(find.byKey(_replyKey), findsNothing);
  });

  testWidgets('a reply is continued as a new topic from a full-width row '
      'under the buttons, once', (tester) async {
    var replies = 0;
    await _openShare(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(390, 844),
      postNumber: 2,
      onReplyAsNewTopic: () async => replies++,
    );

    final reply = tester.getRect(find.byKey(_replyKey));
    final card = tester.getRect(find.byKey(_cardKey));
    expect(
      reply.top,
      greaterThan(tester.getRect(find.byKey(_shareKey)).bottom),
    );
    expect(reply.left, closeTo(card.left, .01));
    expect(reply.width, closeTo(card.width, .01));

    await tester.tap(find.byKey(_replyKey));
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(find.byKey(_replyKey), findsNothing);
  });

  testWidgets('post sharing continues a message as a message, never a topic', (
    tester,
  ) async {
    for (final privateMessage in [false, true]) {
      await _openShare(
        tester,
        postNumber: 2,
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
            postNumber: 2,
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
            if (platform == TargetPlatform.iOS) {
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
                      onInvite: onInvite,
                      privateMessage: privateMessage,
                    )
                  : showPostShareSheet(
                      context: context,
                      topicTitle: _title,
                      url: _url,
                      postNumber: postNumber,
                      onReplyAsNewTopic: onReplyAsNewTopic,
                      privateMessage: privateMessage,
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
