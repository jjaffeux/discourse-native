import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/composer_target.dart';
import 'package:discourse_native/src/shell/composer/composer_identity_directory.dart';
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
    await shell.composerIdentities.searchHashtags(siteUrl: _site, term: 'sail');
    await shell.composerIdentities.searchUsers(
      siteUrl: _site,
      topicId: 7,
      term: 'ali',
    );
    expect(pills.hashtag('sailing'), _hashtag);
    expect(pills.mention('Alice'), isTrue);
    shell.lifecycle.invalidate(_site);
    expect(pills.hashtag('sailing'), isNull);
    expect(pills.mention('Alice'), isNull);
  });

  test('a directory built without a shell retires with its lease', () async {
    final lifecycle = SiteLifecycle();
    final api = _IdentityApi();
    final changes = <(String, bool)>[];
    final directory = ComposerIdentityDirectory(
      credentials: FakeAuthenticator()..keys[_site] = 'key',
      lifecycle: lifecycle,
      search: api,
      lookups: api,
      isConnected: (_) => true,
      emoji: (
        enabled: (_) => false,
        ensureCatalog: (_) async => null,
        ensureSearchAliases: (_) async => null,
        search: (_, _, {limit = 0}) => const [],
        urlFor: (_, name) => name,
        ensurePreferences: (_) async {},
        skinTone: (_) => EmojiSkinTone.neutral,
      ),
      pluginHashtagPresentation: (_) => null,
      pluginHashtagTypes: () => const [],
      onChanged: (siteUrl, artwork) => changes.add((siteUrl, artwork)),
    );
    addTearDown(directory.dispose);
    const target = ReplyComposerTarget(
      siteUrl: _site,
      topicTitle: 'Topic',
      topicId: 7,
      slug: 'topic',
      privateMessageTopic: false,
    );

    final retiredPills = directory.pills(target);
    await directory.searchHashtags(siteUrl: _site, term: 'sail');
    expect(retiredPills.hashtag('sailing'), _hashtag);
    expect(directory.cookingIdentities(_site).hashtags, contains('sailing'));
    expect(changes, [(_site, false)]);

    api.searchGate = Completer<void>();
    final stale = directory.searchHashtags(siteUrl: _site, term: 'saili');
    await pumpEventQueue();
    lifecycle.invalidate(_site);
    expect(retiredPills.hashtag('sailing'), isNull);
    expect(directory.cookingIdentities(_site).hashtags, isEmpty);
    api.searchGate!.complete();
    expect(await stale, isEmpty);
    expect(changes, hasLength(1));

    api.searchGate = null;
    final replacementPills = directory.pills(target);
    expect(replacementPills.hashtag('sailing'), isNull);
    await directory.searchHashtags(siteUrl: _site, term: 'sail');
    expect(replacementPills.hashtag('sailing'), _hashtag);
    expect(retiredPills.hashtag('sailing'), isNull);
  });

  test('search seeds the same pills and frozen cooking identity', () async {
    final api = _IdentityApi();
    final shell = await _shell(api);
    final pills = _pills(shell);
    final before = shell.cookingRequest(siteUrl: _site, raw: '#sailing @Alice');
    await shell.composerIdentities.searchHashtags(siteUrl: _site, term: 'sail');
    await shell.composerIdentities.searchUsers(
      siteUrl: _site,
      topicId: 7,
      term: 'ali',
    );
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
      final oldSearch = shell.composerIdentities.searchHashtags(
        siteUrl: _site,
        term: 'sail',
      );
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
        await shell.composerIdentities.searchUsers(
          siteUrl: _site,
          topicId: 7,
          term: 'bad',
        ),
        isEmpty,
      );
      expect(
        await shell.composerIdentities.searchHashtags(
          siteUrl: _site,
          term: 'bad',
        ),
        isEmpty,
      );
    },
  );

  test('credential retirement prevents identity dispatch', () async {
    final auth = _GatedAuthenticator()..keys[_site] = 'key';
    final api = _IdentityApi();
    final shell = await _shell(api, authenticator: auth);
    auth.gate = Completer<void>();
    final pending = shell.composerIdentities.searchHashtags(
      siteUrl: _site,
      term: 'sail',
    );
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
    await shell.composerIdentities.searchHashtags(siteUrl: _site, term: 'bulk');
    await shell.composerIdentities.searchUsers(
      siteUrl: _site,
      topicId: 7,
      term: 'bulk',
    );
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
  group('recent search answers', () {
    testWidgets('retyped mention terms reuse the answer and keep known names', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 8);
      final api = _IdentityApi()
        ..mentionAnswers.addAll({
          '': ['alice'],
          's': ['sam', 'sara'],
          'sa': ['sam', 'sara'],
          'san': ['sandra'],
          'sam': ['sam'],
        });
      final shell = (await tester.runAsync(
        () => _shell(api, clock: () => now),
      ))!;
      _pills(shell);
      final composer = shell.visibleComposer!;
      final revisionBefore = shell.cooking.contextRevisionFor(_site);

      for (final typed in _retypedTrigger('@')) {
        composer.text.value = TextEditingValue(
          text: typed,
          selection: TextSelection.collapsed(offset: typed.length),
        );
        await tester.pump(_keyInterval);
        now = now.add(_keyInterval);
      }

      final searches = api.userSearchesRequested.length;
      final bumps = shell.cooking.contextRevisionFor(_site) - revisionBefore;
      // ignore: avoid_print
      print('PERF_PROOF mention-cache user_searches=$searches');
      // ignore: avoid_print
      print('PERF_PROOF mention-cache context_bumps=$bumps');
      expect(searches, lessThanOrEqualTo(5));
      expect(bumps, lessThanOrEqualTo(3));
      expect(api.userSearchesRequested.map((search) => search.term).toSet(), {
        '',
        's',
        'sa',
        'san',
        'sam',
      });
      expect(bumps, 3, reason: 'each answer that taught a name still counts');
      expect(composer.autocomplete.suggestions.map((row) => row.value), [
        'sam',
      ]);
      expect(_pills(shell).mention('sandra'), isTrue);

      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => pumpEventQueue());
    });

    testWidgets('retyped hashtag terms reuse the answer and keep known tags', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 8);
      final api = _IdentityApi();
      final shell = (await tester.runAsync(
        () => _shell(api, clock: () => now),
      ))!;
      _pills(shell);
      final composer = shell.visibleComposer!;
      final revisionBefore = shell.cooking.contextRevisionFor(_site);

      for (final typed in _retypedTrigger('#')) {
        composer.text.value = TextEditingValue(
          text: typed,
          selection: TextSelection.collapsed(offset: typed.length),
        );
        await tester.pump(_keyInterval);
        now = now.add(_keyInterval);
      }

      final searches = api.hashtagSearchesRequested.length;
      final bumps = shell.cooking.contextRevisionFor(_site) - revisionBefore;
      // ignore: avoid_print
      print('PERF_PROOF mention-cache hashtag_searches=$searches');
      // ignore: avoid_print
      print('PERF_PROOF mention-cache hashtag_context_bumps=$bumps');
      expect(searches, lessThanOrEqualTo(4));
      expect(bumps, lessThanOrEqualTo(1));
      expect(api.hashtagSearchesRequested.toSet(), {'s', 'sa', 'san', 'sam'});
      expect(bumps, 1, reason: 'the first answer taught the tag');
      expect(composer.autocomplete.suggestions.map((row) => row.value), [
        'sailing',
      ]);

      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => pumpEventQueue());
    });

    test(
      'a term is asked again once its answer is thirty seconds old',
      () async {
        var now = DateTime(2026, 11, 8);
        final api = _IdentityApi();
        final shell = await _shell(api, clock: () => now);
        _pills(shell);
        final search = shell.visibleComposer!.autocomplete.search!;

        await search.users('ali');
        await search.hashtags('sail');
        now = now.add(const Duration(seconds: 29));
        expect((await search.users('ali')).map((row) => row.value), [
          'crew',
          'Alice',
        ]);
        expect((await search.hashtags('sail')).single.value, 'sailing');
        expect(api.userSearchesRequested, hasLength(1));
        expect(api.hashtagSearchesRequested, hasLength(1));

        now = now.add(const Duration(seconds: 2));
        await search.users('ali');
        await search.hashtags('sail');
        expect(api.userSearchesRequested, hasLength(2));
        expect(api.hashtagSearchesRequested, hasLength(2));
      },
    );

    test('a failed search is not remembered', () async {
      final api = _IdentityApi()..failSearch = true;
      final shell = await _shell(api);
      _pills(shell);
      final search = shell.visibleComposer!.autocomplete.search!;

      await expectLater(search.users('ali'), throwsStateError);
      expect(await search.hashtags('sail'), isEmpty);

      api.failSearch = false;
      expect(await search.users('ali'), hasLength(2));
      expect(await search.hashtags('sail'), hasLength(1));
      expect(api.mentionSearchTopicIds, hasLength(2));
      expect(api.hashtagSearchesRequested, hasLength(2));
    });

    test('an empty answer is remembered like any other', () async {
      final api = _IdentityApi()..mentionAnswers['nobody'] = const [];
      final shell = await _shell(api);
      _pills(shell);
      final search = shell.visibleComposer!.autocomplete.search!;

      await search.users('nobody');
      expect(await search.users('nobody'), isEmpty);
      expect(api.userSearchesRequested, hasLength(1));
    });

    test('a topic is not served another topic\'s mention answer', () async {
      final api = _IdentityApi();
      final shell = await _shell(api);
      final first = shell.composerIdentities.search(_replyTo(7));
      final second = shell.composerIdentities.search(_replyTo(8));

      await first.users('ali');
      await second.users('ali');
      expect(api.mentionSearchTopicIds, [7, 8]);

      await first.users('ali');
      await second.users('ali');
      expect(api.mentionSearchTopicIds, [7, 8]);
    });

    test('a replaced lease does not answer from the retired one', () async {
      final api = _IdentityApi();
      final shell = await _shell(api);
      final search = shell.composerIdentities.search(_replyTo(7));

      await search.users('ali');
      await search.hashtags('sail');
      shell.lifecycle.invalidate(_site);
      await search.users('ali');
      await search.hashtags('sail');

      expect(api.userSearchesRequested, hasLength(2));
      expect(api.hashtagSearchesRequested, hasLength(2));
    });

    test('an older answer landing last does not replace a newer one', () async {
      var now = DateTime(2026, 11, 8);
      final older = Completer<FoundUsersAndGroups>();
      final newer = Completer<FoundUsersAndGroups>();
      final api = _IdentityApi()..mentionReplies.addAll([older, newer]);
      final shell = await _shell(api, clock: () => now);
      final search = shell.composerIdentities.search(_replyTo(7));

      final slow = search.users('ali');
      await pumpEventQueue();
      now = now.add(const Duration(seconds: 1));
      final fast = search.users('ali');
      await pumpEventQueue();
      newer.complete(
        const FoundUsersAndGroups(users: [FoundUser(username: 'newer')]),
      );
      await fast;
      older.complete(
        const FoundUsersAndGroups(users: [FoundUser(username: 'older')]),
      );
      await slow;

      expect((await search.users('ali')).single.value, 'newer');
      expect(api.userSearchesRequested, hasLength(2));
    });

    test('remembered answers stay bounded', () async {
      final api = _IdentityApi();
      final shell = await _shell(api);
      final search = shell.composerIdentities.search(_replyTo(7));

      for (var i = 0; i <= 256; i++) {
        await search.users('term$i');
      }
      final asked = api.userSearchesRequested.length;
      await search.users('term256');
      expect(api.userSearchesRequested, hasLength(asked));
      await search.users('term0');
      expect(api.userSearchesRequested, hasLength(asked + 1));
    });

    test('a changed hashtag still invalidates prepared cooks', () async {
      final api = _IdentityApi();
      final shell = await _shell(api);
      await shell.composerIdentities.searchHashtags(siteUrl: _site, term: 'a');
      final known = shell.cooking.contextRevisionFor(_site);
      await shell.composerIdentities.searchHashtags(siteUrl: _site, term: 'b');
      expect(shell.cooking.contextRevisionFor(_site), known);

      api.hashtagSearchAnswer = const [
        FoundHashtag(
          type: 'tag',
          ref: 'sailing',
          slug: 'sailing',
          text: 'Sailing',
          id: 8,
          colors: ['ff0000'],
        ),
      ];
      await shell.composerIdentities.searchHashtags(siteUrl: _site, term: 'c');

      expect(shell.cooking.contextRevisionFor(_site), known + 1);
      expect(
        shell
            .cookingRequest(siteUrl: _site, raw: '#sailing')
            .snapshot
            .hashtags['sailing'],
        containsPair('colors', ['ff0000']),
      );
    });
  });
}

