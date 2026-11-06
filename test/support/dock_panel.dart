import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grows a phone's bar into its panel of places as a person does: a pull up
/// on the bar's first place, let go as a flick, and settled open before it
/// returns. A phone's bar has no ⋮; this is the one way in, besides pressing
/// the page added to the bar. A bar that cannot grow, with nothing past its
/// columns or something over it, is pulled all the same and found still a
/// bar when [settlesOpen] is false.
Future<void> openDockPanel(
  WidgetTester tester, {
  bool settlesOpen = true,
}) async {
  final place = find
      .descendant(
        of: find.byKey(const ValueKey('mobile-dock-surface')),
        matching: find.byType(DMobileDockItem),
      )
      .first;
  final gesture = await tester.createGesture();
  await gesture.down(tester.getCenter(place), timeStamp: Duration.zero);
  await tester.pump();
  for (var step = 1; step <= 6; step++) {
    await gesture.moveBy(
      const Offset(0, -12),
      timeStamp: Duration(milliseconds: 16 * step),
    );
    await tester.pump();
  }
  await gesture.up(timeStamp: const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  expect(
    find.byKey(DMobileDock.panelKey),
    settlesOpen ? findsOneWidget : findsNothing,
  );
}

/// The panel's tile for the place called [label].
Finder dockPanelTile(String label) => find.descendant(
  of: find.byKey(DMobileDock.panelKey),
  matching: find.widgetWithText(DMobileDockItem, label),
);
