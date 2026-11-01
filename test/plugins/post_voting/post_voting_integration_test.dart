import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_composer.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_data.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_module.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_plugin.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_reader.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';
import '../../support/native_ui_evidence.dart';
import '../../support/shell_test_harness.dart';

const site = 'https://meta.discourse.org';
const registry = PluginRegistry([
  PostVotingPlugin(),
  PostVotingPostPlugin(),
  PostVotingCategoryPlugin(),
  PostVotingUserPlugin(),
]);
const models = DiscourseModelCodec(extensions: registry);
const user = DiscourseUser(id: 9, username: 'reader', staff: true);

class VotingTestApi extends FakeDiscourseApi {
  VotingTestApi({
    required super.models,
    required super.user,
    required super.siteConfigs,
    required super.feeds,
    required super.topics,
    required super.pluginResponses,
    super.categoryList,
  });
  Future<void>? writeGate;
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    await writeGate;
    return super.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }
}

Map<String, dynamic> post(int number, {int? score}) => {
  'id': 100 + number,
  'topic_id': 7,
  'post_number': number,
  'post_type': 1,
  'user_id': number,
  'username': number == 1 ? 'anna' : 'sam$number',
  'created_at': '2026-11-01T08:00:00Z',
  'cooked':
      '<p>${number == 1
          ? 'How do you keep a small project easy to maintain?'
          : number == 3
          ? 'Keep the boundaries simple, and test the behavior people rely on.'
          : 'Start with the smallest useful change, then build on what you learn.'}</p>',
  'raw': 'A useful answer body',
  'post_voting_vote_count': score ?? (number == 3 ? 12 : 3),
  'post_voting_has_votes': true,
  'comments_count': number == 3 ? 1 : 0,
  'comments': number == 3 ? [comment()] : <Object?>[],
  'can_edit': true,
  'can_delete': true,
  'can_recover': false,
};
Map<String, dynamic> comment({
  String body = 'That helped, thank you.',
  bool voted = false,
}) => {
  'id': 51,
  'post_id': 103,
  'user_id': 9,
  'username': 'reader',
  'created_at': '2026-11-01T08:30:00Z',
  'raw': body,
  'cooked': '<p>$body</p>',
  'post_voting_vote_count': 2,
  'user_voted': voted,
  'available_flags': ['spam', 'inappropriate'],
};
Map<String, dynamic> topic({
  bool activity = false,
  List<int>? ids,
  List<Map<String, dynamic>>? posts,
}) => {
  'id': 7,
  'title': 'Keeping a project easy to maintain',
  'slug': 'project',
  'is_post_voting': true,
  'answer_count': 2,
  'highest_post_number': 3,
  'last_read_post_number': 3,
  'posts_count': 3,
  'category_id': 1,
  'details': {
    'can_create_post': true,
    'can_edit': true,
    'participants': <Object?>[],
  },
  'post_stream': {
    'stream': ids ?? (activity ? [101, 102, 103] : [101, 103, 102]),
    'posts': posts ?? [post(1), post(3), post(2)],
  },
};

Future<
  ({
    ShellController shell,
    FakeDiscourseApi api,
    Topic row,
    PostVotingServices services,
    PluginTopicReader reader,
  })
