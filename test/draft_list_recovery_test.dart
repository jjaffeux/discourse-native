import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topic = Topic(id: 7, title: 'A topic with a draft', slug: 'a-topic');
const _draft = UserDraft(
  key: 'topic_7',
  sequence: 4,
  topicId: 7,
  title: 'A topic with a draft',
  data: ComposerDraft(reply: 'Deleted reply'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final localFallback in [false, true]) {
    testWidgets(
      'list deletion retires ${localFallback ? 'local fallback' : 'cached topic'} recovery before Reply',
      (tester) async {
        final drafts = FakeDraftStore();
        if (localFallback) {
          await drafts.write(_siteUrl, _draft.key, _draft.data!.encode());
        }
        const unrelated = ComposerDraft(reply: 'Keep another draft');
        await drafts.write(_siteUrl, 'topic_8', unrelated.encode());
        await drafts.write(
          'https://team.discourse.org',
          _draft.key,
          unrelated.encode(),
        );
        final api = _api();
        final shell = await _visitTopic(tester, api: api, drafts: drafts);
        expect(shell.currentTopic?.draft?.reply, 'Deleted reply');

        await _removeThroughList(tester, shell);
        expect(find.text('No drafts yet'), findsOneWidget);
        expect(api.userDraftsDeleted, const [
          (siteUrl: _siteUrl, draftKey: 'topic_7', sequence: 4),
        ]);
        expect(shell.draftCountFor(_siteUrl), 0);

        shell.openTopic(_topic);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Reply to this topic'));
        await tester.pumpAndSettle();

        expect(find.byType(ComposerPanel), findsOneWidget);
        expect(shell.visibleComposer?.text.text, isEmpty);
        expect(shell.currentTopic?.draft, isNull);
        expect(await drafts.read(_siteUrl, _draft.key), isNull);
        expect(await drafts.read(_siteUrl, 'topic_8'), unrelated.encode());
        expect(
          await drafts.read('https://team.discourse.org', _draft.key),
          unrelated.encode(),
        );
        expect(api.draftsSaved, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets('Reply waits for list deletion before reading recovery', (
    tester,
  ) async {
    final gate = Completer<void>();
    final drafts = FakeDraftStore();
    await drafts.write(_siteUrl, _draft.key, _draft.data!.encode());
    final api = _api(deleteGate: gate);
    final shell = await _visitTopic(tester, api: api, drafts: drafts);
    final deletion = shell.draftList.delete(shell.currentInstance!, _draft);
    await tester.pump();
    expect(api.userDraftsDeleted, hasLength(1));

    shell.openReply();
    await tester.pump();
    expect(shell.visibleComposer?.text.text, isEmpty);
    gate.complete();
    expect(await deletion, isTrue);
    await tester.pumpAndSettle();
    expect(shell.visibleComposer?.text.text, isEmpty);
    expect(shell.currentTopic?.draft, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'a newer local save survives list deletion and follows its DELETE',
    (tester) async {
      final gate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = _api(
        deleteGate: gate,
        saveFailure: const WriteException(WriteFailure.unreachable),
      );
      final shell = await _visitTopic(tester, api: api, drafts: drafts);
      shell.openReply();
      await tester.pumpAndSettle();
      final composer = shell.visibleComposer!;
      expect(composer.text.text, 'Deleted reply');
      final deletion = shell.draftList.delete(shell.currentInstance!, _draft);
      await tester.pump();

      composer.text.text = 'Newer edit';
      final save = composer.flushDraft();
      await tester.pump();
      expect(await drafts.read(_siteUrl, _draft.key), contains('Newer edit'));
      expect(api.draftsSaved, isEmpty);

      gate.complete();
      expect(await deletion, isTrue);
      await save;
      expect(api.draftsSaved.single['data'], contains('Newer edit'));
      expect(api.draftsSaved.single['sequence'], 4);
      expect(await drafts.read(_siteUrl, _draft.key), contains('Newer edit'));
      expect(composer.text.text, 'Newer edit');
      shell.closeComposer();
      shell.openReply();
      await tester.pumpAndSettle();
      expect(shell.visibleComposer?.text.text, 'Newer edit');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('a save already in flight keeps its newer server draft', (
    tester,
  ) async {
    final gate = Completer<void>();
    final drafts = FakeDraftStore();
    final api = _api(saveGate: gate);
    final shell = await _visitTopic(tester, api: api, drafts: drafts);
    shell.openReply();
    await tester.pumpAndSettle();
    final composer = shell.visibleComposer!;
    composer.text.text = 'Already saving';
    final save = composer.flushDraft();
    await tester.pump();
    expect(api.draftsSaved, hasLength(1));

    final deletion = shell.draftList.delete(shell.currentInstance!, _draft);
    await tester.pump();
    expect(api.userDraftsDeleted, isEmpty);
    gate.complete();
    await save;
    expect(await deletion, isFalse);
    expect(api.userDraftsDeleted, isEmpty);
    expect(shell.currentTopic?.draft?.reply, 'Already saving');
    expect(shell.currentTopic?.draftSequence, 5);
    expect(shell.draftCountFor(_siteUrl), 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a failed list DELETE leaves both recovery copies available', (
    tester,
  ) async {
    final drafts = FakeDraftStore();
    await drafts.write(_siteUrl, _draft.key, _draft.data!.encode());
    final api = _api(
      deleteFailure: const WriteException(WriteFailure.unreachable),
    );
    final shell = await _visitTopic(tester, api: api, drafts: drafts);

    await _removeThroughList(tester, shell);
    expect(find.text("Couldn't remove that draft. Try again."), findsOneWidget);
    expect(shell.draftCountFor(_siteUrl), 1);
    expect(shell.draftList.feedFor(_siteUrl).drafts.single.key, _draft.key);
    expect(await drafts.read(_siteUrl, _draft.key), _draft.data!.encode());
    shell.openTopic(_topic);
    await tester.pumpAndSettle();
    shell.openReply();
    await tester.pumpAndSettle();
    expect(shell.visibleComposer?.text.text, 'Deleted reply');
    expect(shell.currentTopic?.draft?.reply, 'Deleted reply');
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a completed DELETE cannot clear a replacement account draft', (
    tester,
  ) async {
    final gate = Completer<void>();
    final drafts = FakeDraftStore();
    final api = _api(deleteGate: gate);
    final shell = await _visitTopic(tester, api: api, drafts: drafts);
    final deletion = shell.draftList.delete(shell.currentInstance!, _draft);
    await tester.pump();
    expect(api.userDraftsDeleted, hasLength(1));

    shell.lifecycle.invalidate(_siteUrl);
    shell.draftList.forget(_siteUrl);
    const replacement = ComposerDraft(reply: 'Replacement account');
    await drafts.write(_siteUrl, _draft.key, replacement.encode());
    shell.store.update<TopicDetail>(
      _siteUrl,
      7,
      (detail) => detail.withDraft(replacement, 2),
    );
    gate.complete();
    expect(await deletion, isFalse);
    expect(await drafts.read(_siteUrl, _draft.key), replacement.encode());
    expect(shell.currentTopic?.draft?.reply, 'Replacement account');
    expect(shell.currentTopic?.draftSequence, 2);
    expect(shell.draftCountFor(_siteUrl), 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  group('resuming a listed reply draft', () {
    const listed = UserDraft(
      key: 'topic_7',
      sequence: 3,
      topicId: 7,
      slug: 'a-topic',
      title: 'A topic with a draft',
      data: ComposerDraft(reply: 'Older text the site has'),
    );

    testWidgets('keeps a newer local-only copy over the row', (tester) async {
      final drafts = FakeDraftStore();
      // Written while the site could not be reached, so it never received it.
      await drafts.write(
        _siteUrl,
        listed.key,
        const ComposerDraft(reply: 'Newer text kept on this device').encode(),
      );
      final api = _api(serverDraft: listed);
      final shell = await _openShell(tester, api: api, drafts: drafts);

      await shell.resumeDraft(_siteUrl, listed);
      await tester.pumpAndSettle();
      final composer = shell.visibleComposer!;
      expect(composer.text.text, 'Newer text kept on this device');

      composer.text.text = '${composer.text.text} and more';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
      expect(
        api.draftsSaved.single['data'],
        contains('Newer text kept on this device and more'),
      );
      expect(api.draftsSaved.single['sequence'], 3);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('fills the composer from the row without another copy', (
      tester,
    ) async {
      final api = _api(serverDraft: null);
      final shell = await _openShell(
        tester,
        api: api,
        drafts: FakeDraftStore(),
      );

      await shell.resumeDraft(_siteUrl, listed);
      await tester.pumpAndSettle();
      final composer = shell.visibleComposer!;
      expect(composer.text.text, 'Older text the site has');
      expect(composer.draftSequence, 3);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets("a stale row keeps an open composer's newer sequence", (
      tester,
    ) async {
      final api = _api();
      final shell = await _visitTopic(
        tester,
        api: api,
        drafts: FakeDraftStore(),
      );
      shell.openReply();
      await tester.pumpAndSettle();
      final composer = shell.visibleComposer!;
      composer.text.text = 'Current reply';
      await composer.flushDraft();
      expect(composer.draftSequence, 5);

      await shell.resumeDraft(_siteUrl, listed);
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, same(composer));
      expect(composer.text.text, 'Current reply');
      expect(composer.draftSequence, 5);

      composer.text.text = 'Current reply, edited';
      await composer.flushDraft();
      expect(api.draftsSaved.map((save) => save['sequence']), [4, 5]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}

FakeDiscourseApi _api({
  Completer<void>? deleteGate,
  Completer<void>? saveGate,
  WriteException? deleteFailure,
  WriteException? saveFailure,
  UserDraft? serverDraft = _draft,
}) => FakeDiscourseApi(
  feeds: const {
    '/latest.json': [_topic],
  },
  topics: {
    7: topicPayload(
      id: 7,
      title: _topic.title,
      posts: const [
        Post(id: 1, postNumber: 1, username: 'reader', cooked: '<p>A post</p>'),
      ],
      canCreatePost: true,
      draft: serverDraft?.data,
      draftSequence: serverDraft?.sequence ?? 0,
    ),
  },
  userDraftList: [?serverDraft],
  draftDeleteGate: deleteGate,
  draftDeleteFailure: deleteFailure,
  draftGate: saveGate,
  draftFailure: saveFailure,
  user: const DiscourseUser(id: 1, username: 'reader', draftCount: 1),
);

Future<ShellController> _openShell(
  WidgetTester tester, {
  required FakeDiscourseApi api,
  required FakeDraftStore drafts,
}) async {
  await pumpShell(
    tester,
    desktop,
    api: api,
    drafts: drafts,
    instances: [instance('meta.discourse.org').copyWith(user: api.user)],
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
  );
  return ShellScope.read(tester.element(primaryMainContent));
}

Future<ShellController> _visitTopic(
  WidgetTester tester, {
  required FakeDiscourseApi api,
  required FakeDraftStore drafts,
}) async {
  final shell = await _openShell(tester, api: api, drafts: drafts);
  await tester.tap(contentText(_topic.title));
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _removeThroughList(
  WidgetTester tester,
  ShellController shell,
) async {
  shell.openDrafts(_siteUrl);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Remove draft'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove'));
  await tester.pumpAndSettle();
}
