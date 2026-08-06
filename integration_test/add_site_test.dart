import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';

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

    // Anchored on the rail, which is present at every size and never replaced
    // — unlike the list, which the topic view takes over from.
    ShellController controller() =>
        ShellScope.of(tester.element(find.byType(InstanceRail)));

    await pumpUntil(
      tester,
      'the topic list to load',
      () =>
          find.byType(TopicListView).evaluate().isNotEmpty &&
          (controller().currentFeed?.topicIds.isNotEmpty ?? false),
    );

    final firstPage = controller().currentFeed!.topicIds.length;
    expect(firstPage, greaterThan(0));
    expect(controller().currentFeed!.hasMore, isTrue);

    // Scrolling to the end pulls the next page over the real network.
    //
    // drag, not fling: a fling leaves a deceleration animation running, and
    // ScrollAwareImageProvider defers image resolution while it does, so the
    // callbacks outlive the test and the binding reports them as a leak.
    await tester.drag(
      find.descendant(
        of: find.byType(TopicListView),
        matching: find.byType(ListView),
      ),
      const Offset(0, -6000),
    );

    await pumpUntil(
      tester,
      'a second page to append',
      () => (controller().currentFeed?.topicIds.length ?? 0) > firstPage,
    );

    // Back to the top: after scrolling this far the earlier rows have been
    // disposed, which is the list being lazy — their titles are not in the
    // tree to tap.
    await tester.drag(
      find.descendant(
        of: find.byType(TopicListView),
        matching: find.byType(ListView),
      ),
      const Offset(0, 12000),
    );
    await tester.pump();

    // Opening a topic fetches it and replaces the list.
    final firstTitle = controller().store
        .read<Topic>(
          controller().currentInstance!.url,
          controller().currentFeed!.topicIds.first,
        )!
        .title;
    await pumpUntil(
      tester,
      'the first row to be back on screen',
      () => find.text(firstTitle).evaluate().isNotEmpty,
    );
    await tester.tap(find.text(firstTitle).first);
    await tester.pump();

    await pumpUntil(
      tester,
      'the topic and its posts to load',
      () => controller().currentPostIds.isNotEmpty,
    );

    expect(find.byType(TopicView), findsOneWidget);
    expect(find.byType(TopicListView), findsNothing);
    final siteUrl = controller().currentInstance!.url;
    expect(
      controller().currentPostIds.every(
        (id) => controller().store.read<Post>(siteUrl, id)!.cooked.isNotEmpty,
      ),
      isTrue,
    );

    // Let anything still in flight finish before teardown.
    await pumpUntil(
      tester,
      'the topic to go quiet',
      () => !controller().loadingMorePosts,
    );
  });
}
