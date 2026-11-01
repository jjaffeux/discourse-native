import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';
import 'support/user_metadata_plugin.dart';

const _site = 'https://meta.discourse.org';
const _owner = PluginId('summary-identity');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(1440, 900), const Size(390, 844)]) {
    testWidgets(
      'summary identity uses canonical card and normal refresh at ${size.width}',
      (tester) async {
        final cards = <String, UserCard>{
          'reader': const UserCard(username: 'reader', title: 'before'),
        };
        final api = _SummaryApi(cards);
        await pumpShell(
          tester,
          size,
          api: api,
          instances: [instance('meta.discourse.org', user: api.user)],
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
          pluginManifest: const PluginManifest([
            _IdentityModule(),
            userMetadataTestModule,
          ]),
        );
        final shell = ShellScope.read(
          tester.element(find.byType(UserMenuButton).first),
        );
        shell.pushContent(
          const ContentRoute(
            destination: PageDestination(CorePage.summary),
            title: 'Summary',
            icon: DIcons.user,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(UserSummaryView), findsOneWidget);
        expect(api.cardsRequested, ['reader']);
        expect(
          find.text('Identity before summary-identity/summary-identity'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Profile metadata reader: before user-metadata-test/user-metadata-test',
          ),
          findsOneWidget,
        );
        final name = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('user-summary-profile')),
            matching: find.text('Reader Example'),
          ),
        );
        final decoration = tester.getRect(
          find.byKey(const ValueKey('summary-owned-identity')),
        );
        if (decoration.top < name.bottom) {
          expect(decoration.left, greaterThan(name.right));
        } else {
          expect(decoration.top, greaterThanOrEqualTo(name.bottom));
        }
        await shell.loadUserCard('reader', siteUrl: _site);
        expect(api.cardsRequested, ['reader']);
        cards['reader'] = const UserCard(username: 'reader', title: 'after');
        await shell.refreshCurrentTab();
        await tester.pumpAndSettle();
        expect(api.cardsRequested, ['reader', 'reader']);
        expect(
          find.text('Identity after summary-identity/summary-identity'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Profile metadata reader: after user-metadata-test/user-metadata-test',
          ),
          findsOneWidget,
        );
        api.failSummary = true;
        await shell.userSummary.load(shell.currentInstance!, refresh: true);
        await tester.pumpAndSettle();
        api.failSummary = false;
        cards['reader'] = const UserCard(username: 'reader', title: 'retry');
        await tester.tap(find.widgetWithText(DButton, 'Retry'));
        await tester.pumpAndSettle();
        expect(api.cardsRequested, ['reader', 'reader', 'reader']);
        expect(
          find.text('Identity retry summary-identity/summary-identity'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Profile metadata reader: retry user-metadata-test/user-metadata-test',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'identity-only contributor triggers card load and fits large text',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = FakeDiscourseApi(
        user: const DiscourseUser(
          id: 7,
          username: 'reader',
          name: 'Reader with a very long display name',
        ),
        cards: {'reader': const UserCard(username: 'reader', title: 'visible')},
        summary: const UserSummary(canSeeSummaryStats: true),
        feeds: const {'/latest.json': []},
      );
      await pumpShell(
        tester,
        const Size(390, 844),
        api: api,
        instances: [instance('meta.discourse.org', user: api.user)],
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        pluginManifest: const PluginManifest([_IdentityModule()]),
      );
      final shell = ShellScope.read(
        tester.element(find.byType(UserMenuButton).first),
      );
      shell.pushContent(
        const ContentRoute(
          destination: PageDestination(CorePage.summary),
          title: 'Summary',
          icon: DIcons.user,
        ),
      );
      await tester.pumpAndSettle();
      expect(api.cardsRequested, ['reader']);
      expect(
        find.text('Identity visible summary-identity/summary-identity'),
        findsOneWidget,
      );
      api.cards['reader'] = const UserCard(
        username: 'reader',
        title: 'refreshed',
      );
      await shell.refreshCurrentTab();
      await tester.pumpAndSettle();
      expect(api.cardsRequested, ['reader', 'reader']);
      expect(
        find.text('Identity refreshed summary-identity/summary-identity'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('absent identity leaves fallback and performs no card request', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: const DiscourseUser(
        id: 7,
        username: 'reader',
        name: 'Reader Example',
      ),
      summary: const UserSummary(),
      feeds: const {'/latest.json': []},
    );
    await pumpShell(
      tester,
      const Size(390, 844),
      api: api,
      instances: [instance('meta.discourse.org', user: api.user)],
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
      pluginManifest: const PluginManifest([]),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(UserMenuButton).first),
    );
    shell.pushContent(
      const ContentRoute(
        destination: PageDestination(CorePage.summary),
        title: 'Summary',
        icon: DIcons.user,
      ),
    );
    await tester.pumpAndSettle();
    await shell.refreshCurrentTab();
    await tester.pumpAndSettle();
    expect(api.cardsRequested, isEmpty);
    expect(find.text('Reader Example'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _IdentityModule implements PluginModule {
  const _IdentityModule();
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: _owner);
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _IdentityPlugin());
}

final class _IdentityPlugin
    implements SitePlugin, UserCardIdentityDecorationPlugin {
  const _IdentityPlugin();
  @override
  String get name => _owner.value;
  @override
  Listenable? userCardIdentityDecorationsListenable(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => null;

  @override
  List<Widget> userCardIdentityDecorations(
    BuildContext context,
    String siteUrl,
    UserCard user,
  ) => [_OwnedIdentity(user.title ?? '', PluginUiScope.ownerOf(context))];
}

final class _OwnedIdentity extends StatelessWidget {
  const _OwnedIdentity(this.title, this.callbackOwner);
  final String title;
  final PluginId callbackOwner;
  @override
  Widget build(BuildContext context) => DBadge(
    key: const ValueKey('summary-owned-identity'),
    child: Text(
      'Identity $title ${callbackOwner.value}/${PluginUiScope.ownerOf(context).value}',
    ),
  );
}

final class _SummaryApi extends FakeDiscourseApi {
  _SummaryApi(Map<String, UserCard> cards)
    : super(
        user: const DiscourseUser(
          id: 7,
          username: 'reader',
          name: 'Reader Example',
        ),
        cards: cards,
        summary: const UserSummary(canSeeSummaryStats: true),
        feeds: const {'/latest.json': []},
      );
  bool failSummary = false;
  @override
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    final value = await super.userSummary(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      clientId: clientId,
    );
    if (failSummary) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return value;
  }
}
