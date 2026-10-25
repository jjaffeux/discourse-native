import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/plugins/boards/boards_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/boards_fixture.dart';
import '../../support/native_ui_evidence.dart';

typedef BoardCapture = Future<void> Function(WidgetTester tester, String name);

void main() => boardsWidgetTests();

void boardsWidgetTests({bool nativeView = false, BoardCapture? onCapture}) {
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
      await tester.tap(find.text('Improve search'));
      expect(fixture.host.openedTopic, 500);
      await tester.tap(find.widgetWithText(DButton, 'New card').first);
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
