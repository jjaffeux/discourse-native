import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

      final inkWell = find.descendant(
        of: target,
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
      expect(
        tester.widget<InkWell>(inkWell).focusColor,
        Theme.of(tester.element(target)).shell.hover,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        tester.getSemantics(target),
        isSemantics(isFocusable: true, isFocused: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(launched, ['https://meta.discourse.org/uploads/notes.pdf']);
    } finally {
      semantics.dispose();
    }
  });
}
