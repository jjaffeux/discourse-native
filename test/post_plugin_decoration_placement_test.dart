import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_tables.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/alert_fixtures.dart';
import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('Assign and Prometheus stay after the body; Solved is a header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const site = 'https://meta.example';
    final posts = [
      const Post(
        id: 1,
        postNumber: 1,
        username: 'system',
        cooked: '<p>Runbook</p>',
      ),
      Post(
        id: 2,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Investigating</p>',
        plugins: pluginRegistry.readPost({
          'assigned_to_user': {'id': 5, 'username': 'alex'},
          'can_assign': false,
        }, site),
      ),
      Post(
        id: 3,
        postNumber: 3,
        username: 'alex',
        cooked: '<p>Resolved</p>',
        plugins: pluginRegistry.readPost({
          'accepted_answer': true,
          'can_unaccept_answer': false,
        }, site),
      ),
    ];
    final shell = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([instance('meta.example')]),
      api: FakeDiscourseApi(
        topics: {
          7: topicPayload(
            id: 7,
            posts: posts,
            plugins: pluginRegistry.readTopic({
              'alert_data': [alertJson()],
            }, site),
          ),
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'runbook', title: 'Runbook'),
    );
    await shell.loadTopic(7, 'runbook');
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: PluginScope(
          session: shell.pluginSession,
          registry: pluginRegistry,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: TopicView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder body(int id) => find.byWidgetPredicate(
      (widget) => widget is CookedHtml && widget.post?.id == id,
    );
    final alert = find.byType(AlertTables);
    final assignment = find.byKey(const Key('assign-post-2-assignment'));
    final solution = find.byKey(const ValueKey('solved-post-3'));
    expect(alert, findsOneWidget);
    expect(assignment, findsOneWidget);
    expect(solution, findsOneWidget);
    expect(
      tester.getTopLeft(alert).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(body(1)).dy),
    );
    expect(
      tester.getTopLeft(assignment).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(body(2)).dy),
    );
    expect(
      tester.getBottomLeft(solution).dy,
      lessThan(tester.getTopLeft(body(3)).dy),
    );
    expect(find.byKey(const ValueKey('post-news-card-1')), findsNothing);
    expect(find.byKey(const ValueKey('post-news-card-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('post-news-card-3')), findsOneWidget);
    expect(
      tester
          .widget<DCard>(find.byKey(const ValueKey('post-news-card-3')))
          .backgroundColor,
      DTokens.of(
        tester.element(find.byType(TopicView)),
      ).success.withValues(alpha: .08),
    );
    expect(tester.takeException(), isNull);
  });
}
