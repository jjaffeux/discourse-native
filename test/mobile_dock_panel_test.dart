import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

/// The phone bar's panel of places inside the shell: what it must leave
/// alone while it moves, and what the shell leaves to it.
void main() {
  final panel = find.byKey(DMobileDock.panelKey);

  testWidgets('a drag on the bar rebuilds neither the shell nor the page', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    final root = tester.element(find.byType(MobileForumRoot));
    final chrome = tester.element(
      find
          .descendant(
            of: find.byType(MobileForumRoot),
            matching: find.byType(ListenableBuilder),
          )
          .first,
    );
    final page = tester.element(find.byType(TopicListView));
    final header = tester.element(find.byKey(const ValueKey('mobile-header')));
    var notifications = 0;
    void count() => notifications++;
    shell.addListener(count);
    addTearDown(() => shell.removeListener(count));
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    final topics = tester.getCenter(
      find.byKey(const ValueKey('mobile-mode-topics')),
    );
    final gesture = await tester.createGesture();
    await gesture.down(topics, timeStamp: Duration.zero);
    for (var step = 1; step <= 6; step++) {
      await gesture.moveBy(
        const Offset(0, -12),
        timeStamp: Duration(milliseconds: 16 * step),
      );
      await tester.pump();
    }
    expect(panel, findsOneWidget);
    expect(rebuilt, isNotEmpty);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(chrome)));
    expect(rebuilt, isNot(contains(page)));
    expect(rebuilt, isNot(contains(header)));
    expect(notifications, 0);
    await gesture.up(timeStamp: const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(chrome)));
    expect(rebuilt, isNot(contains(page)));
    expect(notifications, 0);
    // The drag pressed nothing: Topics was under the finger and is still
    // the place, not a place gone to.
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(tester.takeException(), isNull);
  });
}
