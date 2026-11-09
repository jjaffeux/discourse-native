import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

/// Upstream publishes a `stats` message on `/topic/<id>` after every like,
/// unlike, new post and deletion. The totals belong to the topic map under
/// the opening post; no other mounted post shows them.
void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    final name = platform.name.toLowerCase();
    testWidgets('$name: a topic stats message leaves mounted posts alone', (
      tester,
    ) async {
      final reader = await _openTopic(tester, platform);
      final bodies = find.byType(CookedHtml).evaluate().toSet();
      expect(bodies.length, greaterThan(2));

      final rebuilt = _countRebuilds();
      reader.tracker.deliverTopicMessage('/topic/7', const {
        'type': 'stats',
        'like_count': 5,
        'posts_count': 31,
      });
      await _settle(tester);
      final elements = rebuilt.length;
      // ignore: avoid_print
      print('PERF_PROOF topic-totals ${name}_stats_elements=$elements');

      expect(rebuilt.intersection(bodies), isEmpty);
      expect(elements, lessThanOrEqualTo(_statsBudget[platform]!));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('macOS: a live reply leaves the posts already read alone', (
    tester,
  ) async {
    final reader = await _openTopic(tester, TargetPlatform.macOS);
    final bodies = find.byType(CookedHtml).evaluate().toSet();
    reader.api.publish(_post(31));

    final rebuilt = _countRebuilds();
    reader.tracker.deliverTopicMessage('/topic/7', const {
      'type': 'created',
      'id': 31,
      'post_number': 31,
    });
    await _settle(tester);
    final elements = rebuilt.length;
    // ignore: avoid_print
    print('PERF_PROOF topic-totals macos_created_elements=$elements');

    expect(rebuilt.intersection(bodies), isEmpty);
    expect(elements, lessThanOrEqualTo(_createdBudget));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the topic map shows the totals a stats message carries', (
    tester,
  ) async {
    final reader = await _openTopic(tester, TargetPlatform.macOS);
    expect(_stat('topic-map-likes', '2'), findsOneWidget);
    expect(_stat('topic-map-replies', '29'), findsOneWidget);

    reader.tracker.deliverTopicMessage('/topic/7', const {
      'type': 'stats',
      'like_count': 5,
      'posts_count': 31,
    });
    await _settle(tester);

    expect(_stat('topic-map-likes', '5'), findsOneWidget);
    expect(_stat('topic-map-replies', '30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a post plugin still sees a topic field change', (tester) async {
    final reader = await _openTopic(
      tester,
      TargetPlatform.macOS,
      extraModule: const _TopicFieldModule(),
    );
    expect(find.text('private=false'), findsWidgets);
    expect(find.text('private=true'), findsNothing);

    reader.api.publish(_post(31), privateMessage: true);
    reader.tracker.deliverTopicMessage('/topic/7', const {
      'reload_topic': true,
    });
    await _settle(tester);

    expect(find.text('private=true'), findsWidgets);
    expect(find.text('private=false'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// The after-numbers of the proof, so a regression fails here.
const _statsBudget = {TargetPlatform.macOS: 950, TargetPlatform.iOS: 702};
const _createdBudget = 950;

const _site = 'https://meta.discourse.org';
const _reader = DiscourseUser(id: 7, username: 'reader');

Finder _stat(String key, String value) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(value));

Post _post(int id) => Post(
  id: id,
  postNumber: id,
  username: 'sam',
  userId: 9,
  createdAt: DateTime.utc(2026, 9, 1, 0, id),
  cooked: '<p>Short reply $id</p>',
  canLike: true,
);

Set<Element> _countRebuilds() {
  final rebuilt = <Element>{};
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    rebuilt.add(element);
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilt;
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
}

final class _Reader {
  _Reader(this.controller, this.tracker, this.api);

  final ShellController controller;
  final FakeSiteTracker tracker;
  final _TopicApi api;
}

final class _TopicApi extends FakeDiscourseApi {
  _TopicApi({super.user, super.feeds, super.topics, super.postsById});

  /// Adds [post] to topic 7 as the server would hold it after a reply.
  void publish(Post post, {bool privateMessage = false}) {
    postsById[post.id] = post;
    topics[7] = _payload(
      postsById.values.toList(),
      privateMessage: privateMessage,
    );
  }
}

TopicPayload _payload(List<Post> posts, {bool privateMessage = false}) =>
    topicPayload(
      id: 7,
      title: 'A topic',
      posts: posts,
      likeCount: 2,
      canCreatePost: true,
      privateMessage: privateMessage,
    );

Future<_Reader> _openTopic(
  WidgetTester tester,
  TargetPlatform platform, {
  PluginModule? extraModule,
}) async {
  final mobile = platform == TargetPlatform.iOS;
  final size = mobile ? const Size(390, 844) : const Size(1440, 844);
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final byId = <int, Post>{for (var id = 1; id <= 30; id++) id: _post(id)};
  final api = _TopicApi(
    user: _reader,
    feeds: {
      '/latest.json': [
        Topic(
          id: 7,
          title: 'A topic',
          slug: 'a-topic',
          bumpedAt: DateTime.utc(2026, 9, 1),
        ),
      ],
    },
    topics: {7: _payload(byId.values.toList())},
    postsById: byId,
  );
  final installed = PluginInstaller.install(
    PluginManifest([...bundledWidgetTestManifest.modules, ?extraModule]),
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    mobileNavigationEnabled: mobile,
    plugins: installed,
  );
  addTearDown(() async {
    controller.dispose();
    await installed.close();
  });
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
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  await controller.loadTopic(7, 'a-topic');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  return _Reader(controller, FakeSiteTracker.built.single, api);
}

final class _TopicFieldModule implements PluginModule {
  const _TopicFieldModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('topic-field-test'));

  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _TopicFieldPlugin());
}

final class _TopicFieldPlugin implements SitePlugin, PostDecorationPlugin {
  const _TopicFieldPlugin();

  @override
  String get name => 'topic-field-test';

  @override
  List<Widget> postDecorations(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
    Post post,
  ) => [Text('private=${topic.privateMessage}')];
}
