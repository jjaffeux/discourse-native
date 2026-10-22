import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer/pills.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _hashtag = FoundHashtag(
  type: 'tag',
  ref: 'sailing',
  slug: 'sailing',
  text: 'Sailing',
  id: 8,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('search seeds the same pills and frozen cooking identity', () async {
    final api = _IdentityApi();
    final shell = await _shell(api);
    final pills = _pills(shell);
    final before = shell.cookingRequest(siteUrl: _site, raw: '#sailing @Alice');
    await shell.searchHashtags(siteUrl: _site, term: 'sail');
    await shell.searchUsers(siteUrl: _site, topicId: 7, term: 'ali');
    expect(pills.hashtag('sailing'), _hashtag);
    expect(pills.mention('Alice'), isTrue);
    pills.resolve({'sailing'}, {'Alice'});
    await pumpEventQueue();
    expect(api.hashtagLookupsRequested, isEmpty);
    expect(api.mentionChecksRequested, isEmpty);
    final after = shell.cookingRequest(siteUrl: _site, raw: '#sailing @Alice');
    expect(before.snapshot.hashtags, isEmpty);
    expect(before.snapshot.mentions, isEmpty);
    expect(after.snapshot.hashtags['sailing'], containsPair('id', 8));
    expect(after.snapshot.mentions['Alice'], isTrue);
  });

  test('negative lookup entries deduplicate and failures can retry', () async {
    final api = _IdentityApi()..lookupGate = Completer<void>();
    final shell = await _shell(api);
    final pills = _pills(shell);
    pills.resolve({'missing'}, {'Nobody'});
    pills.resolve({'missing'}, {'Nobody'});
    await pumpEventQueue();
    expect(api.hashtagLookupsRequested, hasLength(1));
    expect(api.mentionChecksRequested, hasLength(1));
    expect(api.mentionTopicIds, [7]);
    api.lookupGate!.complete();
    await pumpEventQueue();
    expect(pills.mention('Nobody'), isFalse);
    pills.resolve({'missing'}, {'Nobody'});
    await pumpEventQueue();
    expect(api.hashtagLookupsRequested, hasLength(1));
    expect(api.mentionChecksRequested, hasLength(1));
    api.lookupGate = null;
    api.failLookup = true;
    pills.resolve({'retry'}, {});
    await pumpEventQueue();
    api.failLookup = false;
    pills.resolve({'retry'}, {});
    await pumpEventQueue();
    expect(
      api.hashtagLookupsRequested.where((r) => r.contains('retry')),
      hasLength(2),
    );
  });

  test(
    'retired work cannot publish or release replacement admission',
    () async {
      final oldLookup = Completer<List<FoundHashtag>>();
      final newLookup = Completer<List<FoundHashtag>>();
      final api = _IdentityApi()
        ..hashtagReplies.addAll([oldLookup, newLookup])
        ..searchGate = Completer<void>();
      final shell = await _shell(api);
      final oldPills = _pills(shell);
      oldPills.resolve({'sailing'}, {});
      final oldSearch = shell.searchHashtags(siteUrl: _site, term: 'sail');
      await pumpEventQueue();
      shell.lifecycle.invalidate(_site);
      shell.clearAccountSessionState(_site);
      shell.applyAccountSessionInstance(
        shell.currentInstance!,
        AccountSessionPhase.restored,
      );
      final freshPills = _pills(shell);
      freshPills.resolve({'sailing'}, {});
      await pumpEventQueue();
      expect(api.hashtagLookupsRequested, hasLength(2));
      api.searchGate!.complete();
      expect(await oldSearch, isEmpty);
      oldLookup.complete([_hashtag]);
      await pumpEventQueue();
      expect(freshPills.hashtag('sailing'), isNull);
      expect(
        shell.cookingRequest(siteUrl: _site, raw: '#sailing').snapshot.hashtags,
        isEmpty,
      );
      freshPills.resolve({'sailing'}, {});
      await pumpEventQueue();
      expect(api.hashtagLookupsRequested, hasLength(2));
      newLookup.complete([_hashtag]);
      await pumpEventQueue();
      expect(freshPills.hashtag('sailing'), _hashtag);
    },
  );

  test(
    'mention search seeds users and groups and preserves error policy',
    () async {
      final api = _IdentityApi();
      final shell = await _shell(api);
      final pills = _pills(shell);
      final search = shell.visibleComposer!.autocomplete.search!;
      final found = await search.users('ali');
      expect(found.map((s) => s.value), ['crew', 'Alice']);
      expect(pills.mention('crew'), isTrue);
      expect(pills.mention('Alice'), isTrue);
      expect(api.mentionSearchTopicIds, [7]);
      api.failSearch = true;
      await expectLater(search.users('bad'), throwsStateError);
      expect(
        await shell.searchUsers(siteUrl: _site, topicId: 7, term: 'bad'),
        isEmpty,
      );
      expect(await shell.searchHashtags(siteUrl: _site, term: 'bad'), isEmpty);
    },
  );

  test('credential retirement prevents identity dispatch', () async {
    final auth = _GatedAuthenticator()..keys[_site] = 'key';
    final api = _IdentityApi();
    final shell = await _shell(api, authenticator: auth);
    auth.gate = Completer<void>();
    final pending = shell.searchHashtags(siteUrl: _site, term: 'sail');
    await pumpEventQueue();
    shell.lifecycle.invalidate(_site);
    shell.clearAccountSessionState(_site);
    auth.gate!.complete();
    expect(await pending, isEmpty);
    expect(api.hashtagSearchesRequested, isEmpty);
  });

  test('both identity caches retain only 2048 entries', () async {
    final api = _IdentityApi()..bulk = true;
    final shell = await _shell(api);
    final pills = _pills(shell);
    await shell.searchHashtags(siteUrl: _site, term: 'bulk');
    await shell.searchUsers(siteUrl: _site, topicId: 7, term: 'bulk');
    expect(pills.hashtag('tag0'), isNull);
    expect(pills.hashtag('tag1'), isNotNull);
    expect(pills.mention('user0'), isNull);
    expect(pills.mention('user1'), isTrue);
    pills.resolve({'tag0', 'tag1'}, {'user0', 'user1'});
    await pumpEventQueue();
    expect(api.hashtagLookupsRequested, [
      {'tag0'},
    ]);
    expect(api.mentionChecksRequested, [
      {'user0'},
    ]);
  });
}

