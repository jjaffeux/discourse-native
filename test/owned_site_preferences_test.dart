import 'dart:async';

import 'package:discourse_native/src/data/bookmark_reminder_store.dart';
import 'package:discourse_native/src/data/recent_search_store.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _short = 'https://a.b';
const _long = 'https://a.b.c';
const _identity = SitePreferenceIdentity.account(_short, 'c.d');
const _data = OwnedSitePreferences(
  id: 'test.owned',
  scope: SitePreferenceScope.account,
  value: SitePreferenceValue.string,
  operation: 'testOwned',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DiagnosticsController diagnostics;
  late DiagnosticsSinkBinding binding;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'owned-preferences',
    );
    binding = DiagnosticsSink.install(diagnostics);
  });
  tearDown(() async {
    binding.close();
    await diagnostics.close();
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'versioned identities separate scope, dotted URLs and accounts',
    () async {
      const siteData = OwnedSitePreferences(
        id: 'test.owned',
        scope: SitePreferenceScope.site,
        value: SitePreferenceValue.string,
        operation: 'testOwned',
      );
      final identities = [
        _identity,
        const SitePreferenceIdentity.account(_long, 'd'),
        const SitePreferenceIdentity.account(_short, 'other'),
        const SitePreferenceIdentity.account('https://a.b/forum.old', '名.字'),
        const SitePreferenceIdentity.account(_short, ''),
      ];
      expect(
        identities.map(_data.keyFor).toSet(),
        hasLength(identities.length),
      );
      expect(
        siteData.keyFor(const SitePreferenceIdentity.site(_short)),
        isNot(_data.keyFor(identities.last)),
      );
      for (var index = 0; index < identities.length; index++) {
        await _data.write(identities[index], '$index');
      }
      for (var index = 0; index < identities.length; index++) {
        expect(await _data.read(identities[index]), '$index');
      }
      expect(
        () => _data.keyFor(const SitePreferenceIdentity.site(_short)),
        throwsArgumentError,
      );
    },
  );

  test(
    'both stores migrate twice without overwriting newer exact values',
    () async {
      const bookmark = BookmarkReminderStore();
      const search = RecentSearchStore();
      final oldBookmark = '${BookmarkReminderStore.keys.of(_short)}.reader';
      final oldSearch = '${RecentSearchStore.keys.of(_short)}.Reader';
      SharedPreferences.setMockInitialValues({
        oldBookmark: '2030-01-02T03:04:05+01:00',
        oldSearch: <String>['first'],
      });
      for (var repeat = 0; repeat < 2; repeat++) {
        expect(
          await bookmark.read(_short, 'Reader'),
          DateTime.utc(2030, 1, 2, 2, 4, 5),
        );
        expect(await search.read(_short, 'Reader'), {'first'});
      }
      await bookmark.write(_short, 'Reader', DateTime.utc(2031));
      await search.write(_short, 'Reader', {});
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      for (var repeat = 0; repeat < 2; repeat++) {
        expect(await bookmark.read(_short, 'reader'), DateTime.utc(2031));
        expect(await search.read(_short, 'Reader'), isEmpty);
      }
      expect(preferences.getString(oldBookmark), '2030-01-02T03:04:05+01:00');
      expect(preferences.getStringList(oldSearch), ['first']);
      expect(
        await search.read(_short, 'reader'),
        isEmpty,
        reason:
            'Recent searches retain their existing exact username spelling.',
      );
    },
  );

  test('exact removal keeps ambiguous legacy keys for a kept forum', () async {
    const search = RecentSearchStore();
    final ambiguous = '${RecentSearchStore.keys.of(_short)}.c.d';
    SharedPreferences.setMockInitialValues({
      ambiguous: <String>['legacy'],
    });
    await search.read(_short, 'c.d');
    await search.write(_long, 'd', {'kept'});
    await forgetSitePreferences([
      RecentSearchStore.keys,
    ], () => ForgottenSites.removed(_short, keeping: [_long]));
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.getStringList(ambiguous), ['legacy']);
    expect(
      preferences.containsKey(RecentSearchStore.preferences.keyFor(_identity)),
      isFalse,
    );
    expect(await search.read(_long, 'd'), {'kept'});
  });

  test(
    'cold cleanup covers unknown modern stores and preserves unknown versions',
    () async {
      final key = _data.keyFor(_identity);
      final unknownVersion = key.replaceFirst('.v1.', '.v99.');
      const malformed = 'discourse_native.site.v1.invalid!';
      SharedPreferences.setMockInitialValues({
        key: 'old',
        unknownVersion: 'future',
        malformed: 'unknown',
      });
      await forgetSitePreferences(
        [],
        () => ForgottenSites.removed(_short, keeping: []),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(key), isFalse);
      expect(preferences.getString(unknownVersion), 'future');
      expect(preferences.getString(malformed), 'unknown');
    },
  );

  for (final freshWrite in [false, true]) {
    test(
      'removal orders admitted writes, queued writes and re-add $freshWrite',
      () async {
        final backend = _ControlledPreferences({})..holdWrites = true;
        SharedPreferencesStorePlatform.instance = backend;
        addTearDown(() {
          if (!backend.release.isCompleted) backend.release.complete();
        });
        final admitted = _data.write(_identity, 'admitted');
        await backend.started.future;
        final queued = _data.write(_identity, 'old queued');
        final retired = Completer<void>();
        final key = SitePreferenceKey(
          'test.retirement',
          onForget: (_) => retired.complete(),
        );
        final removal = forgetSitePreferences([
          key,
        ], () => ForgottenSites.removed(_short, keeping: []));
        await retired.future;
        final fresh = freshWrite
            ? _data.write(_identity, 'fresh')
            : Future<void>.value();
        backend.holdWrites = false;
        backend.release.complete();
        await Future.wait([admitted, queued, removal, fresh]);
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        expect(await _data.read(_identity), freshWrite ? 'fresh' : isNull);
        expect(
          backend.values,
          freshWrite ? ['admitted', 'fresh'] : ['admitted'],
        );
      },
    );
  }

  test('a declined removal leaves generations and values intact', () async {
    await _data.write(_identity, 'kept');
    await forgetSitePreferences([], () => null);
    expect(await _data.read(_identity), 'kept');
  });

  test(
    'a rejected write cannot overwrite a different site pending cache',
    () async {
      const other = SitePreferenceIdentity.account(
        'https://other.example',
        'sam',
      );
      final backend = _ControlledPreferences({});
      SharedPreferencesStorePlatform.instance = backend;
      await _data.write(_identity, 'accepted');
      backend.holdWrites = true;
      final pending = _data.write(other, 'other');
      await backend.started.future;
      backend.holdWrites = false;
      backend.reject = true;
      await _data.write(_identity, 'rejected');
      backend.reject = false;
      backend.release.complete();
      await pending;
      expect(await _data.read(_identity), 'accepted');
      expect(await _data.read(other), 'other');
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(preferences.getString(_data.keyFor(_identity)), 'accepted');
      expect(preferences.getString(_data.keyFor(other)), 'other');
    },
  );

  for (final throwsError in [false, true]) {
    test(
      'failed permanent removal retries keys no longer in cache $throwsError',
      () async {
        final backend = _ControlledPreferences({});
        SharedPreferencesStorePlatform.instance = backend;
        await _data.write(_identity, 'old');
        backend.reject = !throwsError;
        backend.failure = throwsError
            ? PlatformException(code: 'unavailable')
            : null;
        await forgetSitePreferences(
          [],
          () => ForgottenSites.removed(_short, keeping: []),
        );
        expect(
          (await backend.getAll())['flutter.${_data.keyFor(_identity)}'],
          'old',
        );
        final event = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .single;
        expect(event.operation, 'sitePreferences.forget');
        backend.reject = false;
        backend.failure = null;
        await forgetSitePreferences(
          [],
          () => ForgottenSites.removed(_short, keeping: []),
        );
        expect(
          (await backend.getAll()).containsKey(
            'flutter.${_data.keyFor(_identity)}',
          ),
          isFalse,
        );
      },
    );
    test(
      'migration ${throwsError ? 'exception' : 'rejection'} retains legacy and retries',
      () async {
        final oldKey = '${RecentSearchStore.keys.of(_short)}.sam';
        final backend =
            _ControlledPreferences({
                'flutter.$oldKey': <String>['legacy'],
              })
              ..reject = !throwsError
              ..failure = throwsError
                  ? PlatformException(code: 'unavailable')
                  : null;
        SharedPreferencesStorePlatform.instance = backend;
        const store = RecentSearchStore();
        expect(await store.read(_short, 'sam'), {'legacy'});
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().single.operation,
          'recentSearch.migrate',
        );
        backend.reject = false;
        backend.failure = null;
        for (var repeat = 0; repeat < 2; repeat++) {
          expect(await store.read(_short, 'sam'), {'legacy'});
        }
        expect(backend.values, hasLength(2));
        expect((await backend.getAll())['flutter.$oldKey'], ['legacy']);
      },
    );
    test(
      'recent-search write ${throwsError ? 'exception' : 'rejection'} reports storage failure',
      () async {
        final backend = _ControlledPreferences({})
          ..reject = !throwsError
          ..failure = throwsError
              ? PlatformException(code: 'unavailable')
              : null;
        SharedPreferencesStorePlatform.instance = backend;
        await const RecentSearchStore().write(_short, 'sam', {'term'});
        final event = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .single;
        expect(event.operation, 'recentSearch.write');
        expect(event.source, 'storage');
        expect(event.degraded, isTrue);
        expect(event.handled, isTrue);
      },
    );
  }
}

final class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences(super.data) : super.withData();
  bool holdWrites = false;
  bool reject = false;
  Object? failure;
  final started = Completer<void>();
  final release = Completer<void>();
  final values = <Object>[];
  @override
  Future<bool> remove(String key) {
    if (failure case final error?) return Future.error(error);
    return reject ? Future.value(false) : super.remove(key);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    values.add(value);
    if (holdWrites) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    if (failure case final error?) throw error;
    return reject ? false : super.setValue(valueType, key, value);
  }
}
