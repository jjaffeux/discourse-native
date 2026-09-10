import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/voice_review_fixture.dart';

void main() {
  testWidgets(
    'native review Voice fixture opens simulated devices without hardware',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: VoiceReviewFixture()),
        ),
      );
      await tester.tap(find.text('Join room'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Media settings'));
      await tester.pumpAndSettle();
      expect(find.byType(DSelect<String>), findsNWidgets(3));
      await tester.tap(find.byType(DSelect<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travel microphone').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
