import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
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
  bool createLands = true;
  bool createdByReachable = true;

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
    final current = sequences[draftKey] ?? 0;
    // A draft at another sequence is a conflict the client retries with
    // force_save, which advances it; with no draft at all the controller
    // sets it again at the current sequence.
    final saved = drafts.containsKey(draftKey) && sequence != current
        ? current + 1
        : current;
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
  }) async => (
    draft: ComposerDraft.decode(drafts[draftKey]),
    sequence: sequences[draftKey] ?? 0,
  );

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
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
    throw const WriteException(WriteFailure.unreachable);
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

  test('a create that never ran is still told apart by its draft', () async {
    final composer = await compose('Printer is on fire', 'Please send help.');
    api.createLands = false;

    await shell.submitComposer();

    expect(composer.state, ComposerState.editing);
    expect(composer.canSubmit, isTrue);
    expect(api.topicCreates, hasLength(1));
  });
}
