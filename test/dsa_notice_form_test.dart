import 'package:discourse_native/src/data/dsa_notices_api.dart';
import 'package:discourse_native/src/shell/dsa_notice_controller.dart';
import 'package:discourse_native/src/shell/dsa_notice_form.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_ui_evidence.dart';

void main() {
  testWidgets('confirmed reporter submits complete notice and sees reference', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = _Connection();
    final controller = DsaNoticeController(
      connection: connection,
      execute: <T>(action) => action(),
      sessionIsCurrent: () => true,
      useAccountEmail: true,
    );
    await prepareNativeUiEvidence(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: nativeUiEvidenceBuilder,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DsaNoticeForm(
                controller: controller,
                contentUrl: 'https://forum.example/t/example/10/2',
                initialName: 'Reporter',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('dsa-email')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('dsa-explanation')),
      'This content contains an illegal threat against a named person.',
    );
    await tester.tap(find.byKey(const ValueKey('dsa-declaration')));
    await tester.pumpAndSettle();
    await captureNativeUi(tester, 'dsa-account-report');
    await tester.tap(find.byKey(const ValueKey('dsa-submit')));
    await tester.pumpAndSettle();
    expect(
      connection.notice?['content_url'],
      'https://forum.example/t/example/10/2',
    );
    expect(connection.notice?['declaration'], isTrue);
    expect(connection.notice?.containsKey('email'), isFalse);
    expect(find.text('Report reference: DSA-123'), findsOneWidget);
    await captureNativeUi(tester, 'dsa-receipt');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'email edits invalidate a verified guest without losing explanation',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = DsaNoticeController(
        connection: _Connection(),
        execute: <T>(action) => action(),
        sessionIsCurrent: () => true,
        useAccountEmail: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DsaNoticeForm(
                controller: controller,
                contentUrl: 'https://forum.example/t/example/10/2',
                initialName: 'Reporter',
              ),
            ),
          ),
        ),
      );
      const explanation =
          'This content contains an illegal threat against a named person.';
      await tester.enterText(
        find.byKey(const ValueKey('dsa-explanation')),
        explanation,
      );
      await tester.enterText(
        find.byKey(const ValueKey('dsa-email')),
        'guest@example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dsa-send-code')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('dsa-code')), '123456');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dsa-verify-code')));
      await tester.pumpAndSettle();
      expect(find.text('Email verified'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('dsa-email')),
        'changed@example.com',
      );
      await tester.pumpAndSettle();
      expect(find.text('Email verified'), findsNothing);
      expect(find.text(explanation), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

class _Connection implements DsaNoticeConnection {
  Map<String, Object?>? notice;
  @override
  Future<String> requestVerification(String email) async => 'a' * 64;
  @override
  Future<void> verifyEmail(String email, String token, String code) async {}
  @override
  Future<String> submit(Map<String, Object?> notice, {String? token}) async {
    this.notice = notice;
    return 'DSA-123';
  }

  @override
  void dispose() {}
}
