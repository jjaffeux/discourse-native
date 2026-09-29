import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostic_error_cause.dart';

enum UpdateChannel {
  stable,
  canary;

  static UpdateChannel? byName(String? name) {
    for (final channel in values) {
      if (channel.name == name) return channel;
    }
    return null;
  }

  String get label => switch (this) {
    UpdateChannel.stable => appL10n.stable,
    UpdateChannel.canary => appL10n.canary,
  };
}

@immutable
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.channel,
    this.notes,
    this.publishedAt,
    this.sizeBytes,
    this.isDowngrade = false,
  });

  final String version;
  final UpdateChannel channel;

  final String? notes;

  final DateTime? publishedAt;
  final int? sizeBytes;

  final bool isDowngrade;
}

enum UpdateFailure { unreachable, malformed, untrusted, install }

class UpdateException implements Exception, DiagnosticErrorCause {
  const UpdateException(this.failure, [this.detail])
    : cause = null,
      causeStackTrace = null;

  const UpdateException.caused(
    this.failure,
    this.detail,
    this.cause,
    this.causeStackTrace,
  );

  final UpdateFailure failure;

  final String? detail;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  Object get diagnosticCause => cause ?? this;

  @override
  StackTrace? get diagnosticCauseStackTrace => causeStackTrace;

  String get message => switch (failure) {
    UpdateFailure.unreachable => appL10n.couldnTReachTheUpdateServer,
    UpdateFailure.malformed =>
      appL10n.theUpdateServerAnsweredWithSomethingThisVersionDoesNotUnderstand,
    UpdateFailure.untrusted =>
      appL10n.theDownloadDidNotMatchItsSignatureAndWasThrownAway,
    UpdateFailure.install => appL10n.theUpdateDownloadedButCouldNotBeInstalled,
  };

  @override
  String toString() => 'UpdateException($failure)';
}

abstract interface class Updater {
  bool get isSupported;

  Future<UpdateRelease?> check({required UpdateChannel channel});

  Future<void> download(
    UpdateRelease release, {
    void Function(double fraction)? onProgress,
  });

  Future<void> installAndRestart();

  Future<void> discard();
}

class UnsupportedUpdater implements Updater {
  const UnsupportedUpdater();

  static UpdateException get _failure => UpdateException(
    UpdateFailure.install,
    appL10n.thisBuildCannotUpdateItself,
  );

  @override
  bool get isSupported => false;

  @override
  Future<UpdateRelease?> check({required UpdateChannel channel}) async =>
      throw _failure;

  @override
  Future<void> download(
    UpdateRelease release, {
    void Function(double fraction)? onProgress,
  }) async => throw _failure;

  @override
  Future<void> installAndRestart() async => throw _failure;

  @override
  Future<void> discard() async {}
}
