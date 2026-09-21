import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://forum.example/discuss';
const _names = {11: 'Handbook', 22: 'Roadmap', 33: 'Support'};

Map<String, dynamic> _json({bool public = false, List<int>? order}) => {
  'id': 9,
  'title': 'Projects',
  'public': public,
  'links': [
    for (final id in order ?? _names.keys)
      {'id': id, 'name': _names[id], 'value': '/link-$id', 'icon': 'link'},
  ],
};

Future<FakeDiscourseApi> _pump(
  WidgetTester tester, {
  bool public = false,
  bool admin = false,
  bool connected = true,
  Size size = desktop,
}) async {
  final user = DiscourseUser(id: 7, username: 'reader', admin: admin);
  final api = FakeDiscourseApi(
    user: user,
    customSidebarSectionsBySite: {
      _site: [SidebarSection.customFromJson(_json(public: public), index: 0)!],
    },
  );
  final auth = FakeAuthenticator();
  if (connected) auth.keys[_site] = 'key';
  await pumpShell(
    tester,
    size,
    instances: [
      DiscourseInstance(
        url: _site,
        title: 'Forum',
        user: connected ? user : null,
      ),
    ],
    api: api,
    authenticator: auth,
  );
  return api;
}

// The dragged label lives in the overlay until its drop animation completes.
List<String> _order(WidgetTester tester) => (_names.values.toList()
  ..sort(
    (a, b) => tester
        .getTopLeft(find.text(a))
        .dy
        .compareTo(tester.getTopLeft(find.text(b)).dy),
  ));

Future<void> _drag(
  WidgetTester tester,
  String from,
  String to, {
  bool after = true,
  bool touch = false,
  VoidCallback? onDropFrame,
}) async {
  final start = tester.getCenter(sidebarDestination(from));
  final end =
      tester.getCenter(sidebarDestination(to)) +
      Offset(0, (after ? 1 : -1) * (touch ? 80 : 40));
  final gesture = await tester.startGesture(
    start,
    kind: touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
  );
  if (touch) await tester.pump(kLongPressTimeout);
  await gesture.moveBy(const Offset(0, 10));
  await tester.pump();
  await gesture.moveTo(Offset(start.dx, (start.dy + end.dy) / 2));
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.up();
  // Include the proxy's drop animation and the handoff back to the list.
  if (onDropFrame != null) {
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      onDropFrame();
    }
  }
  await tester.pumpAndSettle();
}

