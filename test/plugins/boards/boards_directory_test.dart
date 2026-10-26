import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart' show TopicCategory;
import 'package:discourse_native/src/plugins/boards/boards_navigation.dart';
import 'package:discourse_native/src/plugins/boards/boards_page.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/boards_fixture.dart';
import '../../support/native_ui_evidence.dart';

Map<String, dynamic> directoryBoard(
  int id,
  String name, {
  bool archived = false,
  bool simple = false,
  bool? public,
  String? creator,
  List<String> columns = const ['To do', 'Doing', 'Done'],
  List<String> tags = const [],
}) => {
  'id': id,
  'name': name,
  'archived': archived,
  'card_style': simple ? 'simple' : 'detailed',
  'anonymous_can_read': ?public,
  if (creator != null) 'created_by': {'username': creator},
  'tag_names': tags,
  'columns': [
    for (var i = 0; i < columns.length; i++)
      {'id': id * 100 + i, 'title': columns[i], 'icon': 'check'},
  ],
};

void main() => boardsDirectoryWidgetTests();

void boardsDirectoryWidgetTests({
  bool nativeView = false,
  Future<void> Function(WidgetTester, String)? onCapture,
}) {
  void resize(WidgetTester tester, Size size) {
    if (nativeView) return;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget page(
    BoardsFixture fixture, {
    String site = boardsSite,
    bool dark = false,
    double scale = 1,
    bool disableAnimations = false,
    AppSettingsController? settings,
  }) {
    Widget body = BoardsPage(
      key: const ValueKey('directory-page'),
      site: site,
      route: const BoardsRoute(),
      controller: fixture.controller,
      navigation: fixture.navigation,
    );
    if (settings != null) {
      body = ContentSettingsScope(
        controller: settings,
        child: DPageContentSettings(
          limitContentSize: settings.limitContentSize,
          child: body,
        ),
      );
    }
    return MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => nativeUiEvidenceBuilder(
        context,
        MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
      ),
      home: RepaintBoundary(
        key: const ValueKey('boards-native-capture'),
        child: Scaffold(body: body),
      ),
    );
  }

  void respond(BoardsFixture fixture, List<Map<String, dynamic>> boards) {
    fixture.transport.responders['GET /boards/api/boards.json'] = (_) => {
      'boards': boards,
    };
  }

  testWidgets('pending directory uses card skeletons until boards arrive', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards.json'] = (_) =>
        pending.future;
    await prepareNativeUiEvidence(tester);
    await tester.pumpWidget(page(fixture, disableAnimations: true));
    await tester.pumpAndSettle();
    await captureNativeUi(tester, 'boards-directory-loading');
    await onCapture?.call(tester, 'boards-directory-loading');
    expect(find.byType(DSpinner), findsNothing);
    expect(find.byType(DSkeletonRegion), findsWidgets);
    expect(find.byType(DPlaceCardSkeleton), findsWidgets);
    expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
    expect(fixture.transport.reads, hasLength(1));
    pending.complete({
      'boards': [directoryBoard(1, 'Team roadmap')],
    });
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.text('Team roadmap'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending directory skeleton fits narrow large text', (
    tester,
  ) async {
    resize(tester, const Size(320, 740));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    final pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards.json'] = (_) =>
        pending.future;
    await prepareNativeUiEvidence(tester);
    await tester.pumpWidget(page(fixture, scale: 2, disableAnimations: true));
    await tester.pumpAndSettle();
    expect(find.byType(DPlaceCardSkeleton), findsWidgets);
    expect(find.byType(DSpinner), findsNothing);
    expect(tester.takeException(), isNull);
    await captureNativeUi(tester, 'boards-directory-loading-narrow');
    await onCapture?.call(tester, 'boards-directory-loading-narrow');
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete({'boards': <Object?>[]});
    await tester.pumpAndSettle();
  });

  for (final limited in [false, true]) {
    testWidgets(
      'directory cards align with the heading and filters at width preference $limited',
      (tester) async {
        resize(tester, const Size(1280, 800));
        SharedPreferences.setMockInitialValues({});
        final settings = AppSettingsController();
        addTearDown(settings.dispose);
        await settings.setLimitContentSize(limited);
        final fixture = BoardsFixture();
        addTearDown(fixture.dispose);
        respond(fixture, [
          for (var id = 1; id <= 12; id++) directoryBoard(id, 'Board $id'),
        ]);
        await prepareNativeUiEvidence(tester);
        await tester.pumpWidget(page(fixture, settings: settings));
        await tester.pumpAndSettle();
        final title = tester.getRect(find.text('Boards'));
        final search = tester.getRect(find.byType(DInput));
        final controls = tester.getRect(find.byType(DControlWrap));
        final cards = find.byType(DPlaceCard);
        final first = tester.getRect(cards.first);
        final row = [
          for (var i = 0; i < cards.evaluate().length; i++)
            tester.getRect(cards.at(i)),
        ].where((rect) => (rect.top - first.top).abs() < 0.01);
        expect(title.left, closeTo(search.left, 0.01));
        expect(first.left, closeTo(controls.left, 0.01));
        expect(row.last.right, closeTo(controls.right, 0.01));
        expect(
          find.text('Create and manage boards with columns.'),
          findsNothing,
        );
        final viewportWidth = tester.getSize(find.byType(Scaffold)).width;
        final headerWidth = limited
            ? viewportWidth.clamp(0.0, DPageReadingLane.maxWidth)
            : viewportWidth;
        expect(
          title.left,
          closeTo((viewportWidth - headerWidth) / 2 + 16, 0.01),
        );
        expect(controls.width, closeTo(headerWidth - 32, 0.01));
        await captureNativeUi(tester, 'boards-directory-header-$limited');
        await onCapture?.call(tester, 'boards-directory-header-$limited');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'directory uses category cards and exposes board metadata without detail requests',
    (tester) async {
      resize(tester, const Size(1100, 800));
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      respond(fixture, [
        directoryBoard(
          1,
          'AI Team',
          creator: 'lee',
          public: false,
          tags: ['ai'],
        ),
        directoryBoard(
          2,
          'Design team board',
          simple: true,
          public: true,
          columns: ['UI Kit', 'Blocks'],
        ),
        directoryBoard(3, 'Past launches', archived: true, columns: []),
        directoryBoard(4, 'Operations', columns: ['Triage']),
      ]);
      await prepareNativeUiEvidence(tester);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      expect(find.byType(DPlaceCard), findsNWidgets(4));
      expect(find.text('Created by lee'), findsOneWidget);
      expect(find.text('3 columns'), findsOneWidget);
      expect(find.text('2 columns'), findsOneWidget);
      expect(find.text('0 columns'), findsOneWidget);
      expect(find.text('Simple'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DIcon && widget.semanticLabel == 'Private board',
        ),
        findsOneWidget,
      );
      expect(fixture.transport.reads.map((request) => request.path), [
        '/boards/api/boards.json',
      ]);
      if (!nativeView) {
        final cards = find.byType(DPlaceCard);
        final first = tester.getRect(cards.at(0));
        final second = tester.getRect(cards.at(1));
        expect(first.top, second.top);
        final fourth = tester.getRect(cards.at(3));
        expect(fourth.top, first.top);
        expect(fourth.right, greaterThan(1000));
        await tester.tapAt(
          Offset((first.right + second.left) / 2, first.center.dy),
        );
        expect(fixture.host.currentContent, isNull);
      }
      await captureNativeUi(tester, 'boards-directory-wide');
      await onCapture?.call(tester, 'boards-directory-wide');
      await tester.tap(find.text('Design team board'));
      expect(fixture.host.currentContent?.id, 'boards/2');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'directory search and status filter compose without network reads',
    (tester) async {
      resize(tester, const Size(900, 800));
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      respond(fixture, [
        directoryBoard(1, 'Team roadmap', tags: ['native']),
        directoryBoard(2, 'Team archive', archived: true, tags: ['native']),
        directoryBoard(3, 'Marketing'),
      ]);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(DInput), ' NATIVE team ');
      await tester.pumpAndSettle();
      expect(find.text('Team roadmap'), findsOneWidget);
      expect(find.text('Team archive'), findsOneWidget);
      expect(find.text('Marketing'), findsNothing);
      await tester.tap(find.text('All boards'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archived boards').last);
      await tester.pumpAndSettle();
      expect(find.text('Team archive'), findsOneWidget);
      expect(find.text('Team roadmap'), findsNothing);
      await tester.enterText(find.byType(DInput), 'unmatched');
      await tester.pumpAndSettle();
      expect(find.text('No boards match your filters.'), findsOneWidget);
      expect(fixture.transport.reads, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'directory search matches column and category names and active hides archives',
    (tester) async {
      resize(tester, const Size(900, 800));
      final fixture = BoardsFixture(
        categories: {
          7: const TopicCategory(id: 7, name: 'Support', color: '12b5d8'),
        },
      );
      addTearDown(fixture.dispose);
      respond(fixture, [
        directoryBoard(1, 'Roadmap', columns: ['Triage']),
        {
          ...directoryBoard(2, 'Helpdesk'),
          'category_ids': [7],
        },
        directoryBoard(3, 'Old roadmap', archived: true),
      ]);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(DInput), 'triage');
      await tester.pumpAndSettle();
      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.text('Helpdesk'), findsNothing);
      await tester.enterText(find.byType(DInput), 'support');
      await tester.pumpAndSettle();
      expect(find.text('Helpdesk'), findsOneWidget);
      expect(find.text('Roadmap'), findsNothing);
      await tester.enterText(find.byType(DInput), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('All boards'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active boards').last);
      await tester.pumpAndSettle();
      expect(find.text('Roadmap'), findsOneWidget);
      expect(find.text('Helpdesk'), findsOneWidget);
      expect(find.text('Old roadmap'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> pull(WidgetTester tester) async {
    await tester.drag(find.byType(DPullToRefresh), const Offset(0, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'pulling the directory keeps its cards and filters while it refreshes',
    (tester) async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      respond(fixture, [directoryBoard(1, 'Team roadmap')]);
      await tester.pumpWidget(page(fixture));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(DButton, 'Refresh'), findsNothing);
      await tester.enterText(find.byType(DInput), 'team');
      await tester.pumpAndSettle();
      final pending = Completer<Map<String, dynamic>>();
      fixture.transport.responders['GET /boards/api/boards.json'] = (_) =>
          pending.future;
      await pull(tester);
      expect(find.bySemanticsLabel('Refreshing'), findsOneWidget);
      expect(find.byType(DSpinner), findsOneWidget);
      expect(find.text('Team roadmap'), findsOneWidget);
      pending.complete({
        'boards': [
          directoryBoard(2, 'Team release'),
          directoryBoard(3, 'Other'),
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Team release'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      expect(find.text('Team roadmap'), findsNothing);
      expect(find.byType(DSpinner), findsNothing);
      expect(fixture.transport.reads, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a failed directory pull keeps its cards and can retry', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    respond(fixture, [directoryBoard(1, 'Team roadmap')]);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    final pending = Completer<Map<String, dynamic>>();
    fixture.transport.responders['GET /boards/api/boards.json'] = (_) =>
        pending.future;
    await pull(tester);
    pending.completeError(StateError('Directory unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Directory unavailable'), findsOneWidget);
    expect(find.text('Team roadmap'), findsOneWidget);
    respond(fixture, [directoryBoard(2, 'Team release')]);
    await tester.tap(find.widgetWithText(DButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Directory unavailable'), findsNothing);
    expect(find.text('Team release'), findsOneWidget);
    expect(fixture.transport.reads, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to the directory shows its boards without a read', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    respond(fixture, [directoryBoard(1, 'Team roadmap')]);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    respond(fixture, [directoryBoard(2, 'Team release')]);
    await tester.pumpWidget(page(fixture));
    expect(find.byType(DSpinner), findsNothing);
    expect(find.text('Team roadmap'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Team roadmap'), findsOneWidget);
    expect(fixture.transport.reads, hasLength(1));
    await pull(tester);
    await tester.pumpAndSettle();
    expect(find.text('Team release'), findsOneWidget);
    expect(fixture.transport.reads, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'directory loading failure can retry and distinguish an empty directory',
    (tester) async {
      final fixture = BoardsFixture();
      addTearDown(fixture.dispose);
      late final Completer<Map<String, dynamic>> pending;
      fixture.transport.responders['GET /boards/api/boards.json'] = (_) {
        pending = Completer<Map<String, dynamic>>();
        return pending.future;
      };
      await tester.pumpWidget(page(fixture));
      await tester.pump();
      expect(find.byType(DPlaceCardSkeleton), findsWidgets);
      expect(find.byType(DSpinner), findsNothing);
      await pull(tester);
      expect(find.byType(DPlaceCardSkeleton), findsWidgets);
      expect(find.byType(DSpinner), findsNothing);
      expect(fixture.transport.reads, hasLength(1));
      pending.completeError(StateError('Directory unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Directory unavailable'), findsOneWidget);
      respond(fixture, []);
      await tester.tap(find.widgetWithText(DButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No boards are available.'), findsOneWidget);
      expect(find.text('No boards match your filters.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('directory filters reset after site and account changes', (
    tester,
  ) async {
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    respond(fixture, [directoryBoard(1, 'Team roadmap')]);
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(DInput), 'unmatched');
    await tester.pumpAndSettle();
    await tester.pumpWidget(page(fixture, site: 'https://other.example'));
    await tester.pumpAndSettle();
    expect(find.text('Team roadmap'), findsOneWidget);
    await tester.enterText(find.byType(DInput), 'unmatched');
    await tester.pumpAndSettle();
    fixture.requests.forget('https://other.example');
    fixture.controller.forget('https://other.example');
    await tester.pumpAndSettle();
    expect(find.text('Team roadmap'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('directory scroll resets for another site and account', (
    tester,
  ) async {
    resize(tester, const Size(800, 600));
    final fixture = BoardsFixture();
    addTearDown(fixture.dispose);
    respond(fixture, [
      for (var id = 1; id <= 40; id++) directoryBoard(id, 'Board $id'),
    ]);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    await tester.pumpWidget(page(fixture));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(0));
    await tester.pumpWidget(page(fixture, site: 'https://other.example'));
    await tester.pumpAndSettle();
    expect(position().pixels, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(position().pixels, greaterThan(0));
    fixture.requests.forget('https://other.example');
    fixture.controller.forget('https://other.example');
    await tester.pumpAndSettle();
    expect(position().pixels, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'narrow directory wraps long columns and creator at 2x text at width $width',
      (tester) async {
        resize(tester, Size(width, 1100));
        final fixture = BoardsFixture();
        addTearDown(fixture.dispose);
        respond(fixture, [
          directoryBoard(
            1,
            'Enterprise setup',
            creator: 'a_very_long_creator_username_for_this_board',
            public: false,
            columns: [
              'Active concerns',
              'AWS Setup',
              'Metal setup',
              'Community Success',
              'Training',
              'Site customization',
              'Launching this month',
              'Balance due',
              'POST LAUNCH CHECK-IN',
              'Case study opportunity',
            ],
          ),
        ]);
        await prepareNativeUiEvidence(tester);
        await tester.pumpWidget(page(fixture, dark: true, scale: 2));
        await tester.pumpAndSettle();
        expect(find.byType(DPlaceCard), findsOneWidget);
        expect(find.text('10 columns'), findsOneWidget);
        expect(find.text('Case study opportunity'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureNativeUi(
          tester,
          'boards-directory-narrow-${width.toInt()}',
        );
        await onCapture?.call(
          tester,
          'boards-directory-narrow-${width.toInt()}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
