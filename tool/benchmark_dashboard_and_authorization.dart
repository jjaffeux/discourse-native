import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils;
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/dashboard_api.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/shell/dashboard_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';

import '../test/support/dashboard_fixture.dart';

const _site = 'https://forum.example';
const _registrationLatency = Duration(milliseconds: 55);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  stdout.writeln(
    jsonEncode({
      'authorize_with_push_registration': await _median(_authorize),
      'refresh_dashboard_period_comparison': await _median(_dashboard),
    }),
  );
  exit(0);
}

Future<int> _median(Future<int> Function() operation) async {
  final times = <int>[];
  for (var sample = 0; sample < 9; sample++) {
    final time = await operation();
    if (sample >= 2) times.add(time);
  }
  times.sort();
  return times[times.length ~/ 2];
}

Future<int> _authorize() async {
  final registration = _PushRegistration();
  final client = _ClientPersistence();
  var launches = 0;
  final authenticator = Authenticator(
    store: SecureStore(pushClientIds: client),
    pushRegistrations: registration,
    applicationName: 'Discourse Native',
    launcher: (url, scheme) async {
      launches++;
      final query = Uri.parse(url).queryParameters;
      if (query['client_id'] != 'platform-push-client' ||
          query['push_url'] != 'https://push.example/') {
        throw StateError('Authorization omitted the registered push identity');
      }
      final publicKey = CryptoUtils.rsaPublicKeyFromPem(query['public_key']!);
      final encrypted = PKCS1Encoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      final payload = base64Encode(
        encrypted.process(
          utf8.encode(
            jsonEncode({
              'key': 'test-api-key',
              'nonce': query['nonce'],
              'api': 4,
              'push': true,
            }),
          ),
        ),
      );
      return Uri(
        scheme: scheme,
        host: 'auth_redirect',
        queryParameters: {'payload': payload},
      ).toString();
    },
  );
  final watch = Stopwatch()..start();
  final credential = await authenticator.authorize(_site);
  watch.stop();
  if (credential.key != 'test-api-key' ||
      !credential.push ||
      client.value != 'platform-push-client' ||
      registration.requests != 1 ||
      launches != 1) {
    throw StateError('Authorization did not complete');
  }
  return watch.elapsedMicroseconds;
}

Future<int> _dashboard() async {
  final now = DateTime(2026, 10, 25);
  final range = DashboardPeriod.last30Days.rangeAt(now);
  final seen = <String>[];
  final transport = DiscourseApi(
    client: MockClient((request) async {
      if (request.headers['user-api-key'] != 'staff-key') {
        throw StateError('Dashboard request lost its staff identity');
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (request.url.path == '/admin/dashboard.json') {
        seen.add('dashboard');
        return http.Response(jsonEncode(dashboardFixture), 200);
      }
      if (request.url.path != '/admin/dashboard/reports/bulk.json') {
        throw StateError('Unexpected dashboard route');
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final filters = body['filters'] as Map<String, dynamic>;
      final from = filters['start_date'];
      final prior = from == range.previous.query['start_date'];
      if (!prior && from != range.query['start_date'] ||
          (body['items'] as List<Object?>).length != 2) {
        throw StateError('Wrong report range or requested items');
      }
      seen.add(prior ? 'previous' : 'current');
      return http.Response(
        jsonEncode({
          'items': [
            for (final identifier in [
              'daily_engaged_users',
              'time_to_first_response',
            ])
              {
                'key': 'core_report:$identifier',
                'data': {
                  'data': [
                    {'x': from, 'y': prior ? 10 : 15},
                  ],
                },
              },
          ],
        }),
        200,
      );
    }),
  );
  final lifecycle = SiteLifecycle();
  final controller = DashboardController(
    api: DiscourseDashboardApi(transport),
    credentials: const _StaffCredentials(),
    lease: lifecycle.capture(_site),
    siteUrl: _site,
    staff: true,
    admin: true,
    now: () => now,
  );
  try {
    final watch = Stopwatch()..start();
    await controller.refresh();
    watch.stop();
    final state = controller.state;
    final report = state.reports['core_report:daily_engaged_users'];
    if (state.loading ||
        state.error ||
        state.snapshot == null ||
        state.reports.length != 2 ||
        report?.value != 15 ||
        report?.previousValue != 10 ||
        report?.change != 50 ||
        seen.length != 3 ||
        !seen.toSet().containsAll(['dashboard', 'current', 'previous'])) {
      throw StateError('Dashboard did not publish compared report values');
    }
    return watch.elapsedMicroseconds;
  } finally {
    controller.dispose();
    lifecycle.close();
    transport.close();
  }
}

final class _StaffCredentials implements ApiCredentialReader {
  const _StaffCredentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'staff-key';

  @override
  Future<String> clientId() async => '';
}

final class _PushRegistration implements PushRegistrationProvider {
  int requests = 0;

  @override
  Future<PushRegistration?> registration() async {
    requests++;
    await Future<void>.delayed(_registrationLatency);
    return const PushRegistration(
      clientId: 'platform-push-client',
      pushUrl: 'https://push.example/',
    );
  }
}

final class _ClientPersistence implements ClientIdPersistence {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
