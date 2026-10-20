import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'support/chat_scroll_fixture.dart';

const _captureKey = ValueKey('floating-date-repaint-capture');
const _captureImages = bool.fromEnvironment('FLOATING_DATE_CAPTURE');

void main() => floatingDateRepaintTests();

void floatingDateRepaintTests({bool native = false}) {
  for (final dark in [true, false]) {
    testWidgets(
      'chat floating date keeps its glass when entering a clip (dark: $dark)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        if (native) {
          await tester.runAsync(LiquidGlass.precache);
          expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
        }
        final controller = await chatScrollController(count: 24);
        addTearDown(controller.dispose);
        final top = ValueNotifier<double>(-47);
        addTearDown(top.dispose);
        await tester.pumpWidget(_host(controller, top, dark: dark));
        await tester.pumpAndSettle();
        final floating = find.byWidgetPredicate(
          (widget) => widget is StreamDaySeparator && widget.floating,
        );
        expect(floating, findsOneWidget);
        if (native) {
          expect(
            find.descendant(of: floating, matching: find.byType(FakeGlass)),
            findsNothing,
          );
        }
        final separator = tester.widget<StreamDaySeparator>(floating);
        final initialElement = tester.element(floating);
        top.value = 40;
        await tester.pumpAndSettle();
        expect(tester.widget(floating), same(separator));
        expect(tester.element(floating), same(initialElement));
        final button = find.descendant(
          of: floating,
          matching: find.byType(DButton),
        );
        final captureOrigin = tester.getTopLeft(find.byKey(_captureKey));
        final bounds = tester.getRect(button).shift(-captureOrigin);
        final moved = await _capture(tester, '$dark-moved');
        tester.renderObject<RenderBox>(floating).markNeedsPaint();
        await tester.pumpAndSettle();
        final repainted = await _capture(tester, '$dark-repainted');
        expect(
          _differentPixels(moved, repainted, bounds),
          0,
          reason:
              'moving the visible date must preserve the fully painted pill',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

Widget _host(
  ShellController controller,
  ValueNotifier<double> top, {
  required bool dark,
}) => ShellScope(
  controller: controller,
  child: PluginUiScope.own(
    chatPluginId,
    MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: DMaterialTheme.apply(
        (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.iOS,
        ),
        DAppearanceMaterial.liquidGlass,
      ),
      home: Center(
        child: RepaintBoundary(
          key: _captureKey,
          child: SizedBox(
            width: 380,
            height: 220,
            child: ClipRect(
              child: DMaterialSurface(
                depth: DSurfaceDepth.panel,
                color: dark ? const Color(0xff303030) : const Color(0xffeeeeee),
                radius: BorderRadius.circular(20),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: top,
                      builder: (_, value, child) => Positioned(
                        left: 0,
                        right: 0,
                        top: value,
                        height: 600,
                        child: child!,
                      ),
                      child: const ChatChannelView(
                        channelId: 9,
                        showHeader: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _capture(WidgetTester tester, String name) async {
  late Uint8List pixels;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey))
        .toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    pixels = Uint8List.fromList(data!.buffer.asUint8List());
    if (_captureImages) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/private/tmp/floating-date-repaint-$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
    }
    image.dispose();
  });
  return pixels;
}

int _differentPixels(Uint8List first, Uint8List second, Rect bounds) {
  var count = 0;
  for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
    for (var x = bounds.left.ceil(); x < bounds.right.floor(); x++) {
      final offset = (y * 380 + x) * 4;
      if (first[offset] != second[offset] ||
          first[offset + 1] != second[offset + 1] ||
          first[offset + 2] != second[offset + 2] ||
          first[offset + 3] != second[offset + 3]) {
        count++;
      }
    }
  }
  return count;
}
