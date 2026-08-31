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
    UpdateChannel.stable => 'Stable',
    UpdateChannel.canary => 'Canary',
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
    UpdateFailure.unreachable => "Couldn't reach the update server.",
    UpdateFailure.malformed =>
      'The update server answered with something this version does not '
          'understand.',
    UpdateFailure.untrusted =>
      'The download did not match its signature and was thrown away.',
    UpdateFailure.install =>
      'The update downloaded but could not be installed.',
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

  static const UpdateException _failure = UpdateException(
    UpdateFailure.install,
    'This build cannot update itself.',
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
  Future<void> discard() async => throw _failure;
}
