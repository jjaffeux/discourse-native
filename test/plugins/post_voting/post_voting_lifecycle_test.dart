import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_controller.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_data.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_module.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';
import '../../support/shell_test_harness.dart';
import 'post_voting_integration_test.dart' as fixture;

const _root = 'https://forum.example';
const _subfolder = '$_root/community';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'refresh retires a held page without retaining busy state or stale rows',
    (tester) async {
      final f = await fixture.pumpFixture(tester, desktop);
      final controller = PostVotingController(
        reader: f.reader,
        services: f.services,
      );
      addTearDown(controller.dispose);
      f.api.pluginResponses['GET /t/7.json?post_number=1'] = fixture.topic(
        posts: [fixture.post(1), fixture.post(3)],
      );
      await controller.initialize();
      expect(controller.visibleIds, [101, 103]);
      expect(controller.hasMore, isTrue);
      const path = '/t/7/posts.json?post_ids[]=102';
      final gate = Completer<void>();
      f.api.pluginReadGates[path] = gate;
      f.api.pluginResponses['GET $path'] = {
        'post_stream': {
          'posts': [
            {...fixture.post(2), 'raw': 'Superseded page body'},
          ],
        },
      };
      final paging = controller.loadMore();
      await tester.pump();
      expect(controller.loadingMore, isTrue);
      expect(f.api.pluginReadPaths, contains(path));

      f.api.pluginResponses['GET /t/7.json?post_number=1'] = fixture.topic(
        ids: [101, 103],
        posts: [fixture.post(1), fixture.post(3)],
      );
      await controller.refresh();
      expect(controller.loadingMore, isFalse);
      gate.complete();
      await paging;
      expect(controller.visibleIds, [101, 103]);
      expect(controller.orderedIds, [101, 103]);
      expect(f.reader.post(102)!.raw, isNot('Superseded page body'));
      expect(controller.loading, isFalse);
      expect(controller.loadingMore, isFalse);
      expect(controller.error, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'Activity membership wins over a late ranked window and preserves post identities',
    (tester) async {
      final f = await fixture.pumpFixture(tester, desktop);
      final controller = PostVotingController(
        reader: f.reader,
        services: f.services,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      const ranked = '/t/7.json?post_number=1';
      final gate = Completer<void>();
      f.api.pluginReadGates[ranked] = gate;
      f.api.pluginResponses['GET $ranked'] = fixture.topic(
        ids: [101, 102],
        posts: [
          fixture.post(1),
          {...fixture.post(2), 'raw': 'Old ranked result'},
        ],
      );
      final old = controller.refresh();
      await tester.pump();
      expect(controller.loading, isTrue);
      f.api.pluginResponses['GET /t/7.json?filter=activity&post_number=1'] =
          fixture.topic(
            ids: [101, 103],
            posts: [fixture.post(1), fixture.post(3)],
          );
      await controller.changeOrder(PostVotingOrder.activity);
      expect(controller.answerIds, [103]);
      expect(f.reader.post(103)!.postNumber, 3);
      gate.complete();
      await old;
      expect(controller.order, PostVotingOrder.activity);
      expect(controller.orderedIds, [101, 103]);
      expect(controller.visibleIds, [101, 103]);
      expect(f.reader.post(102)!.raw, isNot('Old ranked result'));
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
      expect(
        Uri(query: f.reader.route.topicQuery).queryParameters['filter'],
        'activity',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'anonymous comment event retains authenticated flags and vote until authenticated reread',
    (tester) async {
      final f = await fixture.pumpFixture(tester, desktop);
      final own = PostVotingComment.fromJson(
        fixture.comment(voted: true),
        parentPostId: 103,
        authoritativeVote: true,
      );
      f.services.actions.publishComments(f.reader, 103, [own], total: 1);
      const path = '/post_voting/comments.json?post_id=103&last_comment_id=0';
      final gate = Completer<void>();
      f.api.pluginReadGates[path] = gate;
      f.api.pluginResponses['GET $path'] = {
        'comments': [fixture.comment(body: 'Authenticated edit', voted: true)],
      };
      final tracker = FakeSiteTracker.built.lastWhere(
        (t) => t.siteUrl == fixture.site,
      );
      tracker.deliverTopicMessage('/topic/7', {
        'type': 'post_voting_post_comment_edited',
        'id': 103,
        'comments_count': 1,
        'comment': {
          ...fixture.comment(body: 'Anonymous event'),
          'user_voted': null,
          'available_flags': <Object?>[],
        },
      });
      await tester.pump();
      final held = f.services.actions
          .record(fixture.site, 103)!
          .initialComments!
          .single;
      expect(held.raw, 'That helped, thank you.');
      expect(held.myUpvote, isTrue);
      expect(held.availableFlags, ['spam', 'inappropriate']);
      expect(f.api.pluginReadPaths, contains(path));
      gate.complete();
      await fixture.frames(tester);
      final fresh = f.services.actions
          .record(fixture.site, 103)!
          .initialComments!
          .single;
      expect(fresh.raw, 'Authenticated edit');
      expect(fresh.myUpvote, isTrue);
      expect(fresh.availableFlags, ['spam', 'inappropriate']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('disconnect retires an in-flight authenticated comment read', (
    tester,
  ) async {
    final f = await fixture.pumpFixture(tester, desktop);
    const path = '/post_voting/comments.json?post_id=103&last_comment_id=0';
    final gate = Completer<void>();
    f.api.pluginReadGates[path] = gate;
    final old = f.services.actions.loadComments(f.reader, 103);
    await tester.pump();
    expect(f.reader.isCurrent, isTrue);
    expect(await f.shell.disconnectInstance(fixture.site), isTrue);
    expect(f.reader.isCurrent, isFalse);
    gate.complete();
    expect(await old, isNull);
    await fixture.frames(tester);
    expect(f.services.actions.commentState(fixture.site, 103).pending, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final target in [_root, _subfolder]) {
    for (final endpoint in ['p/103', 't/project/7/3', 't/project/7']) {
      testWidgets(
        '$target/$endpoint comment link preserves serving site, query and panel intent',
        (tester) async {
          final f = await _twoSites(tester);
          expect(f.shell.currentInstance!.url, _root);
          var navigations = 0;
          expect(
            await f.services.openPluginUrl(
              '$target/$endpoint?filter=activity&source=notification#post-voting-comment-51',
              origin: PluginLinkOrigin.secondaryPanelNewTab,
              onNavigated: () => navigations++,
            ),
            isTrue,
          );
          expect(f.shell.currentInstance!.url, target);
          final tab = f.shell.tabsForCurrentForum.singleWhere(
            (tab) => tab.currentContent.topicId == 7,
          );
          expect(tab.panel, ForumPanel.secondary);
          final route = tab.currentContent;
          expect(route.topicId, 7);
          expect(route.postNumber, endpoint == 't/project/7' ? 1 : 3);
          expect(Uri(query: route.topicQuery).queryParameters, {
            'filter': 'activity',
            'source': 'notification',
            'post-voting-comment': '51',
          });
          expect(navigations, 1);
          if (endpoint.startsWith('p/')) {
            expect(f.api.parentLookups, [
              (target, target == _root ? 'root-key' : 'sub-key'),
            ]);
          } else {
            expect(f.api.parentLookups, isEmpty);
          }
          await fixture.frames(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
  testWidgets(
    'account retirement during parent lookup cannot navigate or invoke completion',
    (tester) async {
      final f = await _twoSites(tester);
      final gate = Completer<void>();
      f.api.pluginReadGates['/posts/103.json'] = gate;
      var navigations = 0;
      final old = f.services.openPluginUrl(
        '$_subfolder/p/103#post-voting-comment-51',
        onNavigated: () => navigations++,
      );
      await tester.pump();
      expect(f.api.parentLookups, [(_subfolder, 'sub-key')]);
      expect(await f.shell.disconnectInstance(_subfolder), isTrue);
      gate.complete();
      expect(await old, isFalse);
      expect(f.shell.currentInstance!.url, _root);
      expect(f.shell.currentContent?.topicId, isNull);
      expect(navigations, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'identical topic and post IDs keep votes and comments within their serving site',
    (tester) async {
      final f = await _twoSites(tester);
      final row = fixture.models.topicSummary(fixture.topic(), _root);
      f.shell.openTopic(row);
      await fixture.frames(tester);
      final rootReader = f.services.readers.forVisibleTopic(_root, 7)!;
      addTearDown(rootReader.close);
      f.services.actions.publishComments(rootReader, 103, [
        PostVotingComment.fromJson(
          fixture.comment(body: 'Root comment', voted: true),
          parentPostId: 103,
          authoritativeVote: true,
        ),
      ], total: 1);
      f.services.actions.votedEvent(rootReader, {
        'id': 103,
        'post_voting_vote_count': 90,
        'post_voting_has_votes': true,
        'post_voting_user_voted_id': 9,
        'post_voting_user_voted_direction': 'down',
      });
      final rootPostId = rootReader.post(103)!.id;
      f.shell.selectInstance(1);
      f.shell.openTopic(
        fixture.models.topicSummary(fixture.topic(), _subfolder),
      );
      await fixture.frames(tester);
      final subReader = f.services.readers.forVisibleTopic(_subfolder, 7)!;
      addTearDown(subReader.close);
      final sub = f.services.actions.record(_subfolder, 103)!;
      expect(sub.score, 12);
      expect(sub.myVote, isNull);
      expect(sub.initialComments!.single.raw, 'That helped, thank you.');
      final root = f.services.actions.record(_root, 103)!;
      expect(root.score, 90);
      expect(root.myVote, PostVoteDirection.down);
      expect(root.initialComments!.single.raw, 'Root comment');
      expect(root.initialComments!.single.myUpvote, isTrue);
      expect(subReader.post(103)!.id, rootPostId);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

Future<({ShellController shell, _LookupApi api, PostVotingServices services})>
_twoSites(WidgetTester tester) async {
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      postVotingSettingsKey,
      const PostVotingSettings(enabled: true),
    ),
  );
  final api = _LookupApi(config);
  await pumpShell(
    tester,
    desktop,
    instances: [
      for (final site in [_root, _subfolder])
        DiscourseInstance(
          url: site,
          title: site,
          apiVersion: 4,
          loginRequired: false,
          user: fixture.user,
          config: config,
        ),
    ],
    api: api,
    authenticator: FakeAuthenticator()
      ..keys.addAll({_root: 'root-key', _subfolder: 'sub-key'}),
    pluginManifest: const PluginManifest([postVotingModule]),
  );
  final shell = ShellScope.read(tester.element(primaryMainContent));
  shell.desktopTopicTabs = true;
  return (
    shell: shell,
    api: api,
    services: shell.pluginSession.require(postVotingServicesKey),
  );
}

final class _LookupApi extends FakeDiscourseApi {
  _LookupApi(SiteConfig config)
    : super(
        models: fixture.models,
        user: fixture.user,
        siteConfigs: {_root: config, _subfolder: config},
        topics: {7: fixture.models.topic(fixture.topic(), _root)},
        pluginResponses: {
          'GET /posts/103.json': {
            'id': 103,
            'topic_id': 7,
            'post_number': 3,
            'topic_slug': 'project',
          },
          'GET /t/7.json': fixture.topic(),
          'GET /t/7.json?post_number=1': fixture.topic(),
          'GET /t/7.json?post_number=3': fixture.topic(),
          'GET /t/7.json?filter=activity&post_number=3': fixture.topic(
            activity: true,
          ),
          'GET /post_voting/comments.json?post_id=103&last_comment_id=0': {
            'comments': [fixture.comment()],
          },
          'GET /post_voting/comments.json?post_id=103&last_comment_id=51': {
            'comments': <Object?>[],
          },
        },
      );
  final List<(String, String?)> parentLookups = [];
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    if (path == '/posts/103.json') parentLookups.add((siteUrl, apiKey));
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
