import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_admin_page.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_module.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/shell_test_harness.dart';
import 'gamification_fixture.dart';

void main() {
  for (final size in [const Size(1360, 900), const Size(390, 844)]) {
    testWidgets(
      'real shell Back restores leaderboard period and scroll at ${size.width}',
      (tester) async {
        final fixture = GamificationFixture();
        addTearDown(fixture.dispose);
        fixture.publicResponse = gameResponse(
          users: [for (var id = 1; id <= 35; id++) gameUser(id: id, rank: id)],
        );
        final api = _GameShellApi(fixture);
        await pumpShell(
          tester,
          size,
          revealMobileNavigation: size.width < 600,
          instances: [
            DiscourseInstance(
              url: gameSite,
              title: 'Community',
              apiVersion: 4,
              loginRequired: false,
              user: api.user,
              config: fixture.config.value,
            ),
          ],
          api: api,
          authenticator: FakeAuthenticator()..keys[gameSite] = 'key',
          pluginManifest: const PluginManifest([gamificationModule]),
        );
        final shell = ShellScope.read(
          tester.element(find.byType(UserMenuButton).first),
        );
        expect(await shell.openPluginUrl('$gameSite/leaderboard'), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(GamificationPage), findsOneWidget);
        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Last week'));
        await tester.pumpAndSettle();
        final scroll = find.descendant(
          of: find.byType(GamificationPage),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await tester.drag(scroll.first, const Offset(0, -550));
        await tester.pumpAndSettle();
        final before = tester
            .state<ScrollableState>(scroll.first)
            .position
            .pixels;
        expect(before, greaterThan(100));
        await tester.tap(find.text('Manage leaderboards'));
        await tester.pumpAndSettle();
        expect(find.byType(GamificationAdminPage), findsOneWidget);
        expect(shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(GamificationPage), findsOneWidget);
        expect(find.text('Last week'), findsOneWidget);
        expect(
          tester.state<ScrollableState>(scroll.first).position.pixels,
          closeTo(before, 1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({
        size.width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS,
      }),
    );
  }
}

final class _GameShellApi extends FakeDiscourseApi {
  _GameShellApi(this.fixture)
    : super(
        user: fixture.user,
        feeds: const {'/latest.json': []},
        siteConfigs: {gameSite: fixture.config.value},
      );
  final GamificationFixture fixture;
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => fixture.transport.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => fixture.transport.pluginWriteJson(
    siteUrl: siteUrl,
    path: path,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );
}
