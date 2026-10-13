import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget fixture({
  double width = 390,
  bool collapsed = false,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  ValueChanged<int>? onOverflow,
  VoidCallback? onReveal,
  bool hidden = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: DMobileDock(
                collapsed: collapsed,
                destinationsHidden: hidden,
                onOverflowChanged: onOverflow ?? (_) {},
                destinations: [
                  for (final name in [
                    'Start',
                    'Topics',
                    'Chat',
                    'Inbox',
                    'Users',
                    'A very long destination',
                  ])
                    DMobileDockItem(
                      key: ValueKey(name),
                      icon: const Icon(Icons.forum),
                      label: name,
                      badge: name == 'Chat'
                          ? const DBadge.overlay(child: Text('99+'))
                          : null,
                      selected: name == 'Topics',
                      onPressed: () {},
                    ),
                ],
                more: DMobileDockItem(
                  key: const ValueKey('more'),
                  bare: true,
                  icon: const Icon(Icons.more_vert),
                  label: 'More',
                  onPressed: () {},
                ),
                collapsedDestination: DMobileDockItem(
                  key: const ValueKey('reveal'),
                  collapsed: true,
                  icon: const Icon(Icons.forum),
                  label: 'Reveal navigation',
                  onPressed: onReveal ?? () {},
                ),
                action: DMobileDockAction(
                  icon: const Icon(Icons.add),
                  label: 'New topic',
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

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'measures labels and badges, keeps overflow and action visible ($direction)',
      (tester) async {
        var shown = 0;
        await tester.pumpWidget(
          fixture(direction: direction, onOverflow: (n) => shown = n),
        );
        await tester.pumpAndSettle();
        expect(shown, 3);
        final surface = tester.getRect(
          find.byKey(const ValueKey('mobile-dock-surface')),
        );
        for (final key in ['Start', 'Topics', 'Chat', 'more']) {
          final item = find.byKey(ValueKey(key));
          expect(item.hitTestable(), findsOneWidget);
          final rect = tester.getRect(item);
          expect(rect.left, greaterThanOrEqualTo(surface.left));
          expect(rect.right, lessThanOrEqualTo(surface.right));
        }
        expect(find.byKey(const ValueKey('Inbox')).hitTestable(), findsNothing);
        expect(find.text('More'), findsNothing);
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('more')))
              .getSemanticsData()
              .label,
          'More',
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('folded dock retains only a bounded reveal target', (
    tester,
  ) async {
    var revealed = 0;
    await tester.pumpWidget(fixture());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      fixture(collapsed: true, onReveal: () => revealed++),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-dock-surface'))),
      const Size(48, 48),
    );
    expect(find.byKey(const ValueKey('Start')).hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('reveal')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reveal')));
    expect(revealed, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'large text spills destinations without clipping action or More',
    (tester) async {
      for (final width in [320.0, 430.0, 700.0]) {
        await tester.pumpWidget(fixture(width: width, scale: 2));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('more')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(DMobileDockAction).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
