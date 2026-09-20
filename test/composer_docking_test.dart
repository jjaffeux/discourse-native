import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_presentation.dart';
import 'package:discourse_native/src/shell/composer_presentation_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'full screen retains draft and reader and restores the chosen dock',
    (tester) async {
      final h = await _Harness.create(tester);
      final editor = tester.state(find.byType(ComposerEditor));
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'Keep this draft and selection';
      composer.text.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      h.presentation.dock(ComposerPlacement.left);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerPanel)), const Size(1000, 700));
      expect(
        find.byKey(const ValueKey('reader-list')).hitTestable(),
        findsNothing,
      );
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      expect(composer.raw, 'Keep this draft and selection');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      await tester.tap(find.byTooltip('Dock side'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dock left'));
      await tester.pumpAndSettle();
      expect(h.presentation.preference.placement, ComposerPlacement.left);
      expect(
        find.byKey(const ValueKey('reader-list')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reader position reports do not rebuild the editor', (
    tester,
  ) async {
    final harness = await _Harness.create(tester);
    final editor = tester.element(find.byType(ComposerEditor));
    final panel = tester.element(find.byType(ComposerPanel));
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      rebuilt.add(element);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    for (var frame = 0; frame < 10; frame++) {
      harness.shell.reportReaderContentBounds(
        Rect.fromLTWH(0, frame.toDouble(), 800, 600),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rebuilt, isNot(contains(panel)));
    expect(rebuilt, isNot(contains(editor)));
    expect(harness.shell.visibleComposer!.focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening and revealing the composer focuses its editor', (
    tester,
  ) async {
    final readerFocus = FocusNode();
    addTearDown(readerFocus.dispose);
    final harness = await _Harness.create(tester, readerFocus: readerFocus);
    final composer = harness.shell.visibleComposer!;
    expect(composer.focus.hasFocus, isTrue);

    harness.shell.hideComposerForClose(composer);
    await tester.pumpAndSettle();
    readerFocus.requestFocus();
    await tester.pump();
    expect(readerFocus.hasFocus, isTrue);

    harness.shell.restoreComposerAfterFailedClose(composer);
    await tester.pumpAndSettle();
    expect(composer.focus.hasFocus, isTrue);

    readerFocus.requestFocus();
    await tester.pump();
    harness.presentation.resize(
      placement: ComposerPlacement.right,
      extent: 450,
      topic: true,
    );
    await tester.pumpAndSettle();
    expect(readerFocus.hasFocus, isTrue);
  });

  test(
    'preferences restore dock sizes and ignore obsolete floating coordinates',
    () async {
      final first = ComposerPresentationController();
      final second = ComposerPresentationController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load();
      expect(first.preference.placement, ComposerPlacement.right);
      first.dock(ComposerPlacement.left);
      first.resize(
        placement: ComposerPlacement.left,
        extent: 480,
        topic: false,
      );
      first.resize(
        placement: ComposerPlacement.bottom,
        extent: 350,
        topic: false,
      );
      await first.store.write(first.preference);
      await second.load();
      expect(second.preference.placement, ComposerPlacement.left);
      expect(second.preference.sideWidth, 480);
      expect(second.preference.replyHeight, 350);
      expect(
        second.effectivePlacement(mobile: false, width: 600),
        ComposerPlacement.bottom,
      );
      expect(
        second.effectivePlacement(mobile: false, width: 900),
        ComposerPlacement.left,
      );
      expect(
        second.effectivePlacement(mobile: true, width: 1200),
        ComposerPlacement.bottom,
      );
    },
  );

  test('corrupt dimensions and unknown placement fall back to right', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ComposerLayoutStore.storageKey,
      '{"placement":"obsolete","sideWidth":420,"replyHeight":280,"topicHeight":380}',
    );
    expect(
      (await const ComposerLayoutStore().read()).placement,
      ComposerPlacement.right,
    );
    await prefs.setString(ComposerLayoutStore.storageKey, '{invalid');
    expect((await const ComposerLayoutStore().read()).sideWidth, 420);
  });

  testWidgets('restored draft keeps Cancel and save-and-close actions', (
    tester,
  ) async {
    final harness = await _Harness.create(tester);
    harness.shell.visibleComposer!.restore(
      const ComposerDraft(
        reply: 'Previously saved draft',
        title: 'A topic',
        action: ComposerDraft.createTopicAction,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-discard')), findsNothing);
    expect(find.byKey(const ValueKey('composer-cancel')), findsOneWidget);
    expect(find.byTooltip('Save and close'), findsOneWidget);
  });

  for (final mobile in [false, true]) {
    testWidgets('Cancel can discard a saved draft (mobile: $mobile)', (
      tester,
    ) async {
      final harness = await _Harness.create(tester, mobile: mobile);
      final composer = harness.shell.visibleComposer!;
      final cancel = find.byKey(const ValueKey('composer-cancel'));
      composer.text.text = 'A saved topic draft';
      await tester.runAsync(composer.flushDraft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-discard')), findsNothing);
      composer.text.text = 'A saved topic draft with edits';
      await tester.pump();
      if (mobile) {
        await tester.tap(find.byKey(const ValueKey('composer-mobile-options')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(cancel);
      // Autosave stays pending while the prompt is open; its spinner keeps
      // animating, so wait for the dialog rather than all scheduled frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(composer.raw, 'A saved topic draft with edits');
      if (mobile) {
        await tester.tap(find.byKey(const ValueKey('composer-mobile-options')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(cancel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();
      expect(harness.shell.visibleComposer, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'placement and minimization retain the same editor state and undo history',
    (tester) async {
      final harness = await _Harness.create(tester);
      final composer = harness.shell.visibleComposer!;
      final editor = find.byType(ComposerEditor);
      final state = tester.state(editor);
      final scrollState = tester.element(
        find.byKey(const ValueKey('reader-list')),
      );
      final panel = find.byType(ComposerPanel);
      expect(tester.getSize(panel).width, 420);
      await tester.enterText(
        find.descendant(of: editor, matching: find.byType(EditableText)),
        'First draft',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(
        find.descendant(of: editor, matching: find.byType(EditableText)),
        'First draft with more',
      );
      await tester.pump(const Duration(milliseconds: 600));
      composer.text.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      final selection = composer.text.selection;
      for (final placement in [
        ComposerPlacement.left,
        ComposerPlacement.bottom,
        ComposerPlacement.right,
      ]) {
        harness.presentation.dock(placement);
        await tester.pumpAndSettle();
        expect(identical(tester.state(editor), state), isTrue);
        expect(
          identical(
            tester.element(find.byKey(const ValueKey('reader-list'))),
            scrollState,
          ),
          isTrue,
        );
        expect(composer.text.selection, selection);
        final reader = tester.getRect(
          find.byKey(const ValueKey('reader-list')),
        );
        final frame = tester.getRect(panel);
        expect(reader.overlaps(frame), isFalse);
        if (placement == ComposerPlacement.left) {
          expect(frame.right, lessThanOrEqualTo(reader.left));
        }
        if (placement == ComposerPlacement.right) {
          expect(frame.left, greaterThanOrEqualTo(reader.right));
        }
        if (placement == ComposerPlacement.bottom) {
          expect(frame.top, greaterThanOrEqualTo(reader.bottom));
        }
      }
      await tester.tap(find.byKey(const ValueKey('composer-minimize')));
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(find.byKey(const ValueKey('composer-restore')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('composer-restore')));
      await tester.pumpAndSettle();
      expect(identical(tester.state(editor), state), isTrue);
      expect(tester.getSize(panel).width, 420);
      expect(composer.text.selection, selection);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(composer.raw, 'First draft');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('composer-minimize')));
      await tester.pump();
      expect(find.byTooltip('Save and close'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('composer-restore')));
      await tester.pump();
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(composer.isDisposed, isTrue);
      expect(harness.shell.visibleComposer, isNull);
      final api = harness.shell.api.composerPersistence as FakeDiscourseApi;
      expect(
        ComposerDraft.decode(api.draftsSaved.last['data']! as String)?.reply,
        'First draft',
      );
      expect(api.userDraftsDeleted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow windows use bottom and restore preferred side and width',
    (tester) async {
      final harness = await _Harness.create(tester);
      harness.presentation.dock(ComposerPlacement.left);
      harness.presentation.resize(
        placement: ComposerPlacement.left,
        extent: 470,
        topic: true,
      );
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(620, 700));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerPanel)).width, 620);
      expect(harness.presentation.preference.placement, ComposerPlacement.left);
      expect(harness.presentation.preference.sideWidth, 470);
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerPanel)).width, 470);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    for (final placement in [
      ComposerPlacement.left,
      ComposerPlacement.right,
      ComposerPlacement.bottom,
    ]) {
      testWidgets(
        'composer gutter stays open during resize: $direction $placement',
        (tester) async {
          final harness = await _Harness.create(tester, direction: direction);
          harness.presentation.dock(placement);
          await tester.pumpAndSettle();
          final reader = find.byWidgetPredicate(
            (w) => w is DResizablePanel && w.id == 'reader',
          );
          final editor = find.byType(ComposerPanel);
          final editorState = tester.state(find.byType(ComposerEditor));
          double gap() {
            final r = tester.getRect(reader);
            final e = tester.getRect(find.byType(WorkspacePanel));
            return switch (placement) {
              ComposerPlacement.left => r.left + 5.5 - e.right,
              ComposerPlacement.right => e.left - (r.right - 5.5),
              _ => e.top - (r.bottom - 5.5),
            };
          }

          expect(gap(), 12);
          final before = tester.getSize(editor);
          await tester.drag(
            find.byType(DResizableHandle),
            placement.isSide
                ? Offset(placement == ComposerPlacement.left ? 40 : -40, 0)
                : const Offset(0, -40),
          );
          await tester.pumpAndSettle();
          expect(gap(), 12);
          expect(
            placement.isSide
                ? tester.getSize(editor).width
                : tester.getSize(editor).height,
            greaterThan(placement.isSide ? before.width : before.height),
          );
          expect(tester.state(find.byType(ComposerEditor)), same(editorState));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('divider resizes and persists the composer width', (
    tester,
  ) async {
    final harness = await _Harness.create(tester);
    final before = tester.getSize(find.byType(ComposerPanel)).width;
    await tester.drag(find.byType(DResizableHandle), const Offset(-60, 0));
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(ComposerPanel)).width;
    expect(after, greaterThan(before));
    expect(harness.presentation.preference.sideWidth, after);
    final stored = await const ComposerLayoutStore().read();
    expect(stored.sideWidth, after);
  });

  testWidgets(
    'A menu selects physical sides in RTL and has accessible icon names',
    (tester) async {
      final harness = await _Harness.create(
        tester,
        direction: TextDirection.rtl,
      );
      final semantics = tester.ensureSemantics();

      await tester.tap(find.byTooltip('Dock side'));
      await tester.pumpAndSettle();
      expect(find.text('Dock side'), findsOneWidget);
      expect(find.bySemanticsLabel('Separate window'), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      expect(find.text('Save and close'), findsNothing);
      expect(find.text('Discard'), findsOneWidget);
      for (final placement in ComposerPlacement.values) {
        expect(find.byTooltip(placement.label), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Dock left'));
      await tester.pumpAndSettle();
      expect(harness.presentation.preference.placement, ComposerPlacement.left);
      final frame = tester.getRect(find.byType(ComposerPanel));
      final reader = tester.getRect(find.byKey(const ValueKey('reader-list')));
      expect(frame.right, lessThanOrEqualTo(reader.left));
      expect(find.text('Dock side'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'mobile hides placement and keeps submit above the visible keyboard',
    (tester) async {
      await _Harness.create(tester, mobile: true, size: const Size(390, 800));
      tester.view.viewInsets = FakeViewPadding(
        bottom: 330 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final frame = tester.getRect(find.byType(ComposerPanel));
      expect(frame, const Rect.fromLTWH(0, 0, 390, 470));
      final submit = tester.getRect(
        find.byKey(const ValueKey('composer-submit')),
      );
      final title = tester.getRect(
        find.byKey(const ValueKey('composer-topic-title')),
      );
      final taxonomy = tester.getRect(
        find.byKey(const ValueKey('composer-category-action')),
      );
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('composer-toolbar-scroll')),
      );
      expect(submit.bottom, lessThanOrEqualTo(title.top));
      expect(taxonomy.top, greaterThan(title.bottom));
      expect(taxonomy.bottom, lessThanOrEqualTo(toolbar.top));
      expect(find.text('Create topic'), findsNothing);
      expect(find.text('Discard'), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('composer-submit'))).bottom,
        lessThanOrEqualTo(470),
      );
      expect(
        tester.getSize(find.byType(ComposerEditor)).height,
        greaterThan(30),
      );
      expect(find.byTooltip('Dock side'), findsNothing);
      expect(find.text('Dock side'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mobile keyboard and minimize preserve the draft and editor', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      mobile: true,
      size: const Size(390, 800),
    );
    final composer = harness.shell.visibleComposer!;
    final editor = tester.state(find.byType(ComposerEditor));
    final submit = find.byKey(const ValueKey('composer-submit'));
    expect(tester.widget<DButton>(submit).onPressed, isNull);
    composer.title.text = 'A topic with enough title text';
    composer.text.value = const TextEditingValue(
      text: 'A draft that survives keyboard changes.',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(submit).onPressed, isNotNull);
    addTearDown(tester.view.resetViewInsets);
    for (final inset in [330.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(
        bottom: inset * tester.view.devicePixelRatio,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerPanel)).height, 800 - inset);
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      expect(composer.text.selection.extentOffset, 7);
    }
    await tester.tap(find.byKey(const ValueKey('composer-mobile-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimize composer'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reader-list')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('composer-restore')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ComposerEditor)), same(editor));
    expect(composer.raw, 'A draft that survives keyboard changes.');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text and a short keyboard viewport keep editing and submission reachable',
    (tester) async {
      await _Harness.create(
        tester,
        mobile: true,
        size: const Size(390, 650),
        textScale: 2,
      );
      tester.view.viewInsets = FakeViewPadding(
        bottom: 330 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('composer-submit'))).bottom,
        lessThanOrEqualTo(320),
      );
      expect(
        tester.getSize(find.byType(ComposerEditor)).height,
        greaterThan(30),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Harness {
  _Harness(this.shell, this.presentation);
  final ShellController shell;
  final ComposerPresentationController presentation;
  static Future<_Harness> create(
    WidgetTester tester, {
    bool mobile = false,
    Size size = const Size(1000, 700),
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
    FocusNode? readerFocus,
  }) async {
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    final presentation = ComposerPresentationController();
    addTearDown(shell.dispose);
    addTearDown(presentation.dispose);
    await shell.load();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(
            platform: mobile ? TargetPlatform.iOS : TargetPlatform.linux,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: DToaster(child: child!),
          ),
          home: Scaffold(
            body: DDirection(
              textDirection: direction,
              child: ComposerPresentationHost(
                controller: presentation,
                child: ComposerDock(
                  child: Focus(
                    focusNode: readerFocus,
                    autofocus: readerFocus != null,
                    child: ListView(
                      key: const ValueKey('reader-list'),
                      children: [for (var i = 0; i < 100; i++) Text('Post $i')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await shell.openNewTopicFromSidebar();
    await tester.pumpAndSettle();
    return _Harness(shell, presentation);
  }
}
