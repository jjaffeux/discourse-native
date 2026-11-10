import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_global_search.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/global_search_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/global_search_fixtures.dart';

void main() {
  for (final (canSearch, offered) in [(false, false), (null, true)]) {
    testWidgets(
      'an anonymous reader is ${offered ? '' : 'not '}offered search when '
      'site.json ${canSearch == null ? 'omits' : 'denies'} can_search',
      (tester) async {
        final api = _SiteMetadataApi({'can_search': ?canSearch});
        final shell = ShellController(
          instanceStore: FakeInstanceStore([instance('meta.example')]),
          api: api,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
          ownsApi: false,
        );
        addTearDown(shell.dispose);
        await tester.runAsync(() async {
          await shell.load();
          await pumpEventQueue();
        });
        expect(api.siteMetadataRequests, 1);

        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 600, child: ForumSearch()),
                ),
              ),
            ),
          ),
        );
        expect(
          find.byKey(ForumSearch.inputKey),
          offered ? findsOneWidget : findsNothing,
        );

        shell.search.requestFocus();
        await tester.pumpAndSettle();
        expect(
          find.byKey(ForumSearch.panelKey),
          offered ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  group('a shell notification', () {
    for (final (name, platform, field) in [
      ('field', TargetPlatform.macOS, const ForumSearch()),
      (
        'trigger',
        TargetPlatform.iOS,
        const ForumSearch(fullScreen: true, showNavigationControls: false),
      ),
    ]) {
      testWidgets('that changes nothing rebuilds no element of the $name', (
        tester,
      ) async {
        final shell = createGlobalSearchFixtureController();
        addTearDown(shell.dispose);
        await shell.load();
        await _pumpSearch(tester, shell, field, platform: platform);
        await tester.pumpAndSettle();
        final rebuilt = _recordSearchRebuilds();

        shell.notifyPluginStateChanged();
        await tester.pump();

        _proof('rebuilds_per_notify_$name', rebuilt.length);
        expect(rebuilt, isEmpty);
      });
    }

    for (final (expression, words, chips) in [
      ('hello', 'hello', 0),
      ('category:1', '', 1),
    ]) {
      testWidgets('redraws the closed field for the route "$expression"', (
        tester,
      ) async {
        final shell = createGlobalSearchFixtureController();
        addTearDown(shell.dispose);
        await shell.load();
        await _pumpSearch(tester, shell, const ForumSearch());
        await tester.pumpAndSettle();
        expect(find.byKey(_clearKey), findsNothing);

        shell.pushContent(ContentRoute.searchList(expression));
        await tester.pumpAndSettle();

        expect(_input(tester).text, words);
        expect(find.byType(SearchFilterChip), findsNWidgets(chips));
        expect(find.byKey(_clearKey), findsOneWidget);
      });
    }

    testWidgets('redraws the closed field when capabilities arrive', (
      tester,
    ) async {
      final api = _GatedDiscoveryApi();
      final shell = createGlobalSearchFixtureController(api: api);
      addTearDown(shell.dispose);
      await shell.load();
      await _pumpSearch(tester, shell, const ForumSearch());
      await tester.pumpAndSettle();

      shell.pushContent(ContentRoute.searchList('status:solved'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchFilterChip), findsNothing);
      expect(_input(tester).text, 'status:solved');

      api.settings.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SearchFilterChip), findsOneWidget);
      expect(_input(tester).text, isEmpty);
    });
  });

  group('capability discovery', () {
    testWidgets('waits for the first open and asks once per forum session', (
      tester,
    ) async {
      final api = GlobalSearchFixtureApi();
      final shell = createGlobalSearchFixtureController(api: api);
      addTearDown(shell.dispose);
      await shell.load();
      await _pumpSearch(tester, shell, const ForumSearch());
      await tester.pumpAndSettle();
      final startup = _discoveryReads(api);

      shell.selectInstance(1);
      await tester.pumpAndSettle();
      shell.selectInstance(0);
      await tester.pumpAndSettle();
      final forumSwitch = _discoveryReads(api) - startup;

      shell.search.requestFocus();
      await tester.pumpAndSettle();
      final firstOpen = _discoveryReads(api) - startup - forumSwitch;

      shell.search.closePanel();
      await tester.pumpAndSettle();
      shell.search.requestFocus();
      await tester.pumpAndSettle();
      final secondOpen =
          _discoveryReads(api) - startup - forumSwitch - firstOpen;

      _proof('startup_discovery_reads', startup);
      _proof('forum_switch_discovery_reads', forumSwitch);
      _proof('first_open_discovery_reads', firstOpen);
      _proof('second_open_discovery_reads', secondOpen);
      expect([startup, forumSwitch, firstOpen, secondOpen], [0, 0, 3, 0]);
    });

    testWidgets('offers plugin scopes once the first open is answered', (
      tester,
    ) async {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      await shell.load();
      await _pumpSearch(tester, shell, const ForumSearch());
      await tester.pumpAndSettle();

      shell.search.requestFocus();
      await tester.pumpAndSettle();

      expect(shell.globalSearch.scopes, contains(chatSearchScope));
      expect(find.text(chatSearchScope.label), findsOneWidget);
    });

    testWidgets('runs for a search page that opened without a field', (
      tester,
    ) async {
      final api = GlobalSearchFixtureApi();
      final shell = createGlobalSearchFixtureController(api: api);
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.search());

      await _pumpSearch(tester, shell, const ForumSearch.page());
      await tester.pumpAndSettle();

      expect(_discoveryReads(api), 3);
      expect(shell.globalSearch.scopes, contains(chatSearchScope));
    });
  });

  for (final (platform, field) in [
    (TargetPlatform.iOS, 44.0),
    (TargetPlatform.android, 44.0),
    (TargetPlatform.macOS, 30.0),
  ]) {
    testWidgets('the search screen field is $field tall on $platform', (
      tester,
    ) async {
      final shell = createGlobalSearchFixtureController(
        api: GlobalSearchFixtureApi(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.search());

      await _pumpSearch(
        tester,
        shell,
        const ForumSearch.page(),
        platform: platform,
      );
      await tester.pumpAndSettle();

      final head = tester.getRect(find.byKey(ForumSearch.panelKey));
      final editor = tester.getRect(
        find.ancestor(
          of: find.byKey(ForumSearch.inputKey),
          matching: find.byType(DInputGroup),
        ),
      );
      expect(editor.height, field);
      expect(
        tester.getRect(find.byType(GlobalSearchPanel)).top - head.top,
        8 + field + 8,
        reason: 'what it finds starts 8 under the field',
      );
    });
  }
}

