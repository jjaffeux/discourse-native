import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'content-sized rows include their trailing controls immediately',
    (tester) async {
      for (final count in ['1234', '123456', '1']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: IntrinsicWidth(
                  child: DSidebarMenuItem(
                    badge: DSidebarMenuBadge(child: Text(count)),
                    action: DSidebarMenuAction(
                      semanticLabel: 'Project actions',
                      onPressed: () {},
                      child: const Icon(Icons.more_horiz),
                    ),
                    child: DSidebarMenuButton(
                      onPressed: () {},
                      child: const Text('Projects'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final label = tester.renderObject<RenderParagraph>(
          find.text('Projects'),
        );
        expect(
          label.size.width,
          closeTo(label.getMaxIntrinsicWidth(100), .001),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('intrinsic height includes wrapping after trailing reservation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                child: IntrinsicHeight(
                  child: DSidebarMenuItem(
                    badge: const DSidebarMenuBadge(child: Text('1234')),
                    child: DSidebarMenuButton(
                      onPressed: () {},
                      child: const Text('Project navigation'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final label = tester.renderObject<RenderParagraph>(
      find.text('Project navigation'),
    );
    expect(
      label.size.height,
      closeTo(label.getMaxIntrinsicHeight(label.size.width), .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dry layout predicts resized rows with wrapping badges', (
    tester,
  ) async {
    Future<void> show(double width) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: UnconstrainedBox(
              constrainedAxis: Axis.horizontal,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: DSidebarMenuItem(
                  badge: const DSidebarMenuBadge(
                    child: Wrap(children: [Text('Live'), Text('1234')]),
                  ),
                  child: DSidebarMenuButton(
                    onPressed: () {},
                    child: const Text('Project navigation'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await show(300);
    for (final width in [180.0, 260.0, 200.0]) {
      final row = tester.renderObject<RenderBox>(find.byType(DSidebarMenuItem));
      final expected = row.getDryLayout(BoxConstraints.tightFor(width: width));
      await show(width);
      expect(tester.getSize(find.byType(DSidebarMenuItem)), expected);
      expect(tester.takeException(), isNull);
    }
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'submenu labels do not inherit parent badge width in $direction',
      (tester) async {
        var count = '1';
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: Directionality(
                textDirection: direction,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 260,
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        return DSidebarMenuItem(
                          badge: DSidebarMenuBadge(child: Text(count)),
                          submenu: DSidebarMenuSub(
                            children: [
                              DSidebarMenuSubButton(
                                onPressed: () {},
                                child: const Text(
                                  'A long nested destination label',
                                ),
                              ),
                            ],
                          ),
                          child: DSidebarMenuButton(
                            onPressed: () {},
                            child: const Text('Projects'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final before = tester.getRect(
          find.text('A long nested destination label'),
        );
        update(() => count = '123456');
        await tester.pump();
        expect(
          tester.getRect(find.text('A long nested destination label')),
          before,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final submenu in [false, true]) {
    testWidgets('lazy row focus follows its stable key (submenu=$submenu)', (
      tester,
    ) async {
      var values = ['first', 'second', 'third'];
      String? selected;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                Widget row(BuildContext context, int index) {
                  final value = values[index];
                  return DSidebarMenuButton(
                    key: ValueKey(value),
                    onPressed: () => selected = value,
                    child: Text(value),
                  );
                }

                int? findIndex(Key key) {
                  final index = values.indexOf((key as ValueKey<String>).value);
                  return index < 0 ? null : index;
                }

                return DSidebarContent.slivers(
                  slivers: [
                    if (submenu)
                      DSidebarMenuSub.sliverBuilder(
                        itemCount: values.length,
                        itemExtent: 32,
                        itemBuilder: row,
                        findChildIndexCallback: findIndex,
                      )
                    else
                      DSidebarMenu.sliverBuilder(
                        itemCount: values.length,
                        itemExtent: 32,
                        itemBuilder: row,
                        findChildIndexCallback: findIndex,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final focused = tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: find.byKey(const ValueKey('first')),
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      focused.requestFocus();
      await tester.pump();
      update(() => values = ['third', 'second', 'first']);
      await tester.pump();
      expect(focused.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, 'first');
      expect(tester.takeException(), isNull);
    });
  }
}
