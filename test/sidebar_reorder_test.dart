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

Map<String, dynamic> _json({
  bool public = false,
  List<int>? order,
  int id = 9,
  String title = 'Projects',
}) => {
  'id': id,
  'title': title,
  'public': public,
  'links': [
    for (final id in order ?? _names.keys)
      {
        'id': id,
        'name': _names[id] ?? 'Link $id',
        'value': '/link-$id',
        'icon': 'link',
      },
  ],
};

Future<FakeDiscourseApi> _pump(
  WidgetTester tester, {
  bool public = false,
  bool admin = false,
  bool connected = true,
  Size size = desktop,
  List<int>? sourceOrder,
  List<int>? targetOrder,
  bool targetPublic = false,
}) async {
  final user = DiscourseUser(id: 7, username: 'reader', admin: admin);
  final api = FakeDiscourseApi(
    user: user,
    customSidebarSectionsBySite: {
      _site: [
        SidebarSection.customFromJson(
          _json(public: public, order: sourceOrder),
          index: 0,
        )!,
        if (targetOrder != null)
          SidebarSection.customFromJson(
            _json(
              id: 10,
              title: 'Team links',
              public: targetPublic,
              order: targetOrder,
            ),
            index: 1,
          )!,
      ],
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
    revealMobileNavigation: size == phone,
  );
  if (size == phone) {
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
  } else {
    final shortcuts = find.byKey(
      const ValueKey('sidebar-panel-switch-shortcuts'),
    );
    await tester.ensureVisible(shortcuts);
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getRect(shortcuts).centerLeft + const Offset(8, 0),
    );
    await tester.pumpAndSettle();
  }
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
  for (var step = 1; step <= 16; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 16)!);
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(milliseconds: 300));
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

Future<void> _transfer(
  WidgetTester tester, {
  String from = 'Handbook',
  String to = 'Team links',
  bool touch = false,
  double offset = 0,
}) async {
  final start = tester.getCenter(sidebarDestination(from));
  final end = tester.getCenter(find.text(to)) + Offset(0, offset);
  final gesture = await tester.startGesture(
    start,
    kind: touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
  );
  if (touch) await tester.pump(kLongPressTimeout);
  await gesture.moveBy(const Offset(0, 10));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await tester.pumpAndSettle();
}

