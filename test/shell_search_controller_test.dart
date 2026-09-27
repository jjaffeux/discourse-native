import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/shell/shell_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  const site = 'https://example.com';

  group('recent-search lifecycle', () {
    testWidgets(
      'forgetting history admits a new load before the old one settles',
      (tester) async {
        final api = _SearchApi()..gateRecentSearches = true;
        final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
        final search = ShellSearchController(
          api: api,
          credentials: credentials,
          lifecycle: SiteLifecycle(),
        )..selectSite(site);
        addTearDown(search.dispose);
        search.openPanel();
        await tester.pump();
        search.forget(site);
        search.openPanel();
        await tester.pump();
        expect(api.recentSites, [site, site]);

        api.completeRecent(1, const ['current account']);
        await tester.pump();
        api.completeRecent(0, const ['retired account']);
        await tester.pump();

        expect(search.recentSearches, ['current account']);
      },
    );

    for (final unrelatedForum in [false, true]) {
      testWidgets(
        '${unrelatedForum ? 'forgetting another forum' : 'clearing the panel'} preserves current history',
        (tester) async {
          final api = _SearchApi()..recent = const ['remembered'];
          final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
          final search = ShellSearchController(
            api: api,
            credentials: credentials,
            lifecycle: SiteLifecycle(),
          )..selectSite(site);
          addTearDown(search.dispose);
          search.openPanel();
          await tester.pump();

          if (unrelatedForum) {
            search.forget('https://unrelated.example');
          } else {
            search.clear();
          }
          search.openPanel();
          await tester.pump();

          expect(search.recentSearches, ['remembered']);
          expect(api.recentSites, [site]);
        },
      );
    }

    testWidgets('loads authenticated searches once and reuses them', (
      tester,
    ) async {
      final api = _SearchApi()..recent = const ['yellow', 'blue'];
      final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);
      final field = Object();
      final unregister = search.registerFocus(field, (_) {});
      addTearDown(unregister);

      search.activateField(field);
      await tester.pump();
      expect(search.panelOpen, isTrue);
      expect(search.ownsPanel(field), isTrue);
      expect(search.recentSearches, ['yellow', 'blue']);
      expect(api.recentSites, [site]);

      search.closePanel();
      search.activateField(field);
      await tester.pump();
      expect(search.panelOpen, isTrue);
      expect(search.recentSearches, ['yellow', 'blue']);
      expect(api.recentSites, [site]);
    });

    testWidgets('ignores older loads after a newer site request completes', (
      tester,
    ) async {
      const otherSite = 'https://other.example';
      final api = _SearchApi()..gateRecentSearches = true;
      final credentials = FakeApiCredentialReader()
        ..keys[site] = 'first-secret'
        ..keys[otherSite] = 'other-secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);
      final field = Object();
      final unregister = search.registerFocus(field, (_) {});
      addTearDown(unregister);

      search.activateField(field);
      await tester.pump();
      search.selectSite(otherSite);
      search.activateField(field);
      await tester.pump();
      search.selectSite(site);
      search.activateField(field);
      await tester.pump();

      expect(api.recentSites, [site, otherSite, site]);
      api.completeRecent(2, const ['newest']);
      await tester.pump();
      expect(search.recentSearches, ['newest']);

      api.completeRecent(1, const ['other']);
      api.completeRecent(0, const ['stale']);
      await tester.pump();
      expect(search.recentSearches, ['newest']);
    });

    testWidgets('a forum switch closes the panel and drops its history', (
      tester,
    ) async {
      final api = _SearchApi()..recent = const ['private query'];
      final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);
      search.openPanel();
      await tester.pump();
      expect(search.recentSearches, ['private query']);

      search.selectSite('https://other.example');

      expect(search.panelOpen, isFalse);
      expect(search.recentSearches, isEmpty);
    });
  });

  group('account ownership', () {
    testWidgets('only a keyed recent-history load reads the client id', (
      tester,
    ) async {
      // Reading it may raise the platform's notification permission prompt,
      // and the site ignores the id without a key.
      final api = _SearchApi()..recent = const ['keyed'];
      final credentials = _RecordingCredentials();
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);

      search.openPanel();
      await tester.pump();
      expect(api.recentSites, isEmpty);
      expect(credentials.clientIdReads, 0);

      credentials.keys[site] = 'key';
      search.forget(site);
      search.openPanel();
      await tester.pump();
      expect(api.recentSites, [site]);
      expect(credentials.clientIdReads, 1);
      expect(search.recentSearches, ['keyed']);
    });

    for (final dispose in [false, true]) {
      testWidgets(
        'recent history cannot load after ${dispose ? 'disposal' : 'rotation'} during client ID lookup',
        (tester) async {
          final api = _SearchApi();
          final lifecycle = SiteLifecycle();
          final clientId = Completer<String>();
          final credentials = _GatedClientIdCredentials()
            ..keys[site] = 'secret'
            ..pendingClientId = clientId;
          final search = ShellSearchController(
            api: api,
            credentials: credentials,
            lifecycle: lifecycle,
          )..selectSite(site);
          if (!dispose) addTearDown(search.dispose);
          search.openPanel();
          await tester.pump();

          if (dispose) {
            search.dispose();
          } else {
            lifecycle.invalidate(site);
          }
          clientId.complete('old-client');
          await tester.pump();

          expect(api.recentSites, isEmpty);
          expect(search.recentSearches, isEmpty);
        },
      );
    }
  });

  group('recent-search failure handling', () {
    test('reports a failed load once without degrading search', () async {
      final diagnostics = await _installDiagnostics('recent-search-failure');
      final api = _SearchApi()..recentFailure = StateError('offline');
      final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);

      search.openPanel();
      await pumpEventQueue();
      search.closePanel();
      search.openPanel();
      await pumpEventQueue();

      expect(search.recentSearches, isEmpty);
      expect(api.recentSites, [site]);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        isA<ErrorDiagnosticEvent>()
            .having(
              (event) => event.operation,
              'operation',
              'search.loadRecent',
            )
            .having((event) => event.source, 'source', 'search')
            .having((event) => event.handled, 'handled', isTrue)
            .having((event) => event.degraded, 'degraded', isFalse),
      );
    });
  });
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

final class _RecordingCredentials extends FakeApiCredentialReader {
  int clientIdReads = 0;

  @override
  Future<String> clientId() {
    clientIdReads++;
    return super.clientId();
  }
}

final class _GatedClientIdCredentials extends FakeApiCredentialReader {
  Completer<String>? pendingClientId;

  @override
  Future<String> clientId() => pendingClientId?.future ?? super.clientId();
}

class _SearchApi extends FakeDiscourseApi {
  List<String> recent = const [];
  Object? recentFailure;
  bool gateRecentSearches = false;
  final List<String> recentSites = [];
  final List<Completer<List<String>>> recentAnswers = [];

  @override
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    recentSites.add(siteUrl);
    if (recentFailure case final failure?) throw failure;
    if (!gateRecentSearches) return recent;
    final answer = Completer<List<String>>();
    recentAnswers.add(answer);
    return answer.future;
  }

  void completeRecent(int index, List<String> searches) {
    recentAnswers[index].complete(searches);
  }
}
