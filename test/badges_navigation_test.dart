import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  const site = DiscourseInstance(
    url: 'https://example.com/forum',
    title: 'Forum',
  );

  testWidgets('More opens native grouped badges, then details and recipients', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      pluginResponses: {
        'GET /badges.json?only_listable=true': badgeCatalogWire,
        'GET /badges/1.json': {'badge': badgeWire},
        'GET /user_badges.json?badge_id=1&offset=0': badgeGrantsWire(),
      },
    );
    await pumpShell(tester, desktop, instances: [site], api: api);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Badges').last);
    await tester.pumpAndSettle();
    expect(find.byType(BadgeCard), findsNWidgets(3));
    final shell = ShellScope.read(tester.element(find.byType(MainContent)));
    expect(shell.currentContent!.badgeRoute, const BadgeRoute.directory());
    await tester.tap(find.text('Autobiographer'));
    await tester.pumpAndSettle();
    expect(shell.currentContent!.badgeRoute?.badgeId, 1);
    expect(find.text('Recently awarded'), findsOneWidget);
    expect(find.text('sam'), findsOneWidget);
    await tester.tap(find.text('Welcome to the community'));
    await tester.pumpAndSettle();
    expect(shell.currentContent!.topicId, 100);
    expect(shell.currentContent!.postNumber, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notification links retain recipient filters and refresh open badges',
    (tester) async {
      final api = FakeDiscourseApi(
        pluginResponses: {
          'GET /badges/1.json': {'badge': badgeWire},
          'GET /user_badges.json?badge_id=1&offset=0&username=sam':
              badgeGrantsWire(),
        },
      );
      await pumpShell(
        tester,
        desktop,
        instances: [
          site.copyWith(user: const DiscourseUser(id: 42, username: 'sam')),
        ],
        api: api,
        authenticator: FakeAuthenticator()..keys[site.url] = 'test-key',
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(
        await shell.openNotificationUrl(
          '${site.url}/badges/1/autobiographer?username=sam',
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent!.badgeRoute?.username, 'sam');
      expect(find.text('Awarded to sam'), findsOneWidget);
      final before = api.pluginReadPaths
          .where((path) => path == '/badges/1.json')
          .length;
      await shell.openNotificationUrl(
        '${site.url}/badges/1/autobiographer?username=sam',
      );
      await tester.pumpAndSettle();
      expect(
        api.pluginReadPaths.where((path) => path == '/badges/1.json').length,
        before + 1,
      );
      expect(shell.openBadgeUrl('https://external.example/badges/1'), isFalse);
      expect(
        shell.openLinkInNewTab(
          '${site.url}/badges/1/autobiographer?username=sam',
          title: 'Autobiographer',
        ),
        TabOpenResult.opened,
      );
      final tab = shell.tabsForCurrentForum.last;
      expect(tab.currentContent.badgeRoute?.username, 'sam');
      shell.selectTab(tab.id);
      await tester.pumpAndSettle();
      expect(find.text('Awarded to sam'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('signing out clears personalized badge state', (tester) async {
    final responses = <String, Map<String, dynamic>>{
      'GET /badges.json?only_listable=true': badgeCatalogWire,
    };
    await pumpShell(
      tester,
      desktop,
      api: FakeDiscourseApi(pluginResponses: responses),
      instances: [
        site.copyWith(user: const DiscourseUser(id: 42, username: 'sam')),
      ],
      authenticator: FakeAuthenticator()..keys[site.url] = 'test-key',
    );
    final shell = ShellScope.read(tester.element(find.byType(MainContent)));
    shell.openBadgeUrl('${site.url}/badges');
    await tester.pumpAndSettle();
    expect(find.text('3 badges · 2 earned'), findsOneWidget);
    responses['GET /badges.json?only_listable=true'] = {
      ...badgeCatalogWire,
      'badges': [
        {...badgeWire}..remove('has_badge'),
      ],
    };
    await shell.disconnectCurrentInstance();
    await tester.pumpAndSettle();
    expect(
      shell.badges.stateFor(site.url, const BadgeRoute.directory()).catalog,
      isNull,
    );
    shell.openBadgeUrl('${site.url}/badges');
    await tester.pumpAndSettle();
    expect(find.text('1 badge'), findsOneWidget);
    expect(find.text('3 badges · 2 earned'), findsNothing);
  });

  testWidgets('disabled badges are absent from More and do not claim links', (
    tester,
  ) async {
    await pumpShell(
      tester,
      desktop,
      instances: [
        site.copyWith(config: const SiteConfig(badgesEnabled: false)),
      ],
    );
    final shell = ShellScope.read(tester.element(find.byType(MainContent)));
    expect(shell.openBadgeUrl('${site.url}/badges'), isFalse);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Badges'), findsNothing);
  });
}
