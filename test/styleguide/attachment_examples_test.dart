import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/attachment_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with one top-level kitchen-sink example', () {
    expect(attachmentExamples.omittedSections, contains('Features'));
    expect(
      attachmentExamples.examples.where((example) => example.topLevel),
      hasLength(1),
    );
    expect(attachmentExamples.examples.first.title, 'Overview');
    expect(attachmentExamples.examples.first.topLevel, isTrue);
  });

  testWidgets('all Attachment examples render at narrow 200 percent RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final example in attachmentExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 720),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Builder(builder: example.builder),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DAttachment), findsWidgets, reason: example.title);
      expect(tester.takeException(), isNull, reason: example.title);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('overview combines image, upload, file, and working actions', (
    tester,
  ) async {
    final overview = attachmentExamples.examples.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: overview.builder)),
      ),
    );
    await tester.pump();

    expect(find.byType(DAttachmentGroup), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DAttachmentMedia &&
            widget.variant == DAttachmentMediaVariant.image,
      ),
      findsNWidgets(3),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DAttachment && widget.state == DAttachmentState.uploading,
      ),
      findsOneWidget,
    );
    expect(find.text('sales-dashboard.pdf'), findsOneWidget);
    expect(find.text('message-renderer.tsx'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel('Cancel sales-dashboard.pdf upload'),
    );
    await tester.pump();
    expect(find.text('sales-dashboard.pdf'), findsNothing);
    expect(find.widgetWithText(DButton, 'Restore files'), findsOneWidget);

    await tester.tap(find.widgetWithText(DButton, 'Restore files'));
    await tester.pump();
    expect(find.text('sales-dashboard.pdf'), findsOneWidget);
  });

  testWidgets('image and trigger examples preserve independent interactions', (
    tester,
  ) async {
    final image = attachmentExamples.examples.singleWhere(
      (example) => example.title == 'Image',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: image.builder)),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Open workspace.png'));
    await tester.pump();
    expect(find.text('workspace.png opened'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove workspace.png'));
    await tester.pump();
    expect(find.text('workspace.png removed'), findsOneWidget);
    expect(find.bySemanticsLabel('Open workspace.png'), findsNothing);

    final trigger = attachmentExamples.examples.singleWhere(
      (example) => example.title == 'Trigger',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: trigger.builder)),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Copy link'));
    await tester.pump();
    expect(find.text('Link copied locally'), findsOneWidget);
    expect(find.byType(DDialogContent), findsNothing);
    await tester.tap(find.bySemanticsLabel('Preview research-summary.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(DDialogContent), findsOneWidget);
  });
}
