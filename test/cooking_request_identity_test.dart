import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity retains canonical context and source hash inputs', () {
    final request = _request(raw: '你好 **hello** 😀');
    final context = cookingFingerprint({
      'snapshot': request.snapshot.toJson(),
      'profile': request.profile.toJson(),
      'configuration': request.effectiveConfiguration.toJson(),
      'engine': cookingEngineRevision,
      'bundle': cookingBundleRevision,
    });
    final fingerprint = cookingFingerprint({
      'context': context,
      'raw': request.raw,
    });
    for (var i = 0; i < 3; i++) {
      expect(request.contextFingerprint, context);
      expect(request.fingerprint, fingerprint);
    }

    final edited = CookingRequest(
      raw: 'different source',
      snapshot: request.snapshot,
      profile: request.profile,
      configuration: request.configuration,
    );
    expect(edited.contextFingerprint, context);
    expect(edited.fingerprint, isNot(fingerprint));
  });

  test('repeated identity reads reuse the immutable digest strings', () {
    final request = _request();
    final context = request.contextFingerprint;
    final fingerprint = request.fingerprint;
    for (var i = 0; i < 3; i++) {
      expect(request.contextFingerprint, same(context));
      expect(request.fingerprint, same(fingerprint));
    }
  });

  test('all request context dimensions keep distinct identities', () {
    final original = _request();
    final variants = <String, CookingRequest>{
      'site': _request(siteId: 'other-site'),
      'account': _request(accountId: 'other-account'),
      'generation': _request(accountGeneration: 2),
      'profile': _request(profile: CookingProfile.chat),
      'configuration': _request(
        configuration: CookingConfiguration(
          modules: const [CookingModule.spoiler],
        ),
      ),
      'context': _request(context: const CookingContext(locale: 'fr')),
      'metadata': _request(siteSettings: const {'enable_emoji': false}),
    };
    for (final entry in variants.entries) {
      expect(
        entry.value.contextFingerprint,
        isNot(original.contextFingerprint),
        reason: entry.key,
      );
      expect(
        entry.value.fingerprint,
        isNot(original.fingerprint),
        reason: entry.key,
      );
    }
  });

  test('identity survives reordered JSON and a serialized round trip', () {
    final request = _request(
      siteSettings: const {
        'nested': {
          'z': [2, 1],
          'a': true,
        },
        'enable_emoji': true,
      },
    );
    final context = request.contextFingerprint;
    final fingerprint = request.fingerprint;
    final decoded = (jsonDecode(jsonEncode(request.toJson())) as Map)
        .cast<String, Object?>();
    final restored = CookingRequest.fromJson(
      _reverseMapOrder(decoded) as Map<String, Object?>,
    );
    expect(restored.toJson(), request.toJson());
    expect(restored.contextFingerprint, context);
    expect(restored.fingerprint, fingerprint);
    expect(request.toJson().keys, [
      'raw',
      'profile',
      'configuration',
      'snapshot',
    ]);
  });

  test('input and serialization mutations cannot alter request identity', () {
    final ids = <Object?>[1, 2];
    final mentions = <String, Object?>{
      'alice': <String, Object?>{'ids': ids},
    };
    final features = <String>['mentions'];
    final rules = <String>['link'];
    final settings = <String, Object?>{'enable_emoji': true};
    final profile = CookingProfile(
      name: 'custom',
      features: features,
      rules: rules,
      settings: settings,
    );
    final modules = <CookingModule>[CookingModule.spoiler];
    final profiles = <CookingProfile>[profile];
    final request = CookingRequest(
      raw: '@alice',
      snapshot: CookingSnapshot(
        siteId: 'site',
        accountId: 'account',
        mentions: mentions,
      ),
      profile: profile,
      configuration: CookingConfiguration(modules: modules, profiles: profiles),
    );
    final originalJson = jsonEncode(request.toJson());
    final context = request.contextFingerprint;
    final fingerprint = request.fingerprint;
    ids[0] = 9;
    mentions.clear();
    features.clear();
    rules.clear();
    settings.clear();
    modules.clear();
    profiles.clear();

    final serialized = request.toJson();
    serialized['raw'] = 'changed';
    final snapshotJson = serialized['snapshot']! as Map<String, Object?>;
    snapshotJson['accountId'] = 'changed';
    (snapshotJson['context']! as Map<String, Object?>)['locale'] = 'fr';
    final profileJson = serialized['profile']! as Map<String, Object?>;
    profileJson['name'] = 'changed';
    final configurationJson =
        serialized['configuration']! as Map<String, Object?>;
    (configurationJson['modules']! as List).clear();
    expect(
      () => (request.snapshot.mentions['alice']! as Map)['ids'] = <Object?>[],
      throwsUnsupportedError,
    );
    expect(() => request.profile.features!.clear(), throwsUnsupportedError);
    expect(() => request.profile.settings.clear(), throwsUnsupportedError);
    expect(jsonEncode(request.toJson()), originalJson);
    expect(request.contextFingerprint, context);
    expect(request.fingerprint, fingerprint);
    final restored = CookingRequest.fromJson(request.toJson());
    expect(restored.contextFingerprint, context);
    expect(restored.fingerprint, fingerprint);
  });

  test(
    'worker results retain identity through cache and invalidation',
    () async {
      final host = CookingHostService(
        runtimeFactory: () => OfflineCookingService(
          limits: const CookingLimits(maxRequestBytes: 8192),
        ),
      );
      addTearDown(host.dispose);
      final request = _request(raw: 'A **native** offline cook');
      final first = await host.cook(request);
      expect(first.failure, isNull);
      expect(first.html, '<p>A <strong>native</strong> offline cook</p>');
      expect(first.contextFingerprint, request.contextFingerprint);
      expect(first.requestFingerprint, request.fingerprint);
      expect(
        await host.cook(CookingRequest.fromJson(request.toJson())),
        same(first),
      );
      expect(host.cachedResultCount, 1);

      host.invalidate();
      expect(host.cachedResultCount, 0);
      final fresh = await host.cook(request);
      expect(fresh, isNot(same(first)));
      expect(fresh.html, first.html);
      expect(fresh.contextFingerprint, first.contextFingerprint);
      expect(fresh.requestFingerprint, first.requestFingerprint);

      final overBudget = _request(raw: 'x' * 9000);
      final failure = await host.cook(overBudget);
      final retried = await host.cook(overBudget);
      expect(failure.failure, CookingFailure.inputLimit);
      expect(retried.failure, CookingFailure.inputLimit);
      expect(retried, isNot(same(failure)));
      expect(failure.contextFingerprint, overBudget.contextFingerprint);
      expect(failure.requestFingerprint, overBudget.fingerprint);
      expect(host.cachedResultCount, 1);

      final oversized = await host.cook(_request(raw: 'x' * 65537));
      expect(oversized.failure, CookingFailure.inputLimit);
      expect(oversized.requestFingerprint, isNull);
      expect(oversized.contextFingerprint, isNull);
    },
  );
}

CookingRequest _request({
  String raw = '**hello**',
  String siteId = 'site',
  String accountId = 'account',
  int accountGeneration = 1,
  CookingProfile profile = CookingProfile.post,
  CookingConfiguration? configuration,
  CookingContext context = const CookingContext(),
  Map<String, Object?> siteSettings = const {},
}) => CookingRequest(
  raw: raw,
  snapshot: CookingSnapshot(
    siteId: siteId,
    accountId: accountId,
    accountGeneration: accountGeneration,
    context: context,
    siteSettings: siteSettings,
  ),
  profile: profile,
  configuration: configuration,
);

Object? _reverseMapOrder(Object? value) => switch (value) {
  Map<String, Object?>() => {
    for (final entry in value.entries.toList().reversed)
      entry.key: _reverseMapOrder(entry.value),
  },
  List<Object?>() => value.map(_reverseMapOrder).toList(),
  _ => value,
};
