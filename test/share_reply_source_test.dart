import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteA = 'https://a.example';
const _siteB = 'https://b.example';
const _reader = DiscourseUser(id: 1, username: 'reader');
const _title = r'A [real] topic \ notes';
const _replyKey = ValueKey('topic-share-reply-as-new-topic');

void main() {
  for (final postNumber in <int?>[null, 3]) {
    final kind = postNumber == null ? 'topic' : 'post';

    for (final replacement in ['forum', 'topic', 'tab', 'account']) {
      for (final existingComposer in [false, true]) {
        testWidgets(
          '$kind share cannot ${existingComposer ? 'replace' : 'create'} a composer after $replacement replacement',
          (tester) async {
            final harness = await _Harness.create(tester, postNumber);
            final shell = harness.shell;
            final sourceTabId = shell.activeTabId;
            await harness.open(tester);

            switch (replacement) {
              case 'forum':
                shell.selectInstance(1);
                _openTopic(shell);
                expect(shell.currentInstance!.url, _siteB);
                // Both forums deliberately use the same topic and post IDs.
                expect(shell.currentTopic!.id, 7);
              case 'topic':
                _openTopic(shell, topicId: 8);
                expect(shell.currentTopic!.id, 8);
              case 'tab':
                shell.createTab();
                _openTopic(shell);
                expect(shell.activeTabId, isNot(sourceTabId));
                expect(shell.currentTopic!.id, 7);
              case 'account':
                await shell.disconnectCurrentInstance();
                harness.api.account = const DiscourseUser(
                  id: 2,
                  username: 'replacement',
                );
                await shell.connectCurrentInstance();
                _openTopic(shell);
                expect(shell.currentInstance!.user!.id, 2);
            }

            if (existingComposer) {
              shell.openReply();
              await shell.finishComposerDraftRestore(shell.visibleComposer!);
              shell.visibleComposer!.text.text = 'Keep this replacement draft';
            }
            final composer = shell.visibleComposer;
            await tester.pumpAndSettle();
            expect(find.byKey(_replyKey), findsOneWidget);
            expect(find.text(harness.shareUrl), findsOneWidget);

            await harness.reply(tester);

            expect(shell.visibleComposer, same(composer));
            if (composer != null) {
              expect(composer.isDisposed, isFalse);
              expect(composer.raw, 'Keep this replacement draft');
              expect(composer.target.isNewTopic, isFalse);
            }
            if (replacement == 'forum') shell.selectInstance(0);
            if (replacement == 'tab') shell.selectTab(sourceTabId!);
            if (replacement == 'forum' || replacement == 'tab') {
              expect(shell.visibleComposer, isNull);
            }
          },
        );
      }
    }

    testWidgets('$kind share expires with an otherwise identical session', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, postNumber);
      await harness.open(tester);
      // Account-session invalidation must work even when the same user,
      // topic and tab IDs are retained by a reconnect or rollback.
      harness.shell.lifecycle.invalidate(_siteA);
      await harness.reply(tester);
      expect(harness.shell.visibleComposer, isNull);
    });

    for (final disposeOriginal in [false, true]) {
      testWidgets(
        '$kind share expires after controller replacement${disposeOriginal ? ' and disposal' : ''}',
        (tester) async {
          final harness = await _Harness.create(tester, postNumber);
          final original = harness.shell;
          await harness.open(tester);
          final replacement = await _createShell(_ShareApi());
          addTearDown(replacement.dispose);
          harness.active.value = replacement;
          await tester.pumpAndSettle();
          if (disposeOriginal) original.dispose();
          expect(find.byKey(_replyKey), findsOneWidget);

          await harness.reply(tester);

          expect(replacement.visibleComposer, isNull);
          if (!disposeOriginal) expect(original.visibleComposer, isNull);
        },
      );
    }

    testWidgets('$kind share expires when its opening widget is removed', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, postNumber);
      await harness.open(tester);
      harness.showSource.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(_replyKey), findsOneWidget);

      await harness.reply(tester);

      expect(harness.shell.visibleComposer, isNull);
    });

    testWidgets('$kind share restores a draft before prepending continuation', (
      tester,
    ) async {
      final harness = await _Harness.create(
        tester,
        postNumber,
        draft: const ComposerDraft(
          action: ComposerDraft.createTopicAction,
          title: 'An unfinished topic',
          reply: 'Keep my draft body',
          categoryId: 6,
        ),
      );
      await harness.open(tester);
      await harness.reply(tester);

      final composer = harness.shell.visibleComposer!;
      expect(composer.target.isNewTopic, isTrue);
      expect(composer.target.originTopicId, 7);
      expect(composer.title.text, 'An unfinished topic');
      expect(composer.categoryId, 6);
      expect(composer.raw, '${harness.continuation}\n\nKeep my draft body');
    });
  }

  testWidgets(
    'post share is safe after its source is removed by forum navigation',
    (tester) async {
      final harness = await _Harness.create(tester, 3);
      await harness.open(tester);
      harness.showSource.value = false;
      await tester.pumpAndSettle();
      harness.shell.selectInstance(1);
      _openTopic(harness.shell);
      await tester.pumpAndSettle();
      expect(find.byKey(_replyKey), findsOneWidget);

      await harness.reply(tester);

      expect(harness.shell.visibleComposer, isNull);
    },
  );

  for (final postNumber in <int?>[null, 1, 3]) {
    testWidgets(
      '${postNumber == null ? 'topic' : 'post #$postNumber'} share keeps its canonical source when the source route updates',
      (tester) async {
        final harness = await _Harness.create(tester, postNumber);
        final shell = harness.shell;
        final tabId = shell.activeTabId;
        await harness.open(tester);
        shell.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'updated-slug',
            title: _title,
            postNumber: 4,
          ),
        );
        await tester.pumpAndSettle();

        await harness.reply(tester);

        final composer = shell.visibleComposer!;
        expect(composer.target.isNewTopic, isTrue);
        expect(composer.target.siteUrl, _siteA);
        expect(composer.target.tabId, tabId);
        expect(composer.target.originTopicId, 7);
        expect(composer.categoryId, 5);
        expect(
          composer.taxonomyValidationMessage,
          'Choose at least 1 tags for this category.',
        );
        expect(composer.raw, harness.continuation);
        expect(composer.raw, isNot(contains('?u=')));
      },
    );
  }
}

