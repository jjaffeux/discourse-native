import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/boards/boards_controller.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_module.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/plugins/boards/boards_plugin.dart';
import 'package:discourse_native/src/shell/content_page_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';

void main() {
  test(
    'Boards schema is owned by its independently installable plugin',
    () async {
      final installed = PluginInstaller.install(
        const PluginManifest([boardsModule]),
      );
      addTearDown(installed.close);
      final json = <String, dynamic>{
        'id': 500,
        'title': 'Search',
        'board_memberships': [
          {
            'board_id': 1,
            'board_name': 'Roadmap',
            'cards': [
              {'card_id': 101, 'column_title': 'Backlog'},
            ],
          },
        ],
      };
      expect(
        installed.models
            .topicSummary(json, boardsSite)
            .plugins
            .get(boardsMembershipKey)!
            .values
            .single
            .cardId,
        101,
      );
      expect(
        const DiscourseModelCodec.core()
            .topicSummary(json, boardsSite)
            .plugins
            .get(boardsMembershipKey),
        isNull,
      );
      expect(installed.descriptors.single.dependencies, isEmpty);
      expect(installed.descriptors.single.routeNamespaces, {'boards'});
    },
  );
  for (final enabled in [false, true]) {
    testWidgets(
      'registered Boards sidebar, route and heading respect setting $enabled',
      (tester) async {
        final fixture = BoardsFixture(enabled: enabled);
        addTearDown(fixture.dispose);
        final host = await PluginHostHarness.open(
          transport: fixture.transport,
          manifest: const PluginManifest([boardsModule]),
          sites: [
            PluginHostSite(
              url: boardsSite,
              apiKey: 'key',
              user: const PluginHostUser(id: 2, username: 'lee'),
              config: fixture.config,
            ),
          ],
        );
        addTearDown(host.close);
        final controller = host.require(boardsControllerKey);
        final navigation = host.require(boardsNavigationKey);
        expect(controller.enabled(boardsSite), enabled);
        final navigated = await navigation.openPluginUrl(
          '$boardsSite/boards/roadmap/1',
        );
        expect(navigated, enabled);
        const plugin = BoardsPlugin();
        const route = ContentRoute(
          destination: ExtensionDestination('boards/1'),
          title: 'Boards',
          icon: boardsIcon,
        );
        await tester.pumpWidget(
          host.scope(
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    for (final id in ['boards', 'boards/1']) {
                      final ownedRoute = ContentRoute(
                        destination: ExtensionDestination(id),
                        title: 'Boards',
                        icon: boardsIcon,
                      );
                      final ownsChrome = plugin.ownsContentChrome(
                        context,
                        ownedRoute,
                      );
                      expect(ownsChrome, isTrue);
                      for (final touch in [false, true]) {
                        expect(
                          ContentPageContract.resolve(ownedRoute).headerFor(
                            hasSite: true,
                            connected: enabled,
                            touch: touch,
                            canPop: true,
                            mobileNavigation: touch,
                            nativeTitleBar: !touch,
                            pluginOwnsChrome: ownsChrome,
                          ),
                          PageHeader.none,
                        );
                      }
                    }
                    expect(
                      plugin.ownsContentChrome(
                        context,
                        const ContentRoute(
                          destination: ExtensionDestination('other'),
                          title: 'Other',
                          icon: boardsIcon,
                        ),
                      ),
                      isFalse,
                    );
                    final owned = PluginUiScope.contextFor(
                      context,
                      boardsPluginId,
                    );
                    final destinations = plugin.communitySidebarDestinations(
                      owned,
                    );
                    expect(
                      destinations.map((item) => item.id),
                      enabled ? ['boards'] : isEmpty,
                    );
                    return plugin.content(owned, route)!;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Product roadmap'),
          enabled ? findsOneWidget : findsNothing,
        );
        if (!enabled) expect(fixture.transport.requests, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
