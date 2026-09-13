import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/select_consumers_review.dart' as review;

void main() {
  testWidgets(
    'the native launcher mounts migrated production fixtures with local data',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await review.main();
      await tester.pumpAndSettle();
      for (final label in [
        'Actual status editor',
        'Preferences',
        'Group management',
        'Bookmark editor',
        'Invites',
        'Poll composer',
        'Local Dates composer',
        'Event composer',
        'Assignment editor',
        'Assigned topics',
        'Chat browse',
        'Chat notifications',
        'Chat move messages',
        'Voice devices, roles and quality',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        if (label == 'Chat move messages') {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(
            tester.getCenter(find.byKey(const ValueKey('chat-message-1'))),
          );
          await tester.pump();
          await tester.tap(find.byTooltip('More message actions'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(MenuItemButton, 'Select'));
          await tester.pumpAndSettle();
          await mouse.removePointer();
          await tester.tap(find.byKey(const ValueKey('chat-move-selection')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('chat-move-destination')),
            findsOneWidget,
          );
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pumpAndSettle();
        }
        if (label == 'Assignment editor') {
          expect(find.byKey(const Key('assignment-status')), findsOneWidget);
          await tester.tap(find.text('Waiting'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<DRadioGroup<String>>(
                  find.byKey(const Key('assignment-status')),
                )
                .groupValue,
            'Waiting',
          );
        }
        if (label != 'Assignment editor' &&
            label != 'Voice devices, roles and quality' &&
            label != 'Chat move messages') {
          expect(
            find.byWidgetPredicate((widget) => widget is DSelect),
            findsWidgets,
            reason: label,
          );
        }
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
