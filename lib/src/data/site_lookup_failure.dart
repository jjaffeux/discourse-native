import 'package:discourse_native/l10n/strings.dart';

import 'http_url_safety.dart';

enum SiteLookupFailure { notDiscourse, unreachable }

class SiteLookupException implements Exception {
  const SiteLookupException(
    this.failure,
    this.term, {
    this.statusCode,
    this.errorType,
    this.cause,
    this.causeStackTrace,
  });

  final SiteLookupFailure failure;
  final String term;
  final int? statusCode;

  /// The `error_type` of a refusal Discourse answered in JSON; null for any
  /// other body, which a proxy or firewall in front of the site may send.
  final String? errorType;
  final Object? cause;
  final StackTrace? causeStackTrace;

  String get message => switch (failure) {
    SiteLookupFailure.notDiscourse =>
      appL10n.isNotADiscourseForumOrIsRunningAVersionToo((term).toString()),
    SiteLookupFailure.unreachable => appL10n.couldnTReachAddinstancesheet(
      (term).toString(),
    ),
  };

  @override
  String toString() => [
    'SiteLookupException($failure',
    if (statusCode != null) appL10n.statusCode((statusCode).toString()),
    ')',
  ].join();
}

/// The site refused the user API key itself rather than the request made with
/// it: the key was revoked, expired or never issued, or its account is
/// suspended or deactivated. Every request carrying that key is refused the
/// same way, so nothing can be done as the account with it.
///
/// Only a read whose action never refuses on its own can tell this apart from
/// an ordinary `invalid_access` refusal, which any private resource answers.
final class ApiKeyRejectedException extends SiteLookupException {
  const ApiKeyRejectedException(String term)
    : super(
        SiteLookupFailure.notDiscourse,
        term,
        statusCode: 403,
        errorType: 'invalid_access',
      );

  @override
  String toString() => appL10n.apiKeyRejectedExceptionStatusCode403;
}

final class HttpBasicAuthenticationRequired extends SiteLookupException {
  HttpBasicAuthenticationRequired(Uri url)
    : origin = Uri.parse(requireSafeHttpUrl(url).origin),
      super(SiteLookupFailure.unreachable, url.origin, statusCode: 401);

  final Uri origin;

  @override
  String get message => appL10n.httpBasicAuthenticationRequired(origin.origin);
}
