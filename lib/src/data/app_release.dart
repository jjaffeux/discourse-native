import 'updater.dart';

/// What the release pipeline stamped into this build.
///
/// Compile-time rather than read back from the bundle so tests do not need a
/// platform channel just to render version and channel information:
///
///  - `package_info_plus` is a platform channel, and this app keeps platform
///    channels out of tests deliberately. `pumpShell` builds the whole app in
///    around a hundred tests; none of them should have to stand up a plugin to
///    find out what version they are.
///  - The channel needs the same mechanism, so reading only the version back
///    from a bundle would give the app two sources of release metadata.
///  - On Linux the bundle's version metadata comes from CMake, which is an
///    awkward thing to read back and an easy one to leave stale.
///  - An empty [version] means nobody released this build, distinguishing a
///    developer's `flutter run` from an artifact stamped by CI. A version
///    derived from the pubspec is always populated, and so can never say that.
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

  /// Manual-download fallback for the generic update sheet.
  static const String releasesUrl =
      'https://github.com/jjaffeux/discourse-native/releases';

  /// The channel this build was published on, or stable if the define was
  /// something no longer recognised.
  static UpdateChannel get defaultChannel =>
      UpdateChannel.byName(buildChannel) ?? UpdateChannel.stable;
}
