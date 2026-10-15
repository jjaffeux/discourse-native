import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone and desktop progress retain the selected material', (
    tester,
  ) async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final floating in [false, true]) {
        for (final dark in [false, true]) {
          for (final material in DAppearanceMaterial.values) {
            const capture = ValueKey('progress-button-capture');
            await tester.pumpWidget(
              MaterialApp(
                theme: DMaterialTheme.apply(
                  (dark ? AppTheme.dark : AppTheme.light).copyWith(
                    platform: floating
                        ? TargetPlatform.macOS
                        : TargetPlatform.iOS,
                    textTheme: (dark ? AppTheme.dark : AppTheme.light).textTheme
                        .apply(fontFamily: 'Lato'),
                  ),
                  material,
                ),
                home: Scaffold(
                  body: Center(
                    child: RepaintBoundary(
                      key: capture,
                      child: Builder(
                        builder: (context) => ColoredBox(
                          color: DTokens.of(context).background,
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: TopicProgressButton(
                              position: 1,
                              total: 16,
                              floating: floating,
                              onPressed: () {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final trigger = find.byKey(const ValueKey('topic-progress-button'));
            expect(tester.getSize(trigger).height, floating ? 26 : 30);
            final glass = find.descendant(
              of: trigger,
              matching: find.byType(DMaterialSurface),
            );
            if (material == DAppearanceMaterial.liquidGlass) {
              expect(glass, findsOneWidget);
              final surface = tester.widget<DMaterialSurface>(glass);
              expect(surface.preserveColor, isTrue);
              expect(surface.color.a, closeTo(dark ? .42 : .5, .001));
            } else {
              expect(glass, findsNothing);
            }
            final output =
                Platform.environment['TOPIC_PROGRESS_BUTTON_CAPTURE_DIR'];
            if (output != null) {
              await tester.runAsync(() async {
                final image = await tester
                    .renderObject<RenderRepaintBoundary>(find.byKey(capture))
                    .toImage(pixelRatio: 3);
                try {
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await Directory(output).create(recursive: true);
                  await File(
                    '$output/${floating ? 'desktop' : 'phone'}-${dark ? 'dark' : 'light'}-${material.name}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    } finally {
      debugDisableShadows = shadowsDisabled;
    }
  });

  testWidgets('one-post timeline disables its ends and stays bounded', (
    tester,
  ) async {
    var jumps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: TopicProgressPanel(
              position: 0,
              total: 0,
              onJump: (_) => jumps++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('1 / 1'), findsOneWidget);
    for (final label in ['First post', 'Latest post']) {
      expect(
        tester.widget<DButton>(find.widgetWithText(DButton, label)).onPressed,
        isNull,
      );
    }
    await tester.tap(find.byType(DMultiSlider));
    await tester.pumpAndSettle();
    expect(jumps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large progress counts remain complete on one line and clickable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        for (final scenario in [
          (
            position: 5150,
            total: 5188,
            width: 260.0,
            scale: 1.0,
            floating: false,
          ),
          (
            position: 5150,
            total: 5188,
            width: 110.0,
            scale: 1.0,
            floating: false,
          ),
          (
            position: 99999,
            total: 125000,
            width: 400.0,
            scale: 1.5,
            floating: false,
          ),
          (
            position: 99999,
            total: 125000,
            width: 96.0,
            scale: 1.5,
            floating: false,
          ),
          (
            position: 5150,
            total: 5188,
            width: 110.0,
            scale: 1.0,
            floating: true,
          ),
          (
            position: 99999,
            total: 125000,
            width: 96.0,
            scale: 1.5,
            floating: true,
          ),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scenario.scale),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: scenario.width),
                      child: TopicProgressButton(
                        position: scenario.position,
                        total: scenario.total,
                        floating: scenario.floating,
                        onPressed: () => presses++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final button = find.byKey(const ValueKey('topic-progress-button'));
          final bounds = tester.getRect(button);
          final label = '${scenario.position} / ${scenario.total}';
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          );
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          );
          expect(find.text(label), findsOneWidget);
          expect(boxes.map((box) => box.top).toSet(), hasLength(1));
          expect(paragraph.didExceedMaxLines, isFalse);
          for (final box in boxes) {
            expect(
              bounds
                  .inflate(.01)
                  .contains(paragraph.localToGlobal(Offset(box.left, box.top))),
              isTrue,
            );
            expect(
              bounds
                  .inflate(.01)
                  .contains(
                    paragraph.localToGlobal(Offset(box.right, box.bottom)),
                  ),
              isTrue,
            );
          }
          expect(bounds.width, lessThanOrEqualTo(scenario.width));
          final surface = find.descendant(
            of: button,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is AnimatedContainer &&
                  widget.decoration is DButtonDecoration,
            ),
          );
          expect(bounds, tester.getRect(surface));
          final control = tester.widget<DButton>(button);
          expect(control.variant, DButtonVariant.ghost);
          expect(
            control.density,
            scenario.floating
                ? DButtonDensity.floatingCall
                : DButtonDensity.topicProgress,
          );
          expect(control.icon, isNull);
          expect(
            find.bySemanticsLabel(
              RegExp(
                'Topic progress, post ${scenario.position} of ${scenario.total}',
              ),
            ),
            findsOneWidget,
          );
          final before = presses;
          await tester.tap(button);
          await tester.pump();
          expect(presses, before + 1);
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'progress trigger supports keyboard activation and popup semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: TopicProgressButton(
                position: 0,
                total: 0,
                expanded: true,
                onPressed: () => presses++,
              ),
            ),
          ),
        ),
      );
      final trigger = find.byKey(const ValueKey('topic-progress-button'));
      expect(find.text('1 / 1'), findsOneWidget);
      expect(
        tester
            .getSemantics(trigger)
            .getSemanticsData()
            .flagsCollection
            .isExpanded,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
