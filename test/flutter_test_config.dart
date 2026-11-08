import 'dart:async';

import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gives every test an empty in-memory `shared_preferences` store.
///
/// The shell mounts several stores whose reads nothing awaits — the sidebar
/// and diagnostics panel widths, the stored sidebar sections, Voice's device
/// selection. Without a mock store those cross the real platform channel,
/// whose reply lands whenever the host process gets to it: under full-suite
/// load that is after the widget test's fake clock has stopped, so the
/// continuations holding those stores' `catch` blocks never resume and the
/// channel's `MissingPluginException` surfaces as an unhandled error against a
/// test that has already finished.
///
/// Per test rather than per file, because a working store is one tests can
/// write to: a picker that records what was chosen would otherwise carry it
/// into the next test in the same file. Files that want stored values keep
/// calling [SharedPreferences.setMockInitialValues] from their own `setUp`,
/// which runs after this one.
///
/// The reset initializes no binding, so
/// `frame_safe_notifier_headless_test.dart`'s no-binding contract holds.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    EmojiPickerStore().forgetSites(ForgottenSites.except(const []));
    SharedPreferences.setMockInitialValues(const {});
  });
  await testMain();
}
