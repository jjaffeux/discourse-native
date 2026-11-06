import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_list_scroll_fixture.dart';

void main() {
  testWidgets(
    'rows scrolled into a desktop topic list allocate no animations',
    (tester) async {
      tester.view.physicalSize = const Size(2560, 1720);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      // Every row carries posters, an excerpt, a category and tags, so it
      // mounts the avatar, tooltip, link and count controls a live row does.
      final controller = await topicListScrollController(
        count: 120,
        posters: 5,
      );
      addTearDown(() async {
        controller.dispose();
        await controller.pluginTeardown;
        await controller.plugins.close();
      });
      await tester.pumpWidget(
        TopicListScrollFixture(
          controller: controller,
          width: 1000,
          height: 820,
        ),
      );
      await tester.pumpAndSettle();

      final created = <String, int>{};
      var rows = 0;
      void listen(ObjectEvent event) {
        if (event is! ObjectCreated) return;
        created.update(event.className, (n) => n + 1, ifAbsent: () => 1);
        if (event.object case Element(
          :final widget,
        ) when '${widget.runtimeType}' == '_TopicRow') {
          rows++;
        }
      }

      FlutterMemoryAllocations.instance.addListener(listen);
      addTearDown(
        () => FlutterMemoryAllocations.instance.removeListener(listen),
      );
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(TopicListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final center = tester.getCenter(find.byType(TopicListView));
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(center));
      for (var step = 1; step <= 60; step++) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(center, pan: Offset(0, -60.0 * step)),
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pumpAndSettle();
      FlutterMemoryAllocations.instance.removeListener(listen);

      expect(scrollable.position.pixels, greaterThan(3000));
      expect(rows, greaterThan(20), reason: 'rows must enter the viewport');
      expect(created['Element'], greaterThan(rows * 500));
      expect(created['AnimationController'], isNull);
      expect(created['Ticker'], isNull);
      expect(created['CurvedAnimation'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
