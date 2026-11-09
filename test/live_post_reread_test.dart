import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(id: 7, username: 'reader');
const _deleteSelected = ValueKey('topic-selected-posts-delete');

Post _post(
  int id, {
  String? cooked,
  int likes = 0,
  bool canDelete = false,
}) => Post(
  id: id,
  postNumber: id,
  username: 'sam',
  userId: 9,
  createdAt: DateTime.utc(2026, 9, 1, 0, id),
  cooked:
      cooked ??
      List.filled(
        3,
        '<p>Post $id: a paragraph with a <a href="https://x.test/">link</a> '
        'so that it wraps across several lines of the reading lane.</p>',
      ).join(),
  likeCount: likes,
  canLike: true,
  canDelete: canDelete,
);

typedef _Fixture = ({
  ShellController shell,
  FakeSiteTracker tracker,
  Map<int, Post> served,
});

Future<_Fixture> _openTopic(
  WidgetTester tester, {
  Size size = const Size(1440, 844),
  TargetPlatform platform = TargetPlatform.macOS,
  Set<int> deletable = const {},
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final served = <int, Post>{
    for (var id = 1; id <= 30; id++)
      id: _post(id, canDelete: deletable.contains(id)),
  };
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
    ]),
    api: FakeDiscourseApi(
      user: _reader,
      feeds: {
        '/latest.json': [
          for (var id = 101; id <= 140; id++)
            Topic(
              id: id,
              title: 'Topic $id with a longer title that wraps',
              slug: 'topic-$id',
              bumpedAt: DateTime.utc(2026, 9, 1),
            ),
        ],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: 'A topic',
          posts: served.values.toList(),
          canCreatePost: true,
          canMovePosts: deletable.isNotEmpty,
        ),
      },
      postsById: served,
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    mobileNavigationEnabled: platform == TargetPlatform.iOS,
    plugins: PluginInstaller.install(bundledWidgetTestManifest),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: const AdaptiveShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  await shell.loadTopic(7, 'a-topic');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return (shell: shell, tracker: FakeSiteTracker.built.single, served: served);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
}

/// A `ShellSelector` runs its select once per notification of the shell, so
/// what the shell pays is the selectors mounted times the notifications sent.
Future<({int elements, int notifications, int selectorRuns})> _deliver(
  WidgetTester tester,
  _Fixture fixture,
  Map<String, Object?> message,
) async {
  final selectors = find
      .byWidgetPredicate(
        (widget) => widget is ShellSelector,
        skipOffstage: false,
      )
      .evaluate()
      .length;
  var notifications = 0;
  void counted() => notifications++;
  fixture.shell.addListener(counted);
  var elements = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    elements++;
  };
  try {
    fixture.tracker.deliverTopicMessage('/topic/7', message);
    await _settle(tester);
  } finally {
    debugOnRebuildDirtyWidget = previous;
    fixture.shell.removeListener(counted);
  }
  return (
    elements: elements,
    notifications: notifications,
    selectorRuns: notifications * selectors,
  );
}

void main() {
  for (final (name, size, platform, elementBudget) in [
    ('macos', const Size(1440, 844), TargetPlatform.macOS, 323),
    ('ios', const Size(390, 844), TargetPlatform.iOS, 323),
  ]) {
    testWidgets('a like on a held post on $name redraws only that post', (
      tester,
    ) async {
      final fixture = await _openTopic(tester, size: size, platform: platform);
      fixture.served[1] = _post(1, likes: 1);

      final cost = await _deliver(tester, fixture, const {
        'type': 'liked',
        'id': 1,
      });

      expect(fixture.shell.store.read<Post>(_site, 1)!.likeCount, 1);
      // ignore: avoid_print
      print('PERF_PROOF post-reread ${name}_elements=${cost.elements}');
      // ignore: avoid_print
      print(
        'PERF_PROOF post-reread ${name}_selector_runs=${cost.selectorRuns}',
      );
      expect(cost.elements, lessThanOrEqualTo(elementBudget));
      expect(cost.selectorRuns, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a revised post shows its new body in its own tile', (
    tester,
  ) async {
    final fixture = await _openTopic(tester);
    fixture.served[2] = _post(
      2,
      cooked: '<p>Edited body that is different</p>',
    );

    await _deliver(tester, fixture, const {'type': 'revised', 'id': 2});

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Edited body'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a re-read that finds the post gone takes its row out', (
    tester,
  ) async {
    final fixture = await _openTopic(tester);
    expect(find.byKey(const ValueKey(2), skipOffstage: false), findsOneWidget);
    fixture.served.remove(2);

    final cost = await _deliver(tester, fixture, const {
      'type': 'destroyed',
      'id': 2,
    });

    expect(fixture.shell.store.read<Post>(_site, 2), isNull);
    expect(cost.notifications, greaterThan(0));
    expect(find.byKey(const ValueKey(2), skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a re-read that revokes a selected post updates the toolbar', (
    tester,
  ) async {
    final fixture = await _openTopic(tester, deletable: const {2});
    fixture.shell
      ..setTopicPostSelectionEnabled(_site, 7, true)
      ..toggleTopicPostSelected(_site, 7, 2);
    await _settle(tester);
    expect(
      tester.widget<DButton>(find.byKey(_deleteSelected)).onPressed,
      isNotNull,
    );
    fixture.served[2] = _post(2);

    await _deliver(tester, fixture, const {'type': 'revised', 'id': 2});

    expect(
      tester.widget<DButton>(find.byKey(_deleteSelected)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
