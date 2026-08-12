import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostic_error_cause.dart';

/// Which stream of builds an install follows.
enum UpdateChannel {
  stable,
  canary;

  /// Null rather than a throw for a name that is no longer a channel: a
  /// preference written by an older build must not be able to stop this one
  /// from launching.
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

/// A build other than the one running, as the release manifest describes it.
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

  /// Whatever the release was published with, shown as plain text. The cooked
  /// HTML renderer is for what a Discourse says, not for what we say.
  final String? notes;

  final DateTime? publishedAt;
  final int? sizeBytes;

  /// True when this release is older than the one running, which is what moving
  /// from canary back to stable means.
  ///
  /// Set by the implementation rather than worked out here: deciding there is
  /// an update at all already required comparing the two versions, and doing it
  /// again in the controller would mean a second, differently-written semver
  /// comparison that could disagree with the first.
  final bool isDowngrade;
}

/// Why an update did not happen.
enum UpdateFailure {
  /// Nothing answered: the manifest, the release descriptor, or the artifact.
  unreachable,

  /// The manifest is there but says nothing this build can use — a shape we do
  /// not understand, or a channel with no release for this platform.
  malformed,

  /// The signature or the checksum did not match.
  ///
  /// Its own case rather than folded into [unreachable] on purpose. Every other
  /// failure here means "try again later"; this one means something between us
  /// and the release server is lying, and a user told "couldn't reach it" will
  /// helpfully retry until it works.
  untrusted,

  /// Downloaded and verified, but the swap or the relaunch did not go through.
  install,
}

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

  /// What the implementation said. For logs and [toString]; never shown on its
  /// own, because [message] is what a reader gets.
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

/// Replacing the running application with a newer build of it.
///
/// An interface rather than a class with an injectable collaborator — unlike
/// [DiscourseApi] or [Authenticator], where there is one right way to do the
/// thing and only the transport is swapped.
///
/// Production currently supplies [UnsupportedUpdater]: packaged Linux installs
/// update through apt. The interface keeps that delivery decision out of the
/// shell and gives widget tests something for `FakeUpdater` to implement
/// without standing up platform channels. It also leaves a narrow seam for a
/// future platform integration.
///
/// Everything here throws [UpdateException] and nothing else. That is the whole
/// contract, and what keeps implementations interchangeable.
abstract interface class Updater {
  /// False where an in-app update cannot be installed at all: the wrong
  /// platform, or a build the release pipeline never stamped.
  ///
  /// Everything user-facing hangs off this, so the UI never has to ask what
  /// platform it is on — only whether it can update.
  bool get isSupported;

  /// The newest build on [channel], or null when the running one is already it.
  ///
  /// Takes the channel per call rather than per instance because switching
  /// channels is something the user does while the app is running, and an
  /// implementation that can only be built for one channel should be the thing
  /// that has to deal with that.
  Future<UpdateRelease?> check({required UpdateChannel channel});

  /// Fetches [release], verifies it, and leaves it staged.
  ///
  /// [onProgress] is called with 0..1. A callback rather than a stream for the
  /// same reason [SiteTracker] takes callbacks: there is exactly one listener,
  /// and it is the object that started the download.
  Future<void> download(
    UpdateRelease release, {
    void Function(double fraction)? onProgress,
  });

  /// Swaps in what [download] staged, and relaunches.
  ///
  /// Returns `Future<void>` rather than `Future<Never>` even though a call that
  /// works never comes back: an implementation that fails to exec has to be
  /// able to say so rather than hang forever.
  Future<void> installAndRestart();

  /// Throws away anything staged.
  ///
  /// Called when the channel changes, so a canary build downloaded a moment ago
  /// cannot be installed by someone who has since asked for stable.
  Future<void> discard();
}

/// An [Updater] for the platforms that cannot have one.
///
/// [isSupported] is false, and every other method throws — which nothing
/// reaches, because the UI is gated on [isSupported] and the controller returns
/// early without it. The throws are there so that a caller who ignores the gate
/// fails loudly rather than appearing to update and doing nothing.
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
