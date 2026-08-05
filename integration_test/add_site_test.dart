import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/shell/empty_state.dart';

/// Exercises the add-a-site flow on a real device against the real network,
/// which is the one seam the unit tests cannot cover: real HTTP, real
/// redirects, real shared_preferences.
///
///   `flutter test integration_test -d <device-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// pumpAndSettle never returns while the progress spinner is running, and
  /// the pane cross-fade keeps the outgoing widget mounted for a moment after
  /// the new one appears — so pump in slices until the condition holds.
  Future<void> pumpUntil(
    WidgetTester tester,
    String description,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (condition()) return;
    }
    fail('Timed out waiting for $description');
  }

  testWidgets('connects to meta.discourse.org and keeps it', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await tester.pumpWidget(const DiscourseApp());
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);

    await tester.tap(find.text('Add a site'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'meta.discourse.org');
    await tester.tap(find.text('Connect'));

    await pumpUntil(
      tester,
      'the site to appear',
      () => find.text('Discourse Meta').evaluate().isNotEmpty,
    );
    await pumpUntil(
      tester,
      'the empty state to fade out',
      () => find.byType(EmptyState).evaluate().isEmpty,
    );

    // Persisted, so a relaunch would still have it. reload() re-reads from the
    // platform: without it this would assert against the in-memory cache that
    // SharedPreferences.getInstance() hands back, and prove nothing about disk.
    await prefs.reload();

    final stored = await InstanceStore().load();
    expect(stored.single.url, 'https://meta.discourse.org');
    expect(stored.single.title, 'Discourse Meta');
    expect(stored.single.iconUrl, isNotNull);
  });
}
