import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/shell/badges_page.dart';
import 'package:discourse_native/src/shell/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/progress_review_main.dart';

void main() {
  testWidgets('offline fixture updates current production progress surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(const ProgressReviewApp());
    await tester.pump();
    expect(find.byType(DProgress), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byType(EventUnavailableCard),
        matching: find.byType(DProgress),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BadgesPage),
        matching: find.byType(DProgress),
      ),
      findsOneWidget,
    );
    final download = find.descendant(
      of: find.byType(UpdateDownloadProgress),
      matching: find.byType(DProgress),
    );
    expect(tester.widget<DProgress>(download).value, .25);
    expect(
      tester
          .widget<UpdateDownloadProgress>(find.byType(UpdateDownloadProgress))
          .progress,
      .25,
    );
    await tester.tap(find.text('Sample percentage'));
    await tester.pump();
    expect(tester.widget<DProgress>(download).value, .5);
    expect(
      tester
          .widget<UpdateDownloadProgress>(find.byType(UpdateDownloadProgress))
          .progress,
      .5,
    );
    await tester.tap(find.text('Loading / ready'));
    await tester.pump();
    expect(find.byType(DProgress), findsOneWidget);
    await tester.tap(find.text('Motion'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
