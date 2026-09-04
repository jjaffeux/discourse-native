import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerTopicReplyTests();
  _registerComposerAndDraftTests();
}

void _registerTopicReplyTests() {
  group('replying', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites({DiscourseUser user = me}) => [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: user),
      instance(
        'team.discourse.org',
        title: 'Discourse Team',
      ).copyWith(user: user),
    ];

    FakeAuthenticator signedIn() => FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'meta-key'
      ..keys['https://team.discourse.org'] = 'team-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail({bool canCreatePost = true}) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [
        const Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
      postsCount: 1,
      canCreatePost: canCreatePost,
    );

    Future<void> openTopic(
      WidgetTester tester,
      FakeDiscourseApi api, {
      DiscourseUser user = me,
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(user: user),
        authenticator: signedIn(),
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
    }

    Finder sendButton() => find.descendant(
      of: find.byType(ComposerPanel),
      matching: find.widgetWithText(FilledButton, 'Reply'),
    );

    testWidgets('the reply affordances wait for permission to use them', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(canCreatePost: false)},
      );

      await openTopic(tester, api);

      // can_create_post is the whole question — the guardian behind it has
      // already accounted for closed, archived and who may post past them.
      expect(find.byTooltip('Reply to this topic'), findsNothing);
      await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('Shift R opens a topic reply only where replying is allowed', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: signedIn(),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));
      expect(shell.visibleComposer?.target.replyToPostNumber, isNull);
    });

    testWidgets(
      'Shift R does not retarget a reply while its editor has focus',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail()},
        );

        await openTopic(tester, api);
        await hoverPost(tester);
        await tester.tap(find.byTooltip('Reply to this post'));
        await tester.pumpAndSettle();

        final shell = ShellScope.read(
          tester.element(find.byType(ComposerPanel)),
        );
        expect(shell.visibleComposer?.target.replyToPostNumber, 1);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
          isTrue,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(shell.visibleComposer?.target.replyToPostNumber, 1);
      },
    );

    testWidgets('to a topic posts what was typed', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-reply-options')),
        findsNothing,
      );
      expect(renderedText('First post body'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Sounds good to me.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created, hasLength(1));
      expect(api.created.single['raw'], 'Sounds good to me.');
      expect(api.created.single['topicId'], 7);
      expect(api.created.single['siteUrl'], 'https://meta.discourse.org');
      expect(api.created.single['draftKey'], 'topic_7');
      expect(api.created.single['replyToPostNumber'], isNull);

      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('Sounds good to me.'), findsOneWidget);
    });

    testWidgets(
      'a reply retargeted at a whisper while sending posts as written',
      (tester) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail()},
          createPostGate: gate,
        );

        await openTopic(tester, api);
        await tester.tap(find.byTooltip('Reply to this topic'));
        await tester.pumpAndSettle();
        final shell = ShellScope.read(
          tester.element(find.byType(ComposerPanel)),
        );

        await tester.enterText(find.byType(TextField), 'Said in public.');
        await tester.pumpAndSettle();
        await tester.tap(sendButton());
        await tester.pump();
        expect(shell.visibleComposer?.submitting, isTrue);

        // A reply to a whisper is itself a whisper; while the public one is
        // out, retargeting must neither change what it posts nor where.
        shell.openReply(replyToPostNumber: 1, replyingToWhisper: true);
        await tester.pump();
        expect(shell.visibleComposer?.whisper, isFalse);
        expect(shell.visibleComposer?.target.replyToPostNumber, isNull);

        gate.complete();
        await tester.pumpAndSettle();

        expect(api.created.single['whisper'], isFalse);
        expect(api.created.single['replyToPostNumber'], isNull);
        expect(find.byType(ComposerPanel), findsNothing);
      },
    );

    testWidgets('a whisperer can toggle and submit a whispered reply', (
      tester,
    ) async {
      const whisperer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        whisperer: true,
      );
      final api = FakeDiscourseApi(
        user: whisperer,
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api, user: whisperer);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'For the team only.');
      await tester.pump();
      final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));

      final replyOptions = find.byKey(const ValueKey('composer-reply-options'));
      final composerTitle = find.byKey(const ValueKey('composer-title'));
      expect(replyOptions, findsOneWidget);
      expect(
        find.descendant(of: replyOptions, matching: find.text('Topic')),
        findsNothing,
      );
      expect(
        find.descendant(of: replyOptions, matching: find.dIcon(DIcons.reply)),
        findsOneWidget,
      );
      expect(
        tester.getTopRight(replyOptions).dx,
        lessThan(tester.getTopLeft(composerTitle).dx),
      );
      expect(tester.widget<Text>(composerTitle).data, 'Reply to A real topic');

      await tester.tap(replyOptions);
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('composer-toggle-whisper'));
      final whisperSwitch = find.byKey(
        const ValueKey('composer-whisper-switch'),
      );
      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(whisperSwitch).value, isFalse);

      await tester.tap(whisperSwitch);
      await tester.pump();

      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(whisperSwitch).value, isTrue);
      expect(shell.visibleComposer?.whisper, isTrue);

      await shell.submitComposer();
      await tester.pumpAndSettle();

      expect(api.created.single['whisper'], isTrue);
    });

    testWidgets('to a post addresses it by post number', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await hoverPost(tester);
      await tester.tap(find.byTooltip('Reply to this post'));
      await tester.pumpAndSettle();

      expect(find.text('Reply to @sam'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Agreed.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['replyToPostNumber'], 1);
    });

    testWidgets('a reply to a whisper stays whispered without a toggle', (
      tester,
    ) async {
      const whisperer = DiscourseUser(username: 'joffreyj', whisperer: true);
      final api = FakeDiscourseApi(
        user: whisperer,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
              Post(
                id: 2,
                postNumber: 2,
                username: 'moderator',
                cooked: '<p>Whisper body</p>',
                postType: Post.whisperPostType,
              ),
            ],
            stream: const [1, 2],
            postsCount: 2,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api, user: whisperer);
      await hoverPost(tester, body: 'Whisper body');
      await tester.tap(find.byTooltip('Reply to this post'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-reply-options')),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), 'Following up privately.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['replyToPostNumber'], 2);
      expect(api.created.single['whisper'], isTrue);
    });

    testWidgets('always reports how long the reply took to type', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quick one.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Absent means zero to Discourse, which silences the account on a first
      // post rather than merely queueing it.
      expect(api.created.single['typingDurationMsecs'], isNotNull);
      expect(api.created.single['composerOpenDurationMsecs'], isNotNull);
    });

    testWidgets('cmd-enter sends without reaching for the button', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Shipped.');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(api.created.single['raw'], 'Shipped.');
    });

    testWidgets('a refused reply keeps the text and says why', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['Body is too short (minimum is 20 characters)'],
          statusCode: 422,
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Body is too short (minimum is 20 characters)'),
        findsOneWidget,
      );
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('no'), findsOneWidget);
    });

    testWidgets('a queued reply is not shown as posted', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          message: 'Your post is in the queue.',
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Held for review.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text('Your post is in the queue.'), findsOneWidget);
      expect(renderedText('Held for review.'), findsNothing);

      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
    });

    testWidgets('undo does not hand a queued reply back', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          message: 'Your post is in the queue.',
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Held for review.');
      await tester.pumpAndSettle();
      // What gets recorded for undo is throttled. Without waiting that out
      // there is nothing on the stack, and this passes on a composer that
      // would hand the reply straight back.
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Undo reaching back over the clear is the double post the clear is
      // there to prevent: the text returns, and the send button it returns
      // under works.
      expect(find.text('Held for review.'), findsNothing);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
    });

    testWidgets('switching sites mid-reply does not post to the new one', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meant for meta.');
      await tester.pumpAndSettle();

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.text('DM'));
      await tester.pumpAndSettle();
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Meant for meta.'), findsOneWidget);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['siteUrl'], 'https://meta.discourse.org');
    });

    testWidgets('a rate limit holds sending back until the wait is up', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(
          WriteFailure.rateLimited,
          errors: ['You are posting too quickly.'],
          statusCode: 429,
          retryAfter: Duration(seconds: 2),
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Too eager.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text('You are posting too quickly.'), findsOneWidget);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('an unreachable site is checked rather than retried', (
      tester,
    ) async {
      // The post was created; only the answer was lost. Sending again would
      // publish it twice, since a user API key gets no idempotency.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        postsById: {
          2: const Post(
            id: 2,
            postNumber: 2,
            username: 'joffreyj',
            cooked: '<p>It landed.</p>',
            raw: 'It landed.',
          ),
        },
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'It landed.');
      await tester.pumpAndSettle();

      api.topics[7] = topicPayload(
        id: 7,
        title: 'A real topic',
        posts: [detail().posts.first],
        stream: const [1, 2],
        postsCount: 2,
        canCreatePost: true,
      );

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created, hasLength(1));
      expect(api.postFetches.last, contains(2));
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('It landed.'), findsOneWidget);
    });

    testWidgets('a check that finds nothing lets the reply be sent again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Never arrived.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text("Couldn't reach the site."), findsOneWidget);
      expect(find.text('Never arrived.'), findsOneWidget);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('a check that cannot be made holds sending back', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unknown fate.');
      await tester.pumpAndSettle();

      api.topics.remove(7);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('may have posted'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Check again');
      expect(button, findsOneWidget);
      expect(find.text('Unknown fate.'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(api.created, hasLength(1));
    });

    testWidgets('a post keeps its actions out of the way until hovered', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      expect(find.byTooltip('Reply to this post'), findsNothing);

      final gesture = await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // Crossing onto the overlaid toolbar must not make the post lose its
      // hover target before the toolbar can receive the same pointer update.
      final toolbar = find.byType(HoverActionToolbar);
      await gesture.moveTo(tester.getCenter(toolbar));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // The macOS embedder can report the overlaid toolbar's enter before the
      // post underneath exits. Neither callback ordering may close the menu.
      final toolbarRegion = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: toolbar,
              matching: find.byWidgetPredicate(
                (widget) => widget is MouseRegion && widget.onHover != null,
              ),
            )
            .first,
      );
      final postRegion = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: renderedText('First post body'),
              matching: find.byWidgetPredicate(
                (widget) => widget is MouseRegion && widget.onHover != null,
              ),
            )
            .first,
      );
      toolbarRegion.onEnter!(const PointerEnterEvent());
      postRegion.onExit!(const PointerExitEvent());
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('copy link writes core post URLs to the clipboard', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
              Post(
                id: 2,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>Second post body</p>',
              ),
            ],
            stream: const [1, 2],
            postsCount: 2,
            canCreatePost: true,
          ),
        },
      );
      final copied = watchClipboard(tester);

      await openTopic(tester, api);
      final gesture = await hoverPost(tester);

      await tester.tap(find.byTooltip('Copy a link to this post to clipboard'));
      await tester.pumpAndSettle();

      expect(copied, [
        'https://meta.discourse.org/t/a-real-topic/7?u=joffreyj',
      ]);
      expect(find.text('Link copied!'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('Second post body')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy a link to this post to clipboard'));
      await tester.pumpAndSettle();

      expect(copied, [
        'https://meta.discourse.org/t/a-real-topic/7?u=joffreyj',
        'https://meta.discourse.org/t/a-real-topic/7/2?u=joffreyj',
      ]);
    });

    testWidgets('copy link is available to anonymous readers', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(canCreatePost: false)},
      );
      final copied = watchClipboard(tester);

      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [instance('meta.discourse.org', title: 'Discourse Meta')],
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await hoverPost(tester);

      expect(find.byTooltip('Reply to this post'), findsNothing);
      await tester.tap(find.byTooltip('Copy a link to this post to clipboard'));
      await tester.pumpAndSettle();

      expect(copied, ['https://meta.discourse.org/t/a-real-topic/7']);
    });

    testWidgets('scrolling hides the post menu until the pointer moves again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Top of the long post</p>${'<p>filler</p>' * 120}',
              ),
            ],
            stream: const [1],
            postsCount: 1,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      final gesture = await hoverPost(tester, body: 'Top of the long post');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      final scroll = await tester.startGesture(
        tester.getCenter(find.byType(TopicView)),
      );
      await scroll.moveBy(const Offset(0, -400));
      await tester.pump();

      // The toolbar leaves before the drag ends, rather than following the post
      // and recomputing its overlay position on every scroll tick.
      expect(find.byTooltip('Reply to this post'), findsNothing);
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsNothing);

      await scroll.up();
      await tester.pumpAndSettle();

      // Ending the scroll is not enough: rows have moved under a stationary
      // pointer, so showing an action surface now would pick one accidentally.
      expect(find.byTooltip('Reply to this post'), findsNothing);

      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
    });

    testWidgets('a recycled post stays closed under a stationary pointer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              for (var i = 1; i <= 30; i++)
                Post(
                  id: i,
                  postNumber: i,
                  username: 'sam',
                  cooked: '<p>Post body $i</p>',
                ),
            ],
            stream: [for (var i = 1; i <= 30; i++) i],
            postsCount: 30,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      final list = find.byType(SuperListView);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(list));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(1200);
      await tester.pump();
      await tester.pump();

      // A synchronous jump can build a fresh row after scrolling has
      // already ended. Its synthetic enter must not be mistaken for real
      // pointer movement and create an overlay during mouse hit testing.
      expect(find.byTooltip('Reply to this post'), findsNothing);
      expect(tester.takeException(), isNull);

      await pointer.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
    });

    testWidgets('the menu goes when its post scrolls out of sight', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              for (var i = 1; i <= 20; i++)
                Post(
                  id: i,
                  postNumber: i,
                  username: 'sam',
                  cooked: '<p>Post body $i</p>',
                ),
            ],
            stream: [for (var i = 1; i <= 20; i++) i],
            postsCount: 20,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      final gesture = await hoverPost(tester, body: 'Post body 5');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await tester.drag(find.byType(TopicView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('on a touch screen the actions arrive as a sheet', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.longPress(find.text('sam'));
      await tester.pumpAndSettle();

      // There is no pointer to hover with, so the same action is reached by
      // holding a non-selectable part of the post. Holding its body selects
      // text and opens the quote toolbar instead.
      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Reply'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Reply to @sam'), findsOneWidget);
    });

    testWidgets('closing the composer sends nothing', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.created, isEmpty);
    });
  });
}

