import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_category_settings.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_comments.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_controller.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_data.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_plugin.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_reader.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/shell_test_harness.dart';
import 'post_voting_integration_test.dart' as fixture;

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
  testWidgets(
    'open voters redact private results immediately after disconnect',
    (tester) async {
      final state = await fixture.pumpFixture(tester, desktop);
      state.api.pluginResponses['GET /post_voting/voters.json?post_id=103'] = {
        'total_voters_count': 1,
        'voters': [
          {'id': 77, 'username': 'private_voter', 'direction': 'up'},
        ],
      };
      await tester.tap(find.byKey(const ValueKey('post-voting-count-103')));
      await fixture.frames(tester);
      expect(find.text('private_voter'), findsOneWidget);
      await tester.runAsync(() => state.shell.disconnectInstance(fixture.site));
      await fixture.frames(tester);
      expect(state.reader.isCurrent, isFalse);
      expect(find.text('private_voter'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('new rank membership between retained answers remains pageable', (
    tester,
  ) async {
    final state = await fixture.pumpFixture(tester, desktop);
    final controller = PostVotingController(
      reader: state.reader,
      services: state.services,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    state.api.pluginResponses['GET /t/7.json?post_number=1'] = fixture.topic(
      ids: [101, 103, 104, 102],
      posts: [fixture.post(1), fixture.post(3)],
    );
    state.api.pluginResponses['GET /t/7/posts.json?post_ids[]=104'] = {
      'post_stream': {
        'posts': [fixture.post(4)],
      },
    };
    await controller.refresh();
    expect(controller.hasMore, isTrue);
    await controller.loadMore();
    expect(controller.visibleIds, [101, 103, 104, 102]);
    expect(controller.hasMore, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Activity child replies cannot offer unsupported comments', (
    tester,
  ) async {
    final state = await fixture.pumpFixture(tester, desktop);
    state.api.pluginResponses['GET /t/7.json?filter=activity&post_number=1'] =
        fixture.topic(
          activity: true,
          posts: [
            fixture.post(1),
            {...fixture.post(2), 'reply_to_post_number': 1},
            fixture.post(3),
          ],
        );
    await tester.tap(find.text('Activity').last);
    await fixture.frames(tester);
    expect(
      find.byWidgetPredicate((w) => w is PostVotingComments && w.postId == 102),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate((w) => w is PostVotingComments && w.postId == 103),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'a question with no answers still opens the full host Answer composer',
    (tester) async {
      final state = await fixture.pumpFixture(
        tester,
        phone,
        topicJson: {
          ...fixture.topic(ids: [101], posts: [fixture.post(1)]),
          'answer_count': 0,
          'posts_count': 1,
          'highest_post_number': 1,
          'last_read_post_number': 1,
        },
      );
      expect(find.byKey(const ValueKey('post-voting-order')), findsNothing);
      await tester.tap(find.byType(PostMoreActionsButton).first);
      await fixture.frames(tester);
      await tester.tap(find.text('Answer').last);
      await fixture.frames(tester);
      expect(state.shell.visibleComposer, isNotNull);
      expect(state.shell.visibleComposer!.target.replyToPostNumber, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a list serializer without answer_count shows a marker instead of a false zero',
    (tester) async {
      final state = await fixture.pumpFixture(tester, desktop);
      final row = fixture.models.topicSummary({
        'id': 8,
        'title': 'Fresh question',
        'slug': 'fresh',
        'is_post_voting': true,
        'posts_count': 25,
      }, fixture.site);
      expect(row.plugins.get(postVotingTopicKey)!.answerCount, isNull);
      final widgets = const PostVotingPlugin().topicListMetadata(
        tester.element(find.byType(PostVotingReader)),
        fixture.site,
        row,
      );
      await tester.pumpWidget(MaterialApp(home: Column(children: widgets)));
      expect(find.text('Post voting'), findsOneWidget);
      expect(find.text('0 Answers'), findsNothing);
      expect(state.reader.isCurrent, isFalse);
    },
  );
  testWidgets(
    'category saves preserve other custom fields and reconcile uncertainty without replay',
    (tester) async {
      final state = await fixture.pumpFixture(tester, desktop);
      final wire = {
        'category': {
          'id': 1,
          'name': 'Support',
          'can_edit': true,
          'custom_fields': {
            'unrelated': 'keep',
            'create_as_post_voting_default': false,
            'only_post_voting_in_this_category': false,
          },
        },
      };
      state.api.pluginResponses['GET /c/1/show.json'] = wire;
      final controller = PostVotingCategoryController(
        reader: state.reader,
        api: state.services.api,
        requests: state.services.requests,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.canEdit, isTrue);
      state.api.pluginWriteFailures['PUT /categories/1.json'] =
          const WriteException(WriteFailure.unreachable);
      await controller.save(defaultOn: true, requiredOn: false);
      expect(controller.uncertain, isTrue);
      await controller.save(defaultOn: true, requiredOn: false);
      expect(state.api.pluginWrites.length, 1);
      expect(
        (state.api.pluginWrites.single.body['custom_fields']
            as Map)['unrelated'],
        'keep',
      );
      state.api.pluginResponses['GET /c/1/show.json'] = {
        'category': {
          'id': 1,
          'name': 'Support',
          'can_edit': true,
          'custom_fields': {
            'unrelated': 'keep',
            'create_as_post_voting_default': true,
          },
        },
      };
      await controller.load();
      expect(controller.uncertain, isFalse);
      expect(controller.defaultOn, isTrue);
      expect(state.api.pluginWrites.length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'comment upvote has a local selected intent and rolls back a refused write',
    (tester) async {
      final wire = {...fixture.comment(), 'user_id': 8, 'username': 'other'};
      final state = await fixture.pumpFixture(
        tester,
        desktop,
        topicJson: fixture.topic(
          posts: [
            fixture.post(1),
            {
              ...fixture.post(3),
              'comments': [wire],
            },
            fixture.post(2),
          ],
        ),
      );
      final gate = Completer<void>();
      (state.api as fixture.VotingTestApi).writeGate = gate.future;
      state.api.pluginWriteFailures['POST /post_voting/vote/comment.json'] =
          const WriteException(WriteFailure.forbidden);
      final toggle = find.byKey(const ValueKey('post-voting-comment-vote-51'));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await fixture.frames(tester);
      expect(tester.widget<DToggle>(toggle).pressed, isTrue);
      expect(
        find.descendant(of: toggle, matching: find.text('3')),
        findsOneWidget,
      );
      gate.complete();
      await fixture.frames(tester);
      expect(tester.widget<DToggle>(toggle).pressed, isFalse);
      expect(
        find.descendant(of: toggle, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        state.services.actions
            .record(fixture.site, 103)!
            .initialComments!
            .single
            .score,
        2,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('authoritative feature removal restores the ordinary reader', (
    tester,
  ) async {
    final state = await fixture.pumpFixture(tester, desktop);
    final ordinary = {...fixture.topic(), 'is_post_voting': false};
    state.api.topics[7] = fixture.models.topic(ordinary, fixture.site);
    await state.services.topics.reloadTopic(fixture.site, 7);
    await fixture.frames(tester);
    expect(find.byType(PostVotingReader), findsNothing);
    expect(find.byKey(const ValueKey('post-voting-up-103')), findsNothing);
    await fixture.capture(tester, 'desktop-disabled');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'closed topics keep engagement disabled while staff can edit and delete comments',
    (tester) async {
      final original = {
        ...fixture.comment(),
        'user_id': 8,
        'username': 'other',
      };
      final state = await fixture.pumpFixture(
        tester,
        desktop,
        topicJson: {
          ...fixture.topic(
            posts: [
              fixture.post(1),
              {
                ...fixture.post(3),
                'comments': [original],
              },
              fixture.post(2),
            ],
          ),
          'closed': true,
        },
      );
      final section = find.byWidgetPredicate(
        (w) => w is PostVotingComments && w.postId == 103,
      );
      expect(
        find.descendant(of: section, matching: find.text('Add a comment')),
        findsNothing,
      );
      expect(
        tester
            .widget<DToggle>(
              find.byKey(const ValueKey('post-voting-comment-vote-51')),
            )
            .enabled,
        isFalse,
      );
      await tester.ensureVisible(
        find
            .descendant(
              of: section,
              matching: find.byType(DDropdownMenuTrigger),
            )
            .last,
      );
      await tester.pump();
      await tester.tap(
        find
            .descendant(
              of: section,
              matching: find.byType(DDropdownMenuTrigger),
            )
            .last,
      );
      await fixture.frames(tester);
      expect(find.text('Flag comment'), findsOneWidget);
      await tester.tap(find.text('Edit comment'));
      await fixture.frames(tester);
      final editor = find.byKey(
        const ValueKey('post-voting-comment-editor-103'),
      );
      expect(tester.widget<DTextarea>(editor).enabled, isTrue);
      await tester.enterText(
        find.descendant(of: editor, matching: find.byType(EditableText)),
        'Staff clarification',
      );
      final edited = {
        ...original,
        'raw': 'Staff clarification',
        'cooked': '<p>Staff clarification</p>',
      };
      state.api.pluginResponses['PUT /post_voting/comments.json'] = edited;
      state
          .api
          .pluginResponses['GET /post_voting/comments.json?post_id=103&last_comment_id=0'] = {
        'comments': [edited],
      };
      final save = find.byKey(const ValueKey('post-voting-comment-submit-103'));
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await fixture.frames(tester);
      expect(state.api.pluginWrites.single.method, 'PUT');
      expect(editor, findsNothing);
      expect(renderedText('Staff clarification'), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: section,
              matching: find.byType(DDropdownMenuTrigger),
            )
            .last,
      );
      await fixture.frames(tester);
      await tester.tap(find.text('Delete comment'));
      await fixture.frames(tester);
      state.api.pluginResponses['DELETE /post_voting/comments.json'] = {
        'success': 'OK',
      };
      state
          .api
          .pluginResponses['GET /post_voting/comments.json?post_id=103&last_comment_id=0'] = {
        'comments': <Object?>[],
      };
      await tester.tap(find.widgetWithText(DButton, 'Delete').last);
      await fixture.frames(tester);
      expect(state.api.pluginWrites.last.method, 'DELETE');
      expect(
        state.services.actions.record(fixture.site, 103)!.initialComments,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'ordinary members cannot author edit delete or vote on closed comments',
    (tester) async {
      final state = await fixture.pumpFixture(
        tester,
        desktop,
        actor: const DiscourseUser(id: 9, username: 'reader'),
        topicJson: {...fixture.topic(), 'closed': true},
      );
      final section = find.byWidgetPredicate(
        (w) => w is PostVotingComments && w.postId == 103,
      );
      expect(
        find.descendant(of: section, matching: find.text('Add a comment')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.byType(DDropdownMenuTrigger),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<DToggle>(
              find.byKey(const ValueKey('post-voting-comment-vote-51')),
            )
            .enabled,
        isFalse,
      );
      expect(state.api.pluginWrites, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'retiring a pending vote releases its original current-account post lane',
    (tester) async {
      final state = await fixture.pumpFixture(tester, desktop);
      final gate = Completer<void>();
      (state.api as fixture.VotingTestApi).writeGate = gate.future;
      final pending = state.services.actions.vote(
        state.reader,
        103,
        PostVoteDirection.up,
      );
      await fixture.frames(tester);
      expect(state.services.posts.writeInFlight(fixture.site, 103), isTrue);
      state.services.actions.forget(fixture.site);
      gate.complete();
      await pending;
      expect(state.services.posts.writeInFlight(fixture.site, 103), isFalse);
      expect(state.services.posts.beginWrite(fixture.site, 103), isTrue);
      state.services.posts.endWrite(fixture.site, 103);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a retired reconciliation cannot release a replacement post writer',
    (tester) async {
      final state = await fixture.pumpFixture(tester, desktop);
      final gate = Completer<void>();
      state.api.pluginReadGates['/t/7.json?post_number=3'] = gate;
      final pending = state.services.actions.vote(
        state.reader,
        103,
        PostVoteDirection.up,
      );
      await fixture.frames(tester);
      expect(state.services.posts.writeInFlight(fixture.site, 103), isFalse);
      expect(state.services.posts.beginWrite(fixture.site, 103), isTrue);
      state.services.actions.forget(fixture.site);
      gate.complete();
      await pending;
      expect(state.services.posts.writeInFlight(fixture.site, 103), isTrue);
      state.services.posts.endWrite(fixture.site, 103);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
