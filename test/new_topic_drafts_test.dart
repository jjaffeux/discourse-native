import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _savedDraft = ComposerDraft(
  action: ComposerDraft.createTopicAction,
  title: 'An unfinished topic',
  reply: 'Keep this saved topic body',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;
  late FakeDiscourseApi api;
  late FakeDraftStore drafts;

  setUp(() async {
    const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
    api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
    );
    drafts = FakeDraftStore();
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: drafts,
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      initialRootMode: ShellRootMode.forum,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1789070000000),
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadFeed('latest');
  });

  ComposerController openChangedPostEdit() {
    final list = shell.currentContent!;
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    shell.openEdit(
      const Post(
        id: 70,
        postNumber: 2,
        username: 'reader',
        cooked: '<p>Original post body</p>',
        raw: 'Original post body',
        canEdit: true,
      ),
    );
    final composer = shell.visibleComposer!;
    expect(composer.canSaveDraft, isFalse);
    composer.text.text = 'Keep this unsaved edit';
    shell.pushContent(list);
    return composer;
  }

  test(
    'starts fresh without looking up or clearing an existing draft',
    () async {
      await drafts.write(_siteUrl, 'new_topic', _savedDraft.encode());
      api.draftRestoreFailure = const WriteException(WriteFailure.unreachable);

      await shell.openNewTopic();
      final composer = shell.visibleComposer!;

      expect(composer.target.draftKey, startsWith('new_topic_'));
      expect(composer.title.text, isEmpty);
      expect(composer.raw, isEmpty);
      expect(await shell.prepareComposerForClose(composer), isTrue);
      expect(api.draftsRequested, isEmpty);
      expect(await drafts.read(_siteUrl, 'new_topic'), _savedDraft.encode());
      expect(api.userDraftsDeleted, isEmpty);
    },
  );

  test(
    'all new-topic entry points allocate separate keys in the same millisecond',
    () async {
      final keys = <String>[];
      for (final open in [
        shell.openNewTopic,
        shell.openNewTopicFromList,
        shell.openNewTopicFromSidebar,
      ]) {
        await open();
        keys.add(shell.visibleComposer!.target.draftKey);
        shell.closeComposer();
      }

      expect(keys.toSet(), hasLength(3));
      expect(keys, everyElement(startsWith('new_topic_')));
    },
  );

  test(
    'a saved topic stays separate from the next topic and can be resumed',
    () async {
      await shell.openNewTopic();
      final first = shell.visibleComposer!;
      first.title.text = _savedDraft.title!;
      first.text.text = _savedDraft.reply;
      expect(await shell.prepareComposerForClose(first), isTrue);
      shell.closeComposer();

      await shell.openNewTopic();
      final second = shell.visibleComposer!;
      expect(second.target.draftKey, isNot(first.target.draftKey));
      expect(second.raw, isEmpty);
      expect(second.title.text, isEmpty);
      second.title.text = 'A different topic';
      second.text.text = 'This text belongs to the second topic';
      expect(await shell.prepareComposerForClose(second), isTrue);
      shell.closeComposer();

      expect(api.draftsSaved.map((draft) => draft['draftKey']).toSet(), {
        first.target.draftKey,
        second.target.draftKey,
      });
      await shell.resumeDraft(
        _siteUrl,
        UserDraft(key: first.target.draftKey, sequence: 1, data: _savedDraft),
      );
      final resumed = shell.visibleComposer!;
      expect(await shell.finishComposerDraftRestore(resumed), isTrue);
      expect(resumed.target.draftKey, first.target.draftKey);
      expect(resumed.raw, _savedDraft.reply);
      expect(resumed.title.text, _savedDraft.title);
    },
  );

  test('opening another topic retains the unfinished draft without '
      'confirmation', () async {
    await shell.openNewTopic();
    final first = shell.visibleComposer!;
    first.title.text = 'Keep this title-only draft';
    var confirmations = 0;
    shell.confirmComposerReplacement = (_) async {
      confirmations++;
    };

    await shell.openNewTopic();
    final second = shell.visibleComposer!;

    expect(confirmations, 0);
    expect(second.target.draftKey, isNot(first.target.draftKey));
    expect(second.title.text, isEmpty);
    expect(second.raw, isEmpty);
    expect(first.isDisposed, isFalse);
    expect(shell.liveComposers, unorderedEquals([first, second]));
    shell.selectComposer(first);
    expect(shell.visibleComposer, same(first));
    expect(first.title.text, 'Keep this title-only draft');
    expect(api.userDraftsDeleted, isEmpty);
  });

  test('canceling replacement retains the same unsaved post edit', () async {
    final first = openChangedPostEdit();
    var confirmations = 0;
    shell.confirmComposerReplacement = (composer) async {
      confirmations++;
      expect(composer, same(first));
    };

    await shell.openNewTopic();

    expect(confirmations, 1);
    expect(shell.visibleComposer, same(first));
    expect(first.raw, 'Keep this unsaved edit');
    expect(shell.liveComposers, [first]);
    expect(api.userDraftsDeleted, isEmpty);
  });

  test('discarding a retained topic deletes only that draft', () async {
    await shell.openNewTopic();
    final first = shell.visibleComposer!;
    first.title.text = _savedDraft.title!;
    first.text.text = _savedDraft.reply;
    expect(await shell.prepareComposerForClose(first), isTrue);

    await shell.openNewTopic();
    final second = shell.visibleComposer!;
    second.title.text = 'A different topic';
    second.text.text = 'Keep the selected draft';
    expect(await shell.prepareComposerForClose(second), isTrue);

    expect(await shell.discardComposer(first), isNull);

    expect(first.isDisposed, isTrue);
    expect(shell.visibleComposer, same(second));
    expect(second.raw, 'Keep the selected draft');
    expect(shell.liveComposers, [second]);
    expect(api.userDraftsDeleted.single.draftKey, first.target.draftKey);
    expect(await drafts.read(_siteUrl, first.target.draftKey), isNull);
    expect(
      ComposerDraft.decode(
        api.draftsSaved
            .where((draft) => draft['draftKey'] == second.target.draftKey)
            .last['data'],
      )!.reply,
      second.raw,
    );
  });

  test(
    'confirmed discard replaces an unsaved post edit with a fresh topic',
    () async {
      final first = openChangedPostEdit();
      var confirmations = 0;
      shell.confirmComposerReplacement = (composer) async {
        confirmations++;
        expect(composer, same(first));
        expect(await shell.discardComposer(composer), isNull);
      };

      await shell.openNewTopic();

      expect(confirmations, 1);
      expect(first.isDisposed, isTrue);
      expect(shell.visibleComposer!.target.mode, ComposerMode.newTopic);
      expect(shell.visibleComposer!.title.text, isEmpty);
      expect(shell.visibleComposer!.raw, isEmpty);
      expect(shell.liveComposers, [shell.visibleComposer]);
      expect(api.userDraftsDeleted, isEmpty);
    },
  );

  test(
    'navigation during confirmation cancels the pending new topic',
    () async {
      final first = openChangedPostEdit();
      final started = Completer<void>();
      final decision = Completer<void>();
      shell.confirmComposerReplacement = (composer) async {
        expect(composer, same(first));
        started.complete();
        await decision.future;
        expect(await shell.discardComposer(composer), isNull);
      };

      final opening = shell.openNewTopic();
      await started.future;
      shell.pushContent(
        ContentRoute.topic(topicId: 8, slug: 'another', title: 'Another topic'),
      );
      decision.complete();
      await opening;

      expect(shell.visibleComposer, isNull);
      expect(shell.liveComposers, isEmpty);
      expect(first.isDisposed, isTrue);
      expect(shell.currentContent!.topicId, 8);
    },
  );
}
