import 'dart:async';

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'invalidating a pending composer tag credential sends no lookup',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.shell.dispose);
      final composer = _openReply(fixture.shell);
      await pumpEventQueue();

      final credential = fixture.authenticator.gateNextApiKey();
      final search = fixture.shell.searchComposerTags(composer, 'safe');
      await credential.started.future;

      fixture.shell.lifecycle.invalidate(_siteUrl);
      credential.release.complete();

      expect(await search, const TopicTagSearch());
      expect(fixture.api.tagSearches, isEmpty);
    },
  );

  test(
    'invalidating a pending new-topic draft credential sends no read',
    () async {
      final drafts = _GatedDraftStore();
      final fixture = await _fixture(drafts: drafts, canCreateTopic: true);
      addTearDown(fixture.shell.dispose);
      expect(fixture.shell.canCreateTopicHere, isTrue);

      final localRead = drafts.gateNextRead();
      await fixture.shell.openNewTopic();
      await localRead.started.future;
      // Let the other composer-owned best-effort reads finish before selecting
      // exactly the credential lookup that follows the local draft read.
      await pumpEventQueue();
      final credential = fixture.authenticator.gateNextApiKey();
      localRead.release.complete();
      await credential.started.future;

      fixture.shell.lifecycle.invalidate(_siteUrl);
      credential.release.complete();
      await pumpEventQueue();

      expect(fixture.api.draftReads, isEmpty);
    },
  );

  test(
    'invalidating a pending mention credential sends no user lookup',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.shell.dispose);
      final credential = fixture.authenticator.gateNextApiKey();

      final search = fixture.shell.searchUsers(
        siteUrl: _siteUrl,
        topicId: 7,
        term: 'sam',
      );
      await credential.started.future;
      fixture.shell.lifecycle.invalidate(_siteUrl);
      credential.release.complete();

      expect(await search, isEmpty);
      expect(fixture.api.userSearchRequests, isEmpty);
    },
  );
}

typedef _Fixture = ({
  ShellController shell,
  _RecordingComposerApi api,
  _GatedAuthenticator authenticator,
});

Future<_Fixture> _fixture({
  FakeDraftStore? drafts,
  bool canCreateTopic = false,
}) async {
  final api = _RecordingComposerApi(
    feeds: const {'/latest.json': []},
    creatableFeedPaths: canCreateTopic ? const {'/latest.json'} : const {},
  );
  final authenticator = _GatedAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: drafts ?? FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await pumpEventQueue();
  return (shell: shell, api: api, authenticator: authenticator);
}

ComposerController _openReply(ShellController shell) {
  shell.store.put(
    _siteUrl,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  shell.openReply();
  return shell.visibleComposer!;
}

final class _Gate {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
}

final class _GatedAuthenticator extends FakeAuthenticator {
  _Gate? _apiKeyGate;

  _Gate gateNextApiKey() => _apiKeyGate = _Gate();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    final gate = _apiKeyGate;
    _apiKeyGate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    return super.apiKeyFor(siteUrl);
  }
}

final class _GatedDraftStore extends FakeDraftStore {
  _Gate? _readGate;

  _Gate gateNextRead() => _readGate = _Gate();

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    final gate = _readGate;
    _readGate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    return super.read(siteUrl, draftKey);
  }
}

final class _RecordingComposerApi extends FakeDiscourseApi {
  _RecordingComposerApi({required super.feeds, super.creatableFeedPaths});

  final List<String> tagSearches = [];
  final List<String> draftReads = [];
  final List<String> userSearchRequests = [];

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = 20,
    String? clientId,
  }) async {
    tagSearches.add(term);
    return const TopicTagSearch();
  }

  @override
  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  }) async {
    draftReads.add(draftKey);
    return (draft: null, sequence: 0);
  }

  @override
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    userSearchRequests.add(term);
    return const [];
  }
}
