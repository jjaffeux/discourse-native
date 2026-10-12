import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide sidebar badges reserve their actual width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: DSidebarMenuItem(
                  badge: const DSidebarMenuBadge(child: Text('1234')),
                  action: DSidebarMenuAction(
                    semanticLabel: 'Channel actions',
                    onPressed: () {},
                    child: const Icon(Icons.more_horiz),
                  ),
                  child: DSidebarMenuButton(
                    onPressed: () {},
                    child: const Text('A long channel name'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final label = tester.getRect(find.text('A long channel name'));
    final badge = tester.getRect(find.byType(DSidebarMenuBadge));
    expect(label.right, lessThanOrEqualTo(badge.left));
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('changing counts keep actions independent in $direction', (
      tester,
    ) async {
      var count = '1';
      var navigations = 0;
      var actions = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: direction,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 200,
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        return DSidebarMenuItem(
                          badge: DSidebarMenuBadge(child: Text(count)),
                          action: DSidebarMenuAction(
                            semanticLabel: 'Actions',

                            onPressed: () => actions++,
                            child: const Icon(Icons.more_horiz),
                          ),
                          child: DSidebarMenuButton(
                            icon: const Icon(Icons.tag),
                            onPressed: () => navigations++,
                            child: const Text('Long channel name'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final initial = tester.getRect(find.text('Long channel name'));
      update(() => count = '1234');
      await tester.pump();
      final label = tester.getRect(find.text('Long channel name'));
      final badge = tester.getRect(find.byType(DSidebarMenuBadge));
      final action = tester.getRect(find.byType(DSidebarMenuAction));
      expect(label.width, lessThan(initial.width));
      expect(label.width, greaterThanOrEqualTo(28));
      if (direction == TextDirection.ltr) {
        expect(label.right + 4, lessThanOrEqualTo(badge.left));
        expect(badge.right, lessThanOrEqualTo(action.left));
      } else {
        expect(label.left - 4, greaterThanOrEqualTo(badge.right));
        expect(badge.left, greaterThanOrEqualTo(action.right));
      }
      expect(badge.center.dy, closeTo(action.center.dy, .001));
      expect(action.height, 20);
      await tester.tap(find.byType(DSidebarMenuAction));
      await tester.pump();
      expect(actions, 1);
      expect(navigations, 0);
      await tester.tap(find.text('Long channel name'));
      await tester.pump();
      expect(navigations, 1);
      expect(actions, 1);
      update(() => count = '1');
      await tester.pump();
      expect(tester.getRect(find.text('Long channel name')), initial);
      expect(tester.takeException(), isNull);
    });
  }
}