void _registerComposerAndDraftTests() {
  group('composer toolbar', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail() => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
      postsCount: 1,
      canCreatePost: true,
    );

    Future<void> openComposer(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('never turns spell check on', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);

      // `EditableText` routes around `controller.buildTextSpan` entirely once
      // spell check results arrive (editable_text.dart:5984), so a
      // spell-checked composer is one with no markdown highlighting — and it
      // would fail by flickering rather than by breaking. This is the tripwire.
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .spellCheckConfiguration,
        isNull,
      );
    });

    testWidgets('marks up the markdown around the selection', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'say hello');
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.bold));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say **hello**');

      await tester.tap(find.dIcon(DIcons.italic));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say ***hello***');
    });
  });

  group('composer autocomplete', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail() => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
      postsCount: 1,
      canCreatePost: true,
    );

    FakeDiscourseApi api() => FakeDiscourseApi(
      feeds: {'/latest.json': listed},
      topics: {7: detail()},
      userSearches: {
        'sa': const [
          FoundUser(username: 'sam', name: 'Sam Saffron'),
          FoundUser(username: 'sally'),
        ],
      },
      hashtagSearches: {
        'ran': const [
          FoundHashtag(
            type: 'category',
            ref: 'random',
            slug: 'random',
            text: 'Random',
            id: 5,
            colors: ['0088CC'],
          ),
          FoundHashtag(
            type: 'tag',
            ref: 'random::tag',
            slug: 'random',
            text: 'random',
            id: 12,
            styleType: 'icon',
            icon: 'tag',
            secondaryText: 'x0',
          ),
        ],
      },
      emojisBySite: {
        'https://meta.discourse.org': const [
          SiteEmoji(name: 'smile', url: 'https://meta.discourse.org/s.png'),
          SiteEmoji(name: 'smirk', url: 'https://meta.discourse.org/k.png'),
        ],
      },
    );

    Future<void> openComposer(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField));

    testWidgets('offers people once enough has been typed', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(find.text('sally'), findsOneWidget);
      // The topic is part of the question: Discourse ranks people already in
      // it first, which is what puts the person being replied to at the top.
      expect(fake.userSearchesRequested.single.topicId, 7);
    });

    testWidgets('writes the whole mention when one is picked', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sam ');
      expect(find.text('Sam Saffron'), findsNothing);
    });

    testWidgets('arrowing down picks the second name', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sally ');
    });

    testWidgets('escape closes the list, not the reply', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(find.text('Sam Saffron'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The list is gone and the half-written reply is still there. Getting
      // this wrong throws away what somebody was writing, which is why the
      // popup handles keys through a plain Focus rather than a second
      // CallbackShortcuts — that one reports a key handled whenever an
      // activator matches, open or not.
      expect(find.text('Sam Saffron'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(field(tester).controller!.text, 'hey @sa');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('cmd+enter still sends with the list open', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(find.text('Sam Saffron'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(fake.created.single['raw'], 'hey @sa');
    });

    testWidgets('offers emoji without asking the site again', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'a :sm');
      await tester.pumpAndSettle();

      expect(find.text('smile'), findsOneWidget);
      expect(find.text('smirk'), findsOneWidget);
      expect(fake.emojisRequested, ['https://meta.discourse.org']);
    });

    testWidgets('offers categories and tags once # is typed', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();

      expect(fake.hashtagSearchesRequested, ['ran']);
      expect(find.text('Random'), findsOneWidget);
      expect(find.text('random'), findsOneWidget);
      expect(find.text('x0'), findsOneWidget);
    });

    testWidgets('writes the ref, not the slug, when one is picked', (
      tester,
    ) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();

      // The tag, whose slug collides with the category's — which is the whole
      // reason the site sends a `ref` at all.
      await tester.tap(find.text('random'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'see #random::tag ');
    });

    testWidgets('a picked hashtag pills without asking again', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Random'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'see #random ');
      expect(find.byType(HashtagPill), findsOneWidget);
      expect(fake.hashtagLookupsRequested, isEmpty);
    });

    testWidgets('a picked mention pills without asking again', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sam Saffron'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sam ');
      expect(find.byType(MentionPill), findsOneWidget);
      expect(fake.mentionChecksRequested, isEmpty);
    });

    testWidgets('a mention uses the hand cursor over its pill', (tester) async {
      final fake = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        realUsernames: const {'sam'},
      );
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sam there');
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.text('@sam')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await mouse.moveTo(tester.getCenter(find.byType(TextField)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
      );
    });

    testWidgets('a hand-typed name is checked once, then pills', (
      tester,
    ) async {
      final fake = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        realUsernames: const {'sam'},
      );
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'ask @sam now');
      await tester.pumpAndSettle();

      expect(fake.mentionChecksRequested, [
        {'sam'},
      ]);
      expect(find.byType(MentionPill), findsOneWidget);
    });

    testWidgets('a hand-typed name nobody has stays text', (tester) async {
      final fake = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'ask @nobody now');
      await tester.pumpAndSettle();

      expect(fake.mentionChecksRequested, [
        {'nobody'},
      ]);
      expect(find.byType(MentionPill), findsNothing);
    });

    testWidgets('says nothing about a hash inside a word', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'issue a#ran');
      await tester.pumpAndSettle();

      expect(fake.hashtagSearchesRequested, isEmpty);
    });

    testWidgets('writes the shortcode when an emoji is picked', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'a :sm');
      await tester.pumpAndSettle();

      await tester.tap(find.text('smirk'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'a :smirk: ');
    });

    testWidgets('draws the artwork for a shortcode that was written', (
      tester,
    ) async {
      // Controller tests inject the resolver and cannot catch shell wiring gaps.
      await openComposer(tester, api());

      // Override the shell fixture's network-free emoji fallback for this case.
      replaceEmojiCache(
        MockClient((_) async => http.Response.bytes(emojiPng, 200)),
      );

      await tester.enterText(find.byType(TextField), 'hey :smile:');
      await tester.pumpAndSettle();

      expect(find.byType(EmojiImage), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hey :smile:',
      );
    });

    testWidgets('says nothing about an email address', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'write to sam@example');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pumpAndSettle();

      expect(fake.userSearchesRequested, isEmpty);
    });
  });

  group('drafts', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites() => [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'meta-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail({ComposerDraft? draft, int draftSequence = 0}) =>
        topicPayload(
          id: 7,
          title: 'A real topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>First post body</p>',
            ),
          ],
          stream: const [1],
          postsCount: 1,
          canCreatePost: true,
          draft: draft,
          draftSequence: draftSequence,
        );

    Future<void> openComposer(
      WidgetTester tester,
      FakeDiscourseApi api, {
      FakeDraftStore? drafts,
      FakeAuthenticator? authenticator,
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: authenticator ?? signedIn(),
        drafts: drafts,
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    Future<void> settleDraft(WidgetTester tester) async {
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
    }

    testWidgets('discard closes an empty reply without confirmation', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsNothing,
      );
      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 0,
        ),
      ]);
    });

    testWidgets('save and close removes an empty reply draft', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsNothing,
      );
      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 0,
        ),
      ]);
    });

    testWidgets(
      'save and close is immediate while draft restoration finishes',
      (tester) async {
        final drafts = _GatedDraftReadStore();
        addTearDown(() {
          if (!drafts.release.isCompleted) drafts.release.complete();
        });
        await drafts.write(
          'https://meta.discourse.org',
          'topic_7',
          const ComposerDraft(
            reply: 'Restored after close was pressed',
          ).encode(),
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail()},
        );

        await openComposer(tester, api, drafts: drafts);
        expect(drafts.started.isCompleted, isTrue);
        await tester.tap(find.byTooltip('Save and close'));
        await tester.pump();

        expect(find.byType(ComposerPanel), findsNothing);
        expect(api.userDraftsDeleted, isEmpty);

        drafts.release.complete();
        await tester.pumpAndSettle();

        expect(api.userDraftsDeleted, isEmpty);
        expect(drafts.saved.values.single, contains('Restored after close'));
      },
    );

    testWidgets('a failed local read is retried before close can delete', (
      tester,
    ) async {
      final drafts = _FlakyDraftStore(readFailures: 1);
      await drafts.write(
        'https://meta.discourse.org',
        'topic_7',
        const ComposerDraft(reply: 'Temporarily unreadable').encode(),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.visibleComposer?.text.text, isEmpty);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(api.userDraftsDeleted, isEmpty);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(drafts.saved.values.single, contains('Temporarily unreadable'));
    });

    testWidgets('close does not delete an unseen draft after restore fails', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        creatableFeedPaths: const {'/latest.json'},
        draftRestoreFailure: const WriteException(WriteFailure.unreachable),
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Recovered server draft',
            title: 'Recovered title',
          ),
          sequence: 3,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await shell.openNewTopic();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text("Couldn't check for an existing draft. Try again."),
        findsOneWidget,
      );
      expect(api.userDraftsDeleted, isEmpty);

      api.draftRestoreFailure = null;
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
    });

    testWidgets('closing a PM preserves a draft for different recipients', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canSendPrivateMessages: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        user: writer,
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Message for moderators',
            title: 'Moderation question',
            action: ComposerDraft.privateMessageAction,
            archetypeId: ComposerDraft.privateMessageArchetype,
            recipients: 'moderators',
          ),
          sequence: 5,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      shell.openPrivateMessage(
        siteUrl: 'https://meta.discourse.org',
        targetRecipients: 'tech-leads',
      );
      await tester.pumpAndSettle();

      expect(shell.visibleComposer?.text.text, isEmpty);
      expect(shell.visibleComposer?.hasUnappliedDraft, isTrue);
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(api.draftsSaved, isEmpty);
    });

    testWidgets('discarding a fresh PM cannot delete another PM draft', (
      tester,
    ) async {
      final restoreGate = Completer<void>();
      addTearDown(() {
        if (!restoreGate.isCompleted) restoreGate.complete();
      });
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canSendPrivateMessages: true,
      );
      final api = FakeDiscourseApi(
        user: writer,
        feeds: {'/latest.json': listed},
        draftRestoreGate: restoreGate,
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Message for moderators',
            title: 'Moderation question',
            action: ComposerDraft.privateMessageAction,
            archetypeId: ComposerDraft.privateMessageArchetype,
            recipients: 'moderators',
          ),
          sequence: 5,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      shell.openPrivateMessage(
        siteUrl: 'https://meta.discourse.org',
        targetRecipients: 'tech-leads',
      );
      await tester.pump();
      shell.visibleComposer!.text.text = 'A new message not saved yet';
      restoreGate.complete();
      await tester.pumpAndSettle();
      expect(shell.visibleComposer!.protectsUnappliedDraft, isTrue);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(api.draftsSaved, isEmpty);
    });

    testWidgets(
      'discard restores another PM after its replacement save was in flight',
      (tester) async {
        final saveGate = Completer<void>();
        addTearDown(() {
          if (!saveGate.isCompleted) saveGate.complete();
        });
        const writer = DiscourseUser(
          username: 'joffreyj',
          name: 'Joffrey',
          canSendPrivateMessages: true,
        );
        const preserved = ComposerDraft(
          reply: 'Message for moderators',
          title: 'Moderation question',
          action: ComposerDraft.privateMessageAction,
          archetypeId: ComposerDraft.privateMessageArchetype,
          recipients: 'moderators',
        );
        final drafts = FakeDraftStore();
        final api = FakeDiscourseApi(
          user: writer,
          feeds: {'/latest.json': listed},
          draftGate: saveGate,
          draftToRestore: const (draft: preserved, sequence: 5),
        );
        await pumpShell(
          tester,
          desktop,
          api: api,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: writer),
          ],
          authenticator: signedIn(),
          drafts: drafts,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        shell.openPrivateMessage(
          siteUrl: 'https://meta.discourse.org',
          targetRecipients: 'tech-leads',
        );
        await tester.pumpAndSettle();
        final composer = shell.visibleComposer!;
        expect(composer.protectsUnappliedDraft, isTrue);
        composer
          ..title.text = 'Replacement title'
          ..text.text = 'Replacement already saving';
        await tester.pump(ComposerController.draftDebounce);
        await tester.pump();
        expect(api.draftsSaved, hasLength(1));

        await tester.tap(find.byKey(const ValueKey('composer-discard')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('composer-confirm-discard')),
        );
        await tester.pump();
        expect(composer.discarding, isTrue);

        saveGate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ComposerPanel), findsNothing);
        expect(api.userDraftsDeleted, isEmpty);
        expect(api.draftsSaved, hasLength(2));
        expect(
          api.draftsSaved.first['data'],
          contains('Replacement already saving'),
        );
        expect(api.draftsSaved.last['sequence'], 6);
        expect(api.draftsSaved.last['data'], preserved.encode());
        expect(drafts.saved, isEmpty);
      },
    );

    testWidgets(
      'discard keeps a local PM after its replacement save was in flight',
      (tester) async {
        final saveGate = Completer<void>();
        addTearDown(() {
          if (!saveGate.isCompleted) saveGate.complete();
        });
        const writer = DiscourseUser(
          username: 'joffreyj',
          name: 'Joffrey',
          canSendPrivateMessages: true,
        );
        const preserved = ComposerDraft(
          reply: 'Local message for moderators',
          title: 'Local moderation question',
          action: ComposerDraft.privateMessageAction,
          archetypeId: ComposerDraft.privateMessageArchetype,
          recipients: 'moderators',
        );
        final drafts = FakeDraftStore();
        await drafts.write(
          'https://meta.discourse.org',
          ComposerDraft.newPrivateMessageDraftKey,
          preserved.encode(),
        );
        final api = FakeDiscourseApi(
          user: writer,
          feeds: {'/latest.json': listed},
          draftGate: saveGate,
        );
        await pumpShell(
          tester,
          desktop,
          api: api,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: writer),
          ],
          authenticator: signedIn(),
          drafts: drafts,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        shell.openPrivateMessage(
          siteUrl: 'https://meta.discourse.org',
          targetRecipients: 'tech-leads',
        );
        await tester.pumpAndSettle();
        final composer = shell.visibleComposer!;
        expect(composer.protectsUnappliedDraft, isTrue);
        composer
          ..title.text = 'Replacement title'
          ..text.text = 'Replacement already saving';
        await tester.pump(ComposerController.draftDebounce);
        await tester.pump();
        expect(api.draftsSaved, hasLength(1));

        await tester.tap(find.byKey(const ValueKey('composer-discard')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('composer-confirm-discard')),
        );
        await tester.pump();
        saveGate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ComposerPanel), findsNothing);
        expect(api.draftsSaved, hasLength(1));
        expect(api.userDraftsDeleted, const [
          (
            siteUrl: 'https://meta.discourse.org',
            draftKey: ComposerDraft.newPrivateMessageDraftKey,
            sequence: 1,
          ),
        ]);
        expect(drafts.saved.values.single, preserved.encode());
      },
    );

    testWidgets('a late restore cannot regress the draft sequence', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final restoreGate = Completer<void>();
      addTearDown(() {
        if (!restoreGate.isCompleted) restoreGate.complete();
      });
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        creatableFeedPaths: const {'/latest.json'},
        draftRestoreGate: restoreGate,
        draftToRestore: const (
          draft: ComposerDraft(reply: 'Older server snapshot'),
          sequence: 1,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await shell.openNewTopic();
      await tester.pump();
      final composer = shell.visibleComposer!;
      composer.title.text = 'A topic title';
      composer.text.text = 'First local revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(1));
      composer.text.text = 'Second local revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(2));

      restoreGate.complete();
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
      expect(composer.draftSequence, 2);
      expect(composer.text.text, 'Second local revision');

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(api.userDraftsDeleted.single.sequence, 2);
    });

    testWidgets('a late restore preserves taxonomy and advances its sequence', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final restoreGate = Completer<void>();
      addTearDown(() {
        if (!restoreGate.isCompleted) restoreGate.complete();
      });
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        creatableFeedPaths: const {'/latest.json'},
        draftRestoreGate: restoreGate,
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Older server text',
            title: 'Older title',
            categoryId: 3,
          ),
          sequence: 7,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await shell.openNewTopic();
      await tester.pump();
      final composer = shell.visibleComposer!;
      composer.setCategory(99);

      restoreGate.complete();
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();

      expect(composer.categoryId, 99);
      expect(composer.title.text, isEmpty);
      expect(composer.text.text, isEmpty);
      expect(composer.draftSequence, 8);
      expect(api.draftsSaved.single['sequence'], 7);
      expect(api.draftsSaved.single['data'], contains('"categoryId":99'));
    });

    testWidgets('discard confirmation can keep or remove a changed reply', (
      tester,
    ) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Come back to this');
      await settleDraft(tester);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();

      expect(find.text('Do you want to discard your post?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Come back to this'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsNothing,
      );
      expect(find.text('Come back to this'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 5,
        ),
      ]);
      expect(drafts.saved, isEmpty);
      expect(drafts.events.last, 'clear');
    });

    testWidgets('composer discard removes the cached draft and badge', (
      tester,
    ) async {
      const draft = ComposerDraft(reply: 'Draft from the list');
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 1,
      );
      final api = FakeDiscourseApi(
        user: writer,
        userDraftList: const [
          UserDraft(
            key: 'topic_7',
            sequence: 4,
            data: draft,
            topicId: 7,
            title: 'A real topic',
            slug: 'a-real-topic',
          ),
        ],
        feeds: {'/latest.json': listed},
        topics: {7: detail(draft: draft, draftSequence: 4)},
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await shell.draftList.load(shell.currentInstance!, refresh: true);

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(
        shell.draftList.feedFor(shell.currentInstance!.url).drafts,
        isEmpty,
      );
      expect(shell.draftCountFor(shell.currentInstance!.url), 0);
    });

    testWidgets('empty close does not decrement unrelated draft counts', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 3,
      );
      final api = FakeDiscourseApi(
        user: writer,
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 5)},
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byTooltip('Reply to this topic'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Save and close'));
        await tester.pumpAndSettle();
      }

      expect(shell.draftCountFor(shell.currentInstance!.url), 3);
    });

    testWidgets('discard locks editing and preserves a concurrent change', (
      tester,
    ) async {
      final deleteGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftDeleteGate: deleteGate,
      );

      await openComposer(tester, api);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final composer = shell.visibleComposer!;
      await tester.enterText(find.byType(TextField), 'First revision');
      await settleDraft(tester);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('composer-confirm-discard'));
      await tester.tap(confirm);
      await tester.tap(confirm);
      await tester.pump();

      expect(api.userDraftsDeleted, hasLength(1));
      expect(composer.discarding, isTrue);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byType(ComposerPanel),
                matching: find.byType(EditableText),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsOneWidget,
      );

      // An upload or plugin can still finish programmatically while the field
      // is locked. The revision check must keep and re-save that newer text.
      composer.text.text = 'Changed during discard';
      deleteGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text(
          'This draft changed before it could be discarded. '
          'Review it and try again.',
        ),
        findsOneWidget,
      );
      expect(composer.discarding, isFalse);
      expect(api.draftsSaved.last['data'], contains('Changed during discard'));
    });

    testWidgets('discard waits for an older save of the same draft key', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Save still in flight');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(1));
      await tester.enterText(find.byType(TextField), 'Queued latest revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(1));

      shell.closeComposer();
      shell.openReply();
      await tester.pumpAndSettle();
      expect(shell.visibleComposer?.text.text, 'Queued latest revision');

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pump();
      expect(api.userDraftsDeleted, isEmpty);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['data'], contains('Queued latest revision'));
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 6,
        ),
      ]);
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('a new composer stays locally durable behind an old save', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Old first revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Old queued revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      shell.closeComposer();
      shell.openReply();
      await tester.pump();
      final newComposer = shell.visibleComposer!;
      newComposer.text.text = 'New first revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(
        drafts.saved.values.single,
        contains('New first revision'),
        reason: 'the new text must be durable before the old request returns',
      );

      newComposer.text.text = 'New queued revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(
        drafts.saved.values.single,
        contains('New queued revision'),
        reason: 'a queued revision must not live only in memory',
      );

      shell.closeComposer();
      saveGate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(3));
      expect(api.draftsSaved[1]['data'], contains('Old queued revision'));
      expect(api.draftsSaved.last['data'], contains('New queued revision'));
      expect(shell.currentTopic?.draft?.reply, 'New queued revision');
      expect(drafts.saved, isEmpty);
    });

    testWidgets('restore sees an old remote save when its local write failed', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = _FailingDraftStore(failures: 1);
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Remote-only revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(drafts.saved, isEmpty);
      expect(api.draftsSaved, hasLength(1));

      shell.closeComposer();
      shell.openReply();
      await tester.pump();
      expect(find.text('Remote-only revision'), findsNothing);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Remote-only revision'), findsOneWidget);
      expect(api.userDraftsDeleted, isEmpty);
    });

    testWidgets('retired saves cannot cross a reconnected account boundary', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = FakeDraftStore();
      final auth = signedIn();
      final api = FakeDiscourseApi(
        user: me,
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts, authenticator: auth);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Account A first');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Account A queued');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      shell.closeComposer();

      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await tester.pumpAndSettle();
      expect(auth.keys['https://meta.discourse.org'], 'api-key');

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      final accountBComposer = shell.visibleComposer!;
      accountBComposer.text.text = 'Account B draft';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.first['apiKey'], 'meta-key');
      expect(api.draftsSaved.last['apiKey'], 'api-key');
      expect(api.draftsSaved.last['data'], contains('Account B draft'));
      expect(drafts.saved.values.single, contains('Account B draft'));

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(2));
      expect(
        api.draftsSaved.where(
          (save) => (save['data'] as String).contains('Account A queued'),
        ),
        isEmpty,
      );
    });

    testWidgets('a failed discard keeps the draft and the queue usable', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftDeleteFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Keep this revision');
      await settleDraft(tester);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text("Couldn't discard this draft. Try again."),
        findsOneWidget,
      );
      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['sequence'], 5);
      expect(api.draftsSaved.last['data'], contains('Keep this revision'));

      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Queue still works');
      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(3));
      expect(api.draftsSaved.last['sequence'], 6);
      expect(api.draftsSaved.last['data'], contains('Queue still works'));
    });

    testWidgets('a failed local clear keeps and re-saves the composer', (
      tester,
    ) async {
      final drafts = _FlakyDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Must not resurrect');
      await settleDraft(tester);
      drafts.clearFailures = 1;

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text("Couldn't discard this draft. Try again."),
        findsOneWidget,
      );
      expect(api.userDraftsDeleted, hasLength(1));
      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['data'], contains('Must not resurrect'));
      expect(drafts.saved, isEmpty);
    });

    testWidgets('typing is saved to the site after a pause', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Half a thought');
      await tester.pumpAndSettle();

      expect(api.draftsSaved, isEmpty);

      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(1));
      expect(api.draftsSaved.single['draftKey'], 'topic_7');
      expect(api.draftsSaved.single['sequence'], 4);
      expect(api.draftsSaved.single['data'], contains('Half a thought'));
    });

    testWidgets('a new draft after a queued reply uses its returned sequence', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          draftSequence: 9,
        ),
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Held for review');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ComposerPanel),
          matching: find.widgetWithText(FilledButton, 'Reply'),
        ),
      );
      await tester.pumpAndSettle();
      api.draftsSaved.clear();

      await tester.enterText(find.byType(TextField), 'A different reply');
      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(1));
      expect(api.draftsSaved.single['sequence'], 9);
      expect(api.draftsSaved.single['data'], contains('A different reply'));
    });

    testWidgets('a slow save cannot clear a newer draft', (tester) async {
      final gate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: gate,
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'First revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Latest revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      expect(api.draftsSaved, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['data'], contains('Latest revision'));
      expect(drafts.events.where((event) => event == 'clear'), hasLength(1));
      expect(drafts.events.last, 'clear');
    });

    testWidgets('a draft is put back when the composer is reopened', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Come back to this');
      await settleDraft(tester);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      expect(find.text('Come back to this'), findsOneWidget);
    });

    testWidgets('a draft the site already had is restored on open', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            draft: const ComposerDraft(
              reply: 'Started in a browser',
              replyToPostNumber: 1,
              replyToUsername: 'sam',
            ),
          ),
        },
      );

      await openComposer(tester, api);

      expect(find.text('Started in a browser'), findsOneWidget);
      expect(find.text('Reply to @sam'), findsOneWidget);
    });

    testWidgets('a draft the site would not take is kept on the device', (
      tester,
    ) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Written offline');
      await settleDraft(tester);

      expect(drafts.saved, hasLength(1));
      expect(drafts.saved.values.single, contains('Written offline'));
      expect(
        find.text('Not saved on the site — kept on this device only.'),
        findsOneWidget,
      );
    });

    testWidgets('the sync stops asking a site that will not answer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api);

      for (
        var attempt = 1;
        attempt <= ComposerController.maxDraftFailures;
        attempt++
      ) {
        await tester.enterText(find.byType(TextField), 'Attempt $attempt');
        await settleDraft(tester);
      }
      expect(api.draftsSaved, hasLength(ComposerController.maxDraftFailures));

      await tester.enterText(find.byType(TextField), 'And one more');
      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(ComposerController.maxDraftFailures));
    });

    testWidgets('posting clears the draft it was written as', (tester) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Going out now');
      await settleDraft(tester);
      expect(drafts.saved, isNotEmpty);

      await tester.tap(
        find.descendant(
          of: find.byType(ComposerPanel),
          matching: find.widgetWithText(FilledButton, 'Reply'),
        ),
      );
      await tester.pumpAndSettle();

      // Discourse deletes its own copy when it accepts a post; ours has to go
      // too, or reopening the composer offers to write the reply again.
      expect(drafts.saved, isEmpty);
    });
  });
}

final class _GatedDraftReadStore extends FakeDraftStore {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.read(siteUrl, draftKey);
  }
}

final class _FailingDraftStore extends FakeDraftStore {
  _FailingDraftStore({required this.failures});

  int failures;

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (failures > 0) {
      failures--;
      throw const DraftWriteException();
    }
    return super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}

final class _FlakyDraftStore extends FakeDraftStore {
  _FlakyDraftStore({this.readFailures = 0});

  int readFailures;
  int clearFailures = 0;

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    if (readFailures > 0) {
      readFailures--;
      throw StateError('Draft read failed');
    }
    return super.read(siteUrl, draftKey);
  }

  @override
  Future<void> clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    if (clearFailures > 0) {
      clearFailures--;
      throw StateError('Draft clear failed');
    }
    return super.clear(siteUrl, draftKey, ifCurrent: ifCurrent);
  }
}
