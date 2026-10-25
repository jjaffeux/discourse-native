import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_chatting_fixture.dart';

const _capture = ValueKey('command-presentation-capture');

void main() => commandPresentationRenderingTests();

void commandPresentationRenderingTests({bool native = false}) {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
    if (ui.ImageFilter.isShaderFilterSupported) {}
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    {
      for (final dark in [false, true]) {
        final name = '${platform.name}-flat-${dark ? 'dark' : 'light'}';
        testWidgets('command presentations share one surface: $name', (
          tester,
        ) async {
          if (!native) {
            tester.view.physicalSize = Size(
              platform == TargetPlatform.iOS ? 390 : 1000,
              844,
            );
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          final controller = DDialogController<String>();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: platform,
              ),
              builder: (context, child) =>
                  RepaintBoundary(key: _capture, child: child!),
              home: Scaffold(
                body: Center(
                  child: DCommandDialog<String>(
                    controller: controller,
                    trigger: DDialogTrigger(
                      builder: (context, open) => DButton(
                        label: const Text('Open command'),
                        onPressed: open,
                      ),
                    ),
                    command: DCommand<String>(
                      onSelected: controller.close,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DCommandInput<String>(),
                          DCommandList<String>(
                            children: [
                              DCommandItem(
                                value: 'Chat',
                                child: Text('Start chatting'),
                              ),
                              DCommandItem(
                                value: 'Search',
                                child: Text('Search topics'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open command'));
          await tester.pumpAndSettle();
          _expectPresentation(tester, platform);
          _expectTransparentCommand(tester);
          await _captureFrame(tester, 'palette-$name');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(DCommand<String>), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());

          SharedPreferences.setMockInitialValues({});
          final shell = await startChattingShell(
            StartChattingApi(),
            maximumMembers: 3,
          );
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: _capture,
                child: StartChattingFixture(shell: shell, platform: platform),
              ),
            );
            if (dark) {
              await tester.tap(find.text('Dark appearance'));
              await tester.pumpAndSettle();
            }
            await tester.tap(find.byKey(const ValueKey('open-start-chatting')));
            await tester.pumpAndSettle();
            _expectPresentation(tester, platform);
            _expectTransparentCommand(tester);

            await _captureFrame(tester, 'chat-$name');
            await tester.enterText(
              find.byKey(const ValueKey('chat-new-direct-message-search')),
              'maya',
            );
            await tester.pump(const Duration(milliseconds: 350));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('chat-new-direct-message-user-maya')),
              findsOneWidget,
            );
            await _captureFrame(tester, 'chat-search-$name');
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            shell.dispose();
            await shell.pluginTeardown;
          }
        });
      }
    }
  }
}

void _expectPresentation(WidgetTester tester, TargetPlatform platform) {
  if (platform == TargetPlatform.iOS) {
    expect(find.byKey(const ValueKey('sheet-drag-handle')), findsOneWidget);
    expect(find.byType(DDialogContent), findsNothing);
  } else {
    expect(find.byType(DSheetContent), findsNothing);
    final bounds = tester.getRect(find.byType(DDialogContent));
    final viewport = tester.getSize(find.byType(Navigator).first);
    expect(bounds.center.dx, closeTo(viewport.width / 2, 1));
    final media = MediaQueryData.fromView(tester.view);
    expect(
      bounds.center.dy,
      closeTo(
        (viewport.height +
                media.padding.top -
                media.padding.bottom +
                media.viewInsets.top -
                media.viewInsets.bottom) /
            2,
        1,
      ),
    );
  }
}

void _expectTransparentCommand(WidgetTester tester) {
  final command = find.byType(DCommand<String>);
  final material = tester.widget<Material>(
    find.descendant(of: command, matching: find.byType(Material)).first,
  );
  expect(material.color, Colors.transparent);
  final scrollbar = tester.widget<DScrollBar>(
    find.descendant(of: command, matching: find.byType(DScrollBar)),
  );
  expect(scrollbar.backgroundColor, Colors.transparent);
}

Future<void> _captureFrame(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('COMMAND_CAPTURE')) return;
  await tester.runAsync(() async {
    final image = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
        .toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '${Directory.systemTemp.path}/command-presentation/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('COMMAND_CAPTURE ${file.path}');
    } finally {
      image.dispose();
    }
  });
}
