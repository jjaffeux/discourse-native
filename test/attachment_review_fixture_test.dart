import 'package:discourse_native/attachment_review_main.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('source review fixture mounts and drives production adapters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AttachmentReviewApp());
    await tester.pump();
    expect(find.byType(ComposerUploadQueue), findsOneWidget);
    expect(find.byType(ChatUploads), findsOneWidget);
    expect(find.byType(DAttachment), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(ComposerUploadQueue),
        matching: find.text('Uploading · 64%'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Fail upload'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fail upload'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ComposerUploadQueue),
        matching: find.text('Upload failed. Try again.'),
      ),
      findsOneWidget,
    );
    final retry = find.descendant(
      of: find.byType(ComposerUploadQueue),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DAttachmentAction && widget.tooltip == 'Retry upload',
      ),
    );
    expect(retry, findsOneWidget);
    tester.widget<DAttachmentAction>(retry).onPressed!();
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ComposerUploadQueue),
        matching: find.text('Retrying · 0%'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Use dark theme'));
    await tester.tap(find.byTooltip('Use right-to-left'));
    await tester.tap(find.byTooltip('Use 200% text'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
