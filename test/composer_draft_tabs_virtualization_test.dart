import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/draft_tabs.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/presentation.dart';
import 'package:discourse_native/src/shell/composer/presentation_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() => composerDraftTabsVirtualizationTests();

void composerDraftTabsVirtualizationTests() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('draft menu keeps live editors beside loading skeletons', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pumpTabs(tester, count: 2, draftGate: gate);
    await tester.tap(find.byKey(const ValueKey('composer-all-drafts')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading drafts…'), findsNothing);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.byType(DSkeleton), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(DDropdownMenuContent),
        matching: find.text('Draft 1'),
      ),
      findsOneWidget,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.text('All drafts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        '200 live draft tabs stay lazy, reveal selection, and close at ${scale}x $direction',
        (tester) async {
          final shell = await _pumpTabs(
            tester,
            count: 200,
            scale: scale,
            direction: direction,
          );
          final drafts = shell.liveComposers.toList();
          final tabs = find.byType(DDocumentTab, skipOffstage: false);
          final firstController = drafts.first.text;
          final firstSelection = firstController.selection;
          expect(drafts, hasLength(200));
          expect(tabs.evaluate().length, lessThan(12));
          expect(tester.getSize(_tab('I')).width, 170);
          expect(_tab('Draft 199').hitTestable(), findsNothing);
          final bounds = tester.getRect(find.byType(ComposerDraftTabs));
          expect(
            bounds.height,
            DControlStyle.scaledHeight(
              DControlSize.documentTab,
              TextScaler.linear(scale),
              context: tester.element(_tab('I')),
            ),
          );
          final firstRect = tester.getRect(_tab('I'));
          final nextRect = tester.getRect(_tab('Draft 1'));
          expect(
            direction == TextDirection.ltr
                ? nextRect.left - firstRect.right
                : firstRect.left - nextRect.right,
            6,
          );
          shell.selectComposer(drafts.last);
          await tester.pumpAndSettle();
          expect(_tab('Draft 199').hitTestable(), findsOneWidget);
          expect(tester.getSize(_tab('Draft 199')).width, 170);
          await tester.binding.setSurfaceSize(const Size(300, 844));
          await tester.pumpAndSettle();
          final resizedBounds = tester.getRect(find.byType(ComposerDraftTabs));
          final selectedRect = tester.getRect(_tab('Draft 199'));
          expect(selectedRect.left, greaterThanOrEqualTo(resizedBounds.left));
          expect(selectedRect.right, lessThanOrEqualTo(resizedBounds.right));
          await tester.binding.setSurfaceSize(const Size(390, 844));
          await tester.pumpAndSettle();
          final neighbor = tester.state(_tab('Draft 198'));
          final neighborFocus = tester
              .widget<DButton>(_buttons('Draft 198').first)
              .focusNode!;
          final neighborHandler = neighborFocus.onKeyEvent;
          await tester.tap(
            find
                .byKey(ValueKey(('composer-draft-close', drafts.last)))
                .hitTestable(),
          );
          await tester.pumpAndSettle();
          expect(drafts.last.isDisposed, isTrue);
          expect(shell.visibleComposer, same(drafts[198]));
          expect(tester.state(_tab('Draft 198')), same(neighbor));
          expect(neighborFocus.onKeyEvent, neighborHandler);
          expect(tabs.evaluate().length, lessThan(12));
          shell.selectComposer(drafts.first);
          await tester.pumpAndSettle();
          expect(_tab('I').hitTestable(), findsOneWidget);
          expect(drafts.first.text, same(firstController));
          expect(firstController.selection, firstSelection);
          drafts.first.history.transact(
            () => firstController.text = 'Changed source',
          );
          drafts.first.history.undo();
          expect(firstController.text, 'First draft source');
          await tester.runAsync(drafts.first.finishDraftSaves);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'draft traversal crosses unmounted tabs and both strip edges in $direction',
      (tester) async {
        final shell = await _pumpTabs(tester, count: 200, direction: direction);
        final drafts = shell.liveComposers.toList();
        final menu = tester
            .widget<DButton>(find.byKey(const ValueKey('composer-all-drafts')))
            .focusNode!;
        menu.requestFocus();
        await tester.pumpAndSettle();
        await _tabKey(tester);
        expect(
          tester
              .widget<DButton>(_buttons('I').first)
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        for (var step = 1; step <= 20; step++) {
          await _tabKey(tester);
          final title = step ~/ 2 == 0 ? 'I' : 'Draft ${step ~/ 2}';
          final action = step.isEven
              ? _buttons(title).first
              : _buttons(title).last;
          expect(
            tester.widget<DButton>(action).focusNode!.hasPrimaryFocus,
            isTrue,
          );
        }
        for (var step = 19; step >= 0; step--) {
          await _tabKey(tester, reverse: true);
          final title = step ~/ 2 == 0 ? 'I' : 'Draft ${step ~/ 2}';
          final action = step.isEven
              ? _buttons(title).first
              : _buttons(title).last;
          expect(
            tester.widget<DButton>(action).focusNode!.hasPrimaryFocus,
            isTrue,
          );
        }
        await _tabKey(tester, reverse: true);
        expect(menu.hasPrimaryFocus, isTrue);
        final after = tester
            .widget<DButton>(find.byKey(const ValueKey('after-draft-tabs')))
            .focusNode!;
        after.requestFocus();
        await tester.pumpAndSettle();
        await _tabKey(tester, reverse: true);
        expect(
          tester
              .widget<DButton>(_buttons('Draft 199').last)
              .focusNode!
              .hasPrimaryFocus,
          isTrue,
        );
        expect(_tab('Draft 199').hitTestable(), findsOneWidget);
        await _tabKey(tester);
        expect(after.hasPrimaryFocus, isTrue);
        expect(shell.visibleComposer, same(drafts.first));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'focused middle tab survives manual scrolling and stale traversal cannot select its replacement',
    (tester) async {
      final shell = await _pumpTabs(tester, count: 200);
      final drafts = shell.liveComposers.toList();
      shell.selectComposer(drafts[8]);
      await tester.pumpAndSettle();
      final focus = tester.widget<DButton>(_buttons('Draft 8').last).focusNode!;
      final element = tester.element(_tab('Draft 8'));
      focus.requestFocus();
      await tester.pumpAndSettle();
      final viewport = _tabViewport(tester);
      viewport.position.jumpTo(viewport.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(tester.element(_tab('Draft 8')), same(element));
      expect(
        find.byType(DDocumentTab, skipOffstage: false).evaluate().length,
        lessThan(14),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      shell.closeComposer(composer: drafts[9]);
      await tester.pumpAndSettle();
      expect(drafts[9].isDisposed, isTrue);
      expect(shell.visibleComposer, same(drafts[8]));
      expect(
        tester
            .widget<DButton>(_buttons('Draft 10').first)
            .focusNode!
            .hasPrimaryFocus,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('newer outside focus cancels pending tab traversal', (
    tester,
  ) async {
    final shell = await _pumpTabs(tester, count: 200);
    shell.selectComposer(shell.liveComposers.elementAt(8));
    await tester.pumpAndSettle();
    final close = tester.widget<DButton>(_buttons('Draft 8').last).focusNode!;
    close.requestFocus();
    await tester.pumpAndSettle();
    final viewport = _tabViewport(tester);
    viewport.position.jumpTo(viewport.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_tab('Draft 9'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final outside = tester
        .widget<DButton>(find.byKey(const ValueKey('after-draft-tabs')))
        .focusNode!;
    outside.requestFocus();
    await tester.pumpAndSettle();
    expect(outside.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid Tab requests advance through consecutive actions', (
    tester,
  ) async {
    final shell = await _pumpTabs(tester, count: 200);
    tester.widget<DButton>(_buttons('I').first).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DButton>(_buttons('Draft 1').first)
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DButton>(_buttons('I').first).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    tester
        .widget<DButton>(_buttons('Draft 199').first)
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('after-draft-tabs')))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    shell.selectComposer(shell.liveComposers.elementAt(8));
    await tester.pumpAndSettle();
    tester.widget<DButton>(_buttons('Draft 8').last).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final viewport = _tabViewport(tester);
    viewport.position.jumpTo(viewport.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_tab('Draft 9'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DButton>(_buttons('Draft 9').last)
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  {
    testWidgets(
      '200 draft retained composer presentation keeps semantics through minimize in flat',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final shell = await _pumpTabs(tester, count: 200, hosted: true);
          final first = shell.visibleComposer!;
          final editor = tester.state(
            find.byType(ComposerEditor).hitTestable(),
          );
          final last = shell.liveComposers.last;
          shell.selectComposer(last);
          await tester.pumpAndSettle();
          expect(shell.visibleComposer, same(last));
          shell.selectComposer(first);
          await tester.pumpAndSettle();
          expect(
            tester.state(find.byType(ComposerEditor).hitTestable()),
            same(editor),
          );
          final presentation = tester
              .widget<ComposerPresentationHost>(
                find.byType(ComposerPresentationHost),
              )
              .controller!;
          presentation.dock(ComposerPlacement.fullScreen);
          await tester.pumpAndSettle();
          presentation.dock(ComposerPlacement.bottom);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('composer-minimize')).hitTestable(),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byKey(const ValueKey('composer-restore')).hitTestable(),
          );
          await tester.pumpAndSettle();
          expect(shell.visibleComposer, same(first));
          expect(
            tester.state(find.byType(ComposerEditor).hitTestable()),
            same(editor),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'closing the first tab promotes its neighbor without replacing Native state',
    (tester) async {
      final shell = await _pumpTabs(tester, count: 3);
      final drafts = shell.liveComposers.toList();
      final neighbor = tester.state(_tab('Draft 1'));
      await tester.tap(
        find
            .byKey(ValueKey(('composer-draft-close', drafts.first)))
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, same(drafts[1]));
      expect(tester.state(_tab('Draft 1')), same(neighbor));
      expect(tester.takeException(), isNull);
    },
  );
}

ScrollableState _tabViewport(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ComposerDraftTabs),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
        ),
      ),
    );

Future<void> _tabKey(WidgetTester tester, {bool reverse = false}) async {
  if (reverse) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

Finder _tab(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is DDocumentTab &&
      widget.child is Text &&
      (widget.child as Text).data == title,
  skipOffstage: false,
);

Finder _buttons(String title) => find.descendant(
  of: _tab(title),
  matching: find.byType(DButton, skipOffstage: false),
  skipOffstage: false,
);

Future<ShellController> _pumpTabs(
  WidgetTester tester, {
  required int count,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool hosted = false,
  Completer<void>? draftGate,
}) async {
  const siteUrl = 'https://meta.discourse.org';
  const user = DiscourseUser(id: 7, username: 'writer', canCreateTopic: true);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      userDraftGate: draftGate,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
    ),
    authenticator: FakeAuthenticator()..keys[siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  for (var index = 0; index < count; index++) {
    await shell.openNewTopicFromSidebar();
    shell.visibleComposer!.title.text = index == 0 ? 'I' : 'Draft $index';
    if (index == 0) {
      shell.visibleComposer!.text.value = const TextEditingValue(
        text: 'First draft source',
        selection: TextSelection.collapsed(offset: 5),
      );
      shell.visibleComposer!.history.reset();
    }
  }
  await tester.runAsync(() async {
    for (final draft in shell.liveComposers) {
      await draft.finishDraftSaves();
    }
  });
  shell.selectComposer(shell.liveComposers.first);
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  ComposerController shown = shell.visibleComposer!;
  final presentation = ComposerPresentationController();
  addTearDown(presentation.dispose);
  final afterFocus = FocusNode();
  addTearDown(afterFocus.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(
          platform: hosted ? TargetPlatform.linux : TargetPlatform.iOS,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: direction, child: child!),
        ),
        home: hosted
            ? ComposerPresentationHost(
                controller: presentation,
                child: const Scaffold(
                  body: ComposerDock(child: SizedBox.expand()),
                ),
              )
            : Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListenableBuilder(
                        listenable: shell,
                        builder: (context, _) {
                          shown = shell.visibleComposer ?? shown;
                          return ComposerDraftTabs(composer: shown);
                        },
                      ),
                      DButton(
                        key: const ValueKey('after-draft-tabs'),
                        focusNode: afterFocus,
                        onPressed: () {},
                        label: const Text('After tabs'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}