void platformTest(
  String name,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.macOS,
}) {
  testWidgets(name, callback, variant: TargetPlatformVariant({platform}));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'reorder uses Core endpoint, auth headers, IDs and returned order',
    () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/discuss/sidebar_sections/9/reorder.json');
          expect(request.headers['User-Api-Key'], 'key');
          expect(request.headers['User-Api-Client-Id'], 'client');
          expect(jsonDecode(request.body), {
            'links_order': [33, 11, 22],
          });
          return http.Response(
            jsonEncode({
              'sidebar_section': _json(order: [33, 11, 22]),
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final section = await api.reorderSidebarLinks(
        siteUrl: _site,
        apiKey: 'key',
        clientId: 'client',
        sectionId: 9,
        linksOrder: [33, 11, 22],
      );
      expect(section.destinations.map((link) => link.linkId), [33, 11, 22]);
      expect(section.remoteId, 9);
    },
  );

  test('partial and built-in sections cannot be reordered', () {
    final partial = _json();
    (partial['links'] as List).add({'id': 44});
    expect(SidebarSection.customFromJson(partial, index: 0)!.remoteId, isNull);
    expect(
      SidebarSection.customFromJson({
        ..._json(),
        'section_type': 'community',
      }, index: 0)!.remoteId,
      isNull,
    );
  });

  platformTest('drags links down and up and skips unchanged drops', (
    tester,
  ) async {
    final api = await _pump(tester);
    expect(_order(tester), ['Handbook', 'Roadmap', 'Support']);
    await _drag(tester, 'Handbook', 'Support');
    expect(api.sidebarReorders.single.ids, [22, 33, 11]);
    expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
    await _drag(tester, 'Handbook', 'Roadmap', after: false);
    expect(api.sidebarReorders.last.ids, [11, 22, 33]);
    expect(_order(tester), ['Handbook', 'Roadmap', 'Support']);
    final menu = tester.widget<DSidebarReorderableMenu>(
      find.byType(DSidebarReorderableMenu),
    );
    menu.onReorder!(0, 1);
    await tester.pumpAndSettle();
    expect(api.sidebarReorders, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    platformTest(
      'retains dropped position until saving completes on $platform',
      (tester) async {
        final touch = platform != TargetPlatform.macOS;
        final api = await _pump(tester, size: touch ? phone : desktop);
        api.sidebarReorderGate = Completer<void>();
        await tester.ensureVisible(sidebarDestination('Support'));
        await tester.pumpAndSettle();
        await _drag(
          tester,
          'Handbook',
          'Support',
          touch: touch,
          onDropFrame: () =>
              expect(_order(tester), ['Roadmap', 'Support', 'Handbook']),
        );
        expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
        expect(api.sidebarReorders.single.ids, [22, 33, 11]);
        api.sidebarReorderGate!.complete();
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      platform: platform,
    );
  }

  platformTest(
    'shows dropped order during save, disables repeated writes, restores on failure',
    (tester) async {
      final api = await _pump(tester);
      api.sidebarReorderGate = Completer<void>();
      api.sidebarReorderFailure = const WriteException(WriteFailure.forbidden);
      await _drag(tester, 'Handbook', 'Support');
      expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
      expect(
        tester
            .widget<DSidebarReorderableMenu>(
              find.byType(DSidebarReorderableMenu),
            )
            .onReorder,
        isNull,
      );
      api.sidebarReorderGate!.complete();
      await tester.pumpAndSettle();
      expect(_order(tester), ['Handbook', 'Roadmap', 'Support']);
      expect(find.text("Couldn't reorder links. Try again."), findsOneWidget);
      expect(
        tester
            .widget<DSidebarReorderableMenu>(
              find.byType(DSidebarReorderableMenu),
            )
            .onReorder,
        isNotNull,
      );
      api.sidebarReorderGate = null;
      api.sidebarReorderFailure = null;
      await _drag(tester, 'Handbook', 'Support');
      expect(api.sidebarReorders, hasLength(2));
      expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
    },
  );

  platformTest(
    'public changes require admin confirmation and cancellation does not save',
    (tester) async {
      final api = await _pump(tester, public: true, admin: true);
      await _drag(tester, 'Handbook', 'Support');
      expect(find.text('Reorder public links?'), findsOneWidget);
      expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
      expect(api.sidebarReorders, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_order(tester), ['Handbook', 'Roadmap', 'Support']);
      expect(api.sidebarReorders, isEmpty);
      await _drag(tester, 'Handbook', 'Support');
      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();
      expect(api.sidebarReorders.single.ids, [22, 33, 11]);
    },
  );

  for (final scenario in ['public', 'anonymous']) {
    platformTest('$scenario does not expose reordering', (tester) async {
      final api = await _pump(
        tester,
        public: scenario == 'public',
        connected: scenario != 'anonymous',
      );
      expect(find.byType(DSidebarReorderableMenu), findsNothing);
      expect(api.sidebarReorders, isEmpty);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    platformTest('long press reorders mobile links on $platform', (
      tester,
    ) async {
      final api = await _pump(tester, size: phone);
      await tester.ensureVisible(sidebarDestination('Support'));
      await tester.pumpAndSettle();
      await _drag(tester, 'Handbook', 'Support', touch: true);
      expect(api.sidebarReorders.single.ids, [22, 33, 11]);
      expect(_order(tester), ['Roadmap', 'Support', 'Handbook']);
      await _drag(tester, 'Handbook', 'Roadmap', after: false, touch: true);
      expect(api.sidebarReorders.last.ids, [11, 22, 33]);
      expect(_order(tester), ['Handbook', 'Roadmap', 'Support']);
      expect(tester.takeException(), isNull);
    }, platform: platform);
  }

  platformTest('late save cannot restore links after sign-out', (tester) async {
    final api = await _pump(tester);
    api.sidebarReorderGate = Completer<void>();
    await _drag(tester, 'Handbook', 'Support');
    final controller = ShellScope.read(
      tester.element(find.byType(InstanceSidebar)),
    );
    await controller.disconnectCurrentInstance();
    await tester.pumpAndSettle();
    api.sidebarReorderGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.currentInstance!.isConnected, isFalse);
    expect(_order(tester), ['Handbook', 'Roadmap', 'Support']);
    expect(tester.takeException(), isNull);
  });
}