List<int?> _sectionOrder(WidgetTester tester, int id) =>
    ShellScope.read(tester.element(find.byType(InstanceSidebar)))
        .customSidebarSectionsFor(_site)
        .firstWhere((section) => section.remoteId == id)
        .destinations
        .map((link) => link.linkId)
        .toList();

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

  test(
    'move uses the atomic Core endpoint and validates both returned sections',
    () async {
      var malformed = false;
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(
            request.url.path,
            '/discuss/sidebar_sections/9/move_link.json',
          );
          expect(request.headers['User-Api-Key'], 'key');
          expect(request.headers['User-Api-Client-Id'], 'client');
          expect(jsonDecode(request.body), {
            'link_id': 11,
            'target_section_id': 10,
            'position': 1,
          });
          return http.Response(
            jsonEncode({
              'sidebar_sections': [
                _json(order: [22, 33]),
                if (!malformed)
                  _json(id: 10, title: 'Team links', order: [44, 11]),
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      Future<List<SidebarSection>> move() => api.moveSidebarLink(
        siteUrl: _site,
        apiKey: 'key',
        clientId: 'client',
        sourceSectionId: 9,
        targetSectionId: 10,
        linkId: 11,
        position: 1,
      );
      final sections = await move();
      expect(sections.map((section) => section.remoteId), [9, 10]);
      expect(sections.last.destinations.map((link) => link.linkId), [44, 11]);
      malformed = true;
      await expectLater(move(), throwsA(isA<WriteException>()));
    },
  );

  platformTest('moves to a row gap then back to the source header', (
    tester,
  ) async {
    final api = await _pump(tester, targetOrder: [44, 55]);
    await _transfer(tester, to: 'Link 55', offset: -8);
    expect(api.sidebarMoves.single.position, 1);
    expect(_sectionOrder(tester, 9), [22, 33]);
    expect(_sectionOrder(tester, 10), [44, 11, 55]);
    expect(api.sidebarReorders, isEmpty);
    await _transfer(tester, to: 'Projects');
    expect(_sectionOrder(tester, 9), [22, 33, 11]);
    expect(_sectionOrder(tester, 10), [44, 55]);
    expect(tester.takeException(), isNull);
  });

  for (final collapsed in [false, true]) {
    platformTest(
      'moves the last source link into an ${collapsed ? 'collapsed' : 'empty'} section',
      (tester) async {
        final api = await _pump(
          tester,
          sourceOrder: [11],
          targetOrder: collapsed ? [44] : [],
        );
        if (collapsed) {
          await tester.tap(find.text('Team links'));
          await tester.pumpAndSettle();
        }
        await _transfer(tester);
        expect(api.sidebarMoves.single.linkId, 11);
        expect(_sectionOrder(tester, 9), isEmpty);
        expect(_sectionOrder(tester, 10), collapsed ? [44, 11] : [11]);
        if (collapsed) {
          await tester.tap(find.text('Team links'));
          await tester.pumpAndSettle();
        }
        await _transfer(tester, to: 'Projects');
        expect(_sectionOrder(tester, 9), [11]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  platformTest(
    'previews both sections, restores a failed move and allows retry',
    (tester) async {
      final api = await _pump(tester, targetOrder: [44]);
      api.sidebarMoveGate = Completer<void>();
      api.sidebarMoveFailure = const WriteException(WriteFailure.forbidden);
      await _transfer(tester);
      expect(
        tester.getTopLeft(find.text('Handbook')).dy,
        greaterThan(tester.getTopLeft(find.text('Link 44')).dy),
      );
      expect(_sectionOrder(tester, 9), [11, 22, 33]);
      for (final menu in tester.widgetList<DSidebarReorderableMenu>(
        find.byType(DSidebarReorderableMenu),
      )) {
        expect(menu.onReorder, isNull);
      }
      api.sidebarMoveGate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Handbook')).dy,
        lessThan(tester.getTopLeft(find.text('Roadmap')).dy),
      );
      expect(find.text("Couldn't move link. Try again."), findsOneWidget);
      api.sidebarMoveGate = null;
      api.sidebarMoveFailure = null;
      await _transfer(tester);
      expect(api.sidebarMoves, hasLength(2));
      expect(_sectionOrder(tester, 10), [44, 11]);
      expect(tester.takeException(), isNull);
    },
  );

  platformTest('public transfers confirm once and cancel without writing', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      targetOrder: [],
      targetPublic: true,
      admin: true,
    );
    await _transfer(tester);
    expect(find.text('Move public link?'), findsOneWidget);
    expect(api.sidebarMoves, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_sectionOrder(tester, 9), [11, 22, 33]);
    await _transfer(tester);
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(api.sidebarMoves, hasLength(1));
    expect(_sectionOrder(tester, 10), [11]);
  });

  platformTest('non-admin cannot transfer into a public section', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      sourceOrder: [11],
      targetOrder: [],
      targetPublic: true,
    );
    await _transfer(tester);
    expect(api.sidebarMoves, isEmpty);
    expect(_sectionOrder(tester, 9), [11]);
    expect(find.text('Move public link?'), findsNothing);
  });

  platformTest(
    'full and non-editable destinations reject drops without reordering',
    (tester) async {
      for (final full in [false, true]) {
        final api = await _pump(
          tester,
          targetOrder: full ? List.generate(50, (index) => 100 + index) : [],
          targetPublic: !full,
        );
        await _transfer(tester);
        expect(api.sidebarMoves, isEmpty);
        expect(api.sidebarReorders, isEmpty);
        expect(_sectionOrder(tester, 9), [11, 22, 33]);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  platformTest('late move does not restore an account sidebar after sign-out', (
    tester,
  ) async {
    final api = await _pump(tester, targetOrder: []);
    api.sidebarMoveGate = Completer<void>();
    await _transfer(tester);
    final controller = ShellScope.read(
      tester.element(find.byType(InstanceSidebar)),
    );
    await controller.disconnectCurrentInstance();
    await tester.pumpAndSettle();
    final sections = controller.customSidebarSectionsFor(_site);
    api.sidebarMoveGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.currentInstance!.isConnected, isFalse);
    expect(controller.customSidebarSectionsFor(_site), same(sections));
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    platformTest('long press transfers across sections on $platform', (
      tester,
    ) async {
      final api = await _pump(
        tester,
        sourceOrder: [11],
        targetOrder: [],
        size: phone,
      );
      await tester.ensureVisible(find.text('Team links'));
      await tester.pumpAndSettle();
      await _transfer(tester, touch: true);
      expect(api.sidebarMoves.single.linkId, 11);
      expect(_sectionOrder(tester, 10), [11]);
      expect(tester.takeException(), isNull);
    }, platform: platform);
  }

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

  void publish(FakeSiteTracker tracker) =>
      tracker.deliverPluginMessage('/refresh-sidebar-sections', null);

  void editOnServer(FakeDiscourseApi api, List<int> order) =>
      api.customSidebarSectionsBySite[_site] = [
        SidebarSection.customFromJson(
          _json(public: true, order: order),
          index: 0,
        )!,
      ];

  platformTest('reloads sections when Core announces a public change', (
    tester,
  ) async {
    final api = await _pump(tester);
    expect(api.customSidebarSectionRequests, [_site]);
    editOnServer(api, [11, 22, 33, 44]);
    publish(FakeSiteTracker.built.single);
    await tester.pumpAndSettle();
    expect(sidebarDestination('Link 44'), findsOneWidget);
    expect(_sectionOrder(tester, 9), [11, 22, 33, 44]);
    expect(api.customSidebarSectionRequests, [_site, _site]);
    expect(tester.takeException(), isNull);
  });

  platformTest('a later announcement supersedes a reload in flight', (
    tester,
  ) async {
    final api = await _pump(tester);
    final tracker = FakeSiteTracker.built.single;
    final earlier = api.customSidebarSectionsGate = Completer<void>();
    editOnServer(api, [11, 22]);
    publish(tracker);
    await tester.pump();
    api.customSidebarSectionsGate = null;
    editOnServer(api, [11, 22, 33, 44]);
    publish(tracker);
    await tester.pumpAndSettle();
    expect(_sectionOrder(tester, 9), [11, 22, 33, 44]);
    earlier.complete();
    await tester.pumpAndSettle();
    expect(_sectionOrder(tester, 9), [11, 22, 33, 44]);
    expect(api.customSidebarSectionRequests, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  platformTest('an announcement for a previous account does not reload', (
    tester,
  ) async {
    final api = await _pump(tester);
    // A transport may already have queued the previous account's delivery.
    final queued = FakeSiteTracker
        .built
        .single
        .pluginChannelCallbacks['/refresh-sidebar-sections']!
        .single;
    final controller = ShellScope.read(
      tester.element(find.byType(InstanceSidebar)),
    );
    await controller.disconnectCurrentInstance();
    await tester.pumpAndSettle();
    await controller.connectCurrentInstance();
    await tester.pumpAndSettle();
    expect(controller.currentInstance!.isConnected, isTrue);
    final requests = api.customSidebarSectionRequests.length;
    queued(null);
    await tester.pumpAndSettle();
    expect(api.customSidebarSectionRequests, hasLength(requests));
    publish(FakeSiteTracker.built.last);
    await tester.pumpAndSettle();
    expect(api.customSidebarSectionRequests, hasLength(requests + 1));
    expect(tester.takeException(), isNull);
  });
}
