import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_scroll_fixture.dart';

Future<int> _hiddenInk(WidgetTester tester, Finder scroll) async {
  final stream = tester.renderObject<RenderBox>(find.byType(ChatMessageStream));
  ShaderMaskLayer? mask;
  void findMask(RenderObject object) {
    if (object.debugLayer case final ShaderMaskLayer layer
        when layer.maskRect!.width == stream.size.width) {
      mask = layer;
    } else {
      object.visitChildren(findMask);
    }
  }

  findMask(stream);
  expect(mask, isNotNull);
  final bounds = mask!.maskRect!;
  final composer = tester.getRect(find.byKey(const ValueKey('chat-composer')));
  final cutoff = bounds.top + composer.top - tester.getRect(scroll).top;
  return (await tester.runAsync(() async {
    final scene = mask!.buildScene(ui.SceneBuilder());
    final image = await scene.toImage(
      bounds.right.ceil(),
      bounds.bottom.ceil(),
    );
    scene.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var above = 0, below = 0;
    for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
      for (var x = bounds.left.ceil(); x < bounds.right.floor(); x++) {
        if (bytes.getUint8((y * image.width + x) * 4 + 3) == 0) continue;
        if (y >= cutoff.ceil()) below++;
        if (y < cutoff - 40) above++;
      }
    }
    image.dispose();
    expect(
      above,
      greaterThan(0),
      reason: 'the transcript must contain visible ink',
    );
    return below;
  }))!;
}

void main() {
  testWidgets(
    'mobile chat text stops at the floating composer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = await chatScrollController(count: 100);
      addTearDown(controller.dispose);
      try {
        await tester.pumpWidget(
          ScrollConfiguration(
            behavior: const DScrollBehavior(),
            child: ChatScrollFixture(controller: controller, width: 390),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.descendant(
          of: find.byType(ChatMessageStream),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        );
        final position = tester.state<ScrollableState>(scroll).position;
        final pixels = <String, int>{};
        position.jumpTo(250);
        await tester.pumpAndSettle();
        pixels['history'] = await _hiddenInk(tester, scroll);
        position.jumpTo(0);
        await tester.pumpAndSettle();
        pixels['present'] = await _hiddenInk(tester, scroll);
        await tester.drag(scroll, const Offset(0, 180));
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0));
        pixels['scroll to history'] = await _hiddenInk(tester, scroll);
        await tester.drag(scroll, const Offset(0, -80));
        await tester.pumpAndSettle();
        pixels['reverse direction'] = await _hiddenInk(tester, scroll);
        final composer = find.byKey(const ValueKey('chat-composer'));
        final height = tester.getSize(composer).height;
        await tester.enterText(
          find.descendant(of: composer, matching: find.byType(EditableText)),
          'First line\nSecond line\nThird line',
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(composer).height, greaterThan(height));
        pixels['multiline composer'] = await _hiddenInk(tester, scroll);
        expect(pixels.values, everyElement(0), reason: pixels.toString());
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
