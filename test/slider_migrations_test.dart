import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/slider_review_main.dart';

void main() {
  testWidgets(
    'production topic position slider steps by posts and blocks reading shortcuts',
    (tester) async {
      var position = 30;
      late BuildContext scope;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                scope = context;
                return StatefulBuilder(
                  builder: (context, setState) => TopicPositionSlider(
                    position: position,
                    total: 100,
                    onChanged: (v) => setState(() => position = v),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DSlider));
      await tester.pump();
      final before = position;
      expect(navigationShortcutsAllowed(scope), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(position, before + 1);
    },
  );

  testWidgets(
    'offline production video and volume retain state, disable and remove cleanly',
    (tester) async {
      await tester.pumpWidget(const SliderReviewApp());
      await tester.pumpAndSettle();
      expect(find.byType(DSlider), findsNWidgets(3));
      final playback = find.byWidgetPredicate(
        (w) => w is DSlider && w.semanticLabel == 'Playback position',
      );
      await tester.ensureVisible(playback);
      await tester.tap(playback);
      await tester.pump();
      expect(tester.widget<DSlider>(playback).value, 60000);
      await tester.ensureVisible(find.text('Disable / enable'));
      await tester.tap(find.text('Disable / enable'));
      await tester.pump();
      expect(tester.widget<DSlider>(playback).onChanged, isNull);
      await tester.tap(find.text('Remove / restore'));
      await tester.pump();
      expect(find.byType(DSlider), findsNothing);
      await tester.tap(find.text('Remove / restore'));
      await tester.pump();
      expect(find.byType(DSlider), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
}
