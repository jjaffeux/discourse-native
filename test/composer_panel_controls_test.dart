import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('editor layout and controls', () {
    testWidgets(
      'formatting toolbar applies a mark and returns focus to the live editor',
      (tester) async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text: 'One word',
          selection: TextSelection(baseOffset: 4, extentOffset: 8),
        );
        await _pumpPanel(tester, shell, composer);
        await tester.tap(find.byKey(const ValueKey('composer-format-italic')));
        await tester.pumpAndSettle();
        expect(composer.raw, 'One *word*');
        expect(composer.focus.hasFocus, isTrue);
        expect(
          composer.text.selection,
          const TextSelection(baseOffset: 5, extentOffset: 9),
        );
      },
    );

    testWidgets('Linux formatting hints match their keyboard actions', (
      tester,
    ) async {
      await _withTargetPlatform(TargetPlatform.linux, () async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpPanel(tester, shell, composer);

        const actions = [
          ('Bold', LogicalKeyboardKey.keyB, '**format** me'),
          ('Italic', LogicalKeyboardKey.keyI, '*format* me'),
          ('Inline code', LogicalKeyboardKey.keyE, '`format` me'),
          ('Link', LogicalKeyboardKey.keyL, null),
        ];
        for (final (label, key, _) in actions) {
          final button = tester.widget<DButton>(
            find.byWidgetPredicate(
              (widget) => widget is DButton && widget.tooltip == label,
            ),
          );
          expect(button.shortcut![0].trigger, key);
          expect(button.shortcut![0].control, isTrue);
          expect(button.shortcut![0].meta, isFalse);
        }
        composer.focus.requestFocus();

        for (final (_, key, raw) in actions) {
          composer.text.value = const TextEditingValue(
            text: 'format me',
            selection: TextSelection(baseOffset: 0, extentOffset: 6),
          );
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          if (raw != null) {
            expect(composer.raw, raw);
          } else {
            expect(
              find.byKey(const ValueKey('composer-link-dialog')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<DInput>(
                    find.byKey(const ValueKey('composer-link-anchor')),
                  )
                  .controller!
                  .text,
              'format',
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
      'reply context expands without covering the editor and follows post visibility',
      (tester) async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        const post = Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First paragraph.</p><p>Second paragraph.</p>',
        );
        shell.store.put(_replyTarget.siteUrl, post);
        shell.store.put(
          _replyTarget.siteUrl,
          const TopicDetail(id: 7, title: 'A topic', stream: [1]),
        );
        await _pumpPanel(tester, shell, composer);
        final context = find.byKey(const ValueKey('composer-reply-context'));
        final excerpt = find.byKey(const ValueKey('composer-context-excerpt'));
        expect(find.text('Replying to '), findsOneWidget);
        expect(find.text('@sam'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('composer-reply-avatar')),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('composer-title'))).top,
          greaterThan(tester.getRect(find.text('@sam')).bottom),
        );
        expect(excerpt, findsNothing);
        await tester.pump();
        await tester.ensureVisible(context);
        await tester.pumpAndSettle();
        await tester.tap(context);
        await tester.pump();
        expect(find.text('First paragraph. Second paragraph.'), findsOneWidget);
        expect(
          tester.getRect(excerpt).bottom,
          lessThan(tester.getRect(find.byType(ComposerEditor)).top),
        );
        expect(
          tester.getSize(find.byType(ComposerEditor)).height,
          greaterThan(30),
        );

        shell.store.put(_replyTarget.siteUrl, post.copyWith(hidden: true));
        await tester.pump();
        expect(excerpt, findsNothing);
        expect(find.text('First paragraph. Second paragraph.'), findsNothing);
        await tester.ensureVisible(context);
        await tester.pumpAndSettle();
        await tester.tap(context);
        await tester.pump();
        expect(excerpt, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('reply identity and excerpt follow the selected post', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      final client = MockClient((_) async => http.Response('', 404));
      addTearDown(client.close);
      final pipeline = installTestMediaPipeline(client: client);
      const first = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        avatarUrl: 'https://meta.discourse.org/sam.png',
        cooked: '<p>The original message.</p>',
      );
      const second = Post(
        id: 4,
        postNumber: 2,
        username: 'alex',
        avatarUrl: 'https://meta.discourse.org/alex.png',
        cooked: '<p>The selected message.</p>',
      );
      await Future.wait([
        pipeline.avatars.load(first.avatarUrl!),
        pipeline.avatars.load(second.avatarUrl!),
      ]);
      shell.store.putAll(_replyTarget.siteUrl, const [first, second]);
      shell.store.put(
        _replyTarget.siteUrl,
        const TopicDetail(
          id: 7,
          title: 'A topic',
          stream: [1, 4],
          participants: [
            TopicParticipant(
              username: 'alex',
              avatarUrl: 'https://meta.discourse.org/alex.png',
            ),
          ],
        ),
      );
      await _pumpPanel(tester, shell, composer);
      final avatar = find.byKey(const ValueKey('composer-reply-avatar'));
      final context = find.byKey(const ValueKey('composer-reply-context'));
      expect(tester.widget<AvatarImage>(avatar).url, first.avatarUrl);
      await tester.ensureVisible(context);
      await tester.pumpAndSettle();
      await tester.tap(context);
      await tester.pump();
      expect(find.text('The original message.'), findsOneWidget);

      composer.retarget(replyToPostNumber: 2, replyToUsername: 'alex');
      await tester.pump();
      expect(find.text('@alex'), findsOneWidget);
      expect(find.text('@sam'), findsNothing);
      expect(tester.widget<AvatarImage>(avatar).url, second.avatarUrl);
      expect(find.text('The original message.'), findsNothing);
      await tester.ensureVisible(context);
      await tester.pumpAndSettle();
      await tester.tap(context);
      await tester.pump();
      expect(find.text('The selected message.'), findsOneWidget);

      shell.store.remove<Post>(_replyTarget.siteUrl, second.id);
      await tester.pump();
      expect(find.text('@alex'), findsOneWidget);
      expect(tester.widget<AvatarImage>(avatar).url, second.avatarUrl);
      expect(find.text('The selected message.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long reply identities fit a narrow composer with larger text',
      (tester) async {
        final composer = ComposerController(
          _replyTarget.replyingTo(2, 'a_very_long_reply_recipient_username'),
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await _pumpPanel(
            tester,
            shell,
            composer,
            size: const Size(320, 650),
            textScaler: const TextScaler.linear(1.5),
          );

          final frame = tester.getRect(find.byType(ComposerPanel));
          final context = tester.getRect(
            find.byKey(const ValueKey('composer-reply-context')),
          );
          final avatar = tester.getRect(
            find.byKey(const ValueKey('composer-reply-avatar')),
          );
          final username = tester.getRect(
            find.byKey(const ValueKey('composer-reply-username')),
          );
          expect(avatar.left, greaterThan(frame.left));
          expect(avatar.right, lessThan(username.left));
          expect(username.right, lessThan(frame.right));
          expect(
            context.bottom,
            lessThan(tester.getRect(find.byType(ComposerEditor)).top),
          );
          expect(
            find.bySemanticsLabel(
              'Replying to @a_very_long_reply_recipient_username · #2, A topic',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('Command-E wraps the selected topic body in backticks', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pump();

      await _pressCommandE(tester);

      expect(composer.text.text, '`format` me');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 1, extentOffset: 7),
      );
    });

    testWidgets('Command-L links the selected topic body text', (tester) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pump();

      await _pressCommandL(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-link-dialog')),
        findsOneWidget,
      );
      final anchor = tester.widget<DInput>(
        find.byKey(const ValueKey('composer-link-anchor')),
      );
      expect(anchor.controller!.text, 'format');

      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();

      expect(composer.text.text, '[format](https://example.com) me');
      expect(find.byType(ComposerLinkPill), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byType(ComposerLinkPill)));
      await tester.pumpAndSettle();

      final existingAnchor = tester.widget<DInput>(
        find.byKey(const ValueKey('composer-link-anchor')),
      );
      final existingUrl = tester.widget<DInput>(
        find.byKey(const ValueKey('composer-link-url')),
      );
      expect(existingAnchor.controller!.text, 'format');
      expect(existingUrl.controller!.text, 'https://example.com');

      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://meta.discourse.org',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();

      expect(composer.text.text, '[format](https://meta.discourse.org) me');
      expect(find.byType(ComposerLinkPill), findsOneWidget);
    });

    testWidgets('a typed domain becomes an editable link in the topic body', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      composer.text.value = const TextEditingValue(
        text: 'google.fr',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();

      final link = find.byType(ComposerLinkPill);
      expect(link, findsOneWidget);
      expect(composer.text.text, 'google.fr');

      await tester.tapAt(tester.getCenter(link));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DInput>(find.byKey(const ValueKey('composer-link-url')))
            .controller!
            .text,
        'http://google.fr',
      );
    });

    testWidgets('shows working formatting controls only for selected text', (
      tester,
    ) async {
      final composer = ComposerController(_newTopicTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composer-format-italic')),
        findsOneWidget,
      );

      composer.text.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsNothing,
      );
      expect(find.byTooltip('Bold'), findsOneWidget);
      expect(find.byTooltip('Italic'), findsOneWidget);

      final click = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('composer-format-bold'))),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await click.up();
      await tester.pump();

      expect(composer.text.text, '**format** me');
    });

    testWidgets(
      'keeps the primary action in the bottom row when formatting controls appear',
      (tester) async {
        final composer = ComposerController(_newTopicTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpPanel(tester, shell, composer);

        composer.text.value = const TextEditingValue(
          text: 'format me',
          selection: TextSelection(baseOffset: 0, extentOffset: 6),
        );
        composer.focus.requestFocus();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('composer-selection-toolbar')),
          findsNothing,
        );
        final create = tester.getCenter(
          find.widgetWithText(DButton, 'Create topic'),
        );
        final panel = tester.getRect(find.byType(ComposerPanel));

        expect(create.dy, greaterThan(panel.bottom - 52));
      },
    );

    testWidgets('uses the available width in a narrow content pane', (
      tester,
    ) async {
      final composer = ComposerController(_replyTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer, size: const Size(340, 600));

      final panel = tester.getRect(find.byType(ComposerPanel));
      expect(panel.left, 0);
      expect(panel.right, 340);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'keeps writing tools and submit visible without discard in the footer',
      (tester) async {
        final composer = ComposerController(
          _newTopicTarget,
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async =>
                  throw StateError('The picker is not invoked by this test.'),
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpPanel(tester, shell, composer, size: const Size(440, 600));
        await tester.pump();

        final upload = tester.getCenter(
          find.byKey(const ValueKey('composer-upload')),
        );
        final format = tester.getCenter(
          find.byKey(const ValueKey('composer-formatting')),
        );
        final create = tester.getCenter(
          find.widgetWithText(DButton, 'Create topic'),
        );
        expect(upload.dy, closeTo(create.dy, 1));
        expect(
          format.dy,
          lessThan(tester.getRect(find.byType(ComposerEditor)).top),
        );
        expect(
          find.byKey(const ValueKey('composer-toolbar-scroll-forward')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('composer-discard')), findsNothing);
        expect(find.byKey(const ValueKey('composer-options')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    for (final (name, target, whisper, label, icon) in [
      ('reply', _replyTarget, false, 'Reply', DIcons.reply),
      ('whisper', _replyTarget, true, 'Whisper', DIcons.farEyeSlash),
      (
        'edit',
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 7,
          slug: 'a-topic',
          topicTitle: 'A topic',
          editingPostId: 8,
          editingPostNumber: 2,
        ),
        false,
        'Save',
        DIcons.check,
      ),
      (
        'new topic',
        _newTopicTarget,
        false,
        'Create topic',
        DIcons.farPenToSquare,
      ),
    ]) {
      testWidgets('narrow $name footer submits from its labeled icon', (
        tester,
      ) async {
        final composer = ComposerController(target)..setWhisper(whisper);
        final shell = await _InteractionTrackingShellController.create();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pumpPanel(
          tester,
          shell,
          composer,
          size: const Size(340, 650),
          textScaler: const TextScaler.linear(1.5),
        );

        final submit = find.byKey(const ValueKey('composer-submit'));
        expect(
          find.descendant(of: submit, matching: find.text(label)),
          findsNothing,
        );
        expect(
          tester
              .widget<DIcon>(
                find.descendant(of: submit, matching: find.byType(DIcon)),
              )
              .icon,
          icon,
        );
        expect(find.byTooltip(label), findsOneWidget);
        expect(tester.widget<DButton>(submit).onPressed, isNull);
        final semantics = tester.ensureSemantics();
        try {
          expect(tester.getSemantics(submit).label, label);
        } finally {
          semantics.dispose();
        }
        expect(
          tester.getCenter(submit).dy,
          greaterThan(tester.getRect(find.byType(ComposerEditor)).top),
        );

        composer.title.text = 'A title';
        composer.text.text = 'A message ready to submit.';
        await tester.pump();
        expect(tester.widget<DButton>(submit).onPressed, isNotNull);
        await tester.tap(submit);
        await tester.pump();
        expect(shell.submitCalls, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not show toolbar chevrons when all tools fit', (
      tester,
    ) async {
      final composer = ComposerController(
        _newTopicTarget,
        imageUploader:
            (file, {required onProgress, required abortTrigger}) async =>
                throw StateError('The picker is not invoked by this test.'),
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('composer-toolbar-scroll-forward')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composer-toolbar-scroll-backward')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('left aligns the toolbar when all tools fit', (tester) async {
      final composer = ComposerController(
        _newTopicTarget,
        imageUploader:
            (file, {required onProgress, required abortTrigger}) async =>
                throw StateError('The picker is not invoked by this test.'),
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);
      await tester.pump();

      final panel = tester.getRect(find.byType(ComposerPanel));
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('composer-toolbar-scroll')),
      );

      expect(toolbar.left, closeTo(panel.left + 8, 1));
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets(
        'edit topic context is passive and distinct at ${scale}x text',
        (tester) async {
          final composer = ComposerController(
            const ComposerTarget(
              siteUrl: 'https://meta.discourse.org',
              topicId: 7,
              slug: 'a-topic',
              topicTitle: 'Making the first contribution feel easier',
              editingPostId: 12,
              editingPostNumber: 8,
            ),
          )..loadedBody('The published contribution.');
          final shell = await _shell();
          addTearDown(composer.dispose);
          addTearDown(shell.dispose);
          await _pumpPanel(
            tester,
            shell,
            composer,
            size: const Size(360, 650),
            textScaler: TextScaler.linear(scale),
          );
          final context = find.byKey(const ValueKey('composer-edit-context'));
          expect(tester.widget<DItem>(context).onPressed, isNull);
          expect(
            find.descendant(of: context, matching: find.text('Topic')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: context, matching: find.byType(DItemTitle)),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('composer-topic-title')),
            findsNothing,
          );
          expect(find.text('Edit post #8'), findsOneWidget);
          expect(composer.canSaveDraft, isFalse);
          expect(find.text('Draft saved'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('large reply context and cached excerpt fit a narrow dock', (
      tester,
    ) async {
      final composer = ComposerController(
        _replyTarget.replyingTo(2, 'a_long_reply_recipient'),
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      shell.store.put(
        _replyTarget.siteUrl,
        const Post(
          id: 2,
          postNumber: 2,
          username: 'a_long_reply_recipient',
          cooked: '<p>The original contribution.</p>',
        ),
      );
      shell.store.put(
        _replyTarget.siteUrl,
        const TopicDetail(id: 7, title: 'A topic', stream: [2]),
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        size: const Size(360, 650),
        textScaler: const TextScaler.linear(2),
      );
      final context = find.byKey(const ValueKey('composer-reply-context'));
      await tester.ensureVisible(context);
      await tester.pumpAndSettle();
      await tester.tap(context);
      await tester.pumpAndSettle();
      expect(find.text('The original contribution.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'short bottom dock scrolls its tools and retains editor state',
      (tester) async {
        final composer = ComposerController(_replyTarget);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text: 'One word',
          selection: TextSelection(baseOffset: 4, extentOffset: 8),
        );
        await _pumpPanel(
          tester,
          shell,
          composer,
          height: 280,
          size: const Size(360, 650),
        );
        final editorState = tester.state(find.byType(ComposerEditor));
        final italic = find.byKey(const ValueKey('composer-format-italic'));
        await tester.ensureVisible(italic);
        await tester.pumpAndSettle();
        await tester.tap(italic);
        await tester.pumpAndSettle();
        expect(composer.raw, 'One *word*');
        expect(tester.state(find.byType(ComposerEditor)), same(editorState));
        expect(
          find.byKey(const ValueKey('composer-submit')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('composer-selection-toolbar')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('shows private-message fields addressed to the target group', (
      tester,
    ) async {
      final composer = ComposerController(_privateMessageTarget);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      expect(find.text('New message'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-private-message-recipients')),
        findsOneWidget,
      );
      expect(find.text('tech-leads'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Send message'), findsOneWidget);
      expect(find.text('Category'), findsNothing);
      expect(find.text('Tags'), findsNothing);
      expect(find.text('Write your message…'), findsOneWidget);
    });
  });
}

Future<void> _pressCommandE(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _pressCommandL(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<T> _withTargetPlatform<T>(
  TargetPlatform platform,
  Future<T> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    return await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  Size size = const Size(900, 650),
  TextScaler textScaler = TextScaler.noScaling,
  double height = 500,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ComposerPanel(composer: composer, height: height),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _InteractionTrackingShellController extends ShellController {
  _InteractionTrackingShellController()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );

  int closeCalls = 0;
  int submitCalls = 0;

  static Future<_InteractionTrackingShellController> create() async {
    final shell = _InteractionTrackingShellController();
    await shell.load();
    return shell;
  }

  @override
  void closeComposer({ComposerController? composer}) => closeCalls++;

  @override
  Future<void> submitComposer({ComposerController? composer}) async =>
      submitCalls++;
}

const _replyTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

const _newTopicTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 0,
  slug: '',
  topicTitle: '',
  mode: ComposerMode.newTopic,
);

const _privateMessageTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 0,
  slug: '',
  topicTitle: 'New message',
  mode: ComposerMode.privateMessage,
  targetRecipients: 'tech-leads',
);