>
pumpFixture(
  WidgetTester tester,
  Size size, {
  Map<String, dynamic>? topicJson,
  DiscourseUser actor = user,
  List<TopicCategory> categories = const [],
}) async {
  final wire = topicJson ?? topic();
  final configured = SiteConfig(
    plugins: PluginData.none.withValue(
      postVotingSettingsKey,
      const PostVotingSettings(enabled: true),
    ),
  );
  final row = models.topicSummary(wire, site);
  final api = VotingTestApi(
    models: models,
    user: actor,
    siteConfigs: {site: configured},
    feeds: {
      '/latest.json': [row],
    },
    topics: {7: models.topic(wire, site)},
    categoryList: categories,
    pluginResponses: {
      'GET /t/7.json?post_number=1': wire,
      'GET /t/7.json': wire,
      'GET /t/7.json?post_number=3': topic(),
      'GET /t/7.json?filter=activity&post_number=1': topic(activity: true),
      'GET /post_voting/comments.json?post_id=103&last_comment_id=0': {
        'comments': [comment()],
      },
      'GET /post_voting/comments.json?post_id=103&last_comment_id=51': {
        'comments': <Object?>[],
      },
      'POST /post_voting/vote.json': {'success': 'OK'},
      'DELETE /post_voting/vote.json': {'success': 'OK'},
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance('meta.discourse.org').copyWith(user: actor, config: configured),
    ],
    api: api,
    authenticator: FakeAuthenticator()..keys[site] = 'key',
    pluginManifest: const PluginManifest([postVotingModule]),
  );
  final shell = ShellScope.read(tester.element(primaryMainContent));
  await shell.forumSettings.setThemeMode(site, AppThemeMode.dark);
  shell.openTopic(row);
  await frames(tester);
  final element = tester.element(find.byType(PostVotingReader));
  final services = PluginUiScope.require(element, postVotingServicesKey);
  final reader = services.readers.forVisibleTopic(site, 7)!;
  addTearDown(reader.close);
  return (shell: shell, api: api, row: row, services: services, reader: reader);
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump();
  final dir = Platform.environment['NATIVE_UI_EVIDENCE_DIR'];
  if (dir == null) return;
  expect(tester.takeException(), isNull);
  final view = tester.binding.renderViews.single;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  for (final entry in [('desktop', desktop), ('mobile', phone)]) {
    testWidgets(
      'production ${entry.$1} composer offers post voting in options and follows category policy',
      (tester) async {
        await prepareNativeUiEvidence(tester);
        final fixture = await pumpFixture(
          tester,
          entry.$2,
          actor: const DiscourseUser(
            id: 9,
            username: 'reader',
            staff: true,
            canCreateTopic: true,
          ),
          categories: [
            const TopicCategory(
              id: 1,
              name: 'General',
              color: '0088CC',
              permission: 1,
            ),
            TopicCategory(
              id: 2,
              name: 'Questions',
              color: '0088CC',
              permission: 1,
              plugins: PluginData.none.withValue(
                postVotingCategoryKey,
                const PostVotingCategoryData(defaultOn: true),
              ),
            ),
            TopicCategory(
              id: 3,
              name: 'Required voting',
              color: '0088CC',
              permission: 1,
              plugins: PluginData.none.withValue(
                postVotingCategoryKey,
                const PostVotingCategoryData(requiredOn: true),
              ),
            ),
          ],
        );
        await fixture.shell.openNewTopicFromSidebar();
        await frames(tester);
        final composer = fixture.shell.visibleComposer!;
        final options = find.byKey(const ValueKey('composer-options'));
        final voting = find.widgetWithText(
          DDropdownMenuCheckboxItem,
          'Post voting topic',
        );
        Future<void> openOptions() async {
          await tester.ensureVisible(options);
          await frames(tester);
          await tester.tap(options);
          await frames(tester);
          expect(voting, findsOneWidget);
        }

        expect(find.text('Post voting topic'), findsNothing);
        expect(composer.composerCreateFields, isEmpty);
        await capture(tester, '${entry.$1}-composer-header');
        await openOptions();
        expect(
          tester.widget<DDropdownMenuCheckboxItem>(voting).checked,
          isFalse,
        );
        await capture(tester, '${entry.$1}-composer-options');
        await tester.tap(voting);
        await frames(tester);
        expect(voting, findsNothing);
        expect(composer.composerCreateFields, {'create_as_post_voting': true});
        expect(composer.pluginLabels?.submit, 'Create post voting topic');
        await openOptions();
        expect(
          tester.widget<DDropdownMenuCheckboxItem>(voting).checked,
          isTrue,
        );
        await tester.tap(voting);
        await frames(tester);
        expect(composer.composerCreateFields, isEmpty);

        await fixture.shell.changeComposerCategory(composer, 2);
        await frames(tester);
        expect(composer.composerCreateFields, {'create_as_post_voting': true});
        await openOptions();
        expect(
          tester.widget<DDropdownMenuCheckboxItem>(voting).checked,
          isTrue,
        );
        await tester.tap(voting);
        await frames(tester);
        expect(composer.composerCreateFields, isEmpty);
        await fixture.shell.changeComposerCategory(composer, 1);
        await frames(tester);
        expect(composer.composerCreateFields, isEmpty);
        await fixture.shell.changeComposerCategory(composer, 2);
        await frames(tester);
        expect(composer.composerCreateFields, {'create_as_post_voting': true});

        await fixture.shell.changeComposerCategory(composer, 3);
        await frames(tester);
        expect(composer.composerCreateFields, {'create_as_post_voting': true});
        expect(composer.pluginLabels?.submit, 'Create post voting topic');
        expect(composer.pluginLabels?.title, 'Create post voting topic');
        expect(find.text('Post voting topic'), findsNothing);
        expect(
          find.text('This category requires Post Voting topics.'),
          findsNothing,
        );
        expect(options, findsNothing);
        expect(tester.takeException(), isNull);
        await capture(tester, '${entry.$1}-composer-required');
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(
        entry.$1 == 'desktop' ? TargetPlatform.macOS : TargetPlatform.iOS,
      ),
    );
    testWidgets(
      'production ${entry.$1} orders answers, selects vote, and opens full host answer composer',
      (tester) async {
        await prepareNativeUiEvidence(tester);
        final fixture = await pumpFixture(tester, entry.$2);
        expect(tester.takeException(), isNull);
        expect(find.byType(PostVotingReader), findsOneWidget);
        final first = tester
            .getTopLeft(renderedText('Keep the boundaries simple'))
            .dy;
        expect(
          first,
          lessThan(
            tester.getTopLeft(renderedText('Start with the smallest')).dy,
          ),
        );
        await capture(tester, '${entry.$1}-votes');
        fixture.api.pluginResponses['GET /t/7.json?post_number=3'] = topic(
          posts: [
            post(1),
            {...post(3, score: 13), 'post_voting_user_voted_direction': 'up'},
            post(2),
          ],
        );
        await fixture.services.actions.vote(
          fixture.reader,
          103,
          PostVoteDirection.up,
        );
        await frames(tester);
        await capture(tester, '${entry.$1}-selected-vote');
        expect(fixture.api.pluginWrites.single.path, '/post_voting/vote.json');
        expect(
          fixture.services.actions.record(site, 103)!.myVote,
          PostVoteDirection.up,
        );
        expect(fixture.services.actions.record(site, 103)!.score, 13);
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('post-voting-order')),
            matching: find.text('Activity'),
          ),
        );
        await frames(tester);
        expect(
          fixture.api.pluginReadPaths,
          contains('/t/7.json?filter=activity&post_number=1'),
        );
        expect(
          tester.getTopLeft(renderedText('Start with the smallest')).dy,
          lessThan(
            tester.getTopLeft(renderedText('Keep the boundaries simple')).dy,
          ),
        );
        await capture(tester, '${entry.$1}-activity');
        await tester.tap(find.byKey(const ValueKey('post-voting-answer')));
        await frames(tester);
        expect(fixture.shell.visibleComposer != null, isTrue);
        expect(fixture.shell.visibleComposer!.target.replyToPostNumber, isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(
        entry.$1 == 'desktop' ? TargetPlatform.macOS : TargetPlatform.android,
      ),
    );
  }
  testWidgets(
    'authoritative same actor event removes optimistic overlay before HTTP returns',
    (tester) async {
      final fixture = await pumpFixture(tester, desktop);
      final gate = Completer<void>();
      (fixture.api as VotingTestApi).writeGate = gate.future;
      fixture.api.pluginResponses['GET /t/7.json?post_number=3'] = topic(
        posts: [
          post(1),
          {...post(3, score: 13), 'post_voting_user_voted_direction': 'up'},
          post(2),
        ],
      );
      final pending = fixture.services.actions.vote(
        fixture.reader,
        103,
        PostVoteDirection.up,
      );
      await frames(tester);
      expect(fixture.services.actions.displayedRecord(site, 103)!.score, 13);
      expect(fixture.services.actions.voteState(site, 103).pending, isTrue);
      fixture.services.actions.votedEvent(fixture.reader, {
        'id': 103,
        'post_voting_vote_count': 13,
        'post_voting_has_votes': true,
        'post_voting_user_voted_id': 9,
        'post_voting_user_voted_direction': 'up',
      });
      expect(fixture.services.actions.displayedRecord(site, 103)!.score, 13);
      gate.complete();
      await pending;
      expect(fixture.services.actions.record(site, 103)!.score, 13);
      fixture.services.actions.votedEvent(fixture.reader, {
        'id': 103,
        'post_voting_vote_count': 12,
        'post_voting_has_votes': true,
        'post_voting_user_voted_id': 9,
        'post_voting_user_voted_direction': null,
      });
      expect(fixture.services.actions.record(site, 103)!.myVote, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late full comment read cannot replace a later authenticated mutation read',
    (tester) async {
      final fixture = await pumpFixture(tester, desktop);
      final gate = Completer<void>();
      const path = '/post_voting/comments.json?post_id=103&last_comment_id=0';
      fixture.api.pluginReadGates[path] = gate;
      final old = fixture.services.actions.loadComments(fixture.reader, 103);
      await tester.pump();
      fixture.services.actions.invalidateComments(site, 103);
      fixture.api.pluginReadGates.remove(path);
      fixture.api.pluginResponses['GET $path'] = {
        'comments': [comment(body: 'Edited answer clarification')],
      };
      final fresh = await fixture.services.actions.loadComments(
        fixture.reader,
        103,
      );
      fixture.services.actions.publishComments(
        fixture.reader,
        103,
        fresh!.comments,
        total: 1,
      );
      gate.complete();
      expect(await old, isNull);
      expect(
        fixture.services.actions.record(site, 103)!.initialComments!.single.raw,
        'Edited answer clarification',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'refused Activity fetch restores the previously accepted sort and URL',
    (tester) async {
      final fixture = await pumpFixture(tester, desktop);
      fixture.api.pluginResponses.remove(
        'GET /t/7.json?filter=activity&post_number=1',
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('post-voting-order')),
          matching: find.text('Activity'),
        ),
      );
      await frames(tester);
      expect(
        tester
            .widget<DToggleGroup<PostVotingOrder>>(
              find.byKey(const ValueKey('post-voting-order')),
            )
            .values,
        [PostVotingOrder.votes],
      );
      expect(
        fixture.reader.route.topicQuery,
        isNot(contains('filter=activity')),
      );
      expect(
        tester.getTopLeft(renderedText('Keep the boundaries simple')).dy,
        lessThan(tester.getTopLeft(renderedText('Start with the smallest')).dy),
      );
      await capture(tester, 'desktop-activity-error');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dispatched vote timeout cannot replay before authoritative status check',
    (tester) async {
      final fixture = await pumpFixture(tester, desktop);
      fixture.api.pluginWriteFailures['POST /post_voting/vote.json'] =
          const WriteException(WriteFailure.unreachable);
      await fixture.services.actions.vote(
        fixture.reader,
        103,
        PostVoteDirection.up,
      );
      expect(fixture.services.actions.voteState(site, 103).uncertain, isTrue);
      await fixture.services.actions.vote(
        fixture.reader,
        103,
        PostVoteDirection.up,
      );
      expect(fixture.api.pluginWrites.length, 1);
      fixture.api.pluginResponses['GET /t/7.json?post_number=3'] = topic(
        posts: [
          post(1),
          {...post(3, score: 13), 'post_voting_user_voted_direction': 'up'},
          post(2),
        ],
      );
      await fixture.services.actions.checkVote(fixture.reader, 103);
      expect(fixture.services.actions.voteState(site, 103).uncertain, isFalse);
      expect(
        fixture.services.actions.record(site, 103)!.myVote,
        PostVoteDirection.up,
      );
      expect(fixture.api.pluginWrites.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'comment draft survives refusal and accepted cooked response replaces editor',
    (tester) async {
      final fixture = await pumpFixture(tester, desktop);
      final editor = find.byKey(
        const ValueKey('post-voting-comment-editor-103'),
      );
      final section = find.byWidgetPredicate(
        (w) =>
            w.key ==
            ValueKey((
              'post-voting-comments',
              site,
              7,
              103,
              fixture.services.actions.epochFor(site),
            )),
      );
      await tester.ensureVisible(
        find.descendant(of: section, matching: find.text('Add a comment')).last,
      );
      await tester.tap(
        find.descendant(of: section, matching: find.text('Add a comment')).last,
      );
      await frames(tester);
      await tester.enterText(
        find.descendant(of: editor, matching: find.byType(EditableText)),
        'A new clarification',
      );
      await capture(tester, 'desktop-comment-editor');
      fixture.api.pluginWriteFailures['POST /post_voting/comments.json'] =
          const WriteException(WriteFailure.forbidden);
      final save = find.byKey(const ValueKey('post-voting-comment-submit-103'));
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await frames(tester);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: editor, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'A new clarification',
      );
      expect(fixture.api.pluginWrites.length, 1);
      final created = {...comment(body: 'A new clarification'), 'id': 52};
      fixture.api.pluginResponses['POST /post_voting/comments.json'] = created;
      fixture
          .api
          .pluginResponses['GET /post_voting/comments.json?post_id=103&last_comment_id=0'] = {
        'comments': [comment(), created],
      };
      await tester.ensureVisible(save);
      await tester.pump();
      expect(tester.widget<DButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await frames(tester);
      expect(
        fixture.api.pluginWrites.length,
        2,
        reason: '${fixture.services.actions.commentState(site, 103).error}',
      );
      expect(fixture.services.actions.commentState(site, 103).error, isNull);
      expect(editor, findsNothing);
      expect(
        fixture.services.actions
            .record(site, 103)!
            .initialComments!
            .map((c) => c.id),
        [51, 52],
      );
      expect(renderedText('A new clarification'), findsOneWidget);
      await capture(tester, 'desktop-comment-created');
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'category change derives new default and required mode; replies never emit create field',
    () {
      const plugin = PostVotingComposerPlugin();
      final before = PluginComposerContext(
        siteUrl: site,
        createsTopic: true,
        isEdit: false,
        isPrivateMessage: false,
        categoryId: 1,
        siteSettings: PluginData.none.withValue(
          postVotingSettingsKey,
          const PostVotingSettings(enabled: true),
        ),
      );
      final after = PluginComposerContext(
        siteUrl: site,
        createsTopic: true,
        isEdit: false,
        isPrivateMessage: false,
        categoryId: 2,
        categoryData: PluginData.none.withValue(
          postVotingCategoryKey,
          const PostVotingCategoryData(requiredOn: true),
        ),
        siteSettings: before.siteSettings,
      );
      final choice = plugin.reconcileMetadata(
        before,
        after,
        const PostVotingComposerChoice(false),
      );
      expect(plugin.createPayload(after, choice), {
        'create_as_post_voting': true,
      });
      expect(
        plugin.createPayload(
          PluginComposerContext(
            siteUrl: site,
            createsTopic: false,
            isEdit: false,
            isPrivateMessage: false,
            siteSettings: before.siteSettings,
          ),
          choice,
        ),
        isEmpty,
      );
    },
  );
}
