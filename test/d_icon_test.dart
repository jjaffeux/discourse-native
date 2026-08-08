import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';

void main() {
  group('DIcon', () {
    testWidgets('every generated icon renders', (tester) async {
      // The generator lifts symbols out of a sprite by hand. A malformed one
      // fails at parse time, inside a future, where nothing else would notice.
      for (final icon in DIcons.byName.values.toSet()) {
        await tester.pumpWidget(
          MaterialApp(home: Center(child: DIcon(icon, size: 24))),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${icon.name} did not render',
        );
        expect(find.dIcon(icon), findsOneWidget);
      }
    });

    testWidgets('sizes to the box it is given, not the viewBox', (
      tester,
    ) async {
      // `hand-point-right` is 448x512, so a widget that passed the viewBox
      // through would not be square.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: DIcon(DIcons.handPointRight, size: 32)),
        ),
      );

      expect(
        tester.getSize(find.dIcon(DIcons.handPointRight)),
        const Size(32, 32),
      );
    });

    testWidgets('takes its size and color from the ambient IconTheme', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IconTheme(
            data: IconThemeData(size: 18, color: Color(0xFF00FF00)),
            child: Center(child: DIcon(DIcons.gear)),
          ),
        ),
      );

      expect(tester.getSize(find.dIcon(DIcons.gear)), const Size(18, 18));
    });

    test('aliases resolve to the icon Discourse maps them to', () {
      expect(DIcons.byName['d-liked'], DIcons.heart);
      expect(DIcons.byName['d-unliked'], DIcons.farHeart);
      expect(DIcons.byName['topic.closed'], DIcons.lock);
      expect(DIcons.byName['notification.mentioned'], DIcons.at);
    });
  });
}
