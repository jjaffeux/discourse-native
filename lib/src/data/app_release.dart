import 'updater.dart';

abstract final class AppRelease {
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

  static const String releasesUrl =
      'https://github.com/jjaffeux/discourse-native/releases';

  static UpdateChannel get defaultChannel =>
      UpdateChannel.byName(buildChannel) ?? UpdateChannel.stable;
}
