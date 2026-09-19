import 'dart:convert';
import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

void main() {
  final fixtures =
      (jsonDecode(File('js/test/chat-corpus.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
  final configuration = CookingConfiguration(
    modules: [
      for (final id in [
        'chat-source',
        'chat-slash-format',
        'chat-html-inline',
        'chat-transcript',
      ])
        CookingModule(id: id, owner: 'chat', version: '1'),
      CookingModule(
        id: 'discourse-local-dates',
        owner: 'discourse-local-dates',
        version: '1',
      ),
      for (final (index, id) in [
        'cooking-links',
        'cooking-bidi',
        'cooking-media',
        'cooking-mentions',
      ].indexed)
        CookingModule(
          id: id,
          owner: 'cooking',
          version: '1',
          order: 100 + index,
        ),
      CookingModule.spoiler,
      CookingModule.missingUploads,
    ],
  );
  late OfflineCookingService service;
  setUpAll(() => service = OfflineCookingService());
  tearDownAll(() => service.dispose());
  for (final fixture in fixtures) {
    test('pinned Chat rules: ${fixture['name']}', () async {
      final result = await service.cook(
        CookingRequest(
          raw: fixture['raw'] as String,
          profile: CookingProfile.values.byName(fixture['profile'] as String),
          configuration: configuration,
          snapshot: CookingSnapshot.fromJson({
            'siteId': 'a',
            'accountId': '7',
            'baseUrl': 'https://a.test',
            'context': fixture['context'],
            'pluginContext': {
              'discourse-local-dates': {
                'settings': {'discourse_local_dates_enabled': true},
              },
            },
            ...fixture['snapshot'] as Map<String, dynamic>,
          }),
        ),
      );
      expect(result.failure, isNull);
      if (fixture['html'] case final String html) expect(result.html, html);
      for (final value in fixture['includes'] as List? ?? []) {
        expect(result.html, contains(value));
      }
      for (final value in fixture['excludes'] as List? ?? []) {
        expect(result.html, isNot(contains(value)));
      }
    });
  }
  test('all frozen context fields change identity', () {
    final first = CookingRequest(
      raw: 'hello',
      snapshot: CookingSnapshot(siteId: 'a', accountId: '7'),
    );
    for (final context in [
      const CookingContext(authorId: -1),
      const CookingContext(editorId: 8),
      const CookingContext(locale: 'fr'),
      const CookingContext(asOfEpochMilliseconds: 1),
      const CookingContext(timezone: 'Europe/Paris'),
      const CookingContext(sourcePolicy: CookingSourcePolicy.submission),
    ]) {
      final next = CookingRequest(
        raw: 'hello',
        snapshot: CookingSnapshot(
          siteId: 'a',
          accountId: '7',
          context: context,
        ),
      );
      expect(next.fingerprint, isNot(first.fingerprint));
      expect(
        CookingRequest.fromJson(next.toJson()).fingerprint,
        next.fingerprint,
      );
    }
  });
  test('Unicode replacement stays bounded near the source limit', () async {
    final raw = '${'a' * 60000} 👨‍👩‍👧‍👦';
    final watch = Stopwatch()..start();
    final result = await service.cook(
      CookingRequest(
        raw: raw,
        profile: CookingProfile.chat,
        configuration: configuration,
        snapshot: CookingSnapshot(siteId: 'a', accountId: '7'),
      ),
    );
    expect(result.failure, isNull);
    expect(result.html, contains('family_man_woman_girl_boy'));
    expect(result.html, isNot(contains('‍')));
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'Worker stays under the existing real watchdog',
    );
  });
}
