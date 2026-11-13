import 'package:discourse_native/l10n/strings.dart';

import '../foundation/retry_wait.dart';

/// Writes preserve failure categories because each requires different recovery.
enum WriteFailure {
  validation,

  rateLimited,

  /// Not allowed here — or the key is gone. The two are indistinguishable from
  /// the status alone, since Discourse answers 403 to both.
  forbidden,

  /// Only edits can conflict.
  conflict,

  unreachable,
}

class WriteException implements Exception {
  const WriteException(
    this.failure, {
    this.errors = const [],
    this.statusCode,
    this.retryAfter,
    this.notSent = false,
    this.affectedUserCount,
    this.cause,
    this.causeStackTrace,
  });

  final WriteFailure failure;

  /// Server-localized messages are shown verbatim rather than translated again.
  final List<String> errors;

  final int? statusCode;

  /// How long the site or its origin cooldown holds this write; null when
  /// neither named a wait.
  final Duration? retryAfter;

  /// The request provably never reached the site, so nothing it asked for can
  /// have happened there and sending it again cannot duplicate it. Any other
  /// [WriteFailure.unreachable] failure may have been applied with only the
  /// answer lost.
  final bool notSent;

  /// How many existing users a refused change would reach, when the site
  /// refuses it until told whether it applies to them (`user_count`).
  final int? affectedUserCount;

  final Object? cause;
  final StackTrace? causeStackTrace;

  /// How long a sender holds before trying this write again. Nothing asked the
  /// site to wait for a request that never reached it.
  Duration get retryWait =>
      notSent ? Duration.zero : retryWaitAfter(retryAfter);

  /// Whether the sender may wait this out itself instead of reporting it.
  bool get canWaitInPlace => retryWait <= maximumInlineRetryWait;

  String get message {
    if (errors.isNotEmpty) return errors.join('\n');
    return switch (failure) {
      WriteFailure.validation => appL10n.thatWasnTAccepted,
      WriteFailure.rateLimited => switch (retryAfter) {
        final wait? => appL10n.tooFastTryAgainInS(waitSeconds(wait).toString()),
        null => appL10n.tooFastTryAgainInAMoment,
      },
      WriteFailure.forbidden =>
        appL10n.youCanTPostThatHereOrTheConnectionToThis,
      WriteFailure.conflict => appL10n.someoneElseChangedThatFirst,
      WriteFailure.unreachable => appL10n.couldnTReachTheSite,
    };
  }

  @override
  String toString() => appL10n.writeExceptionStatusCodeRetryAfter(
    (notSent).toString(),
    (failure).toString(),
    (statusCode).toString(),
    (retryAfter).toString(),
  );
}
