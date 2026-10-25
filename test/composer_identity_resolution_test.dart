import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/pills.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  for (final mentions in [true, false]) {
    final kind = mentions ? 'mentions' : 'hashtags';
    testWidgets('pasted $kind resolve beyond the first request', (
      tester,
    ) async {
      final wire = _IdentityWire()..gate = Completer<void>();
      final api = _IdentityApi()..wire = wire.api;
      final shell = (await tester.runAsync(() => _shell(api)))!;
      final pills = _pills(shell);
      final composer = shell.visibleComposer!;
      final identities = {
        for (var i = 0; i < 45; i++) '${mentions ? 'user' : 'tag'}$i',
        'missing',
      };
      final prefix = mentions ? '@' : '#';
      final raw = [
        ...identities,
        identities.first,
        identities.last,
      ].map((identity) => '$prefix$identity').join(' ');
      final before = shell.cookingRequest(siteUrl: _site, raw: raw);
      composer.text.text = '$raw ';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: ComposerEditor(
                composer: composer,
                hintText: 'Reply',
                textStyle: const TextStyle(fontSize: 16),
                hintStyle: null,
                enableDropTarget: false,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => pumpEventQueue());
      final requests = mentions ? wire.mentionRequests : wire.hashtagRequests;
      expect(requests, isNotEmpty);
      final pendingRequests = requests.length;
      pills.resolve(mentions ? {} : identities, mentions ? identities : {});
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      expect(requests, hasLength(pendingRequests));
      wire.gate!.complete();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();

      for (var i = 0; i < 45; i++) {
        if (mentions) {
          expect(
            pills.mention('user$i'),
            isTrue,
            reason: 'user$i must resolve',
          );
        } else {
          expect(pills.hashtag('tag$i')?.ref, 'tag$i');
        }
      }
      expect(requests.every((batch) => batch.length <= 20), isTrue);
      expect(requests.expand((batch) => batch), unorderedEquals(identities));
      final after = shell.cookingRequest(siteUrl: _site, raw: raw);
      expect(before.snapshot.mentions, isEmpty);
      expect(before.snapshot.hashtags, isEmpty);
      if (mentions) {
        expect(pills.mention('missing'), isFalse);
        expect(after.snapshot.mentions['user44'], isTrue);
        expect(after.snapshot.mentions['missing'], isFalse);
      } else {
        expect(pills.hashtag('missing'), isNull);
        expect(after.snapshot.hashtags['tag44'], containsPair('id', 45));
        expect(after.snapshot.hashtags, isNot(contains('missing')));
      }
      final completedRequests = requests.length;
      pills.resolve(mentions ? {} : identities, mentions ? identities : {});
      composer.text.text = '$raw  ';
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
      expect(requests, hasLength(completedRequests));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => pumpEventQueue());
    });
  }

  test(
    'failed identity batches retry without repeating successful batches',
    () async {
      final wire = _IdentityWire()
        ..failMentionBatchOnce = true
        ..failHashtagBatchOnce = true;
      final api = _IdentityApi()..wire = wire.api;
      final shell = await _shell(api);
      final pills = _pills(shell);
      final refs = {for (var i = 0; i < 45; i++) 'tag$i'};
      final names = {for (var i = 0; i < 45; i++) 'user$i'};
      pills.resolve(refs, names);
      await pumpEventQueue();
      expect(pills.mention('user0'), isTrue);
      expect(pills.hashtag('tag0')?.ref, 'tag0');
      expect(pills.mention('user20'), isNull);
      expect(pills.hashtag('tag20'), isNull);
      expect(pills.mention('user44'), isTrue);
      expect(pills.hashtag('tag44')?.ref, 'tag44');
      pills.resolve(refs, names);
      await pumpEventQueue();
      for (var i = 0; i < 45; i++) {
        expect(pills.mention('user$i'), isTrue);
        expect(pills.hashtag('tag$i')?.ref, 'tag$i');
      }
      expect(
        wire.mentionRequests.where((batch) => batch.contains('user0')),
        hasLength(1),
      );
      expect(
        wire.hashtagRequests.where((batch) => batch.contains('tag0')),
        hasLength(1),
      );
      expect(
        wire.mentionRequests.where((batch) => batch.contains('user20')),
        hasLength(2),
      );
      expect(
        wire.hashtagRequests.where((batch) => batch.contains('tag20')),
        hasLength(2),
      );
      expect(wire.mentionRequests.every((batch) => batch.length <= 20), isTrue);
      expect(wire.hashtagRequests.every((batch) => batch.length <= 20), isTrue);
    },
  );

  for (final retirement in ['lease and state', 'lease', 'state']) {
    test('$retirement retirement cancels remaining identity batches', () async {
      final wire = _IdentityWire()..gate = Completer<void>();
      final api = _IdentityApi()..wire = wire.api;
      final shell = await _shell(api);
      final pills = _pills(shell);
      final refs = {for (var i = 0; i < 45; i++) 'tag$i'};
      final names = {for (var i = 0; i < 45; i++) 'user$i'};
      pills.resolve(refs, names);
      await pumpEventQueue();
      expect(wire.hashtagRequests, hasLength(1));
      expect(wire.mentionRequests, hasLength(1));
      if (retirement != 'state') shell.lifecycle.invalidate(_site);
      if (retirement != 'lease') shell.clearAccountSessionState(_site);
      wire.gate!.complete();
      await pumpEventQueue();
      pills.resolve(refs, names);
      await pumpEventQueue();
      expect(wire.hashtagRequests, hasLength(1));
      expect(wire.mentionRequests, hasLength(1));
      expect(pills.hashtag('tag0'), isNull);
      expect(pills.mention('user0'), isNull);
      if (retirement == 'lease and state') {
        final snapshot = shell.cookingRequest(
          siteUrl: _site,
          raw: '#tag0 @user0',
        );
        expect(snapshot.snapshot.hashtags, isEmpty);
        expect(snapshot.snapshot.mentions, isEmpty);
      }
    });
  }

  test('a retired lease hides identities before its state clears', () async {
    final api = _IdentityApi();
    final shell = await _shell(api);
    final pills = _pills(shell);
    await shell.searchHashtags(siteUrl: _site, term: 'sail');
    await shell.searchUsers(siteUrl: _site, topicId: 7, term: 'ali');
    expect(pills.hashtag('sailing'), _hashtag);
    expect(pills.mention('Alice'), isTrue);
    shell.lifecycle.invalidate(_site);
    expect(pills.hashtag('sailing'), isNull);
    expect(pills.mention('Alice'), isNull);
  });

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

  testWidgets(
    'canonical hashtag case resolves authored pills and cooking keys',
    (tester) async {
      final requests = <List<String>>[];
      final api = _IdentityApi()
        ..wire = DiscourseApi(
          client: MockClient((request) async {
            expect(request.url.path, '/hashtags.json');
            requests.add(request.url.queryParametersAll['slugs[]']!);
            return http.Response(
              jsonEncode({
                'tag': [
                  {'type': 'tag', 'ref': 'sailing', 'slug': 'sailing', 'id': 8},
                ],
                'category': [
                  {
                    'type': 'category',
                    'ref': 'sailing',
                    'slug': 'sailing',
                    'id': 3,
                  },
                ],
              }),
              200,
            );
          }),
        );
      final shell = (await tester.runAsync(() => _shell(api)))!;
      final pills = _pills(shell);
      final composer = shell.visibleComposer!;
      const authored = '#SAILING #SAILING::tag ';
      composer.text.text = authored;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ShellScope(
            controller: shell,
            child: Scaffold(
              body: ComposerEditor(
                composer: composer,
                hintText: 'Reply',
                textStyle: const TextStyle(fontSize: 16),
                hintStyle: null,
                enableDropTarget: false,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();
      expect(requests, [
        ['SAILING', 'SAILING::tag'],
      ]);
      expect(pills.hashtag('SAILING')?.type, 'category');
      expect(pills.hashtag('SAILING::tag')?.type, 'tag');
      expect(
        tester
            .widgetList<HashtagPill>(find.byType(HashtagPill))
            .map((pill) => pill.label),
        ['#SAILING', '#SAILING::tag'],
      );
      expect(composer.text.text, authored);
      final snapshot = shell
          .cookingRequest(siteUrl: _site, raw: authored)
          .snapshot;
      expect(snapshot.hashtags['SAILING'], containsPair('id', 3));
      expect(snapshot.hashtags['SAILING::tag'], containsPair('id', 8));
      pills.resolve({'SAILING', 'SAILING::tag'}, {});
      await tester.runAsync(() => pumpEventQueue());
      expect(requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      shell.closeComposer(composer: composer);
    },
  );

  test('canonical tag result resolves the authored spelling', () async {
    final reply = Completer<List<FoundHashtag>>()..complete([_hashtag]);
    final api = _IdentityApi()..hashtagReplies.add(reply);
    final shell = await _shell(api);
    final pills = _pills(shell);
    pills.resolve({'SAILING'}, {});
    await pumpEventQueue();
    expect(pills.hashtag('SAILING'), _hashtag);
    expect(
      shell
          .cookingRequest(siteUrl: _site, raw: '#SAILING')
          .snapshot
          .hashtags['SAILING'],
      containsPair('id', 8),
    );
  });

  test('typed hashtag results do not seed an ambiguous bare alias', () async {
    final reply = Completer<List<FoundHashtag>>()..complete([_hashtag]);
    final api = _IdentityApi()..hashtagReplies.add(reply);
    final shell = await _shell(api);
    final pills = _pills(shell);
    pills.resolve({'SAILING', 'SAILING::tag'}, {});
    await pumpEventQueue();
    expect(pills.hashtag('SAILING'), isNull);
    expect(pills.hashtag('SAILING::tag'), _hashtag);
    final snapshot = shell
        .cookingRequest(siteUrl: _site, raw: '#SAILING #SAILING::tag')
        .snapshot;
    expect(snapshot.hashtags, isNot(contains('SAILING')));
    expect(snapshot.hashtags['SAILING::tag'], containsPair('id', 8));
  });

  test('canonical typed suppression spans lookup batches', () async {
    final requested = <List<String>>[];
    final api = _IdentityApi()
      ..wire = DiscourseApi(
        client: MockClient((request) async {
          final refs = request.url.queryParametersAll['slugs[]']!;
          requested.add(refs);
          return http.Response(
            jsonEncode({
              'tag': [
                if (refs.contains('SAILING') || refs.contains('SAILING::tag'))
                  {'type': 'tag', 'ref': 'sailing', 'slug': 'sailing', 'id': 8},
              ],
            }),
            200,
          );
        }),
      );
    final shell = await _shell(api);
    final pills = _pills(shell);
    final refs = {
      'SAILING',
      for (var i = 0; i < 19; i++) 'missing$i',
      'SAILING::tag',
    };
    pills.resolve(refs, {});
    await pumpEventQueue();
    expect(requested.map((batch) => batch.length), [20, 1]);
    expect(requested.last, ['SAILING::tag']);
    expect(pills.hashtag('SAILING'), isNull);
    expect(pills.hashtag('SAILING::tag')?.id, 8);
    final snapshot = shell
        .cookingRequest(siteUrl: _site, raw: '#SAILING #SAILING::tag')
        .snapshot;
    expect(snapshot.hashtags, isNot(contains('SAILING')));
    expect(snapshot.hashtags['SAILING::tag'], containsPair('id', 8));
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
  DiscourseApi? wire;
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
    if (wire case final wire?) {
      return wire.lookupHashtags(
        siteUrl: siteUrl,
        refs: refs,
        order: order,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
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
    if (wire case final wire?) {
      return wire.checkMentions(
        siteUrl: siteUrl,
        names: names,
        topicId: topicId,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
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

final class _IdentityWire {
  final mentionRequests = <List<String>>[];
  final hashtagRequests = <List<String>>[];
  Completer<void>? gate;
  bool failMentionBatchOnce = false;
  bool failHashtagBatchOnce = false;
  late final api = DiscourseApi(client: MockClient(_respond));

  Future<http.Response> _respond(http.Request request) async {
    if (request.url.path == '/composer/mentions') {
      final names = request.url.queryParametersAll['names[]']!;
      mentionRequests.add(names);
      expect(request.url.queryParameters['topic_id'], '7');
      await gate?.future;
      if (failMentionBatchOnce && names.contains('user20')) {
        failMentionBatchOnce = false;
        return http.Response('{}', 500);
      }
      return http.Response(
        jsonEncode({
          'users': names.where((name) => name != 'missing').toList(),
          'groups': <String, Object?>{},
        }),
        200,
      );
    }
    if (request.url.path == '/hashtags.json') {
      final refs = request.url.queryParametersAll['slugs[]']!;
      hashtagRequests.add(refs);
      await gate?.future;
      if (failHashtagBatchOnce && refs.contains('tag20')) {
        failHashtagBatchOnce = false;
        return http.Response('{}', 500);
      }
      return http.Response(
        jsonEncode({
          'tag': [
            for (final ref in refs.where((ref) => ref != 'missing'))
              {
                'type': 'tag',
                'ref': ref,
                'slug': ref,
                'text': ref,
                'relative_url': '/tag/$ref',
                'id': int.parse(ref.substring(3)) + 1,
              },
          ],
        }),
        200,
      );
    }
    throw StateError('Unexpected identity request ${request.url}');
  }
}
