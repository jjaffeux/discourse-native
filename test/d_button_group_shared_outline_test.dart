import 'dart:ui' show ImageByteFormat;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'shared outline has no internal borders or separator hit routing on $platform $direction',
        (tester) async {
          final boundary = GlobalKey();
          final selected = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: Scaffold(
                body: Center(
                  child: Directionality(
                    textDirection: direction,
                    child: RepaintBoundary(
                      key: boundary,
                      child: DButtonGroup(
                        sharedOutline: true,
                        children: [
                          DButton(
                            size: DButtonSize.filter,
                            variant: DButtonVariant.outline,
                            label: const Text('Support'),
                            onPressed: () => selected.add('Support'),
                          ),
                          const DButtonGroupText(
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            child: DBreadcrumbSeparator(),
                          ),
                          DButton(
                            size: DButtonSize.filter,
                            variant: DButtonVariant.outline,
                            label: const Text('Bugs'),
                            onPressed: () => selected.add('Bugs'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final group = tester.getRect(find.byType(DButtonGroup));
          final divider = tester.getRect(find.byType(DButtonGroupText));
          final buttons = find.byType(DButton);
          for (final button in buttons.evaluate()) {
            final finder = find.byWidget(button.widget);
            expect(
              buttonSurface(tester, of: finder).borderColor,
              Colors.transparent,
            );
            expect(
              tester.getRect(
                find.descendant(
                  of: finder,
                  matching: find.byType(FilledButton),
                ),
              ),
              tester.getRect(finder),
            );
          }
          final theme = DTokens.of(
            tester.element(find.byType(DButtonGroup)),
          ).buttonTheme;
          final origin = tester.getTopLeft(find.byKey(boundary));
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = (await image.toByteData(
              format: ImageByteFormat.rawRgba,
            ))!;
            Color pixel(Offset position) {
              final point = (position - origin) * 2;
              final offset =
                  (point.dy.floor() * image.width + point.dx.floor()) * 4;
              return Color.fromARGB(
                bytes.getUint8(offset + 3),
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2),
              );
            }

            // Both joins are uninterrupted fill; the frame continues over the separator.
            for (final x in [
              divider.left - 1,
              divider.left + 1,
              divider.right - 1,
              divider.right + 1,
            ]) {
              expect(
                pixel(Offset(x, group.top + 5)).toARGB32(),
                theme.outline.background.toARGB32(),
              );
            }
            expect(
              pixel(Offset(divider.center.dx, group.top + .25)).toARGB32(),
              theme.outline.border.toARGB32(),
            );
            image.dispose();
          });
          await tester.tapAt(divider.center);
          await tester.pump();
          expect(selected, isEmpty);
          await tester.tap(buttons.first);
          await tester.tap(buttons.last);
          await tester.pumpAndSettle();
          expect(selected, ['Support', 'Bugs']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'shared outline retains keyboard focus and does not affect overlay buttons',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: DButtonGroup(
                sharedOutline: true,
                children: [
                  DButton(
                    autofocus: true,
                    variant: DButtonVariant.outline,
                    label: const Text('Support'),
                    onPressed: () => activations++,
                  ),
                  DPopover(
                    content: DPopoverContent(
                      child: DButton(
                        key: const ValueKey('overlay-action'),
                        variant: DButtonVariant.outline,
                        label: const Text('Overlay'),
                        onPressed: () {},
                      ),
                    ),
                    child: DPopoverTrigger(
                      builder: (context, trigger) => DButton(
                        variant: DButtonVariant.outline,
                        label: const Text('Bugs'),
                        focusNode: trigger.focusNode,
                        onPressed: trigger.toggle,
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
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(
        buttonSurface(tester, of: find.byType(DButton).first).ringWidth,
        greaterThan(0),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('overlay-action')), findsOneWidget);
      expect(
        buttonSurface(
          tester,
          of: find.byKey(const ValueKey('overlay-action')),
        ).borderColor.a,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
