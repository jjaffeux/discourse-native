import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart' show TopicCategory;
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/plugins/boards/boards_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';
import '../../support/native_ui_evidence.dart';

typedef BoardCapture = Future<void> Function(WidgetTester tester, String name);

void main() => boardsWidgetTests();

void boardsWidgetTests({bool nativeView = false, BoardCapture? onCapture}) {
  Widget retainedPage(
    BoardsFixture fixture, {
    String site = boardsSite,
    BoardsRoute route = const BoardsRoute(boardId: 1),
  }) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: BoardsPage(
        key: const ValueKey('retained-board-page'),
        site: site,
        route: route,
        controller: fixture.controller,
        navigation: fixture.navigation,
      ),
    ),
  );

  void setEnabled(BoardsFixture fixture, bool enabled) {
    fixture.config = SiteConfig(
      plugins: PluginData.none.withValue(
        boardsSettingsKey,
        BoardsSettings(enabled: enabled),
      ),
    );
  }

  testWidgets('pending board uses skeletons without a refresh button', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        pending.future;
    await prepareNativeUiEvidence(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => nativeUiEvidenceBuilder(
          context,
          MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: RepaintBoundary(
          key: const ValueKey('boards-native-capture'),
          child: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureNativeUi(tester, 'board-loading');
    await onCapture?.call(tester, 'board-loading');
    expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
    expect(find.byType(DSpinner), findsNothing);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.byType(DSkeleton), findsWidgets);
    expect(fixture.transport.reads, hasLength(1));
    pending.complete(boardFixtureJson());
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.text('Improve search'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending board retry uses Retry without a Refresh control', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    var pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        pending.future;
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pump();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.byType(DSpinner), findsNothing);
    pending.completeError(StateError('Board unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Board unavailable'), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
    expect(find.widgetWithText(DButton, 'Retry'), findsOneWidget);
    pending = Completer<Map<String, dynamic>>();
    await tester.tap(find.widgetWithText(DButton, 'Retry'));
    await tester.pump();
    expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
    expect(find.byType(DSpinner), findsNothing);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(fixture.transport.reads, hasLength(2));
    pending.complete(boardFixtureJson());
    await tester.pumpAndSettle();
    expect(find.text('Improve search'), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('board pull refresh keeps cards and has no Refresh menu item', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-controls')));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('Open in browser'), findsOneWidget);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    final pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        pending.future;
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('board-title'))),
      const Offset(0, 500),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.transport.reads, hasLength(2));
    expect(find.text('Improve search'), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('board-title'))),
      const Offset(0, 500),
    );
    await tester.pump();
    expect(fixture.transport.reads, hasLength(2));
    pending.completeError(StateError('Board refresh unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Improve search'), findsOneWidget);
    expect(find.textContaining('Board refresh unavailable'), findsOneWidget);
    final refreshed = boardFixtureJson();
    (refreshed['board'] as Map)['name'] = 'Refreshed board';
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        refreshed;
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('board-title'))),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('Refreshed board'), findsOneWidget);
    expect(find.textContaining('Board refresh unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a read-only board has no empty actions menu or Refresh control',
    (tester) async {
      final fixture = BoardsFixture(json: boardFixtureJson(canManage: false));
      addTearDown(fixture.dispose);
      await tester.pumpWidget(retainedPage(fixture));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('board-controls')), findsNothing);
      expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
      expect(find.text('Improve search'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pending board skeleton fits narrow large text and RTL', (
    tester,
  ) async {
    if (!nativeView) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        pending.future;
    await prepareNativeUiEvidence(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => nativeUiEvidenceBuilder(
          context,
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
        ),
        home: RepaintBoundary(
          key: const ValueKey('boards-native-capture'),
          child: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
    expect(tester.takeException(), isNull);
    await captureNativeUi(tester, 'board-loading-narrow-rtl');
    await onCapture?.call(tester, 'board-loading-narrow-rtl');
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(boardFixtureJson());
    await tester.pumpAndSettle();
  });

  for (final initiallyEnabled in [true, false]) {
    testWidgets(
      'retained detail activates with initially enabled $initiallyEnabled',
      (tester) async {
        final fixture = BoardsFixture(enabled: initiallyEnabled);
        addTearDown(fixture.dispose);
        fixture.controller.activatePluginSite(boardsSite, connected: true);
        await tester.pumpWidget(retainedPage(fixture));
        await tester.pumpAndSettle();
        if (!initiallyEnabled) {
          expect(
            find.text('Boards is not enabled on this site.'),
            findsOneWidget,
          );
          expect(fixture.transport.reads, isEmpty);
          setEnabled(fixture, true);
          await tester.pumpAndSettle();
        }
        expect(fixture.transport.reads.map((request) => request.path), [
          '/boards/api/boards/1.json',
        ]);
        expect(find.text('Improve search'), findsOneWidget);
        expect(fixture.live.subscriberCount('/boards/1'), 1);
        fixture.controller.changed();
        await tester.pumpAndSettle();
        expect(fixture.transport.reads, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(fixture.live.channels, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('retained page releases only its shared board reference', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.controller.activatePluginSite(boardsSite, connected: true);
    final external = fixture.controller.acquire(boardsSite, 1);
    await tester.pump();
    expect(external.snapshot?.name, 'Product roadmap');
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pumpAndSettle();
    expect(find.text('Improve search'), findsOneWidget);
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    setEnabled(fixture, false);
    await tester.pumpAndSettle();
    expect(external.snapshot, isNull);
    expect(fixture.live.channels, isEmpty);
    (fixture.data['board'] as Map)['name'] = 'Refreshed shared board';
    setEnabled(fixture, true);
    await tester.pumpAndSettle();
    expect(external.snapshot?.name, 'Refreshed shared board');
    expect(find.text('Refreshed shared board'), findsOneWidget);
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    for (var notification = 0; notification < 3; notification++) {
      fixture.controller.changed();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(external.snapshot?.name, 'Refreshed shared board');
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    external.release();
    expect(fixture.live.channels, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained directory activates on each enable transition', (
    tester,
  ) async {
    final fixture = BoardsFixture(enabled: false);
    addTearDown(fixture.dispose);
    fixture.controller.activatePluginSite(boardsSite, connected: true);
    await tester.pumpWidget(retainedPage(fixture, route: const BoardsRoute()));
    await tester.pumpAndSettle();
    expect(fixture.transport.reads, isEmpty);
    for (var cycle = 0; cycle < 2; cycle++) {
      setEnabled(fixture, true);
      await tester.pumpAndSettle();
      expect(find.text('Product roadmap'), findsOneWidget);
      expect(
        fixture.transport.reads.map((request) => request.path),
        List.filled(cycle + 1, '/boards/api/boards.json'),
      );
      expect(fixture.live.channels, isEmpty);
      setEnabled(fixture, false);
      await tester.pumpAndSettle();
      expect(find.text('Boards is not enabled on this site.'), findsOneWidget);
      expect(find.text('Product roadmap'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    setEnabled(fixture, true);
    await tester.pumpAndSettle();
    expect(fixture.transport.reads, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained directory recovers from coalesced settings changes', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.controller.activatePluginSite(boardsSite, connected: true);
    var cycle = false;
    Widget host() => Builder(
      builder: (_) {
        if (cycle) {
          cycle = false;
          setEnabled(fixture, false);
          setEnabled(fixture, true);
        }
        return retainedPage(fixture, route: const BoardsRoute());
      },
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(fixture.transport.reads, hasLength(1));
    expect(find.text('Product roadmap'), findsOneWidget);
    (fixture.data['board'] as Map)['name'] = 'Refreshed directory board';
    cycle = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(fixture.controller.enabled(boardsSite), isTrue);
    expect(fixture.transport.reads.map((request) => request.path), [
      '/boards/api/boards.json',
      '/boards/api/boards.json',
    ]);
    expect(find.text('Refreshed directory board'), findsOneWidget);
    expect(find.text('Product roadmap'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reenabling detail fences a read from the disabled account', (
    tester,
  ) async {
    final fixture = BoardsFixture(enabled: false);
    addTearDown(fixture.dispose);
    fixture.controller.activatePluginSite(boardsSite, connected: true);
    final old = Completer<Map<String, dynamic>>();
    var reads = 0;
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) {
      if (++reads == 1) return old.future;
      final fresh = boardFixtureJson();
      (fresh['board'] as Map)['name'] = 'Current board';
      return fresh;
    };
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pumpAndSettle();
    setEnabled(fixture, true);
    await tester.pump();
    expect(reads, 1);
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    setEnabled(fixture, false);
    await tester.pumpAndSettle();
    expect(find.text('Boards is not enabled on this site.'), findsOneWidget);
    expect(fixture.live.channels, isEmpty);
    fixture.requests.forget(boardsSite);
    setEnabled(fixture, true);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Current board'), findsOneWidget);
    final stale = boardFixtureJson();
    (stale['board'] as Map)['name'] = 'Private retired board';
    old.complete(stale);
    await tester.pumpAndSettle();
    expect(find.text('Current board'), findsOneWidget);
    expect(find.text('Private retired board'), findsNothing);
    expect(fixture.live.subscriberCount('/boards/1'), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.live.channels, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reenabled directory ignores the old pending failure', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    fixture.controller.activatePluginSite(boardsSite, connected: true);
    late final Completer<Map<String, dynamic>> old;
    var reads = 0;
    fixture.transport.responders['GET /boards/api/boards.json'] = (_) {
      if (++reads == 1) {
        old = Completer<Map<String, dynamic>>();
        return old.future;
      }
      return {
        'boards': [
          {'id': 2, 'name': 'Current directory board'},
        ],
      };
    };
    await tester.pumpWidget(retainedPage(fixture, route: const BoardsRoute()));
    await tester.pump();
    expect(reads, 1);
    setEnabled(fixture, false);
    await tester.pumpAndSettle();
    expect(find.text('Boards is not enabled on this site.'), findsOneWidget);
    setEnabled(fixture, true);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Current directory board'), findsOneWidget);
    old.completeError(StateError('Retired private directory failure'));
    await tester.pumpAndSettle();
    expect(find.text('Current directory board'), findsOneWidget);
    expect(
      find.textContaining('Retired private directory failure'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained detail transfers ownership to its new controller', (
    tester,
  ) async {
    final first = BoardsFixture();
    final json = boardFixtureJson();
    (json['board'] as Map)['name'] = 'Replacement controller board';
    final second = BoardsFixture(json: json);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.controller.activatePluginSite(boardsSite, connected: true);
    second.controller.activatePluginSite(boardsSite, connected: true);
    await tester.pumpWidget(retainedPage(first));
    await tester.pumpAndSettle();
    expect(first.live.subscriberCount('/boards/1'), 1);
    final oldPull = Completer<Map<String, dynamic>>();
    first.transport.responders['GET /boards/api/boards/1.json'] = (_) =>
        oldPull.future;
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('board-title'))),
      const Offset(0, 500),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('Refreshing'), findsOneWidget);
    await tester.pumpWidget(retainedPage(second));
    await tester.pump();
    expect(find.bySemanticsLabel('Refreshing'), findsNothing);
    oldPull.complete(boardFixtureJson());
    await tester.pumpAndSettle();
    expect(find.text('Replacement controller board'), findsOneWidget);
    expect(first.live.channels, isEmpty);
    expect(second.live.subscriberCount('/boards/1'), 1);
    expect(second.transport.reads.single.path, '/boards/api/boards/1.json');
    setEnabled(first, false);
    await tester.pumpAndSettle();
    expect(find.text('Replacement controller board'), findsOneWidget);
    setEnabled(second, false);
    await tester.pumpAndSettle();
    expect(find.text('Boards is not enabled on this site.'), findsOneWidget);
    expect(second.live.channels, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled retained route admits only its latest site and board', (
    tester,
  ) async {
    const otherSite = 'https://other.example';
    final fixture = BoardsFixture(enabled: false);
    addTearDown(fixture.dispose);
    fixture.controller.activatePluginSite(boardsSite, connected: true);
    fixture.controller.activatePluginSite(otherSite, connected: true);
    fixture.transport.responders['GET /boards/api/boards/2.json'] = (_) {
      final json = boardFixtureJson();
      (json['board'] as Map)
        ..['id'] = 2
        ..['name'] = 'Latest route board';
      return json;
    };
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      retainedPage(
        fixture,
        site: otherSite,
        route: const BoardsRoute(boardId: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.transport.reads, isEmpty);
    setEnabled(fixture, true);
    await tester.pumpAndSettle();
    expect(find.text('Latest route board'), findsOneWidget);
    expect(fixture.transport.reads.single.siteUrl, otherSite);
    expect(fixture.transport.reads.single.path, '/boards/api/boards/2.json');
    expect(fixture.live.channels, ['/boards/2']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.live.channels, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('board header follows the topic reader outside the sheet', (
    tester,
  ) async {
    final json = boardFixtureJson();
    (json['board'] as Map)
      ..['tag_names'] = ['roadmap']
      ..['category_ids'] = [5];
    final fixture = BoardsFixture(
      json: json,
      categories: {
        5: const TopicCategory(id: 5, name: 'Support', color: '12b5d8'),
      },
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pumpAndSettle();
    final back = find.byKey(const ValueKey('board-back'));
    final title = tester.getRect(find.byKey(const ValueKey('board-title')));
    expect(tester.getRect(back).bottom, lessThanOrEqualTo(title.top));
    for (final control in [
      find.text('Support'),
      find.text('# roadmap'),
      find.byKey(const ValueKey('board-controls')),
    ]) {
      expect(tester.getRect(control).top, greaterThanOrEqualTo(title.bottom));
    }
    await tester.tap(back);
    expect(fixture.host.currentContent?.id, 'boards');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('board columns keep their scrollbar outside the sheet', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(retainedPage(fixture));
    await tester.pumpAndSettle();
    final scrollbar = find.ancestor(
      of: find.byKey(const ValueKey('board-column-10')),
      matching: find.byWidgetPredicate(
        (widget) => widget is DScrollBar && widget.axis == Axis.horizontal,
      ),
    );
    expect(tester.widget<DScrollBar>(scrollbar).showScrollbar, true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  if (!nativeView) {
    testWidgets('board columns do not repeat the page safe inset', (
      tester,
    ) async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                padding: EdgeInsets.only(top: 70, bottom: 34),
                viewPadding: EdgeInsets.only(top: 70, bottom: 34),
              ),
              child: BoardsPage(
                site: boardsSite,
                route: const BoardsRoute(boardId: 1),
                controller: fixture.controller,
                navigation: fixture.navigation,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const PageStorageKey('board-column-list-10'));
      final card = find.ancestor(
        of: find.text('Improve search'),
        matching: find.byType(DItem),
      );
      expect(tester.getTopLeft(card).dy, tester.getTopLeft(list).dy);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('wide board card links reveal a distant column and card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = boardFixtureJson();
      final columns = json['columns'] as List;
      for (var i = 3; i < 8; i++) {
        columns.add({
          'id': 10 + i,
          'title': 'Column $i',
          'default_sort': 'priority',
          'cards': [
            for (var j = 0; j < 40; j++)
              {
                'id': i * 1000 + j,
                'column_id': 10 + i,
                'card_type': 'floater',
                'title': 'Distant task $i $j',
              },
          ],
        });
      }
      final fixture = BoardsFixture(json: json);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1, cardId: 7039),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final target = find.text('Distant task 7 39');
      expect(target, findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1000));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(760));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'directory site change ignores the old pending request and failure',
    (tester) async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      late final Completer<Map<String, dynamic>> old;
      fixture.transport.responders['GET /boards/api/boards.json'] = (request) {
        if (request.siteUrl == boardsSite) {
          old = Completer<Map<String, dynamic>>();
          return old.future;
        }
        return {
          'boards': [
            {'id': 2, 'name': 'Second community board'},
          ],
        };
      };
      Widget page(String site) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BoardsPage(
            key: const ValueKey('directory'),
            site: site,
            route: const BoardsRoute(),
            controller: fixture.controller,
            navigation: fixture.navigation,
          ),
        ),
      );
      await tester.pumpWidget(page(boardsSite));
      await tester.pump();
      await tester.pumpWidget(page('https://other.example'));
      await tester.pumpAndSettle();
      expect(find.text('Second community board'), findsOneWidget);
      old.completeError(StateError('Old private forum failure'));
      await tester.pumpAndSettle();
      expect(find.text('Second community board'), findsOneWidget);
      expect(find.textContaining('Old private forum failure'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'saving a retained standalone draft does not undo a remote column move',
    (tester) async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write release notes'));
      await tester.pumpAndSettle();
      final from = fixture.columns.first['cards'] as List;
      final card = from.firstWhere((raw) => boardObject(raw)['id'] == 102);
      from.remove(card);
      (card as Map)['column_id'] = 11;
      (fixture.columns[1]['cards'] as List).add(card);
      fixture.live.deliver('/boards/1', {'type': 'card_moved'});
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(DTextarea),
        'New notes after a remote move.',
      );
      await tester.tap(find.widgetWithText(DButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        (fixture.transport.writes.last.body['card'] as Map).containsKey(
          'column_id',
        ),
        isFalse,
      );
      expect(
        (fixture.columns[1]['cards'] as List).where(
          (raw) => boardObject(raw)['id'] == 102,
        ),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'account retirement hides private editor text and prevents a stale save',
    (tester) async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write release notes'));
      await tester.pumpAndSettle();
      expect(find.byType(DTextarea), findsOneWidget);
      fixture.requests.forget(boardsSite);
      fixture.controller.forget(boardsSite);
      await tester.pumpAndSettle();
      expect(find.byType(DTextarea), findsNothing);
      expect(find.widgetWithText(DButton, 'Save'), findsNothing);
      expect(fixture.transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('setting disabling retires an open move picker', (tester) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BoardsPage(
            site: boardsSite,
            route: const BoardsRoute(boardId: 1),
            controller: fixture.controller,
            navigation: fixture.navigation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('Write release notes'),
      matching: find.byType(DItem),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byType(DDropdownMenuTrigger)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    fixture.config = SiteConfig(
      plugins: PluginData.none.withValue(
        boardsSettingsKey,
        const BoardsSettings(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Product roadmap'), findsNothing);
    expect(find.byType(DSelect<int>), findsNothing);
    expect(find.widgetWithText(DButton, 'Move'), findsNothing);
    expect(fixture.live.channels, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('board reader and native move menu persist the server move', (
    tester,
  ) async {
    if (!nativeView) {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    await prepareNativeUiEvidence(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: nativeUiEvidenceBuilder,
        home: RepaintBoundary(
          key: const ValueKey('boards-native-capture'),
          child: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Product roadmap'), findsOneWidget);
    expect(find.text('Improve search'), findsOneWidget);
    expect(find.text('Write release notes'), findsOneWidget);
    await captureNativeUi(tester, 'boards-reader');
    await onCapture?.call(tester, 'boards-reader');
    final card = find.ancestor(
      of: find.text('Write release notes'),
      matching: find.byType(DItem),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byType(DDropdownMenuTrigger)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    final dialog = find.byType(DDialogContent);
    final selector = find
        .descendant(of: dialog, matching: find.byType(DSelect<int>))
        .first;
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('In progress').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DButton, 'Move').last);
    await tester.pumpAndSettle();
    expect(
      fixture.transport.writes.last.path,
      '/boards/api/boards/1/cards/102',
    );
    expect(
      (fixture.transport.writes.last.body['card'] as Map)['column_id'],
      11,
    );
    expect(tester.takeException(), isNull);
    await captureNativeUi(tester, 'boards-after-move');
    await onCapture?.call(tester, 'boards-after-move');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'compact board creates standalone cards and opens native topics',
    (tester) async {
      if (!nativeView) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: nativeUiEvidenceBuilder,
          home: RepaintBoundary(
            key: const ValueKey('boards-native-capture'),
            child: Scaffold(
              body: BoardsPage(
                site: boardsSite,
                route: const BoardsRoute(boardId: 1),
                controller: fixture.controller,
                navigation: fixture.navigation,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Improve search'));
      expect(fixture.host.openedTopic, 500);
      await tester.tap(find.byKey(const ValueKey('board-add-10')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DDropdownMenuItem, 'Add card'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(DInput).first,
        'Review native release',
      );
      await tester.enterText(find.byType(DTextarea), 'Check both devices.');
      await tester.tap(find.widgetWithText(DButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Review native release'), findsOneWidget);
      expect(fixture.transport.writes.last.method, 'POST');
      expect(tester.takeException(), isNull);
      await captureNativeUi(tester, 'boards-new-card');
      await onCapture?.call(tester, 'boards-new-card');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disabled board route renders no board controls or data', (
    tester,
  ) async {
    final fixture = BoardsFixture(enabled: false);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('boards-native-capture'),
          child: Scaffold(
            body: BoardsPage(
              site: boardsSite,
              route: const BoardsRoute(boardId: 1),
              controller: fixture.controller,
              navigation: fixture.navigation,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Boards is not enabled on this site.'), findsOneWidget);
    expect(find.text('Product roadmap'), findsNothing);
    expect(find.byType(DButton), findsNothing);
    expect(fixture.transport.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
