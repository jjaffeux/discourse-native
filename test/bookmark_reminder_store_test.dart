import 'package:discourse_native/src/data/bookmark_reminder_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Fault injection at shared_preferences' platform boundary is test-only.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _site = 'https://one.example';
const _key = 'bookmark.last-custom.https%3A%2F%2Fone.example.reader';
const _privateValue = 'private reminder preference sentinel';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = BookmarkReminderStore();
  late DiagnosticsController diagnostics;
  late DiagnosticsSinkBinding binding;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'bookmark-reminder-preferences',
    );
    binding = DiagnosticsSink.install(diagnostics);
  });

  tearDown(() async {
    binding.close();
    await diagnostics.close();
    SharedPreferences.setMockInitialValues({});
  });

  test('missing choices decode as absent without a warning', () async {
    expect(await store.read(_site, 'reader'), isNull);
    expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), isEmpty);
  });

  test('last custom reminders are isolated by site and account', () async {
    final reminder = DateTime.parse('2030-01-02T03:04:05+01:00');

    await store.write('https://one.example', 'Reader', reminder);

    expect(
      await store.read('https://one.example', 'reader'),
      DateTime.utc(2030, 1, 2, 2, 4, 5),
    );
    expect(await store.read('https://two.example', 'reader'), isNull);
    expect(await store.read('https://one.example', 'someone-else'), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(_key),
      '2030-01-02T02:04:05.000Z',
    );
    expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), isEmpty);
  });

  test('malformed persisted choices decode as absent', () async {
    SharedPreferences.setMockInitialValues({_key: 'not-a-date'});

    expect(await store.read(_site, 'reader'), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(_key),
      'not-a-date',
    );
    expect(diagnostics.events.whereType<ErrorDiagnosticEvent>(), isEmpty);
  });

  for (final (type, value) in <(String, Object)>[
    ('bool', true),
    ('int', 42),
    ('double', 1.5),
    ('list', <String>[_privateValue]),
  ]) {
    test('$type choices are reported as absent without overwriting', () async {
      SharedPreferences.setMockInitialValues({
        _key: value,
        'unrelated': 'kept',
      });

      expect(await store.read(_site, 'reader'), isNull);

      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(preferences.get(_key), value);
      expect(preferences.getString('unrelated'), 'kept');
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        _isStorageWarning('bookmarkReminders.read'),
      );
      expect(diagnostics.buildJsonReport(), isNot(contains(_privateValue)));
      expect(diagnostics.buildJsonReport(), isNot(contains(_key)));
    });
  }

  test(
    'platform read failures are reported and can retry without writing',
    () async {
      final preferences =
          _ControlledPreferences({'flutter.$_key': '2030-01-02T03:04:05+01:00'})
            ..readError = PlatformException(
              code: 'unavailable',
              message: 'api_key="$_privateValue"',
            );
      SharedPreferencesStorePlatform.instance = preferences;

      expect(await store.read(_site, 'reader'), isNull);
      expect(preferences.writes, isEmpty);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        _isStorageWarning('bookmarkReminders.read'),
      );
      expect(diagnostics.buildJsonReport(), isNot(contains(_privateValue)));

      preferences.readError = null;
      final reminder = await store.read(_site, 'reader');
      expect(reminder, DateTime.utc(2030, 1, 2, 2, 4, 5));
      expect(reminder!.isUtc, isTrue);
      expect(preferences.writes, isEmpty);
    },
  );

  test(
    'a write handles failure to open preferences without overwriting',
    () async {
      final preferences =
          _ControlledPreferences({'flutter.$_key': '2030-01-02T03:04:05Z'})
            ..readError = PlatformException(
              code: 'unavailable',
              message: 'api_key="$_privateValue"',
            );
      SharedPreferencesStorePlatform.instance = preferences;

      await store.write(_site, 'reader', DateTime.utc(2030, 2, 3));

      expect(preferences.writes, isEmpty);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        _isStorageWarning('bookmarkReminders.write'),
      );
      expect(diagnostics.buildJsonReport(), isNot(contains(_privateValue)));
      preferences.readError = null;
      expect(
        await store.read(_site, 'reader'),
        DateTime.utc(2030, 1, 2, 3, 4, 5),
      );
    },
  );

  for (final throwsError in [true, false]) {
    test(
      'platform write ${throwsError ? 'exceptions' : 'rejections'} are reported without throwing',
      () async {
        final preferences =
            _ControlledPreferences({
                'flutter.$_key': '2030-01-02T03:04:05Z',
                'flutter.unrelated': 'kept',
              })
              ..acceptWrites = false
              ..writeError = throwsError
                  ? PlatformException(
                      code: 'unavailable',
                      message: 'api_key="$_privateValue"',
                    )
                  : null;
        SharedPreferencesStorePlatform.instance = preferences;

        await store.write(
          _site,
          'Reader',
          DateTime.parse('2030-02-03T04:05:06+01:00'),
        );

        expect(preferences.writes, [
          (
            type: 'String',
            key: 'flutter.$_key',
            value: '2030-02-03T03:05:06.000Z',
          ),
        ]);
        final event = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .single;
        expect(event, _isStorageWarning('bookmarkReminders.write'));
        expect(
          event.errorType,
          throwsError ? 'PlatformException' : 'StateError',
        );
        expect(diagnostics.buildJsonReport(), isNot(contains(_privateValue)));
        final cached = await SharedPreferences.getInstance();
        await cached.reload();
        expect(cached.getString(_key), '2030-01-02T03:04:05Z');
        expect(cached.getString('unrelated'), 'kept');
      },
    );
  }
}

Matcher _isStorageWarning(String operation) => isA<ErrorDiagnosticEvent>()
    .having((event) => event.operation, 'operation', operation)
    .having((event) => event.source, 'source', 'storage')
    .having((event) => event.severity, 'severity', DiagnosticSeverity.warning)
    .having((event) => event.handled, 'handled', isTrue)
    .having((event) => event.degraded, 'degraded', isTrue);

final class _ControlledPreferences extends InMemorySharedPreferencesStore {
  _ControlledPreferences(super.data) : super.withData();

  Object? readError;
  Object? writeError;
  bool acceptWrites = true;
  final writes = <({String type, String key, Object value})>[];

  @override
  Future<Map<String, Object>> getAll() async {
    if (readError case final error?) throw error;
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add((type: valueType, key: key, value: value));
    if (writeError case final error?) throw error;
    if (!acceptWrites) return false;
    return super.setValue(valueType, key, value);
  }
}
