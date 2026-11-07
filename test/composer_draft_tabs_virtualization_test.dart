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

  testWidgets('opening a draft retains inactive editor builds and state', (
    tester,
  ) async {
    final shell = await _pumpTabs(tester, count: 3, hosted: true);
    final retained = shell.liveComposers.toList();
    final editors = find.byType(ComposerEditor, skipOffstage: false);
    final states = {
      for (final element in editors.evaluate())
        (element.widget as ComposerEditor).composer:
            (element as StatefulElement).state,
    };
    final inactive = editors
        .evaluate()
        .where(
          (element) => !identical(
            (element.widget as ComposerEditor).composer,
            shell.visibleComposer,
          ),
        )
        .toSet();
    final rebuilt = <Element>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (inactive.contains(element)) rebuilt.add(element);
    };
    try {
      final opening = shell.openNewTopicFromSidebar();
      await tester.pump();
      await opening;
      await tester.pumpAndSettle();
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    expect(
      rebuilt,
      isEmpty,
      reason: '${rebuilt.length} inactive editor rebuilds during opening',
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.linux),
          builder: app.builder,
          home: app.home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retainedInput = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is ComposerEditor &&
            identical(widget.composer, retained.first),
        skipOffstage: false,
      ),
      matching: find.byType(EditableText, skipOffstage: false),
      skipOffstage: false,
    );
    expect(
      tester.widget<EditableText>(retainedInput).style.color,
      AppTheme.dark.textTheme.bodyLarge!.color,
    );
    final opened = shell.visibleComposer!;
    shell.closeComposer(composer: opened);
    await tester.pumpAndSettle();
    for (final composer in retained) {
      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is ComposerEditor && identical(widget.composer, composer),
        skipOffstage: false,
      );
      expect(tester.state(editor), same(states[composer]));
    }
    expect(retained.first.text.text, 'First draft source');
    expect(
      retained.first.text.selection,
      const TextSelection.collapsed(offset: 5),
    );
    shell.selectComposer(retained.first);
    await tester.pumpAndSettle();
    await tester.enterText(retainedInput, 'First draft source extended');
    await tester.pump(const Duration(milliseconds: 600));
    expect(retained.first.history.undo(), isTrue);
    await tester.pump();
    expect(retained.first.raw, 'First draft source');
    await tester.runAsync(retained.first.flushDraft);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'closing an inactive draft retains other editor builds on $platform',
      (tester) async {
        final shell = await _pumpTabs(
          tester,
          count: 3,
          hosted: true,
          platform: platform,
        );
        final drafts = shell.liveComposers.toList();
        final visible = shell.visibleComposer;
        final survivorElements = find
            .byType(ComposerEditor, skipOffstage: false)
            .evaluate()
            .where(
              (element) => !identical(
                (element.widget as ComposerEditor).composer,
                drafts[1],
              ),
            )
            .toSet();
        final states = {
          for (final element in survivorElements)
            (element.widget as ComposerEditor).composer:
                (element as StatefulElement).state,
        };
        final rebuilt = <Element>[];
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previous?.call(element, builtOnce);
          if (survivorElements.contains(element)) rebuilt.add(element);
        };
        try {
          shell.closeComposer(composer: drafts[1]);
          await tester.pumpAndSettle();
        } finally {
          debugOnRebuildDirtyWidget = previous;
        }
        expect(
          rebuilt,
          isEmpty,
          reason:
              '${rebuilt.length} survivor editor rebuilds during inactive close',
        );
        expect(shell.visibleComposer, same(visible));
        expect(drafts[1].isDisposed, isTrue);
        for (final entry in states.entries) {
          final editor = find.byWidgetPredicate(
            (widget) =>
                widget is ComposerEditor &&
                identical(widget.composer, entry.key),
            skipOffstage: false,
          );
          expect(tester.state(editor), same(entry.value));
        }
        expect(drafts.first.raw, 'First draft source');
        expect(
          drafts.first.text.selection,
          const TextSelection.collapsed(offset: 5),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'closing an inactive draft while changing dock preserves survivors',
    (tester) async {
      final shell = await _pumpTabs(tester, count: 3, hosted: true);
      await tester.binding.setSurfaceSize(const Size(1280, 850));
      final presentation = tester
          .widget<ComposerPresentationHost>(
            find.byType(ComposerPresentationHost),
          )
          .controller!;
      presentation.dock(ComposerPlacement.right);
      await tester.pumpAndSettle();
      final drafts = shell.liveComposers.toList();
      final editor = tester.state(find.byType(ComposerEditor).hitTestable());
      shell.closeComposer(composer: drafts[1]);
      presentation.dock(ComposerPlacement.fullScreen);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.state(find.byType(ComposerEditor).hitTestable()),
        same(editor),
      );
      expect(shell.visibleComposer, same(drafts.first));
      expect(drafts.first.raw, 'First draft source');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('closing the visible mobile draft preserves surviving editors', (
    tester,
  ) async {
    final shell = await _pumpTabs(
      tester,
      count: 3,
      hosted: true,
      platform: TargetPlatform.iOS,
    );
    final drafts = shell.liveComposers.toList();
    final nextEditor = find.byWidgetPredicate(
      (widget) =>
          widget is ComposerEditor && identical(widget.composer, drafts[1]),
      skipOffstage: false,
    );
    final state = tester.state(nextEditor);
    shell.closeComposer(composer: drafts.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(shell.visibleComposer, same(drafts[1]));
    expect(tester.state(nextEditor), same(state));
    expect(nextEditor.hitTestable(), findsOneWidget);
    await tester.enterText(
      find.descendant(of: nextEditor, matching: find.byType(EditableText)),
      'The surviving mobile draft',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(drafts[1].history.undo(), isTrue);
    await tester.pump();
    expect(drafts[1].raw, isEmpty);
    await tester.runAsync(drafts[1].flushDraft);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
  TargetPlatform platform = TargetPlatform.linux,
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
          platform: hosted ? platform : TargetPlatform.iOS,
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
