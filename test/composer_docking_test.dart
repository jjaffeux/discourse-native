import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_presentation.dart';
import 'package:discourse_native/src/shell/composer_presentation_controller.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
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

  testWidgets('the bottom-right window corner moves with the composer', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      windowCorner: 10,
      reader: Builder(
        builder: (context) => DPageSurface(
          key: const ValueKey('corner-reader'),
          borderRadius: WorkspacePanelCorner.borderRadiusOf(context),
          child: const SizedBox.expand(),
        ),
      ),
    );
    DCard readerCard() => tester.widget<DCard>(
      find.descendant(
        of: find.byKey(const ValueKey('corner-reader')),
        matching: find.byType(DCard),
      ),
    );
    DCard composerCard() => tester.widget<DCard>(
      find.descendant(
        of: find.byType(WorkspacePanel),
        matching: find.byType(DCard),
      ),
    );
    bool hasCorner(DCard card) =>
        (card.borderRadius as BorderRadius?)?.bottomRight ==
        const Radius.circular(10);

    for (final placement in [
      ComposerPlacement.right,
      ComposerPlacement.left,
      ComposerPlacement.bottom,
      ComposerPlacement.right,
    ]) {
      harness.presentation.dock(placement);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('composer-header'))).height,
        placement.isSide ? 56 : 44,
      );
      expect(hasCorner(readerCard()), placement == ComposerPlacement.left);
      expect(hasCorner(composerCard()), placement != ComposerPlacement.left);
    }
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    expect(hasCorner(composerCard()), isTrue);
    await tester.tap(find.byKey(const ValueKey('composer-minimize')));
    await tester.pumpAndSettle();
    expect(hasCorner(composerCard()), isTrue);
    expect(hasCorner(readerCard()), isFalse);
    await tester.tap(find.byKey(const ValueKey('composer-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save and close'));
    await tester.pumpAndSettle();
    expect(hasCorner(readerCard()), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final placement in [
    ComposerPlacement.left,
    ComposerPlacement.bottom,
    ComposerPlacement.right,
  ]) {
    testWidgets(
      'Dock exits full screen and restores $placement with the draft intact',
      (tester) async {
        final h = await _Harness.create(tester);
        final editor = tester.state(find.byType(ComposerEditor));
        final composer = h.shell.visibleComposer!;
        composer.text.text = 'Keep this draft and selection';
        composer.text.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 8,
        );
        h.presentation.dock(placement);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Full screen'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(ComposerPanel)),
          const Size(1000, 700),
        );
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
        expect(h.presentation.preference.placement, placement);
        expect(find.text('Dock side'), findsNothing);
        expect(
          find.byKey(const ValueKey('reader-list')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.state(find.byType(ComposerEditor)), same(editor));
        expect(composer.raw, 'Keep this draft and selection');
        expect(
          composer.text.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        await tester.tap(find.byTooltip('Dock side'));
        await tester.pumpAndSettle();
        expect(find.text('Dock side'), findsOneWidget);
        await tester.runAsync(composer.flushDraft);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final placement in [
    ComposerPlacement.left,
    ComposerPlacement.bottom,
    ComposerPlacement.right,
  ]) {
    for (final destination in ['latest', 'messages']) {
      testWidgets('sidebar $destination restores $placement from full screen', (
        tester,
      ) async {
        final h = await _Harness.create(tester, includeSidebar: true);
        final composer = h.shell.visibleComposer!;
        final editor = tester.state(find.byType(ComposerEditor));
        composer.text.value = const TextEditingValue(
          text: 'Keep the draft while navigating',
          selection: TextSelection(baseOffset: 2, extentOffset: 8),
        );
        h.presentation.dock(placement);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Full screen'));
        await tester.pumpAndSettle();
        expect(
          h.presentation.preference.placement,
          ComposerPlacement.fullScreen,
        );
        expect(
          find.byKey(const ValueKey('reader-list')).hitTestable(),
          findsNothing,
        );

        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is SidebarDestinationTile &&
                widget.destination.id == destination,
          ),
        );
        await tester.pumpAndSettle();

        expect(h.presentation.preference.placement, placement);
        expect(h.shell.destinationId, destination);
        expect(
          find.byKey(const ValueKey('reader-list')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Dock side'), findsNothing);
        expect(tester.state(find.byType(ComposerEditor)), same(editor));
        expect(h.shell.visibleComposer, same(composer));
        expect(composer.raw, 'Keep the draft while navigating');
        expect(
          composer.text.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        expect(composer.focus.hasFocus, isFalse);
        await tester.runAsync(composer.flushDraft);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('More reveals destinations before leaving full screen', (
    tester,
  ) async {
    final h = await _Harness.create(tester, includeSidebar: true);
    h.presentation.dock(ComposerPlacement.bottom);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(h.presentation.preference.placement, ComposerPlacement.fullScreen);
    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();
    expect(h.presentation.preference.placement, ComposerPlacement.bottom);
    expect(h.shell.destinationId, 'groups');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar navigation leaves a minimized composer minimized', (
    tester,
  ) async {
    final h = await _Harness.create(tester, includeSidebar: true);
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-minimize')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is SidebarDestinationTile &&
            widget.destination.id == 'messages',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ComposerEditor).hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('composer-restore')).hitTestable(),
      findsOneWidget,
    );
    expect(h.shell.destinationId, 'messages');
    expect(tester.takeException(), isNull);
  });

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
        await tester.tap(find.byKey(const ValueKey('composer-close')));
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
        await tester.tap(find.byKey(const ValueKey('composer-close')));
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
          final gutter = tester.getRect(find.byType(DResizableHandle));
          expect(placement.isSide ? gutter.width : gutter.height, 12);
          await tester.dragFrom(
            Offset(gutter.left + .5, gutter.top + .5),
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

  for (final direction in TextDirection.values) {
    testWidgets('side dock leaves the reader scrollbar clickable: $direction', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final harness = await _Harness.create(
        tester,
        direction: direction,
        reader: DScrollBar(
          controller: scroll,
          child: ListView.builder(
            controller: scroll,
            itemCount: 100,
            itemExtent: 40,
            itemBuilder: (_, index) => Text('Message $index'),
          ),
        ),
      );
      final ltr = direction == TextDirection.ltr;
      harness.presentation.dock(
        ltr ? ComposerPlacement.right : ComposerPlacement.left,
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ListView));
      final width = tester.getSize(find.byType(ComposerPanel)).width;
      final thumb = Offset(
        ltr ? viewport.right - 4 : viewport.left + 4,
        viewport.top + 10,
      );
      final drag = await tester.startGesture(
        thumb,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 60));
      await drag.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(tester.getSize(find.byType(ComposerPanel)).width, width);

      // Clicking the track must page the stream without resizing either pane.
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(thumb.dx, viewport.center.dy));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(tester.getSize(find.byType(ComposerPanel)).width, width);

      await tester.drag(
        find.byType(DResizableHandle),
        Offset(ltr ? -40 : 40, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ComposerPanel)).width,
        greaterThan(width),
      );
      expect(tester.takeException(), isNull);
    });
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
      expect(find.byTooltip('Discard'), findsOneWidget);
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
      expect(
        frame,
        const Rect.fromLTWH(0, DSpacing.sm, 390, 800 - DSpacing.sm),
      );
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
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byType(ComposerEditor),
          matching: find.byType(EditableText),
        ),
      );
      expect(
        tester.getSize(find.byType(ComposerEditor)).height,
        closeTo(editable.renderEditable.preferredLineHeight, 1),
      );
      expect(find.byTooltip('Dock side'), findsNothing);
      expect(find.text('Dock side'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mobile X opens draft actions and Save draft closes safely', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      mobile: true,
      size: const Size(390, 800),
    );
    final composer = harness.shell.visibleComposer!;
    composer.title.text = 'A topic to finish later';
    composer.text.text = 'Keep this draft when I close the sheet.';
    await tester.pumpAndSettle();
    final close = find.byKey(const ValueKey('composer-close'));
    expect(tester.widget<DButton>(close).shape, DButtonShape.pill);
    expect(tester.getSize(close).width, tester.getSize(close).height);
    expect(find.byKey(const ValueKey('composer-mobile-options')), findsNothing);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(harness.shell.visibleComposer, same(composer));
    expect(
      tester
          .widgetList<DDropdownMenuItem>(find.byType(DDropdownMenuItem))
          .map((item) => (item.child as Text).data),
      ['Discard', 'Minimize', 'Save draft'],
    );
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(harness.shell.visibleComposer, isNull);
    final savedRequest =
        (harness.shell.api.composerPersistence as FakeDiscourseApi)
            .draftsSaved
            .last;
    expect(savedRequest['draftKey'], composer.target.draftKey);
    final saved = ComposerDraft.decode(savedRequest['data'] as String);
    expect(saved?.title, 'A topic to finish later');
    expect(saved?.reply, 'Keep this draft when I close the sheet.');
    expect(tester.takeException(), isNull);
  });

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
      expect(
        tester.getSize(find.byType(ComposerPanel)).height,
        800 - DSpacing.sm,
      );
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      expect(composer.text.selection.extentOffset, 7);
    }
    await tester.tap(find.byKey(const ValueKey('composer-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimize'));
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final origin in ['header', 'body', 'bottom']) {
      for (final keyboard in [0.0, 300.0]) {
        testWidgets(
          '$platform composer ${origin == 'bottom' ? 'keeps bottom overscroll open then swipes from the top' : 'swipes from $origin'} and opens close actions (keyboard: $keyboard)',
          (tester) async {
            tester.view.physicalSize =
                const Size(390, 800) * tester.view.devicePixelRatio;
            addTearDown(tester.view.resetPhysicalSize);
            final harness = await _Harness.create(
              tester,
              mobile: true,
              platform: platform,
              size: const Size(390, 800),
            );
            tester.view.viewInsets = FakeViewPadding(
              bottom: keyboard * tester.view.devicePixelRatio,
            );
            addTearDown(tester.view.resetViewInsets);
            final composer = harness.shell.visibleComposer!;
            composer.title.text = 'Keep my draft';
            final text = List.generate(
              60,
              (i) => 'Draft paragraph $i',
            ).join('\n');
            composer.text.value = TextEditingValue(
              text: text,
              selection: const TextSelection.collapsed(offset: 0),
            );
            await tester.runAsync(composer.flushDraft);
            await tester.pumpAndSettle();
            final viewport = find.byKey(
              const ValueKey('composer-mobile-scroll'),
            );
            final scroll = tester
                .widget<CustomScrollView>(viewport)
                .controller!;
            // The pinned header must drag the sheet even far into the draft.
            scroll.jumpTo(
              origin == 'bottom'
                  ? scroll.position.maxScrollExtent
                  : origin == 'header'
                  ? 400
                  : 0,
            );
            await tester.pumpAndSettle();
            final sheet = find.byKey(const ValueKey('composer-mobile-sheet'));
            final editor = tester.state(find.byType(ComposerEditor));
            final top = tester.getTopLeft(sheet).dy;
            final api =
                harness.shell.api.composerPersistence as FakeDiscourseApi;
            final savesBeforeSwipe = api.draftsSaved.length;
            final start = origin == 'header'
                ? tester.getCenter(
                    find.byKey(const ValueKey('composer-header')),
                  )
                : origin == 'bottom'
                ? tester.getBottomLeft(viewport) + const Offset(80, -24)
                : tester.getTopLeft(viewport) + const Offset(80, 180);
            expect(tester.getRect(viewport).contains(start), isTrue);
            expect(start.dy, lessThan(800 - keyboard));
            var gesture = await tester.startGesture(start);
            if (origin == 'bottom') {
              // Scrolling past the bottom continues the editor scroll; only
              // a downward pull from its top edge dismisses the sheet.
              await gesture.moveBy(const Offset(0, -30));
              await gesture.moveBy(const Offset(0, -300));
              await tester.pump();
              expect(tester.getTopLeft(sheet).dy, closeTo(top, .01));
              await gesture.up();
              await tester.pumpAndSettle();
              expect(harness.shell.visibleComposer, same(composer));
              expect(sheet, findsOneWidget);

              scroll.jumpTo(0);
              await tester.pumpAndSettle();
              gesture = await tester.startGesture(
                tester.getTopLeft(viewport) + const Offset(80, 180),
              );
            }
            await gesture.moveBy(const Offset(0, 30));
            await gesture.moveBy(Offset(0, origin == 'header' ? 300 : 600));
            await tester.pump();
            expect(tester.getTopLeft(sheet).dy, greaterThan(top + 50));
            if (origin == 'header') expect(scroll.offset, 400);
            await gesture.up();
            await tester.pumpAndSettle();
            expect(harness.shell.visibleComposer, same(composer));
            expect(composer.closing, isFalse);
            expect(composer.isDisposed, isFalse);
            expect(composer.raw, text);
            expect(composer.text.selection.extentOffset, 0);
            expect(tester.state(find.byType(ComposerEditor)), same(editor));
            expect(tester.getTopLeft(sheet).dy, closeTo(top, .01));
            expect(api.draftsSaved.length, savesBeforeSwipe);
            for (final action in ['Discard', 'Minimize', 'Save draft']) {
              expect(find.text(action).hitTestable(), findsOneWidget);
            }
            await tester.tap(find.text('Save draft'));
            await tester.pumpAndSettle();
            expect(harness.shell.visibleComposer, isNull);
            expect(sheet, findsNothing);
            final request =
                (harness.shell.api.composerPersistence as FakeDiscourseApi)
                    .draftsSaved
                    .last;
            final saved = ComposerDraft.decode(request['data'] as String);
            expect(saved?.title, 'Keep my draft');
            expect(saved?.reply, text);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('composer body scrolls normally until it reaches the top', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      mobile: true,
      size: const Size(390, 800),
    );
    final composer = harness.shell.visibleComposer!;
    composer.text.text = List.generate(60, (i) => 'Paragraph $i').join('\n');
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('composer-mobile-scroll'));
    final scroll = tester.widget<CustomScrollView>(viewport).controller!;
    final sheet = find.byKey(const ValueKey('composer-mobile-sheet'));
    final bounds = tester.getRect(sheet);
    scroll.jumpTo(400);
    await tester.pumpAndSettle();
    await tester.drag(viewport, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(scroll.offset, inExclusiveRange(0, 400));
    expect(tester.getRect(sheet), bounds);
    expect(harness.shell.visibleComposer, same(composer));
    scroll.jumpTo(60);
    await tester.pumpAndSettle();
    await tester.drag(viewport, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(harness.shell.visibleComposer, same(composer));
    expect(tester.getRect(sheet), bounds);
    expect(find.text('Discard').hitTestable(), findsOneWidget);
    expect(find.text('Minimize').hitTestable(), findsOneWidget);
    expect(find.text('Save draft').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'swiping an empty composer opens actions without closing it (reduced: $reducedMotion)',
      (tester) async {
        final harness = await _Harness.create(
          tester,
          mobile: true,
          reducedMotion: reducedMotion,
          size: const Size(390, 800),
        );
        final composer = harness.shell.visibleComposer!;
        final sheet = find.byKey(const ValueKey('composer-mobile-sheet'));
        final bounds = tester.getRect(sheet);
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.dragFrom(
            tester.getCenter(find.byKey(const ValueKey('composer-header'))),
            const Offset(0, 300),
          );
          await tester.pumpAndSettle();
          expect(harness.shell.visibleComposer, same(composer));
          expect(composer.isDisposed, isFalse);
          expect(tester.getRect(sheet), bounds);
          for (final action in ['Discard', 'Minimize', 'Save draft']) {
            expect(find.text(action).hitTestable(), findsOneWidget);
          }
          await tester.tap(find.byKey(const ValueKey('composer-close')));
          await tester.pumpAndSettle();
          expect(find.text('Discard'), findsNothing);
          expect(harness.shell.visibleComposer, same(composer));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final action in ['Discard', 'Minimize']) {
    testWidgets('swipe close actions can $action the composer', (tester) async {
      final harness = await _Harness.create(
        tester,
        mobile: true,
        size: const Size(390, 800),
      );
      final composer = harness.shell.visibleComposer!;
      composer.text.text = 'Keep the draft until an action is chosen';
      await tester.pumpAndSettle();
      final editor = tester.state(find.byType(ComposerEditor));
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('composer-header'))),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(harness.shell.visibleComposer, same(composer));
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      if (action == 'Discard') {
        expect(
          find.byKey(const ValueKey('composer-discard-dialog')),
          findsOneWidget,
        );
        expect(composer.isDisposed, isFalse);
        await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
        await tester.pumpAndSettle();
        expect(composer.raw, 'Keep the draft until an action is chosen');
        await tester.dragFrom(
          tester.getCenter(find.byKey(const ValueKey('composer-header'))),
          const Offset(0, 300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('composer-confirm-discard')),
        );
        await tester.pumpAndSettle();
        expect(harness.shell.visibleComposer, isNull);
      } else {
        expect(
          find.byKey(const ValueKey('composer-mobile-sheet')),
          findsNothing,
        );
        expect(harness.shell.visibleComposer, same(composer));
        await tester.tap(find.byKey(const ValueKey('composer-restore')));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ComposerEditor)), same(editor));
        expect(composer.raw, 'Keep the draft until an action is chosen');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a cancelled swipe keeps the short composer and selection', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      mobile: true,
      size: const Size(390, 800),
    );
    final composer = harness.shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: 'Keep this text',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('composer-mobile-sheet'));
    final bounds = tester.getRect(sheet);
    final editor = tester.state(find.byType(ComposerEditor));
    final shortSwipe = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('composer-header'))),
    );
    await shortSwipe.moveBy(const Offset(0, 30));
    await shortSwipe.moveBy(const Offset(0, 35));
    await tester.pump();
    expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top));
    await shortSwipe.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), bounds);
    expect(find.text('Discard'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('composer-mobile-scroll'))),
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    expect(tester.getTopLeft(sheet).dy, greaterThan(bounds.top));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), bounds);
    expect(harness.shell.visibleComposer, same(composer));
    expect(tester.state(find.byType(ComposerEditor)), same(editor));
    expect(composer.text.selection.extentOffset, 4);
    expect(composer.raw, 'Keep this text');
    expect(find.text('Discard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a swipe cannot close a composer during submission', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      mobile: true,
      size: const Size(390, 800),
    );
    final composer = harness.shell.visibleComposer!;
    composer.text.text = 'Keep the pending post';
    composer.beginSubmit();
    await tester.pump();
    final sheet = find.byKey(const ValueKey('composer-mobile-sheet'));
    final bounds = tester.getRect(sheet);
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('composer-header'))),
      const Offset(0, 300),
    );
    // Submission keeps an indeterminate progress indicator animating.
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(harness.shell.visibleComposer, same(composer));
    expect(tester.getRect(sheet), bounds);
    expect(composer.raw, 'Keep the pending post');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  for (final keyboard in [0.0, 300.0]) {
    testWidgets(
      'picker focus and swipe keep the composer fixed (keyboard: $keyboard)',
      (tester) async {
        final harness = await _Harness.create(
          tester,
          mobile: true,
          size: const Size(390, 800),
        );
        final composer = harness.shell.visibleComposer!;
        composer.text.text = 'Keep the editor in place.';
        composer.focus.requestFocus();
        addTearDown(tester.view.resetViewInsets);
        void setKeyboard(double inset) {
          tester.view.viewInsets = FakeViewPadding(
            bottom: inset * tester.view.devicePixelRatio,
          );
        }

        setKeyboard(keyboard);
        await tester.pumpAndSettle();
        final panel = find.byType(ComposerPanel);
        final toolbar = find.byKey(const ValueKey('composer-toolbar-scroll'));
        final viewport = find.byKey(const ValueKey('composer-mobile-scroll'));
        final bounds = [
          tester.getRect(panel),
          tester.getRect(toolbar),
          tester.getRect(viewport),
        ];
        void expectStill() {
          expect(tester.getRect(panel), bounds[0]);
          expect(tester.getRect(toolbar), bounds[1]);
          expect(tester.getRect(viewport), bounds[2]);
        }

        await tester.tap(
          find.byKey(const ValueKey('composer-category-action')),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();
        final picker = find.byType(DSheetTitle);
        expect(picker, findsOneWidget);
        for (final inset in [0.0, 180.0, 330.0]) {
          setKeyboard(inset);
          await tester.pump(const Duration(milliseconds: 70));
          expectStill();
        }
        await tester.pumpAndSettle();
        for (final inset in [180.0, 0.0, 330.0]) {
          setKeyboard(inset);
          await tester.pumpAndSettle();
          expectStill();
          final surface = find
              .ancestor(of: picker, matching: find.byType(DSheetContent))
              .first;
          expect(
            tester.getBottomLeft(surface).dy,
            closeTo(800 - inset - DSpacing.md, 1),
          );
        }
        showDSheet<void>(
          context: tester.element(picker),
          side: DSheetSide.bottom,
          builder: (_, _) => const DSheetContent(
            side: DSheetSide.bottom,
            children: [
              DSheetHeader(
                children: [DSheetTitle(child: Text('Nested picker'))],
              ),
            ],
          ),
        ).ignore();
        await tester.pumpAndSettle();
        setKeyboard(210);
        await tester.pump();
        expectStill();
        await tester.tap(find.byTooltip('Close').last);
        await tester.pumpAndSettle();
        expect(find.text('Nested picker'), findsNothing);
        expectStill();
        final gesture = await tester.startGesture(tester.getCenter(picker));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 300));
        await tester.pump();
        expectStill();
        await gesture.up();
        await tester.pump();
        // The underlying route is current again before the sheet finishes
        // closing, while the keyboard is still handing focus back.
        setKeyboard(0);
        await tester.pump(const Duration(milliseconds: 60));
        expect(picker, findsOneWidget);
        expectStill();
        setKeyboard(keyboard);
        await tester.pumpAndSettle();
        expect(picker, findsNothing);
        expectStill();
        expect(composer.focus.hasFocus, isTrue);
        expect(composer.raw, 'Keep the editor in place.');

        // Once the picker is gone, real keyboard changes resize the composer.
        setKeyboard(keyboard == 0 ? 300 : 0);
        await tester.pumpAndSettle();
        expect(tester.getRect(toolbar), isNot(bounds[1]));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mobile overflow arrow scales with draft and viewport changes', (
    tester,
  ) async {
    final harness = await _Harness.create(
      tester,
      mobile: true,
      size: const Size(390, 800),
    );
    final composer = harness.shell.visibleComposer!;
    final arrow = find.byKey(const ValueKey('composer-scroll-down'));
    final scale = find.byKey(const ValueKey('composer-scroll-down-scale'));
    final viewport = find.byKey(const ValueKey('composer-mobile-scroll'));
    double targetScale() => tester.widget<AnimatedScale>(scale).scale;
    expect(targetScale(), 0);
    expect(arrow.hitTestable(), findsNothing);

    composer.text.text = List.generate(60, (i) => 'Paragraph $i').join('\n');
    await tester.pumpAndSettle();
    expect(targetScale(), 1);
    expect(arrow.hitTestable(), findsOneWidget);
    expect(tester.widget<DButton>(arrow).shape, DButtonShape.pill);
    expect(tester.getSize(arrow).width, tester.getSize(arrow).height);
    expect(tester.widget<AnimatedScale>(scale).duration, isNot(Duration.zero));
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    expect(targetScale(), 0);
    expect(arrow.hitTestable(), findsNothing);
    final scroll = tester.widget<CustomScrollView>(viewport).controller!;
    expect(scroll.position.extentAfter, closeTo(0, 2));

    await tester.drag(viewport, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(targetScale(), 1);

    composer.text.text = 'Short draft';
    await tester.pumpAndSettle();
    expect(targetScale(), 0);
    composer.focus.unfocus();
    composer.text.value = TextEditingValue(
      text: List.generate(18, (i) => 'Line $i').join('\n'),
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.pumpAndSettle();
    expect(targetScale(), 0);
    tester.view.viewInsets = FakeViewPadding(
      bottom: 330 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(targetScale(), 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long mobile drafts scroll title and body beneath the pinned actions',
    (tester) async {
      final harness = await _Harness.create(
        tester,
        mobile: true,
        size: const Size(390, 800),
      );
      tester.view.viewInsets = FakeViewPadding(
        bottom: 330 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      final composer = harness.shell.visibleComposer!;
      composer.title.text = 'A long topic';
      final text = List.generate(
        60,
        (index) => 'Paragraph $index of this draft.',
      ).join('\n');
      composer.text.value = TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 0),
      );
      await tester.pumpAndSettle();
      final viewport = find.byKey(const ValueKey('composer-mobile-scroll'));
      final title = find.byKey(const ValueKey('composer-topic-title'));
      final titleField = tester.widget<EditableText>(
        find.descendant(of: title, matching: find.byType(EditableText)),
      );
      expect(titleField.style.fontSize, 17);
      expect(titleField.style.height, 1.5);
      final close = find.byKey(const ValueKey('composer-close'));
      final submit = find.byKey(const ValueKey('composer-submit'));
      final footer = find.byKey(const ValueKey('composer-footer'));
      final titleBefore = tester.getTopLeft(title);
      final fixed = [close, submit, footer];
      final bounds = fixed.map(tester.getRect).toList();
      await tester.drag(viewport, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dy, lessThan(titleBefore.dy - 100));
      for (var i = 0; i < fixed.length; i++) {
        expect(tester.getRect(fixed[i]), bounds[i]);
      }
      expect(close.hitTestable(), findsOneWidget);
      expect(submit.hitTestable(), findsOneWidget);
      final scrollbar = tester.widget<DScrollBar>(
        find.ancestor(of: viewport, matching: find.byType(DScrollBar)).first,
      );
      expect(scrollbar.showScrollbar, isFalse);
      final editable = find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(EditableText),
      );
      expect(
        tester
            .widget<EditableText>(editable)
            .scrollController!
            .position
            .maxScrollExtent,
        0,
      );
      await tester.showKeyboard(editable);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '$text\nLast line',
          selection: TextSelection.collapsed(offset: text.length + 10),
        ),
      );
      await tester.pumpAndSettle();
      final render = tester.state<EditableTextState>(editable).renderEditable;
      var caret = render.localToGlobal(
        render.getLocalRectForCaret(composer.text.selection.extent).bottomLeft,
      );
      expect(caret.dy, lessThan(tester.getTopLeft(footer).dy));
      expect(caret.dy, greaterThan(tester.getBottomLeft(close).dy));
      tester.testTextInput.updateEditingValue(
        composer.text.value.copyWith(
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pumpAndSettle();
      caret = render.localToGlobal(
        render.getLocalRectForCaret(composer.text.selection.extent).topLeft,
      );
      expect(caret.dy, greaterThanOrEqualTo(tester.getBottomLeft(close).dy));
      expect(tester.takeException(), isNull);
    },
  );

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
        tester.getRect(find.byKey(const ValueKey('composer-footer-blur'))).top,
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('composer-category-action')))
              .dy,
          .01,
        ),
      );
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
    bool reducedMotion = false,
    TargetPlatform? platform,
    bool includeSidebar = false,
    Size size = const Size(1000, 700),
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
    FocusNode? readerFocus,
    Widget? reader,
    double? windowCorner,
  }) async {
    const user = DiscourseUser(
      id: 7,
      username: 'sam',
      canCreateTopic: true,
      canSendPrivateMessages: true,
    );
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
            platform:
                platform ??
                (mobile ? TargetPlatform.iOS : TargetPlatform.linux),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
            ),
            child: DToaster(child: child!),
          ),
          home: DDirection(
            textDirection: direction,
            child: ComposerPresentationHost(
              controller: presentation,
              child: Scaffold(
                body: Row(
                  children: [
                    if (includeSidebar)
                      const SizedBox(width: 240, child: InstanceSidebar()),
                    Expanded(
                      child: WorkspacePanelCorner(
                        radius: windowCorner,
                        child: ComposerDock(
                          child: Focus(
                            focusNode: readerFocus,
                            autofocus: readerFocus != null,
                            child:
                                reader ??
                                ListView(
                                  key: const ValueKey('reader-list'),
                                  children: [
                                    for (var i = 0; i < 100; i++)
                                      Text('Post $i'),
                                  ],
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
