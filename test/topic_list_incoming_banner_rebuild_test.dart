import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _bannerKey = ValueKey('incoming-topics-button');
const _measuredMessages = 10;

List<Topic> _topics(int first, int count) => [
  for (var id = first; id < first + count; id++)
    Topic(
      id: id,
      title: 'Topic $id with a longer title that wraps',
      slug: 'topic-$id',
      bumpedAt: DateTime.utc(2026, 9, 1),
    ),
];

Map<String, Object?> _latest(int topicId) => {
  'topic_id': topicId,
  'message_type': 'latest',
};

Map<String, Object?> _created(int topicId) => {
  'topic_id': topicId,
  'message_type': 'new_topic',
};

Future<({ShellController controller, FakeSiteTracker tracker})> _pumpShell(
  WidgetTester tester,
  FakeDiscourseApi api, {
  required Size size,
  required TargetPlatform platform,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const user = DiscourseUser(id: 7, username: 'reader');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    plugins: PluginInstaller.install(bundledWidgetTestManifest),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: const AdaptiveShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller: controller, tracker: FakeSiteTracker.built.single);
}

void main() {
  for (final (name, size, platform, elementBudget) in [
    ('macos', const Size(1440, 844), TargetPlatform.macOS, 250),
    ('ios', const Size(390, 844), TargetPlatform.iOS, 150),
  ]) {
    testWidgets('$name: a latest message redraws only the incoming banner', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        user: const DiscourseUser(id: 7, username: 'reader'),
        feeds: {'/latest.json': _topics(1, 40)},
      );
      final (controller: _, :tracker) = await _pumpShell(
        tester,
        api,
        size: size,
        platform: platform,
      );

      tracker.deliver(_latest(1000));
      await tester.pumpAndSettle();
      expect(find.text('See 1 new or updated topic'), findsWidgets);

      var elements = 0;
      var listElements = 0;
      var topicRows = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        elements++;
        if (element.widget.runtimeType.toString() == '_TopicRow') topicRows++;
        if (element.findAncestorWidgetOfExactType<SuperListView>() != null) {
          listElements++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      for (var message = 1; message <= _measuredMessages; message++) {
        tracker.deliver(_latest(1000 + message));
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(
          find.text('See ${message + 1} new or updated topics'),
          findsWidgets,
        );
      }
      debugOnRebuildDirtyWidget = previous;

      final perMessage = elements / _measuredMessages;
      // ignore: avoid_print
      print('PERF_PROOF incoming-banner ${name}_topic_row_builds=$topicRows');
      // ignore: avoid_print
      print('PERF_PROOF incoming-banner ${name}_list_elements=$listElements');
      // ignore: avoid_print
      print(
        'PERF_PROOF incoming-banner ${name}_elements_per_message=$perMessage',
      );
      expect(perMessage, greaterThan(0));
      expect(topicRows, lessThanOrEqualTo(0));
      expect(listElements, lessThanOrEqualTo(0));
      expect(perMessage, lessThanOrEqualTo(elementBudget));
    });
  }

  testWidgets(
    'tapping the banner after a feed switch reveals the current feed',
    (tester) async {
      final api = FakeDiscourseApi(
        user: const DiscourseUser(id: 7, username: 'reader'),
        feeds: {
          '/latest.json': _topics(1, 3),
          '/new.json': _topics(11, 3),
          '/new.json?topic_ids=2000': _topics(2000, 1),
        },
      );
      final (:controller, :tracker) = await _pumpShell(
        tester,
        api,
        size: const Size(390, 844),
        platform: TargetPlatform.iOS,
      );

      tracker.deliver(_created(1999));
      await tester.pumpAndSettle();
      expect(find.text('See 1 new or updated topic'), findsOneWidget);

      await controller.selectTopicListMode(TopicListMode.newActivity);
      await tester.pumpAndSettle();
      expect(find.byKey(_bannerKey), findsNothing);

      tracker.deliver(_created(2000));
      await tester.pumpAndSettle();
      expect(find.text('See 1 new topic'), findsOneWidget);

      await tester.tap(find.byKey(_bannerKey));
      await tester.pumpAndSettle();

      expect(api.feedPaths.last, '/new.json?topic_ids=2000');
      expect(find.textContaining('Topic 2000'), findsOneWidget);
      expect(find.byKey(_bannerKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
