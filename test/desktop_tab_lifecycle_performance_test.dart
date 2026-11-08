import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tab_switch_fixture.dart';

void main() {
  setUp(() {
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets(
    'opening and closing retain unrelated desktop tab controls',
    (tester) async {
      final shell = await pumpTabSwitchFixture(tester);
      // An overflowed strip with several existing tabs, beside a live reader.
      for (var i = 0; i < 6; i++) {
        shell.createTab(panel: ForumPanel.main);
        await tester.pumpAndSettle();
      }
      final original = shell.activeTabId!;
      shell.selectDestination(shell.currentInstance!.defaultDestination);
      await tester.pumpAndSettle();
      final page = tester.state(_page(original));
      final scrollable = find
          .descendant(
            of: _page(original),
            matching: find.byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(400);
      await tester.pumpAndSettle();
      final controls = tester.elementList(find.byType(DDocumentTab)).toSet();
      final counts = <String, Map<String, int>>{};
      final previous = debugOnRebuildDirtyWidget;
      var phase = '';
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (phase.isEmpty) return;
        final work = counts.putIfAbsent(phase, () => {});
        work.update('builds', (n) => n + 1, ifAbsent: () => 1);
        if (controls.contains(element)) {
          work.update('existingControls', (n) => n + 1, ifAbsent: () => 1);
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var round = 0; round < 3; round++) {
        phase = 'open-$round';
        await tester.tap(find.byKey(const ValueKey('forum-tabs-add')).first);
        await tester.pumpAndSettle();
        final opened = shell.activeTabId!;
        expect(opened, isNot(original));
        expect(_page(opened), findsOneWidget);
        phase = 'close-$round';
        await tester.tap(find.byKey(ValueKey('forum-tab-close-$opened')));
        await tester.pumpAndSettle();
        expect(shell.activeTabId, original);
        expect(find.byKey(ValueKey('forum-tab-$opened')), findsNothing);
        expect(tester.state(_page(original)), same(page));
        expect(position.pixels, closeTo(400, 1));
        expect(tester.takeException(), isNull);
      }
      phase = '';
      debugPrint('TAB_LIFECYCLE_WORK ${jsonEncode(counts)}');
      for (final work in counts.values) {
        expect(
          work['existingControls'],
          1,
          reason:
              'Only the existing tab whose selection changes needs rebuilding.',
        );
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );
}

Finder _page(String id) => find.byElementPredicate(
  (element) =>
      element.widget is MainContent && ForumTabScope.idOf(element) == id,
);
