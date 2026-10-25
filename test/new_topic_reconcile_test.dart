import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _createdBy = '/topics/created-by/reader.json';

final _unicodeSpace = RegExp(
  '[\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]',
);

/// The site's side of a new topic whose answer is lost: drafts keyed by
/// sequence as DraftsController#create keeps them, and a create that advances
/// the sequence and drops the draft as PostCreator does.
final class _TopicSiteApi extends FakeDiscourseApi {
  _TopicSiteApi({required super.user})
    : super(
        feeds: {'/latest.json': [], _createdBy: []},
        creatableFeedPaths: const {'/latest.json'},
        postsById: {},
        topics: {},
      );

  final drafts = <String, String>{};
  final sequences = <String, int>{};
  final topicCreates = <String>[];
  final draftReads = <String>[];
  final topicListReads = <String>[];
  bool createLands = true;
  bool missingTopicId = false;
  WriteException createFailure = const WriteException(WriteFailure.unreachable);
  bool createdByReachable = true;
  bool draftSavesReachable = true;

  /// Topic#title after TextCleaner.clean_title with title_prettify.
  String Function(String title) storedTitle = (title) => title;

  @override
  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  }) async {
    if (!draftSavesReachable) {
      throw const WriteException(WriteFailure.unreachable);
    }
    final current = sequences[draftKey] ?? 0;
    // Draft.set advances the sequence on every save of an existing draft
    // (after a force_save retry when the client's sequence is stale); with no
    // draft at all DraftsController sets it at the current sequence.
    final saved = drafts.containsKey(draftKey) ? current + 1 : current;
    sequences[draftKey] = saved;
    drafts[draftKey] = data;
    return saved;
  }

  @override
  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  }) async {
    draftReads.add(draftKey);
    return (
      draft: ComposerDraft.decode(drafts[draftKey]),
      sequence: sequences[draftKey] ?? 0,
    );
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    topicListReads.add(path);
    if (path == _createdBy && !createdByReachable) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<PostCreation> createTopic({
    required String siteUrl,
    required String apiKey,
    required String title,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? categoryId,
    Iterable<TopicTag> tags = const [],
    String? targetRecipients,
    String draftKey = ComposerDraft.newTopicDraftKey,
    String? clientId,
  }) async {
    topicCreates.add(raw);
    if (createLands) {
      sequences[draftKey] = (sequences[draftKey] ?? 0) + 1;
      drafts.remove(draftKey);
      final id = 900 + topicCreates.length;
      final stored = storedTitle(title);
      feeds[_createdBy] = [
        Topic(id: id, title: stored, slug: 'created-$id'),
        ...?feeds[_createdBy],
      ];
      topics[id] = topicPayload(id: id, title: stored, stream: [5000 + id]);
      postsById[5000 + id] = Post(
        id: 5000 + id,
        postNumber: 1,
        username: 'reader',
        cooked: '<p>$raw</p>',
        raw: raw.replaceAll(_unicodeSpace, ' ').trimRight(),
      );
    }
    if (missingTopicId) return const PostCreation(outcome: PostOutcome.created);
    throw createFailure;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TopicSiteApi api;
  late ShellController shell;

  setUp(() async {
    const user = DiscourseUser(id: 7, username: 'reader', canCreateTopic: true);
    api = _TopicSiteApi(user: user);
    shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      initialRootMode: ShellRootMode.forum,
    );
    addTearDown(shell.dispose);
    await shell.load();
    await shell.loadFeed('latest');
  });

  Future<ComposerController> compose(String title, String body) async {
    await shell.openNewTopic();
    await pumpEventQueue();
    final composer = shell.visibleComposer!;
    composer.title.text = title;
    composer.text.text = body;
    await composer.flushDraft();
    await composer.finishDraftSaves();
    expect(api.drafts, isNotEmpty);
    return composer;
  }

  test('a plugin completion receives the reconciled topic only once', () async {
    final outcomes = <PluginTopicCreationOutcome>[];
    api.createdByReachable = false;
    await shell.openNewTopicFromPlugin(
      OpenNewTopicComposerRequest(
        siteUrl: _siteUrl,
        sourceRouteId: shell.currentContent!.id,
        initialTitle: 'A confirmed correlated topic',
        seed: const ComposerSeed(raw: 'The original correlated topic body.'),
        onCompleted: outcomes.add,
      ),
    );
    final composer = shell.visibleComposer!;
    await composer.flushDraft();
    await composer.finishDraftSaves();
    await shell.submitComposer(composer: composer);
    expect(composer.canRecheck, isTrue);
    expect(outcomes, isEmpty);

    api.createdByReachable = true;
    await shell.recheckComposer(composer: composer);

    expect(api.topicCreates, hasLength(1));
    expect(outcomes, hasLength(1));
    expect((outcomes.single as PluginTopicCreated).topicId, 901);
    expect(composer.isDisposed, isTrue);
    shell.closeComposer(composer: composer);
    expect(outcomes, hasLength(1));
  });

  test('a draft recreated after the topic landed does not read as '
      'not posted', () async {
    final composer = await compose('Printer is on fire', 'Please send help.');
    api.createdByReachable = false;
    await shell.submitComposer();
    expect(composer.state, ComposerState.unresolved);

    // Typed and taken back while unresolved: the save lands after the create
    // and the site sets the draft again, at the sequence the create advanced.
    composer.text.text = 'Please send help. Now';
    composer.text.text = 'Please send help.';
    await composer.flushDraft();
    await composer.finishDraftSaves();
    expect(api.drafts, isNotEmpty);

    api.createdByReachable = true;
    await shell.recheckComposer();

    expect(composer.isDisposed, isTrue);
    expect(api.topicCreates, hasLength(1));
  });

  test(
    'Check again uses the original topic and Send tab after editing and navigation',
    () async {
      final composer = await compose(
        'Original sent title',
        'Original sent body',
      );
      final openingTab = shell.activeTabId!;
      shell.createTab();
      final sendingTab = shell.activeTabId!;
      api.createdByReachable = false;
      await shell.submitComposer(composer: composer);
      expect(composer.canRecheck, isTrue);
      composer.title.text = 'Changed title after uncertainty';
      composer.text.text = 'Changed body after uncertainty';
      await composer.flushDraft();
      shell.createTab();
      final selectedTab = shell.activeTabId!;
      shell.pushContent(
        ContentRoute.topic(topicId: 8, slug: 'other', title: 'Other'),
      );
      shell.store.put(
        _siteUrl,
        const TopicDetail(
          id: 8,
          title: 'Other',
          stream: [],
          canCreatePost: true,
        ),
      );
      shell.openReply();
      final selected = shell.visibleComposer!;
      await shell.finishComposerDraftRestore(selected);
      selected.text.text = 'Keep this selected reply';
      api.createdByReachable = true;

      await shell.recheckComposer(composer: composer);

      expect(api.topicCreates, ['Original sent body']);
      expect(composer.isDisposed, isTrue);
      expect(shell.activeTabId, selectedTab);
      expect(shell.currentContent?.topicId, 8);
      expect(shell.visibleComposer, same(selected));
      expect(selected.raw, 'Keep this selected reply');
      shell.selectTab(sendingTab);
      expect(shell.currentContent?.topicId, 901);
      shell.selectTab(openingTab);
      expect(shell.currentContent?.topicId, isNot(901));
    },
  );

  test(
    'Check again cannot adopt a successor account at the same URL',
    () async {
      final composer = await compose(
        'Original sent title',
        'Original sent body',
      );
      api.createdByReachable = false;
      await shell.submitComposer(composer: composer);
      expect(composer.canRecheck, isTrue);
      final draftReads = api.draftReads.length;
      final topicReads = api.topicListReads.length;
      shell.lifecycle.invalidate(_siteUrl);
      api.createdByReachable = true;

      await shell.recheckComposer(composer: composer);

      expect(api.topicCreates, hasLength(1));
      expect(api.draftReads, hasLength(draftReads));
      expect(api.topicListReads, hasLength(topicReads));
      expect(composer.canRecheck, isTrue);
      expect(composer.isDisposed, isFalse);
      expect(shell.currentContent?.topicId, isNot(901));
    },
  );

  test(
    'a created response without topic identity keeps the original attempt for recheck',
    () async {
      api.missingTopicId = true;
      final composer = await compose(
        'Original sent title',
        'Original sent body',
      );
      await shell.submitComposer(composer: composer);
      expect(composer.canRecheck, isTrue);
      expect(composer.canSubmit, isFalse);
      composer.title.text = 'Later title';
      composer.text.text = 'Later body';
      await composer.flushDraft();

      await shell.submitComposer(composer: composer);
      expect(api.topicCreates, ['Original sent body']);
      expect(composer.canRecheck, isTrue);
      await shell.recheckComposer(composer: composer);

      expect(api.topicCreates, ['Original sent body']);
      expect(composer.isDisposed, isTrue);
      expect(shell.currentContent?.topicId, 901);
    },
  );

  test('a topic whose title the site prettified is found posted', () async {
    api.storedTitle = (title) =>
        title[0].toUpperCase() +
        title.substring(1).replaceAll(RegExp(r'\?+$'), '?');
    final composer = await compose(
      'why is my printer on fire??',
      'Please\u00A0send help.',
    );

    await shell.submitComposer();

    expect(composer.isDisposed, isTrue);
    expect(api.topicCreates, hasLength(1));
  });

  test('a draft still at the sent sequence reads as not posted even when '
      'the last save before sending never reached the site', () async {
    final composer = await compose('Printer is on fire', 'Please send help.');
    api.createLands = false;
    api.draftSavesReachable = false;
    // Flushed as the submit starts, but the site keeps the earlier text at
    // the sequence the create is then sent at.
    composer.text.text = 'Please send help, quickly.';

    await shell.submitComposer();
    await shell.recheckComposer();

    expect(composer.state, ComposerState.editing);
    expect(composer.canSubmit, isTrue);
    expect(api.topicCreates, hasLength(1));
  });

  test('a create that never ran is still told apart by its draft', () async {
    final composer = await compose('Printer is on fire', 'Please send help.');
    api.createLands = false;

    await shell.submitComposer();

    expect(composer.state, ComposerState.editing);
    expect(composer.canSubmit, isTrue);
    expect(api.topicCreates, hasLength(1));
  });

  test('a create the site refused is not looked for', () async {
    final composer = await compose('Printer is on fire', 'Please send help.');
    api.createLands = false;
    api.createFailure = const WriteException(
      WriteFailure.validation,
      errors: ['Title is too short'],
    );
    final draftReads = api.draftReads.length;
    final topicListReads = api.topicListReads.length;

    await shell.submitComposer();

    expect(api.topicCreates, hasLength(1));
    expect(api.draftReads, hasLength(draftReads));
    expect(api.topicListReads, hasLength(topicListReads));
    expect(composer.state, ComposerState.editing);
    expect(composer.canSubmit, isTrue);
    expect(composer.error?.message, 'Title is too short');
  });

  test('a create that never reached the site is not looked for', () async {
    final composer = await compose('Printer is on fire', 'Please send help.');
    api.createLands = false;
    api.createFailure = const WriteException(
      WriteFailure.unreachable,
      notSent: true,
    );
    final draftReads = api.draftReads.length;
    final topicListReads = api.topicListReads.length;

    await shell.submitComposer();

    expect(api.topicCreates, hasLength(1));
    expect(api.draftReads, hasLength(draftReads));
    expect(api.topicListReads, hasLength(topicListReads));
    expect(composer.state, ComposerState.editing);
    expect(composer.canSubmit, isTrue);
    expect(
      composer.error?.message,
      "Couldn't reach the site. Nothing was posted.",
    );
  });
}
