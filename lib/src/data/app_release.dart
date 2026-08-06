import 'updater.dart';

/// What the release pipeline stamped into this build.
///
/// Compile-time rather than read back from the bundle, for four reasons — the
/// last of which is the one that decided it:
///
///  - `package_info_plus` is a platform channel, and this app keeps platform
///    channels out of tests deliberately. `pumpShell` builds the whole app in
///    around a hundred tests; none of them should have to stand up a plugin to
///    find out what version they are.
///  - It answers the version and nothing else. The channel and the feed URL
///    would need a second mechanism regardless, so the real choice is between
///    one mechanism and two.
///  - On Linux the bundle's version metadata comes from CMake, which is an
///    awkward thing to read back and an easy one to leave stale.
///  - An empty [version] means nobody released this build — which is exactly
///    when an updater has to stay off, so a developer's `flutter run` can never
///    offer to overwrite their own working tree. A version derived from the
///    pubspec is always populated, and so can never say that.
///
/// The pubspec's `version:` still names the bundle. CI passes `--build-name`
/// and this define from the same tag, so the two cannot drift.
abstract final class AppRelease {
  /// Empty in any build the release pipeline did not produce.
  static const String version = String.fromEnvironment(
    'DISCOURSE_NATIVE_VERSION',
  );

  /// The channel this build was published on.
  ///
  /// Only a default: the channel the app actually follows is a stored
  /// preference, because a user opting into canary needs that choice to exist
  /// before any canary binary carries it, and a user going back to stable has
  /// to stay on stable across the relaunch where the running binary still says
  /// canary. See [UpdateController.load].
  static const String buildChannel = String.fromEnvironment(
    'DISCOURSE_NATIVE_CHANNEL',
    defaultValue: 'stable',
  );

  /// Where the update manifests live.
  ///
  /// A default rather than a required define: the URL is not a secret, does not
  /// vary per build, and a typo in a CI variable should not be able to quietly
  /// turn updates off. Overridable so a staging feed can be pointed at without
  /// a code change.
  static const String feedBaseUrl = String.fromEnvironment(
    'DISCOURSE_NATIVE_FEED_URL',
    defaultValue: 'https://jjaffeux.github.io/discourse-native',
  );

  /// One index per channel, so publishing to one can never rewrite the other.
  static String archiveUrlFor(UpdateChannel channel) =>
      '$feedBaseUrl/${channel.name}/app-archive.json';

  /// Where to send someone whose in-app update failed. The Linux path is
  /// preview-grade, so there has to be a way out that does not depend on it.
  static const String releasesUrl =
      'https://github.com/jjaffeux/discourse-native/releases';

  /// The Ed25519 public keys a release descriptor's signature must verify
  /// against, keyed by the id the signing tool stamps into the descriptor.
  ///
  /// Every channel's keys go in, because the channel is chosen at runtime and
  /// a build has to be able to verify whichever one the user switches to. The
  /// signing profile is bound to a channel's archive URL, so a leaked canary
  /// key still cannot sign a stable release.
  ///
  /// Public material only; safe to commit. Copied verbatim from
  /// `desktop_updater.keys.stable.json` and `desktop_updater.keys.canary.json`,
  /// which `release keygen` wrote — do not hand-edit the ids.
  static const Map<String, String> trustedReleaseKeys = {
    // stable — feed .../stable/app-archive.json
    'release-53f8dbf3173c8829fe44e9d9':
        'MZ7r1Y2HgBf9G8Lw99kJv+VkDGzsc3SZ2RR6gr2kRCk=',
    // canary — feed .../canary/app-archive.json
    'release-305aa96ebc8eaaf8a17bb251':
        'A5kk18HKHJJbAJCQA2KxSPpVKPD5eXCcWo8pB4yMYjI=',
  };

  /// False when there is nothing to check a signature against.
  ///
  /// Its own gate rather than something the adapter assumes, because a build
  /// that cannot verify what it downloads must not offer to install it. An
  /// updater with no pinned keys is worse than no updater.
  static bool get canVerifyReleases => trustedReleaseKeys.isNotEmpty;

  /// False for anything built without the release pipeline: a `flutter run`, a
  /// local `flutter build linux`, a test.
  static bool get isReleaseBuild => version.isNotEmpty;

  /// The channel this build was published on, or stable if the define was
  /// something no longer recognised.
  static UpdateChannel get defaultChannel =>
      UpdateChannel.byName(buildChannel) ?? UpdateChannel.stable;
}
