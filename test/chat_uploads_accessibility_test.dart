import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/lightbox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a GIF can be paused without opening the image viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ChatUploads(
              siteUrl: 'https://meta.discourse.org',
              uploads: [
                ChatUpload(
                  url: '/uploads/party.gif',
                  originalFilename: 'party.gif',
                  kind: ChatUploadKind.image,
                  width: 400,
                  height: 200,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('gif-playback-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.bySemanticsLabel('Pause GIF'), findsOneWidget);
    expect(tester.widget<DButton>(toggle).tooltip, 'Pause GIF');

    await tester.tap(toggle);
    await tester.pump();

    expect(tester.widget<DButton>(toggle).tooltip, 'Play GIF');
    expect(find.byType(LightboxGallery), findsNothing);
  });

  testWidgets('image hover metadata preserves the named image button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ChatUploads(
                siteUrl: 'https://meta.discourse.org',
                uploads: [
                  ChatUpload(
                    url: '/uploads/screenshot.png',
                    originalFilename: 'screenshot.png',
                    kind: ChatUploadKind.image,
                    width: 400,
                    height: 200,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final target = find.bySemanticsLabel('Open image: screenshot.png');
      expect(target, findsOneWidget);
      expect(
        tester.getSemantics(target),
        isSemantics(
          label: 'Open image: screenshot.png',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      final inkWell = find.descendant(
        of: target,
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
      expect(tester.widget<InkWell>(inkWell).hoverColor, Colors.transparent);
      final preview = find.byType(DImagePreview);
      final bounds = tester.getRect(preview);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: bounds.center);
      await tester.pumpAndSettle();
      final opacity = find.descendant(
        of: preview,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, .9);
      expect(find.text('screenshot.png'), findsOneWidget);
      expect(tester.getRect(preview), bounds);
      expect(
        find.bySemanticsLabel('Open image: screenshot.png'),
        findsOneWidget,
      );
      await mouse.removePointer();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('attachment is a named 44-pixel keyboard link', (tester) async {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final launched = <String>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ChatUploads(
                siteUrl: 'https://meta.discourse.org',
                uploads: [
                  ChatUpload(
                    url: '/uploads/notes.pdf',
                    originalFilename: 'notes.pdf',
                    kind: ChatUploadKind.attachment,
                    humanFilesize: '12 KB',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.bySemanticsLabel('Open attachment: notes.pdf, 12 KB');
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, 44);
      expect(
        tester.getSemantics(target),
        isSemantics(
          label: 'Open attachment: notes.pdf, 12 KB',
          isLink: true,
          isButton: false,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final attachmentTrigger = find.ancestor(
        of: target,
        matching: find.byType(DAttachmentTrigger),
      );
      expect(attachmentTrigger, findsOneWidget);
      expect(tester.widget<DAttachmentTrigger>(attachmentTrigger).isLink, true);

      final inkWell = find.descendant(
        of: attachmentTrigger,
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
      final focusNode = tester.widget<InkWell>(inkWell).focusNode!;
      expect(focusNode.canRequestFocus, isTrue);
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(launched, ['https://meta.discourse.org/uploads/notes.pdf']);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('video upload is an accessible lazy player', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ChatUploads(
                siteUrl: 'https://meta.discourse.org',
                uploads: [
                  ChatUpload(
                    url: '/uploads/demo.mp4',
                    originalFilename: 'demo.mp4',
                    kind: ChatUploadKind.video,
                    width: 1920,
                    height: 1080,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(InlineVideo), findsOneWidget);
      expect(find.bySemanticsLabel('Play video: demo.mp4'), findsOneWidget);
      expect(find.byTooltip('Download video'), findsOneWidget);
      expect(find.text('demo.mp4'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Open attachment:')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