const _clearKey = ValueKey('forum-search-clear');

int _discoveryReads(GlobalSearchFixtureApi api) => api.requests
    .where(
      (request) => const {
        '/site/settings.json',
        '/session/current.json',
        '/directory-columns.json',
      }.contains(request.uri.path),
    )
    .length;

TextEditingController _input(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(ForumSearch.inputKey),
        matching: find.byType(EditableText),
      ),
    )
    .controller;

Future<void> _pumpSearch(
  WidgetTester tester,
  ShellController shell,
  Widget search, {
  TargetPlatform platform = TargetPlatform.macOS,
}) => tester.pumpWidget(
  ShellScope(
    controller: shell,
    child: MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 600, child: search),
        ),
      ),
    ),
  ),
);

/// Every element under a [ForumSearch], itself included, built from now on.
List<Widget> _recordSearchRebuilds() {
  final rebuilt = <Widget>[];
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (element.widget is ForumSearch ||
        element.findAncestorWidgetOfExactType<ForumSearch>() != null) {
      rebuilt.add(element.widget);
    }
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  return rebuilt;
}

void _proof(String metric, int value) {
  // ignore: avoid_print
  print('PERF_PROOF search $metric=$value');
}

/// Holds the forum's settings answer, so the moment capability discovery
/// lands is the test's to choose.
final class _GatedDiscoveryApi extends GlobalSearchFixtureApi {
  final settings = Completer<void>();

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (path == '/site/settings.json') await settings.future;
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

/// Reads categories through the production parser so the `/site.json`
/// supplement is interpreted exactly as a live anonymous session would.
final class _SiteMetadataApi extends FakeDiscourseApi {
  _SiteMetadataApi(this.site) : super(feeds: const {'/latest.json': []});

  final Map<String, Object?> site;
  int siteMetadataRequests = 0;

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) => DiscourseApi(
    client: MockClient((request) async {
      if (request.url.path == '/site.json') {
        siteMetadataRequests++;
        return http.Response(jsonEncode(site), 200);
      }
      return http.Response(
        jsonEncode({
          'category_list': {'categories': <Object?>[]},
        }),
        200,
      );
    }),
  ).loadCategories(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);
}
