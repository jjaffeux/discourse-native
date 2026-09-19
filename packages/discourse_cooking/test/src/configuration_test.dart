import 'dart:convert';
import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

void main() {
  CookingSnapshot snapshot({
    Map<String, Object?> settings = const {},
    Map<String, Object?> context = const {},
  }) => CookingSnapshot(
    siteId: 'site',
    accountId: 'account',
    siteSettings: settings,
    pluginContext: context,
  );
  test('snapshots have deterministic JSON and immutable nested values', () {
    final mutable = <String, Object?>{
      'z': [1, 2],
      'a': true,
    };
    final a = snapshot(settings: mutable),
        b = snapshot(
          settings: {
            'a': true,
            'z': [1, 2],
          },
        );
    mutable['a'] = false;
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect(
      CookingRequest(raw: 'hello', snapshot: a).fingerprint,
      CookingRequest(raw: 'hello', snapshot: b).fingerprint,
    );
    expect(() => (a.siteSettings['z'] as List).add(3), throwsUnsupportedError);
    expect(
      CookingRequest(
        raw: 'hello',
        snapshot: CookingSnapshot(
          siteId: 'site',
          accountId: 'account',
          accountGeneration: 1,
        ),
      ).fingerprint,
      isNot(CookingRequest(raw: 'hello', snapshot: a).fingerprint),
    );
  });
  test(
    'configuration validates module owners, duplicates and dependency graph',
    () {
      final mark = CookingModule(
        id: 'fixture-mark',
        owner: 'cooking-fixture',
        version: '1',
      );
      expect(
        () => CookingConfiguration(modules: [mark, mark]),
        throwsArgumentError,
      );
      expect(
        () => CookingConfiguration(modules: [mark], installedOwners: {'other'}),
        throwsArgumentError,
      );
      expect(
        () => CookingConfiguration(
          modules: [
            CookingModule(
              id: 'missing',
              owner: 'cooking-fixture',
              version: '1',
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CookingConfiguration(
          modules: [
            CookingModule(id: 'fixture-mark', owner: 'wrong', version: '1'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CookingConfiguration(
          modules: [
            CookingModule(
              id: 'fixture-mark',
              owner: 'cooking-fixture',
              version: '1',
              dependencies: ['absent'],
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CookingConfiguration(
          modules: [
            CookingModule(
              id: 'fixture-mark',
              owner: 'cooking-fixture',
              version: '1',
              dependencies: ['fixture-tokens'],
            ),
            CookingModule(
              id: 'fixture-tokens',
              owner: 'cooking-fixture',
              version: '1',
              dependencies: ['fixture-mark'],
            ),
          ],
        ),
        throwsArgumentError,
      );
      final config = CookingConfiguration(
        modules: [
          CookingModule(
            id: 'fixture-tokens',
            owner: 'cooking-fixture',
            version: '1',
            dependencies: ['fixture-mark'],
            order: -10,
          ),
          mark,
        ],
      );
      expect(config.modules.map((m) => m.id), [
        'fixture-mark',
        'fixture-tokens',
      ]);
    },
  );
  test(
    'bundled plugin syntax, token and document stages run through worker and final sanitizer',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final config = CookingConfiguration(
        modules: [
          ...CookingConfiguration().modules,
          CookingModule(
            id: 'fixture-mark',
            owner: 'cooking-fixture',
            version: '1',
          ),
          CookingModule(
            id: 'fixture-tokens',
            owner: 'cooking-fixture',
            version: '1',
            dependencies: ['fixture-mark'],
          ),
          CookingModule(
            id: 'fixture-document',
            owner: 'cooking-fixture',
            version: '1',
            dependencies: ['fixture-tokens'],
          ),
        ],
        installedOwners: {'cooking', 'cooking-fixture'},
      );
      final request = CookingRequest(
        raw: '==TOKEN==',
        snapshot: snapshot(
          context: {
            'cooking-fixture': {
              'replace': 'changed',
              'append':
                  '<mark data-fixture="tail" onclick="bad()">tail</mark><script>bad()</script><a href="javascript:bad()">bad</a>',
            },
          },
        ),
        configuration: config,
      );
      final result = await service.cook(request);
      expect(result.failure, isNull);
      expect(
        result.html,
        contains('<mark data-fixture="bundled">changed</mark>'),
      );
      expect(result.html, contains('<mark data-fixture="tail">tail</mark>'));
      expect(result.html, isNot(contains('onclick')));
      expect(result.html, isNot(contains('javascript:')));
      expect(result.html, isNot(contains('<script')));
      expect(result.requestFingerprint, request.fingerprint);
      expect(result.provisional, isTrue);
    },
  );
  test('profiles and declarations reject invalid configuration', () {
    expect(
      () => CookingProfile(name: 'x', settings: {'bad': double.nan}),
      throwsArgumentError,
    );
    expect(
      () => CookingProfile(name: 'x', features: List.filled(257, 'feature')),
      throwsArgumentError,
    );
    expect(
      () => CookingConfiguration(
        modules: [
          CookingModule(
            id: 'fixture-mark',
            owner: 'cooking-fixture',
            version: '1',
            profiles: ['unknown'],
          ),
        ],
      ),
      throwsArgumentError,
    );
    final dependencies = <String>[];
    final module = CookingModule(
      id: 'fixture-mark',
      owner: 'cooking-fixture',
      version: '1',
      dependencies: dependencies,
    );
    dependencies.add('changed');
    expect(module.dependencies, isEmpty);
    expect(() => module.dependencies.add('changed'), throwsUnsupportedError);
    expect(
      () => CookingConfiguration(
        modules: [
          CookingModule(
            id: 'fixture-mark',
            owner: 'cooking-fixture',
            version: '1',
            dependencies: ['fixture-document'],
          ),
          CookingModule(
            id: 'fixture-document',
            owner: 'cooking-fixture',
            version: '1',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
  test(
    'plugin profile and setting gates extend Chat through actual worker',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final config = CookingConfiguration(
        modules: [
          ...CookingConfiguration().modules,
          CookingModule(
            id: 'fixture-mark',
            owner: 'cooking-fixture',
            version: '1',
            profiles: ['chat'],
            enabledSetting: 'enabled',
          ),
          CookingModule(
            id: 'fixture-tokens',
            owner: 'cooking-fixture',
            version: '1',
            profiles: ['chat'],
            dependencies: ['fixture-mark'],
          ),
        ],
      );
      Future<CookingResult> cook(CookingProfile profile, bool enabled) =>
          service.cook(
            CookingRequest(
              raw: '==TOKEN==',
              profile: profile,
              configuration: config,
              snapshot: snapshot(
                context: {
                  'cooking-fixture': {
                    'replace': 'changed',
                    'settings': {'enabled': enabled},
                  },
                },
              ),
            ),
          );
      expect(
        (await cook(CookingProfile.chat, true)).html,
        contains('<mark data-fixture="bundled">changed</mark>'),
      );
      expect((await cook(CookingProfile.chat, false)).html, '<p>==TOKEN==</p>');
      expect((await cook(CookingProfile.post, true)).html, '<p>==TOKEN==</p>');
    },
  );
  test(
    'known hashtags retain Native rendering metadata after final policy',
    () async {
      final service = OfflineCookingService();
      addTearDown(service.dispose);
      final result = await service.cook(
        CookingRequest(
          raw: '#icon #emoji',
          snapshot: CookingSnapshot(
            siteId: 'site',
            accountId: 'account',
            hashtags: {
              'icon': {
                'relative_url': '/c/icon/1',
                'type': 'category',
                'slug': 'icon',
                'id': 1,
                'ref': 'icon',
                'text': 'Icon',
                'style_type': 'icon',
                'icon': 'folder',
              },
              'emoji': {
                'relative_url': '/c/emoji/2',
                'type': 'category',
                'slug': 'emoji',
                'id': 2,
                'ref': 'emoji',
                'text': 'Emoji',
                'style_type': 'emoji',
                'emoji': 'smile',
              },
            },
          ),
        ),
      );
      expect(result.failure, isNull);
      expect(result.html, contains('data-style-type="icon"'));
      expect(result.html, contains('data-icon="folder"'));
      expect(result.html, contains('data-style-type="emoji"'));
      expect(result.html, contains('data-emoji="smile"'));
    },
  );
}