final class _Harness {
  _Harness(this.active, this.api, this.postNumber);

  final ValueNotifier<ShellController> active;
  final _ShareApi api;
  final int? postNumber;
  final showSource = ValueNotifier(true);

  ShellController get shell => active.value;
  String get canonicalUrl =>
      '$_siteA/t/a-real-topic/7${postNumber != null && postNumber! > 1 ? '/$postNumber' : ''}';
  String get shareUrl => '$canonicalUrl?u=reader';
  String get continuation =>
      r'Continue the discussion from [A \[real\] topic \\ notes]'
      '($canonicalUrl)';

  static Future<_Harness> create(
    WidgetTester tester,
    int? postNumber, {
    ComposerDraft? draft,
  }) async {
    final api = _ShareApi(draft: draft);
    final shell = await _createShell(api);
    final harness = _Harness(ValueNotifier(shell), api, postNumber);
    addTearDown(() {
      harness.active.dispose();
      harness.showSource.dispose();
      if (!shell.accountSessionDisposed) shell.dispose();
    });
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: harness.active,
        builder: (context, controller, _) => ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: harness.showSource,
                builder: (context, visible, _) {
                  final controller = ShellScope.of(context);
                  final topic = controller.currentTopic;
                  if (!visible || topic == null) return const SizedBox();
                  return Center(
                    child: postNumber == null
                        ? TopicShareButton(
                            siteUrl: controller.currentInstance!.url,
                            topic: topic,
                            route: controller.currentContent,
                          )
                        : PostActions(
                            siteUrl: controller.currentInstance!.url,
                            post: controller.store.read<Post>(
                              controller.currentInstance!.url,
                              postNumber == 1 ? 1 : 2,
                            )!,
                            persistent: true,
                            child: const PostMoreActionsButton(),
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> open(WidgetTester tester) async {
    if (postNumber == null) {
      await tester.tap(find.byKey(const ValueKey('topic-share-button')));
    } else {
      await tester.tap(find.byKey(ValueKey('post-more-actions-$postNumber')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Share'));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(_replyKey), findsOneWidget);
    expect(find.text(shareUrl), findsOneWidget);
  }

  Future<void> reply(WidgetTester tester) async {
    await tester.tap(find.byKey(_replyKey));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(_replyKey), findsNothing);
  }
}

Future<ShellController> _createShell(_ShareApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('a.example').copyWith(user: _reader),
      instance('b.example').copyWith(user: _reader),
    ]),
    api: api,
    authenticator: FakeAuthenticator()
      ..keys[_siteA] = 'a-key'
      ..keys[_siteB] = 'b-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  _openTopic(shell);
  return shell;
}

void _openTopic(ShellController shell, {int topicId = 7}) {
  final siteUrl = shell.currentInstance!.url;
  shell.store.put(
    siteUrl,
    TopicDetail(
      id: topicId,
      title: topicId == 7 ? _title : 'Another topic',
      stream: const [1, 2],
      categoryId: 5,
      canCreatePost: true,
      canReplyAsNewTopic: true,
    ),
  );
  for (final postNumber in [1, 3]) {
    shell.store.put(
      siteUrl,
      Post(
        id: postNumber == 1 ? 1 : 2,
        postNumber: postNumber,
        username: 'author',
        cooked: '<p>Post $postNumber</p>',
      ),
    );
  }
  shell.pushContent(
    ContentRoute.topic(
      topicId: topicId,
      slug: topicId == 7 ? 'a-real-topic' : 'another-topic',
      title: topicId == 7 ? _title : 'Another topic',
    ),
  );
}

class _ShareApi extends FakeDiscourseApi {
  _ShareApi({ComposerDraft? draft})
    : super(
        feeds: const {'/latest.json': []},
        categoryList: const [
          TopicCategory(
            id: 5,
            name: 'Support',
            color: '0088CC',
            permission: 1,
            minimumRequiredTags: 1,
          ),
          TopicCategory(id: 6, name: 'General', color: '888888', permission: 1),
        ],
        draftToRestore: (draft: draft, sequence: 2),
      );

  DiscourseUser account = _reader;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => account;
}
