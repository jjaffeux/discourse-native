import 'account_request_session.dart';
import 'api_credentials.dart';
import 'discourse_api_contracts.dart';

/// The account's credential for one mutation, or the failure to report for it.
typedef WriteCredential = ({
  String? apiKey,
  AccountRequestCredentials? request,
  WriteException? failure,
});

/// A retired account and an unreadable key are failed writes rather than
/// throws, so every caller reports them through its own write path.
Future<WriteCredential> readWriteCredential(
  AccountRequestSession session,
  ApiCredentialReader credentials, {
  bool withClientId = false,
}) async {
  try {
    final request = withClientId
        ? await session.credentials(credentials)
        : await session.keyCredentials(credentials);
    final apiKey = request.apiKey;
    return apiKey == null
        ? (
            apiKey: null,
            request: null,
            failure: const WriteException(WriteFailure.forbidden),
          )
        : (apiKey: apiKey, request: request, failure: null);
  } catch (error) {
    return (
      apiKey: null,
      request: null,
      failure: const WriteException(WriteFailure.unreachable),
    );
  }
}
