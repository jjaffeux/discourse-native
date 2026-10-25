import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/dashboard.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/dashboard_host.dart';
import 'package:discourse_native/src/shell/dashboard_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/dashboard_fixture.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const siteUrl = 'https://forum.example/discuss';
const staff = DiscourseUser(id: 7, username: 'sam', staff: true, admin: true);

class DashboardTestApi extends FakeDiscourseApi {
  DashboardTestApi() : super(user: staff);
  int requests = 0;
  Completer<Map<String, dynamic>>? dashboardGate;
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (Uri.parse(path).path == '/admin/dashboard.json') {
      requests++;
      return dashboardGate?.future ?? dashboardFixture;
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (path == '/admin/dashboard/reports/bulk.json') {
      return dashboardReportsFixture;
    }
    return super.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }
}

void main() {
  const channel = MethodChannel('org.discourse.native/notification_opens');
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          if (call.method == 'launch') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            launched.add(arguments['url'] as String);
          }
          return true;
        });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(launcher, null);
  });
  test('dashboard links distinguish server URLs from generated app paths', () {
    expect(
      dashboardLinkUrl(
        siteUrl,
        const DashboardLink.server('/discuss/t/sailing/42'),
      ),
      '$siteUrl/t/sailing/42',
    );
    expect(
      dashboardLinkUrl(siteUrl, const DashboardLink.app('/admin/dashboard')),
      '$siteUrl/admin/dashboard',
    );
    expect(
      dashboardLinkUrl(siteUrl, const DashboardLink.app('/search?q=sailing')),
      '$siteUrl/search?q=sailing',
    );
    expect(
      dashboardLinkUrl(
        'https://forum.example/c',
        const DashboardLink.app('/c/7'),
      ),
      'https://forum.example/c/c/7',
    );
    expect(
      dashboardLinkUrl(
        'https://forum.example/search',
        const DashboardLink.app('/search?q=sailing'),
      ),
      'https://forum.example/search/search?q=sailing',
    );
    expect(
      dashboardLinkUrl(
        siteUrl,
        const DashboardLink.server('https://other.example/page'),
      ),
      'https://other.example/page',
    );
  });
  testWidgets(
    'server entry links stay native and admin fallbacks open mounted URLs',
    (tester) async {
      final api = DashboardTestApi();
      final auth = FakeAuthenticator()..keys[siteUrl] = 'staff-key';
      await pumpShell(
        tester,
        desktop,
        api: api,
        authenticator: auth,
        instances: const [
          DiscourseInstance(url: siteUrl, title: 'Forum', user: staff),
        ],
      );
      final shell = ShellScope.read(tester.element(primaryMainContent));
      shell.openCorePageUrl('$siteUrl/admin/dashboard');
      await tester.pumpAndSettle();
      var page = tester.widget<DashboardPage>(find.byType(DashboardPage));
      page.onOpenUrl(const DashboardLink.app('/admin/dashboard'));
      await tester.pumpAndSettle();
      expect(launched, ['$siteUrl/admin/dashboard']);
      expect(find.byType(DashboardPage), findsOneWidget);
      page.onOpenUrl(const DashboardLink.server('/discuss/t/sailing/42'));
      await tester.pumpAndSettle();
      expect(api.topicsOpened, contains(42));
      expect(launched, ['$siteUrl/admin/dashboard']);
      shell.openCorePageUrl('$siteUrl/admin/dashboard');
      await tester.pumpAndSettle();
      page = tester.widget<DashboardPage>(find.byType(DashboardPage));
      page.onOpenUrl(const DashboardLink.server('https://other.example/page'));
      await tester.pumpAndSettle();
      expect(launched.last, 'https://other.example/page');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  for (final platform in [TargetPlatform.linux, TargetPlatform.iOS]) {
    testWidgets(
      'staff dashboard route and shell refresh are native on $platform',
      (tester) async {
        final api = DashboardTestApi();
        final auth = FakeAuthenticator()..keys[siteUrl] = 'staff-key';
        await pumpShell(
          tester,
          platform == TargetPlatform.iOS ? phone : desktop,
          api: api,
          authenticator: auth,
          instances: const [
            DiscourseInstance(url: siteUrl, title: 'Forum', user: staff),
          ],
        );
        final shell = ShellScope.read(tester.element(primaryMainContent));
        expect(shell.openCorePageUrl('$siteUrl/admin/dashboard'), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(DashboardHost), findsOneWidget);
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(find.text('128'), findsOneWidget);
        expect(api.requests, 1);
        await shell.refreshCurrentTab();
        await tester.pumpAndSettle();
        expect(api.requests, 2);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
  testWidgets(
    'disconnect retires a mounted dashboard before its response arrives',
    (tester) async {
      final api = DashboardTestApi()
        ..dashboardGate = Completer<Map<String, dynamic>>();
      final auth = FakeAuthenticator()..keys[siteUrl] = 'staff-key';
      await pumpShell(
        tester,
        desktop,
        api: api,
        authenticator: auth,
        instances: const [
          DiscourseInstance(url: siteUrl, title: 'Forum', user: staff),
        ],
      );
      final shell = ShellScope.read(tester.element(primaryMainContent));
      shell.openCorePageUrl('$siteUrl/admin/dashboard');
      await tester.pump();
      await tester.pump();
      final disconnected = await tester.runAsync(
        () => shell.disconnectInstance(siteUrl),
      );
      expect(disconnected, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(shell.currentInstance?.user, isNull);
      expect(find.text('128'), findsNothing);
      api.dashboardGate!.complete(dashboardFixture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      shell.pushContent(ContentRoute.dashboard());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('128'), findsNothing);
      expect(find.text('Only staff can see the dashboard.'), findsOneWidget);
      expect(
        tester
            .widget<DashboardPage>(find.byType(DashboardPage).first)
            .state
            .loading,
        isFalse,
      );
      expect(api.requests, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