const _keyInterval = Duration(milliseconds: 200);

List<String> _retypedTrigger(String trigger) => [
  trigger,
  '${trigger}s',
  '${trigger}sa',
  '${trigger}san',
  '${trigger}sa',
  '${trigger}sam',
  '${trigger}sam ',
  '${trigger}sam $trigger',
  '${trigger}sam ${trigger}s',
  '${trigger}sam ${trigger}sa',
  '${trigger}sam ${trigger}sam',
];

ReplyComposerTarget _replyTo(int topicId) => ReplyComposerTarget(
  siteUrl: _site,
  topicTitle: 'Topic',
  topicId: topicId,
  slug: 'topic',
  privateMessageTopic: false,
);

Future<ShellController> _shell(
  _IdentityApi api, {
  FakeAuthenticator? authenticator,
  DateTime Function()? clock,
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
    clock: clock,
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
  final mentionAnswers = <String, List<String>>{};
  final mentionReplies = <Completer<FoundUsersAndGroups>>[];
  List<FoundHashtag>? hashtagSearchAnswer;

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
    if (hashtagSearchAnswer case final answer?) return answer;
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
    userSearchesRequested.add((term: term, topicId: topicId));
    if (failSearch) throw StateError('search failed');
    final reply = mentionSearchTopicIds.length - 1;
    if (reply < mentionReplies.length) return mentionReplies[reply].future;
    if (mentionAnswers[term] case final names?) {
      return FoundUsersAndGroups(
        users: [for (final name in names) FoundUser(username: name)],
      );
    }
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
