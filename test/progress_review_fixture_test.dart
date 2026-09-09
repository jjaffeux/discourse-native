import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/progress_review_main.dart';

void main() {
  testWidgets(
    'offline production fixture updates actual upload and download surfaces',
    (tester) async {
      await tester.pumpWidget(const ProgressReviewApp());
      await tester.pump();
      expect(find.byType(ComposerUploadQueue), findsOneWidget);
      final upload = find.descendant(
        of: find.byType(ComposerUploadQueue),
        matching: find.byType(DProgress),
      );
      expect(tester.widget<DProgress>(upload).value, .25);
      await tester.tap(find.text('Advance local upload'));
      await tester.pump();
      expect(tester.widget<DProgress>(upload).value, .75);
      expect(
        tester
            .widget<UpdateDownloadProgress>(find.byType(UpdateDownloadProgress))
            .progress,
        .25,
      );
      await tester.tap(find.text('Sample percentage'));
      await tester.pump();
      expect(
        tester
            .widget<UpdateDownloadProgress>(find.byType(UpdateDownloadProgress))
            .progress,
        .5,
      );
      await tester.tap(find.text('Motion'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
