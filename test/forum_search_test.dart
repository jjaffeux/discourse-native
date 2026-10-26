import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

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
