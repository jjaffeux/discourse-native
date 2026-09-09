import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_select_render_test.dart' as render;
import 'native_select_review.dart' as review;

void main() {
  testWidgets('capture real migrated fixtures with loaded system font', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.discourse.native/window'),
      (_) async => null,
    );
    debugDisableShadows = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.runAsync(render.loadReviewFonts);
    for (final scenario in ['light', 'dark']) {
      await review.startNativeSelectReview(
        wrap: (app) => RepaintBoundary(key: render.boundaryKey, child: app),
      );
      await tester.pumpAndSettle();
      if (scenario == 'dark') {
        await tester.tap(find.text('Dark theme'));
        await tester.pumpAndSettle();
      }
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
          await tester.runAsync(
            () => render.capture(tester, 'fixture-$scenario-chat-move-dialog'),
          );
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pumpAndSettle();
        }
        if (label == 'Voice devices, roles and quality') {
          await tester.tap(find.text('Join room'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Media settings'));
          await tester.pumpAndSettle();
        }
        await tester.runAsync(
          () => render.capture(
            tester,
            'fixture-$scenario-${label.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}',
          ),
        );
        if (label != 'Voice devices, roles and quality' &&
            label != 'Chat move messages') {
          expect(
            find.byWidgetPredicate((widget) => widget is DNativeSelect),
            findsWidgets,
            reason: label,
          );
        }
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  }, skip: render.evidence.isEmpty);
}
