import 'dart:convert';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_scroll_fixture.dart';

void main() {
  testWidgets('retained production chat images suspend and resume', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await chatScrollController(
      count: 100,
      animatedBytes: base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
        'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
      ),
    );
    addTearDown(controller.dispose);
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
    );
    addTearDown(diagnostics.close);
    final fixture = ChatScrollFixture(
      controller: controller,
      diagnostics: diagnostics,
    );
    // Close under the fake clock even when the body fails, so nothing in the
    // finally may throw before the close: a close first reached from a tearDown
    // never completes, because it waits on futures created under the fake
    // clock, which nothing drives once the body has returned.
    try {
      await tester.pumpWidget(TickerMode(enabled: true, child: fixture));
      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 110));
          await tester.pump();
        }
      }

      await frames(15);
      final scrollable = find.descendant(
        of: find.byType(ChatMessageStream),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
        ),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final gifRows = find
          .byType(ChatMessageTile)
          .evaluate()
          .where(
            (element) => const {
              98,
              99,
              100,
            }.contains((element.widget as ChatMessageTile).messageId),
          )
          .toList();
      expect(gifRows, hasLength(3));
      void expectGifPhase({required bool retained}) {
        for (final row in gifRows) {
          expect(row.mounted, isTrue);
          RenderObject? render = row.renderObject;
          while (render != null &&
              render.parentData is! SliverMultiBoxAdaptorParentData) {
            render = render.parent;
          }
          expect(
            (render!.parentData! as SliverMultiBoxAdaptorParentData).keptAlive,
            retained,
          );
          if (!retained) {
            expect(
              tester
                  .getRect(find.byElementPredicate((e) => identical(e, row)))
                  .overlaps(tester.getRect(scrollable)),
              isTrue,
            );
          }
        }
      }

      expectGifPhase(retained: false);

      final tile = find
          .byType(ChatMessageTile)
          .evaluate()
          .firstWhere(
            (element) => find
                .descendant(
                  of: find.byElementPredicate(
                    (candidate) => identical(element, candidate),
                  ),
                  matching: find.byType(SiteImage),
                )
                .evaluate()
                .isNotEmpty,
          );
      final tileFinder = find.byElementPredicate(
        (e) => identical(e, tile),
        skipOffstage: false,
      );
      final images = find.descendant(
        of: tileFinder,
        matching: find.byType(Image, skipOffstage: false),
      );
      final image = images.evaluate().single;
      final imageStream = (image.widget as Image).image.resolve(
        createLocalImageConfiguration(image),
      );
      final completer = imageStream.completer!;
      expect(completer.hasListeners, isTrue);
      expect(
        find.descendant(of: tileFinder, matching: find.byType(SiteImage)),
        findsOneWidget,
      );
      var builds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (identical(element, image)) builds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      await frames(10);
      final visibleBuilds = builds;
      expect(visibleBuilds, greaterThan(0));
      for (var i = 0; i < 8; i++) {
        position.pointerScroll(150);
        await frames(1);
      }
      expect(tile.mounted, isTrue);
      RenderObject? render = tile.renderObject;
      while (render != null &&
          render.parentData is! SliverMultiBoxAdaptorParentData) {
        render = render.parent;
      }
      expect(
        (render!.parentData! as SliverMultiBoxAdaptorParentData).keptAlive,
        isTrue,
      );
      await frames(3);
      expectGifPhase(retained: true);
      builds = 0;
      await frames(10);
      expectGifPhase(retained: true);
      final retainedBuilds = builds;
      debugPrint(
        'CHAT_ANIMATION visible=$visibleBuilds retained=$retainedBuilds ticker=${TickerMode.valuesOf(image).enabled} listeners=${completer.hasListeners} scheduled=${tester.binding.hasScheduledFrame} callbacks=${tester.binding.transientCallbackCount}',
      );
      expect(retainedBuilds, 0);
      expect(completer.hasListeners, isFalse);
      expect(
        Focus.of(image).ancestors.any((node) => !node.descendantsAreFocusable),
        isTrue,
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      for (var i = 0; i < 8; i++) {
        position.pointerScroll(-150);
        await frames(1);
      }
      await frames(4);
      expect(tile.mounted, isTrue);
      expectGifPhase(retained: false);
      builds = 0;
      await frames(10);
      expect(builds, greaterThan(0));
      expect(completer.hasListeners, isTrue);
      expect(
        Focus.of(image).ancestors.any((node) => !node.descendantsAreFocusable),
        isFalse,
      );

      // A hidden tab must still override a row that is locally visible.
      await tester.pumpWidget(TickerMode(enabled: false, child: fixture));
      await frames(3);
      expect(completer.hasListeners, isFalse);
      builds = 0;
      await frames(10);
      expect(builds, 0);
      await tester.pumpWidget(TickerMode(enabled: true, child: fixture));
      await frames(3);
      expect(completer.hasListeners, isTrue);

      // The row boundary must not override a user's explicit GIF pause or
      // reset the playback control's state when reversing back into the row.
      final toggle = find.descendant(
        of: tileFinder,
        matching: find.byKey(const ValueKey('gif-playback-toggle')),
      );
      await tester.tap(toggle);
      await frames(3);
      expect(completer.hasListeners, isFalse);
      for (final delta in [150.0, -150.0]) {
        for (var i = 0; i < 8; i++) {
          position.pointerScroll(delta);
          await frames(1);
        }
      }
      expect(tile.mounted, isTrue);
      expect(completer.hasListeners, isFalse);
      builds = 0;
      await frames(10);
      expect(builds, 0);
      await tester.tap(toggle);
      await frames(3);
      expect(completer.hasListeners, isTrue);
      builds = 0;
      await frames(10);
      expect(builds, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await frames(4);
      expect(tile.mounted, isFalse);
      expect(gifRows.where((row) => row.mounted), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
    expect(tester.takeException(), isNull);
  });
}