Future<ShellController> _shell(
  _IdentityApi api, {
  FakeAuthenticator? authenticator,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator ?? (FakeAuthenticator()..keys[_site] = 'key'),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() async {
    await shell.pluginSession.close();
    shell.dispose();
  });
  await shell.load();
  await pumpEventQueue();
  return shell;
}

ComposerPills _pills(ShellController shell) {
  shell.store.put(
    _site,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  shell.openReply();
  return shell.visibleComposer!.text.pills!;
}

final class _IdentityApi extends FakeDiscourseApi {
  _IdentityApi() : super(feeds: const {'/latest.json': <Topic>[]});
  Completer<void>? lookupGate;
  Completer<void>? searchGate;
  bool failLookup = false;
  bool bulk = false;
  bool failSearch = false;
  final hashtagReplies = <Completer<List<FoundHashtag>>>[];
  final mentionSearchTopicIds = <int?>[];
  final mentionTopicIds = <int?>[];

  @override
  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = const [],
    String? apiKey,
    String? clientId,
  }) async {
    await super.searchHashtags(
      siteUrl: siteUrl,
      term: term,
      order: order,
      apiKey: apiKey,
      clientId: clientId,
    );
    await searchGate?.future;
    if (failSearch) throw StateError('search failed');
    return bulk
        ? [
            for (var i = 0; i <= 2048; i++)
              FoundHashtag(
                type: 'tag',
                ref: 'tag$i',
                slug: 'tag$i',
                text: 'Tag $i',
                id: i,
              ),
          ]
        : [_hashtag];
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
    if (failSearch) throw StateError('search failed');
    return bulk
        ? [for (var i = 0; i <= 2048; i++) FoundUser(username: 'user$i')]
        : [const FoundUser(username: 'Alice')];
  }

  @override
  Future<FoundUsersAndGroups> searchMentions({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 7,
    String? apiKey,
    String? clientId,
  }) async {
    mentionSearchTopicIds.add(topicId);
    if (failSearch) throw StateError('search failed');
    return const FoundUsersAndGroups(
      users: [FoundUser(username: 'Alice')],
      groups: [FoundGroup(name: 'crew')],
    );
  }

  @override
  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    List<String> order = const [],
    String? apiKey,
    String? clientId,
  }) async {
    await super.lookupHashtags(
      siteUrl: siteUrl,
      refs: refs,
      order: order,
      apiKey: apiKey,
      clientId: clientId,
    );
    final index = hashtagLookupsRequested.length - 1;
    if (index < hashtagReplies.length) return hashtagReplies[index].future;
    await lookupGate?.future;
    if (failLookup) throw StateError('lookup failed');
    return const [];
  }

  @override
  Future<Set<String>> checkMentions({
    required String siteUrl,
    required Iterable<String> names,
    int? topicId,
    String? apiKey,
    String? clientId,
  }) async {
    mentionTopicIds.add(topicId);
    await super.checkMentions(
      siteUrl: siteUrl,
      names: names,
      topicId: topicId,
      apiKey: apiKey,
      clientId: clientId,
    );
    await lookupGate?.future;
    return const {};
  }
}

final class _GatedAuthenticator extends FakeAuthenticator {
  Completer<void>? gate;
  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    await gate?.future;
    return super.apiKeyFor(siteUrl);
  }
}
