import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

void main() {
  testWidgets('a list thins under the phone bar as far as the bar reaches', (
    tester,
  ) async {
    await fixture.pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 1; id <= 60; id++)
          Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
      ],
    );
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(TopicListView),
      matching: find.byType(Scrollable),
    );
    final foot = DScrollFootScope.maybeOf(tester.element(scrollable))!;
    final geometry = DMobileDockGeometry.of(
      tester.element(find.byType(DMobileDock)),
    );
    expect(geometry.foot, 34);

    // The list runs on to the bottom the bar floats at.
    final ground = foot.ground()!;
    expect(
      tester.getRect(scrollable).bottom,
      closeTo(ground.localToGlobal(Offset(0, ground.size.height)).dy, .001),
    );

    // Open, from the bar's top margin to the foot: 6 + 86 at the default
    // text scale, more as the dock's text grows.
    expect(foot.extent.value, closeTo(geometry.footerExtent, .001));

    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(300);
    await tester.pump();
    position.pointerScroll(160);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
      isTrue,
    );

    // Folded, as high as the circle in its corner and the margin above it.
    expect(
      foot.extent.value,
      closeTo(
        DMobileDockGeometry.inset +
            geometry.circle +
            geometry.cornerAt(geometry.circle),
        .001,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
