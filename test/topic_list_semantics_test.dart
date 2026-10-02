import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/topic_list_scroll_fixture.dart';
import 'support/topic_scroll_capture.dart';

void main() {
  final binding = _SemanticsBinding();

  testWidgets('compact scrolling sends a connected accessibility tree', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await topicListScrollController(
      mode: TopicListDisplayMode.compact,
      events: true,
      assignments: true,
    );
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: topicScrollCaptureWithoutVm(),
    );
    addTearDown(() async {
      controller.dispose();
      await controller.pluginTeardown;
      await controller.plugins.close();
      await diagnostics.close();
    });
    final semantics = tester.ensureSemantics();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await tester.pumpWidget(
        TopicListScrollFixture(
          controller: controller,
          diagnostics: diagnostics,
        ),
      );
      await tester.pumpAndSettle();
      await mouse.addPointer(location: const Offset(300, 200));
      await tester.pumpAndSettle();
      for (final tooltip in tester.stateList<DTooltipState>(
        find.byType(DTooltip),
      )) {
        tooltip.ensureTooltipVisible();
        await tester.pumpAndSettle();
        expect(binding.errors, isEmpty);
        tooltip.hide();
        await tester.pumpAndSettle();
        expect(binding.errors, isEmpty);
      }
      // A modal replaces the background route's accessibility tree. Closing it
      // must restore every table node, including its cached children.
      unawaited(
        showDDialog<void>(
          context: tester.element(find.byType(SuperListView)),
          builder: (_, _) => const DDialogContent(
            children: [Text('Accessibility tree replacement')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(binding.errors, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(binding.errors, isEmpty);
      // A focused close button can open its tooltip; Escape dismisses that
      // hint before the dialog receives a second Escape.
      if (find.byType(DDialogContent).evaluate().isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(binding.errors, isEmpty);
      }
      expect(find.byType(DDialogContent), findsNothing);
      final position = tester
          .widget<SuperListView>(find.byType(SuperListView))
          .controller!
          .position;
      for (var step = 0; step < 10; step++) {
        final schedule = find
            .byKey(const ValueKey('event-schedule-summary'))
            .first;
        await mouse.moveTo(tester.getCenter(schedule));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 160));
        position.pointerScroll(1200);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          binding.errors,
          isEmpty,
          reason: 'scrolling an open tooltip away',
        );
        await tester.pump(const Duration(milliseconds: 160));
        expect(binding.errors, isEmpty);
      }
      position.jumpTo(0);
      await tester.pumpAndSettle();
      for (final (delta, steps) in [
        (10.0, 40),
        (40.0, 80),
        (1200.0, 20),
        (-1200.0, 20),
        (-40.0, 80),
        (-10.0, 40),
      ]) {
        for (var step = 0; step < steps; step++) {
          position.pointerScroll(delta);
          await tester.pump(const Duration(milliseconds: 16));
          expect(binding.errors, isEmpty, reason: 'offset ${position.pixels}');
        }
      }
      expect(binding.batches, greaterThan(100));
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      await diagnostics.close();
    }
    expect(binding.errors, isEmpty);
  });
}

// Checking the final framework tree misses updates sent for nodes that have
// already left it. Apply the incremental updates as the native bridge does.
// Overlay portals can have different traversal and hit-test parents, so a
// node remains attached while either native tree can reach it.
class _SemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final tree = <int, List<int>>{};
  final hitTestTree = <int, List<int>>{};
  final errors = <String>[];
  var batches = 0;

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _UpdateBuilder(checkUpdate);

  void checkUpdate(
    Map<int, List<int>> update,
    Map<int, List<int>> hitTestUpdate,
  ) {
    batches++;
    final reachable = applyUpdate(tree, update);
    final hitTestReachable = applyUpdate(hitTestTree, hitTestUpdate);
    for (final id in update.keys) {
      if (!reachable.contains(id) && !hitTestReachable.contains(id)) {
        errors.add('Update for detached node $id');
      }
    }
  }

  Set<int> applyUpdate(Map<int, List<int>> tree, Map<int, List<int>> update) {
    // The native AX tree moves nodes by removing their old subtree first,
    // then applying the update that attaches them to the new parent.
    final parents = <int, int>{
      for (final entry in tree.entries)
        for (final child in entry.value) child: entry.key,
    };
    for (final entry in update.entries) {
      for (final child in entry.value) {
        final oldParent = parents[child];
        if (oldParent != null && oldParent != entry.key) {
          tree[oldParent]!.remove(child);
        }
      }
    }
    final retained = <int>{};
    void retain(int id) {
      if (!retained.add(id)) return;
      for (final child in tree[id] ?? <int>[]) {
        retain(child);
      }
    }

    retain(0);
    tree.removeWhere((id, _) => !retained.contains(id));
    tree.addAll(update);
    final reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      final children = tree[id];
      if (children == null) {
        errors.add('Missing node $id');
        return;
      }
      for (final child in children) {
        visit(child);
      }
    }

    visit(0);
    tree.removeWhere((id, _) => !reachable.contains(id));
    return reachable;
  }
}

class _UpdateBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  _UpdateBuilder(this.checkUpdate);
  final void Function(Map<int, List<int>>, Map<int, List<int>>) checkUpdate;
  final update = <int, List<int>>{};
  final hitTestUpdate = <int, List<int>>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      update[args[#id]! as int] = List<int>.of(
        args[#childrenInTraversalOrder]! as List<int>,
      );
      hitTestUpdate[args[#id]! as int] = List<int>.of(
        args[#childrenInHitTestOrder]! as List<int>,
      );
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    checkUpdate(update, hitTestUpdate);
    return ui.SemanticsUpdateBuilder().build();
  }
}
