import 'dart:async';

import 'package:discourse_native/src/data/dsa_notices_api.dart';
import 'package:discourse_native/src/models/dsa_notice.dart';
import 'package:discourse_native/src/shell/dsa_notice_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _draft = DsaNoticeDraft(
  contentUrl: 'https://forum.example/t/example/10/2',
  explanation:
      'This content contains an illegal threat against a named person.',
  name: 'Reporter',
  email: 'guest@example.com',
  declaration: true,
);

void main() {
  test(
    'guest verifies email, changing email invalidates verification',
    () async {
      final connection = _Connection();
      final controller = _controller(connection);
      controller.emailChanged('guest@example.com');
      expect(controller.canSubmit(_draft), isFalse);
      await controller.requestCode();
      await controller.verifyCode('123456');
      expect(controller.canSubmit(_draft), isTrue);
      controller.emailChanged('another@example.com');
      expect(controller.emailVerified, isFalse);
      expect(controller.codeRequested, isFalse);
      expect(controller.canSubmit(_draft), isFalse);
      controller.dispose();
    },
  );

  test(
    'confirmed account skips verification and submits no email or token',
    () async {
      final connection = _Connection();
      final controller = _controller(connection, account: true);
      expect(controller.canSubmit(_draft), isTrue);
      await controller.submit(_draft);
      expect(connection.submissions.single.$1.containsKey('email'), isFalse);
      expect(connection.submissions.single.$2, isNull);
      expect(controller.reference, 'DSA-123');
      await controller.submit(_draft);
      expect(connection.submissions, hasLength(1));
      controller.dispose();
    },
  );

  test(
    'verification_required keeps report editable and switches to email verification',
    () async {
      final connection = _Connection()..expired = true;
      final controller = _controller(connection, account: true);
      await controller.submit(_draft);
      expect(controller.useAccountEmail, isFalse);
      expect(controller.reference, isNull);
      expect(controller.error, 'Verify again');
      expect(controller.canSubmit(_draft), isFalse);
      controller.emailChanged(_draft.email);
      await controller.requestCode();
      await controller.verifyCode('123456');
      connection.expired = false;
      await controller.submit(_draft);
      expect(controller.reference, 'DSA-123');
      controller.dispose();
    },
  );

  test(
    'account retirement discards late verification and prevents submission',
    () async {
      final connection = _Connection()..pendingToken = Completer<String>();
      final controller = _controller(connection);
      controller.emailChanged(_draft.email);
      final pending = controller.requestCode();
      controller.retire();
      connection.pendingToken!.complete('a' * 64);
      await pending;
      expect(controller.codeRequested, isFalse);
      expect(controller.isCurrent, isFalse);
      await controller.submit(_draft);
      expect(connection.submissions, isEmpty);
      controller.dispose();
    },
  );
}

DsaNoticeController _controller(
  _Connection connection, {
  bool account = false,
}) => DsaNoticeController(
  connection: connection,
  execute: <T>(action) => action(),
  sessionIsCurrent: () => true,
  useAccountEmail: account,
);

class _Connection implements DsaNoticeConnection {
  final submissions = <(Map<String, Object?>, String?)>[];
  Completer<String>? pendingToken;
  bool expired = false;
  @override
  Future<String> requestVerification(String email) =>
      pendingToken?.future ?? Future.value('a' * 64);
  @override
  Future<void> verifyEmail(String email, String token, String code) async {}
  @override
  Future<String> submit(Map<String, Object?> notice, {String? token}) async {
    submissions.add((notice, token));
    if (expired) throw const DsaVerificationRequired(errors: ['Verify again']);
    return 'DSA-123';
  }

  @override
  void dispose() {}
}
