import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void scrollGlassBackdropTests({bool native = false}) {
  for (final dark in [false, true]) {
    testWidgets('fixed glass keeps its backdrop while scrolling ($dark)', (
      tester,
    ) async {
      if (native) {
        expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
        await tester.runAsync(LiquidGlass.precache);
      }
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const header = ValueKey('fixed-glass-header');
      await tester.pumpWidget(
        MaterialApp(
          theme: DMaterialTheme.apply(
            (dark ? AppTheme.dark : AppTheme.light).copyWith(
              platform: TargetPlatform.iOS,
            ),
            DAppearanceMaterial.liquidGlass,
          ),
          home: Scaffold(
            body: DPageSurface.scrollable(
              header: ColoredBox(
                color: dark ? const Color(0xff202024) : const Color(0xffeeeeee),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: DButtonGroup(
                      key: header,
                      children: [
                        DButton.iconOnly(
                          icon: const Icon(Icons.bookmark),
                          tooltip: 'Bookmark',
                          variant: DButtonVariant.outline,
                          onPressed: () {},
                        ),
                        DButton.iconOnly(
                          icon: const Icon(Icons.notifications),
                          tooltip: 'Notifications',
                          variant: DButtonVariant.outline,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              bodyBuilder: (context, geometry) => Stack(
                children: [
                  ListView(
                    controller: scroll,
                    children: [
                      geometry.spacer,
                      for (var i = 0; i < 40; i++)
                        ColoredBox(
                          color: i.isEven
                              ? const Color(0xff307030)
                              : const Color(0xffb06040),
                          child: SizedBox(
                            height: 90,
                            child: Center(
                              child: DButton(
                                label: Text('Post action $i'),
                                onPressed: () {},
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    right: 20,
                    bottom: 80,
                    child: ColoredBox(
                      color: dark
                          ? const Color(0xff202024)
                          : const Color(0xffeeeeee),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: TopicProgressButton(
                          position: 79,
                          total: 97,
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controls = [
        find.byKey(header),
        find.byKey(const ValueKey('topic-progress-button')),
      ];
      if (native) {
        for (final control in controls) {
          expect(
            find.descendant(of: control, matching: find.byType(LiquidGlass)),
            findsWidgets,
          );
        }
      }
      Future<List<List<int>>> pixels(String frame) async {
        return tester
            .runAsync(() async {
              final builder = ui.SceneBuilder();
              tester.binding.renderViews.first.debugLayer!.addToScene(builder);
              final scene = builder.build();
              final image = await scene.toImage(390, 844);
              try {
                final bytes = (await image.toByteData())!.buffer.asUint8List();
                if (const bool.fromEnvironment('SCROLL_GLASS_CAPTURE')) {
                  final png = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    '/private/tmp/scroll-glass-$dark-$frame.png',
                  );
                  await file.writeAsBytes(png!.buffer.asUint8List());
                  debugPrint('SCROLL_GLASS_CAPTURE ${file.path}');
                }
                return [
                  for (final control in controls)
                    [
                      for (final point in [
                        tester.getRect(control).topLeft + const Offset(8, 8),
                        tester.getRect(control).topLeft + const Offset(12, 8),
                      ])
                        ...bytes.sublist(
                          (point.dy.floor() * 390 + point.dx.floor()) * 4,
                          (point.dy.floor() * 390 + point.dx.floor()) * 4 + 3,
                        ),
                    ],
                ];
              } finally {
                image.dispose();
                scene.dispose();
              }
            })
            .then((value) => value!);
      }

      final initial = await pixels('initial');
      for (final offset in [120.25, 320.5, 600.75, 0.0]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        final current = await pixels('offset-${offset.toInt()}');
        for (var i = 0; i < controls.length; i++) {
          expect(current[i], initial[i], reason: 'control $i at $offset');
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}

void main() => scrollGlassBackdropTests();
