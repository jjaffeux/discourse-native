import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Gives every test file an in-memory `shared_preferences` store.
///
/// The shell mounts several stores whose reads nothing awaits — the sidebar
/// and diagnostics panel widths, the stored sidebar sections, Resenha's device
/// selection. Without a mock store those cross the real platform channel,
/// whose reply arrives whenever the host process gets to it: under full-suite
/// load that is after the widget test's fake clock has stopped, so the
/// continuations holding those stores' `catch` blocks never resume and the
/// channel's `MissingPluginException` is reported as an unhandled error
/// against a test that has already finished.
///
/// Only the platform store is swapped, so no binding is initialized here and
/// `frame_safe_notifier_headless_test.dart`'s no-binding contract still holds.
/// A file that wants stored values still calls `setMockInitialValues` itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  await testMain();
}
