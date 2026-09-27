import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../foundation/private_file_permissions.dart';

/// Where `shared_preferences_linux` keeps every preference, inside the
/// application support directory.
const String linuxSharedPreferencesFileName = 'shared_preferences.json';

/// Makes the Linux application support and cache directories owner-only, along
/// with the preferences file that already sits in support.
///
/// `path_provider_linux` creates both directories, and
/// `shared_preferences_linux` its file, with process-default permissions:
/// under the usual umask that lets any local user who can traverse the home
/// directory read forum URLs, usernames, and the titles of private messages
/// and chat channels kept for recent destinations and open tabs. The plugin
/// rewrites that file in place, so the mode set here outlives later writes,
/// and a file it creates afterwards still sits behind the private directory.
///
/// Each directory is restricted independently; the first failure is rethrown
/// once both have been attempted. Apple platforms already confine these
/// directories to the app's container, so only Linux changes anything.
Future<void> restrictLinuxApplicationDirectories({
  bool? isLinux,
  Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory,
  Future<Directory> Function() cacheDirectory = getApplicationCacheDirectory,
}) async {
  if (!(isLinux ?? Platform.isLinux)) return;
  await Future.wait([
    () async {
      final support = await supportDirectory();
      await ensurePrivateDirectory(support);
      final preferences = File(
        '${support.path}/$linuxSharedPreferencesFileName',
      );
      if (await preferences.exists()) restrictPrivateFile(preferences);
    }(),
    () async {
      await ensurePrivateDirectory(await cacheDirectory());
    }(),
  ]);
}
