import 'package:discourse_native/l10n/strings.dart';

import 'site_lookup_failure.dart';
import 'write_failure.dart';

/// The sentence a user is shown for a failed request.
///
/// A [WriteException] carries the site's own words or a localized category
/// message. A [SiteLookupException] carries a message naming the site, which
/// holds only when nothing answered. A status other than a basic-auth
/// challenge means the site was reached, so its "couldn't reach" message would
/// be false and [fallback], which names what failed, is shown instead. A 401 or
/// 403 answer to a read of a feature on a forum that is already connected is
/// the forum refusing this account, so the lookup message would call it
/// something other than a forum. Anything else, or no recorded failure at all,
/// is not a message to show, so [fallback] stands in for it rather than a type
/// name or a developer string.
String failureText(Object? error, {required String fallback}) =>
    switch (error) {
      WriteException(:final message) => message,
      HttpBasicAuthenticationRequired(:final message) => message,
      SiteLookupException(
        failure: SiteLookupFailure.notDiscourse,
        statusCode: 401 || 403,
      ) =>
        appL10n.thisAccountCanTAccessThat,
      SiteLookupException(
        failure: SiteLookupFailure.unreachable,
        statusCode: _?,
      ) =>
        fallback,
      SiteLookupException(:final message) => message,
      _ => fallback,
    };
