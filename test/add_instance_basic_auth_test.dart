import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/http_basic_auth.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/basic_auth_storage.dart';
import 'support/discover_sites.dart';
import 'support/fakes.dart';

const _authorization = 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==';

void main() {
  Future<
    ({
      ShellController shell,
      BasicAuthMemoryStorage storage,
      HttpBasicAuthStore authentication,
    })
  >
  open(
    WidgetTester tester, {
    Future<http.Response> Function(http.Request request)? respond,
    FakeInstanceStore? sites,
  }) async {
    final storage = BasicAuthMemoryStorage();
    final authentication = HttpBasicAuthStore(storage: storage);
    final api = DiscourseApi(
      basicAuth: authentication,
      client: MockClient(
        respond ??
            (request) async {
              if (request.headers['authorization'] != _authorization) {
                return http.Response(
                  '',
                  401,
                  headers: {'www-authenticate': 'Basic realm="ngrok"'},
                );
              }
              return request.method == 'HEAD'
                  ? http.Response('', 200, headers: {'auth-api-version': '4'})
                  : http.Response('{"title":"Protected forum"}', 200);
            },
      ),
    );
    final shell = ShellController(
      instanceStore: sites ?? FakeInstanceStore(),
      api: api,
      basicAuth: authentication,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    final source = emptyDiscoverSites();
    addTearDown(source.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Add site'),
                onPressed: () =>
                    showAddInstanceSheet(context, discoverSites: source),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add site'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'forum.example');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    return (shell: shell, storage: storage, authentication: authentication);
  }

  Finder username() => find.byWidgetPredicate(
    (widget) => widget is DInput && widget.labelText == 'Server username',
  );
  Finder password() => find.byWidgetPredicate(
    (widget) => widget is DInput && widget.labelText == 'Server password',
  );

  testWidgets(
    'Basic challenge reveals secure Native fields and retries wrong credentials',
    (tester) async {
      final fixture = await open(tester);
      expect(
        find.text(
          'https://forum.example requires a server username and password.',
        ),
        findsOneWidget,
      );
      expect(username(), findsOneWidget);
      expect(password(), findsOneWidget);
      expect(tester.widget<DInput>(password()).obscureText, isTrue);
      expect(fixture.storage.values, isEmpty);
      await tester.enterText(username(), 'Aladdin');
      await tester.enterText(password(), 'wrong');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The server did not accept that username and password. Try again.',
        ),
        findsOneWidget,
      );
      expect(fixture.shell.instances, isEmpty);
      expect(fixture.storage.values, isEmpty);
      await tester.enterText(password(), 'open sesame');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Add a site'), findsNothing);
      expect(fixture.shell.instances.single.url, 'https://forum.example');
      expect(
        fixture.authentication.authorizationFor(
          Uri.parse('https://forum.example'),
        ),
        _authorization,
      );
      final restarted = HttpBasicAuthStore(storage: fixture.storage);
      await restarted.load();
      expect(
        restarted.authorizationFor(Uri.parse('https://forum.example')),
        _authorization,
      );
    },
  );

  testWidgets(
    'explicit server credential renewal updates an already-listed site',
    (tester) async {
      final fixture = await open(
        tester,
        sites: FakeInstanceStore([instance('forum.example')]),
      );
      var refreshes = 0;
      final detach = fixture.shell.registerContentRefresher(() async {
        refreshes++;
      });
      addTearDown(detach);
      await tester.enterText(username(), 'Aladdin');
      await tester.enterText(password(), 'open sesame');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(fixture.shell.instances, hasLength(1));
      expect(refreshes, 1);
      expect(
        fixture.authentication.authorizationFor(
          Uri.parse('https://forum.example'),
        ),
        _authorization,
      );
      expect(find.text('Add a site'), findsNothing);
    },
  );

  testWidgets('editing the address clears server credentials and challenge', (
    tester,
  ) async {
    final fixture = await open(tester);
    await tester.enterText(username(), 'Aladdin');
    await tester.enterText(password(), 'private-password');
    await tester.enterText(find.byType(EditableText).first, 'other.example');
    await tester.pump();
    expect(username(), findsNothing);
    expect(password(), findsNothing);
    expect(fixture.storage.values, isEmpty);
  });

  testWidgets(
    'dismissal while authenticated discovery waits never saves credentials',
    (tester) async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final fixture = await open(
        tester,
        respond: (request) async {
          if (request.headers['authorization'] == null) {
            return http.Response(
              '',
              401,
              headers: {'www-authenticate': 'Basic realm="private"'},
            );
          }
          if (request.method == 'HEAD') {
            started.complete();
            return response.future;
          }
          return http.Response('{"title":"Protected forum"}', 200);
        },
      );
      await tester.enterText(username(), 'Aladdin');
      await tester.enterText(password(), 'open sesame');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await started.future;
      final context = tester.element(find.text('Add a site'));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      response.complete(
        http.Response('', 200, headers: {'auth-api-version': '4'}),
      );
      await tester.pumpAndSettle();
      expect(fixture.storage.values, isEmpty);
      expect(fixture.shell.instances, isEmpty);
    },
  );

  testWidgets(
    'dismissal during secure persistence rolls back only the pending credential save',
    (tester) async {
      final fixture = await open(tester);
      final write = Completer<void>();
      fixture.storage.writeGate = write;
      await tester.enterText(username(), 'Aladdin');
      await tester.enterText(password(), 'open sesame');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(fixture.storage.writes, 1);
      Navigator.of(tester.element(find.text('Add a site'))).pop();
      await tester.pumpAndSettle();
      write.complete();
      await tester.pumpAndSettle();
      expect(fixture.shell.instances, isEmpty);
      expect(
        fixture.authentication.authorizationFor(
          Uri.parse('https://forum.example'),
        ),
        isNull,
      );
      final restarted = HttpBasicAuthStore(storage: fixture.storage);
      await restarted.load();
      expect(
        restarted.authorizationFor(Uri.parse('https://forum.example')),
        isNull,
      );
    },
  );

  testWidgets(
    'durable addition failure rolls back confirmed server credentials',
    (tester) async {
      final fixture = await open(tester, sites: _FailingSites());
      await tester.enterText(username(), 'Aladdin');
      await tester.enterText(password(), 'open sesame');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(fixture.shell.instances, isEmpty);
      expect(
        fixture.authentication.authorizationFor(
          Uri.parse('https://forum.example'),
        ),
        isNull,
      );
      expect(find.text("Couldn't save this site. Try again."), findsOneWidget);
    },
  );
}

final class _FailingSites extends FakeInstanceStore {
  @override
  Future<void> save(instances) async => throw StateError('save failed');
}
