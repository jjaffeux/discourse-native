import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/badges_host.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/badge_fixtures.dart';
import 'support/fakes.dart';
import 'support/skeleton_expectations.dart';

const _site = 'https://forum.example';
final _route = BadgeRoute.detail(1, slug: 'autobiographer');

final class _Api extends FakeDiscourseApi {
  _Api(this.reader);
  final DiscourseApi reader;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) => reader.pluginGetJson(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );
}

Future<ShellController> _pump(
  WidgetTester tester,
  http.Client client, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('forum.example')]),
    api: _Api(DiscourseApi(client: client)),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  expect(shell.openBadgeUrl('$_site${_route.path}'), isTrue);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(
          platform: size.width < 600
              ? TargetPlatform.android
              : TargetPlatform.macOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: MainContent(layout: ShellLayout.medium)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(BadgesHost), findsOneWidget);
  return shell;
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('Native badge details fill held recipients at $size', (
      tester,
    ) async {
      final grants = Completer<http.Response>();
      addTearDown(() {
        if (!grants.isCompleted) grants.complete(_json(badgeGrantsWire()));
      });
      final sent = <http.Request>[];
      final client = MockClient((request) async {
        sent.add(request);
        return request.url.path == '/badges/1.json'
            ? _json({'badge': badgeWire})
            : grants.future;
      });
      addTearDown(client.close);
      final shell = await _pump(tester, client, size: size);
      expect(sent.map((request) => request.url.path), [
        '/badges/1.json',
        '/user_badges.json',
      ]);
      expect(shell.badges.stateFor(_site, _route).loading, isTrue);
      expect(find.text('Recently awarded'), findsOneWidget);
      expect(find.text('Autobiographer'), findsWidgets);
      expect(find.byKey(const ValueKey('badge-grant-1')), findsNothing);
      expect(find.text('No awards to display.'), findsNothing);
      final semantics = tester.ensureSemantics();
      final pageBounds = tester.getRect(find.byType(BadgesPage));
      expectSkeletonFillsViewport(
        tester,
        label: 'Loading badges',
        bottom: pageBounds.bottom,
      );
      final bounds = tester.getRect(find.byType(DSkeletonRegion));
      expect(
        bounds.top,
        greaterThan(tester.getRect(find.text('Recently awarded')).bottom),
      );
      semantics.dispose();
      grants.complete(_json(badgeGrantsWire()));
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.byKey(const ValueKey('badge-grant-1')), findsOneWidget);
      expect(shell.badges.stateFor(_site, _route).loading, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final outcome in ['empty', 'error']) {
    testWidgets('Native badge recipient loading completes to $outcome', (
      tester,
    ) async {
      final first = Completer<http.Response>();
      addTearDown(() {
        if (!first.isCompleted) first.complete(_json(badgeGrantsWire()));
      });
      var grantReads = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/badges/1.json') {
          return _json({'badge': badgeWire});
        }
        return ++grantReads == 1 ? first.future : _json(badgeGrantsWire());
      });
      addTearDown(client.close);
      await _pump(tester, client);
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      first.complete(
        outcome == 'empty'
            ? _json(badgeGrantsWire(count: 0, total: 0))
            : http.Response('unavailable', 500),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.text('Recently awarded'), findsOneWidget);
      if (outcome == 'empty') {
        expect(find.text('No awards to display.'), findsOneWidget);
        expect(find.byType(DAlert), findsNothing);
      } else {
        expect(find.byType(DAlert), findsOneWidget);
        expect(find.text('No awards to display.'), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(grantReads, 2);
        expect(find.byType(DAlert), findsNothing);
        expect(find.byKey(const ValueKey('badge-grant-1')), findsOneWidget);
        expect(find.byType(DSkeletonRegion), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Native badge Load more retains rows with visible progress', (
    tester,
  ) async {
    final next = Completer<http.Response>();
    addTearDown(() {
      if (!next.isCompleted) next.complete(_json(badgeGrantsWire(offset: 96)));
    });
    final sent = <http.Request>[];
    final client = MockClient((request) async {
      sent.add(request);
      if (request.url.path == '/badges/1.json') {
        return _json({'badge': badgeWire});
      }
      if (request.url.queryParameters['offset'] == '0') {
        return _json(badgeGrantsWire(count: 96, total: 97));
      }
      return next.future;
    });
    addTearDown(client.close);
    final shell = await _pump(tester, client);
    final more = find.byKey(const ValueKey('badge-load-more'));
    await tester.scrollUntilVisible(
      more,
      500,
      scrollable: find
          .descendant(
            of: find.byType(BadgesPage),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
    final last = find.byKey(const ValueKey('badge-grant-96'));
    expect(last, findsOneWidget);
    final oldRow = tester.element(last);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(sent.last.url.queryParameters['offset'], '96');
    expect(shell.badges.stateFor(_site, _route).loadingMore, isTrue);
    expect(shell.badges.stateFor(_site, _route).grants, hasLength(96));
    expect(tester.element(last), same(oldRow));
    expect(more, findsNothing);
    final region = find.byType(DSkeletonRegion);
    expect(region, findsOneWidget);
    final viewport = tester.getRect(find.byType(BadgesPage));
    final shapes = find.descendant(
      of: region,
      matching: find.byType(DSkeleton),
    );
    expect(
      shapes.evaluate().any((element) {
        final bounds = tester.getRect(
          find.byElementPredicate((other) => other == element),
        );
        return bounds.overlaps(viewport);
      }),
      isTrue,
    );
    next.complete(_json(badgeGrantsWire(offset: 96, total: 97)));
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(shell.badges.stateFor(_site, _route).grants, hasLength(97));
    expect(find.byKey(const ValueKey('badge-grant-97')), findsOneWidget);
    expect(more, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
