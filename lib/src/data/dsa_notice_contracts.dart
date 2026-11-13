import 'write_failure.dart';

abstract interface class DsaNoticesApi {
  DsaNoticeConnection dsaNoticeConnection({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
  });
}

abstract interface class DsaNoticeConnection {
  Future<String> requestVerification(String email);
  Future<void> verifyEmail(String email, String token, String code);
  Future<String> submit(Map<String, Object?> notice, {String? token});
  void dispose();
}

final class DsaVerificationRequired extends WriteException {
  const DsaVerificationRequired({super.errors})
    : super(WriteFailure.validation, statusCode: 422);
}
