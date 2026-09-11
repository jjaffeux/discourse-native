import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    for (final component in ['Item', 'Command', 'NavigationMenuLink']) {
      final command = component == 'Command';
      testWidgets(
        '$component transfers highlight atomically in ${theme.brightness}',
        (tester) async {
          final strategy = FocusManager.instance.highlightStrategy;
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
          final activated = <String>[];
          final controller = DCommandController<String>(initialValue: 'First');
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: command
                        ? DCommand<String>(
                            controller: controller,
                            onSelected: activated.add,
                            child: const DCommandList<String>(
                              children: [
                                DCommandItem(
                                  value: 'First',
                                  child: Text('First'),
                                ),
                                DCommandItem(
                                  value: 'Second',
                                  child: Text('Second'),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final label in ['First', 'Second'])
                                if (component == 'NavigationMenuLink')
                                  DNavigationMenuLink(
                                    onPressed: () {},
                                    triggerStyle: false,
                                    child: Text(label),
                                  )
                                else
                                  DItem(
                                    onPressed: () {},
                                    children: [
                                      DItemContent(children: [Text(label)]),
                                    ],
                                  ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (component == 'NavigationMenuLink') {
            Focus.of(tester.element(find.text('First'))).requestFocus();
            await tester.pump();
          }
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          Color? paintedColor(String label) =>
              (tester
                          .widget<DecoratedBox>(
                            find
                                .ancestor(
                                  of: find.text(label),
                                  matching: find.byWidgetPredicate(
                                    (widget) =>
                                        widget is DecoratedBox &&
                                        widget.decoration is BoxDecoration &&
                                        (widget.decoration as BoxDecoration)
                                                .color !=
                                            null,
                                  ),
                                )
                                .first,
                          )
                          .decoration
                      as BoxDecoration)
                  .color;

          for (final label in ['First', 'Second', 'First']) {
            await mouse.moveTo(tester.getCenter(find.text(label)));
            await tester.pump();
            for (final elapsed in [
              Duration.zero,
              const Duration(milliseconds: 16),
              const Duration(milliseconds: 50),
            ]) {
              await tester.pump(elapsed);
              expect(paintedColor(label), isNot(Colors.transparent));
              expect(
                paintedColor(label == 'First' ? 'Second' : 'First'),
                Colors.transparent,
              );
            }
          }
          if (command) {
            Focus.of(tester.element(find.text('First'))).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            expect(paintedColor('First'), Colors.transparent);
            expect(paintedColor('Second'), isNot(Colors.transparent));
            for (final key in [
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.enter,
            ]) {
              await tester.sendKeyEvent(key);
              await tester.pump();
            }
            expect(activated, ['Second', 'Second']);
          }
        },
      );
    }
  }
}
