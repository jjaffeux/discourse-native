import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _target = ComposerTarget(
  siteUrl: _site,
  topicId: 7,
  slug: 'topic',
  topicTitle: 'Topic',
);

void main() {
  for (final newTopic in [false, true]) {
    for (final indent in ['    ', '\t']) {
      testWidgets(
        'Native ${newTopic ? 'new topic' : 'reply'} submission preserves '
        'a leading ${indent.length == 1 ? 'tab' : 'four-space'} code block',
        (tester) async {
          final api = FakeDiscourseApi(
            user: const DiscourseUser(id: 7, username: 'author'),
            feeds: const {'/latest.json': []},
            creatableFeedPaths: const {'/latest.json'},
          );
          final shell = ShellController(
            instanceStore: FakeInstanceStore([
              instance(
                'meta.discourse.org',
              ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
            ]),
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            updateStore: FakeUpdateStore(),
          );
          addTearDown(shell.dispose);
          await shell.load();
          if (newTopic) {
            await shell.loadFeed('latest');
            await shell.openNewTopic();
          } else {
            shell.store.put(
              _site,
              const TopicDetail(
                id: 7,
                title: 'Topic',
                stream: [],
                canCreatePost: true,
              ),
            );
            shell.pushContent(
              ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
            );
            shell.openReply();
          }
          final composer = shell.visibleComposer!;
          await shell.finishComposerDraftRestore(composer);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: ShellScope(
                controller: shell,
                child: Scaffold(
                  body: ListenableBuilder(
                    listenable: shell,
                    builder: (context, _) {
                      final current = shell.visibleComposer;
                      return current == null
                          ? const SizedBox.shrink()
                          : ComposerPanel(composer: current, height: 500);
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (newTopic) {
            await tester.enterText(
              find.byKey(const ValueKey('composer-topic-title')),
              'An indented code sample',
            );
          }
          final raw = '${indent}puts "hi"\n\nA new post body';
          await tester.enterText(
            find.byWidgetPredicate(
              (widget) =>
                  widget is EditableText && widget.controller == composer.text,
            ),
            '$raw\n\n',
          );
          await tester.pumpAndSettle();
          expect(composer.canSubmit, isTrue);
          await tester.tap(find.byKey(const ValueKey('composer-submit')));
          await tester.pumpAndSettle();

          final sent = newTopic ? api.topicsCreated.single : api.created.single;
          // PostCreator normalizes whitespace and rstrips, preserving this start.
          expect(sent['raw'], raw);
          expect(shell.visibleComposer, isNull);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }

  test(
    'submission raw matches the server’s right stripping without unindenting',
    () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      composer.text.text = '\n    code\n\nText  \n';
      expect(composer.raw, '\n    code\n\nText');
      expect(composer.recordSubmission().raw, '\n    code\n\nText');
      for (final blank in ['', '  ', '\n\t \r\n']) {
        composer.text.text = blank;
        expect(composer.raw, isEmpty);
        expect(composer.canSubmit, isFalse);
      }
    },
  );
}
