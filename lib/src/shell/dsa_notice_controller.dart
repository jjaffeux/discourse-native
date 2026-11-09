import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/discourse_api_contracts.dart';
import '../models/dsa_notice.dart';

typedef DsaNoticeExecution = Future<T> Function<T>(Future<T> Function() action);

enum DsaNoticeActivity { idle, requestingEmail, verifyingEmail, submitting }

final class DsaNoticeController extends ChangeNotifier {
  DsaNoticeController({
    required this.connection,
    required this.execute,
    required this.sessionIsCurrent,
    required this.useAccountEmail,
  });

  final DsaNoticeConnection connection;
  final DsaNoticeExecution execute;
  final bool Function() sessionIsCurrent;
  bool useAccountEmail;
  bool _retired = false;
  bool _disposed = false;
  DsaNoticeActivity activity = DsaNoticeActivity.idle;
  String? error;
  String? reference;
  String _email = '';
  ({String email, String token, bool verified})? _verification;

  bool get isCurrent => !_retired && !_disposed && sessionIsCurrent();
  bool get busy => activity != DsaNoticeActivity.idle;
  bool get codeRequested => _verification != null;
  bool get emailVerified => _verification?.verified == true;

  void retire() {
    if (_retired || _disposed) return;
    _retired = true;
    _verification = null;
    connection.dispose();
    error = appL10n.yourConnectionChangedReopenTheFlagFormAndTryAgain;
    notifyListeners();
  }

  void emailChanged(String value) {
    final email = value.trim().toLowerCase();
    if (email == _email || busy) return;
    _email = email;
    _verification = null;
    error = null;
    notifyListeners();
  }

  Future<void> _run(
    DsaNoticeActivity next,
    Future<void> Function() action,
  ) async {
    if (!isCurrent || busy || reference != null) return;
    activity = next;
    error = null;
    notifyListeners();
    try {
      await action();
    } on DsaVerificationRequired catch (failure) {
      if (isCurrent) {
        useAccountEmail = false;
        _verification = null;
        error = failure.errors.isEmpty
            ? appL10n.dsaVerifyEmailRequired
            : failure.message;
      }
    } on WriteException catch (failure) {
      if (isCurrent) error = failure.message;
    } catch (_) {
      if (isCurrent) {
        error = const WriteException(WriteFailure.unreachable).message;
      }
    } finally {
      if (!_disposed) {
        activity = DsaNoticeActivity.idle;
        notifyListeners();
      }
    }
  }

  Future<void> requestCode() async {
    if (!DsaNoticeDraft.validEmail(_email)) return;
    await _run(DsaNoticeActivity.requestingEmail, () async {
      final email = _email;
      final token = await execute(() => connection.requestVerification(email));
      if (isCurrent) {
        _verification = (email: email, token: token, verified: false);
      }
    });
  }

  Future<void> verifyCode(String code) async {
    final held = _verification;
    if (held == null || !RegExp(r'^\d{6}$').hasMatch(code)) return;
    await _run(DsaNoticeActivity.verifyingEmail, () async {
      await execute(() => connection.verifyEmail(held.email, held.token, code));
      if (isCurrent) {
        _verification = (email: held.email, token: held.token, verified: true);
      }
    });
  }

  bool canSubmit(DsaNoticeDraft draft) =>
      isCurrent &&
      !busy &&
      reference == null &&
      draft.valid(useAccountEmail: useAccountEmail) &&
      (useAccountEmail ||
          (emailVerified &&
              draft.email.trim().toLowerCase() == _verification?.email));

  Future<void> submit(DsaNoticeDraft draft) async {
    if (!canSubmit(draft)) return;
    await _run(DsaNoticeActivity.submitting, () async {
      final result = await execute(
        () => connection.submit(
          draft.toJson(useAccountEmail: useAccountEmail),
          token: useAccountEmail ? null : _verification?.token,
        ),
      );
      if (isCurrent) reference = result;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _verification = null;
    connection.dispose();
    super.dispose();
  }
}
