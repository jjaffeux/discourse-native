import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/cached_image_bytes.dart';
import 'package:discourse_native/src/data/dashboard_api.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/data/report_api.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/plugin_api/dashboard_report_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _site = 'https://forum.example';
const _identity = SitePreferenceIdentity.site(_site);
const _list = OwnedSitePreferences(
  id: 'round3.list',
  scope: SitePreferenceScope.site,
  value: SitePreferenceValue.stringList,
);
const _text = OwnedSitePreferences(
  id: 'round3.text',
  scope: SitePreferenceScope.site,
  value: SitePreferenceValue.string,
);
const _report = DashboardReport(
  source: 'extension',
  identifier: '1',
  title: 'Extension',
  path: '/extension',
);
final _range = DashboardRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('queued typed preference writes own their submitted lists', () async {
    final backend = _HeldPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final blocker = _text.write(_identity, 'held');
    await backend.started.future;
    final submitted = ['accepted'];
    final saving = _list.write(_identity, submitted);
    submitted[0] = 'mutated';
    backend.release.complete();
    await Future.wait([blocker, saving]);
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(await _list.read(_identity), ['accepted']);
  });

  test(
    'retirement supervises every owner and still removes durable values',
    () async {
      const first = SitePreferenceKey('round3.first');
      final second = SitePreferenceKey(
        'round3.second',
        onForget: (_) => throw StateError('hook'),
      );
      final legacy = first.of(_site);
      SharedPreferences.setMockInitialValues({
        legacy: true,
        second.of(_site): true,
      });
      await _text.write(_identity, 'private');
      final failedOwner = Object();
      final nextOwner = Object();
      var firstCalls = 0;
      var nextCalls = 0;
      var finalCalls = 0;
      first.track(failedOwner, (_, _) {
        firstCalls++;
        throw StateError('observer');
      });
      first.track(nextOwner, (_, _) {
        nextCalls++;
      });
      final last = SitePreferenceKey(
        'round3.last',
        onForget: (_) {
          finalCalls++;
        },
      );
      await expectLater(
        forgetSitePreferences([
          first,
          second,
          last,
        ], () => ForgottenSites.removed(_site, keeping: [])),
        completes,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(firstCalls, 1);
      expect(nextCalls, 1);
      expect(finalCalls, 1);
      expect(preferences.containsKey(legacy), isFalse);
      expect(preferences.containsKey(second.of(_site)), isFalse);
      expect(await _text.read(_identity), isNull);
    },
  );

  for (final reserved in [false, true]) {
    test(
      'report composition rejects ${reserved ? 'core shadowing' : 'duplicate claims'}',
      () {
        final declarations = reserved
            ? [_Source('core_report')]
            : [_Source('extension'), _Source('extension')];
        expect(() => DashboardReportSources(declarations), throwsArgumentError);
      },
    );
  }

  test(
    'report adapters retain admitted source routing after caller mutation',
    () async {
      final transport = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [
                {'key': _report.key},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(transport.close);
      final declarations = <DashboardReportSource>[_Source('extension')];
      final sources = DashboardReportSources(declarations);
      final dashboard = DiscourseDashboardApi(transport, sources: sources);
      final detail = DiscourseReportApi(transport, sources: sources);
      declarations.clear();
      final reports = await dashboard.reports(
        siteUrl: _site,
        apiKey: 'key',
        clientId: '',
        range: _range,
        items: [_report],
      );
      final details = await detail.load(
        siteUrl: _site,
        apiKey: 'key',
        clientId: '',
        report: _report,
        range: _range,
        filters: {},
      );
      expect(reports[_report.key]!.value, 7);
      expect(details.result.value, 7);
    },
  );

  test(
    'cached public image values own bytes independently of their response',
    () {
      final response = http.Response.bytes([1, 2, 3], 200);
      final image = CachedImageBytes.fromResponse(response);
      response.bodyBytes[0] = 99;
      expect(image.bytes, [1, 2, 3]);
      expect(CachedImageBytes.fromResponse(response), same(image));
    },
  );

  test(
    'public media consumers share immutable bytes from one transfer',
    () async {
      var requests = 0;
      final pipeline = MediaPipeline(
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      addTearDown(pipeline.close);
      final avatarResult = pipeline.avatars.load('$_site/image');
      final emojiResult = pipeline.emoji.load('$_site/image');
      final avatar = (await avatarResult)!;
      final emoji = (await emojiResult)!;
      expect(() => avatar.bytes[0] = 99, throwsUnsupportedError);
      expect(emoji.bytes, [1, 2, 3]);
      expect(identical(avatar, emoji), isTrue);
      expect((await pipeline.avatars.load('$_site/image'))!.bytes, [1, 2, 3]);
      expect(requests, 1);
    },
  );
}

final class _HeldPreferences extends InMemorySharedPreferencesStore {
  _HeldPreferences() : super.withData({});
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

final class _Source implements DashboardReportSource {
  _Source(this.source);
  @override
  String get name => source;
  @override
  final String source;
  @override
  DashboardReportResult decode(Map<String, dynamic> payload) =>
      DashboardReportResult(total: 7);
  @override
  ReportApi createApi(PluginApiTransport transport) => _Details();
}

final class _Details implements ReportApi {
  @override
  Future<ReportDetails> load({
    required String siteUrl,
    required String apiKey,
    required String clientId,
    required DashboardReport report,
    required DashboardRange range,
    required Map<String, Object?> filters,
  }) async => ReportDetails(result: DashboardReportResult(total: 7));
}
