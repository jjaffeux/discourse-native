import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/message_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    WidgetBuilder builder, {
    double width = 640,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('every frozen example renders narrow, scaled, and RTL', (
    tester,
  ) async {
    for (final example in messageExamples.examples) {
      await tester.pumpWidget(
        host(
          example.builder,
          width: 280,
          scale: 2,
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('actions expose independent labels and update local state', (
    tester,
  ) async {
    final example = messageExamples.examples.singleWhere(
      (value) => value.title == 'Actions and delivery states',
    );
    await tester.pumpWidget(host(example.builder));

    for (final label in ['Copy', 'Like', 'Dislike', 'Retry']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    await tester.tap(find.bySemanticsLabel('Copy'));
    await tester.pump();
    expect(find.text('Message copied'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retry'));
    await tester.pump();
    expect(find.text('Delivered'), findsOneWidget);
  });

  testWidgets('attachment download is a real independently labeled action', (
    tester,
  ) async {
    final example = messageExamples.examples.singleWhere(
      (value) => value.title == 'Attachments',
    );
    await tester.pumpWidget(host(example.builder));

    expect(find.byType(DAttachment), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Download'));
    await tester.pump();
    expect(find.text('Download started'), findsOneWidget);
  });

  testWidgets('status controls preserve live status semantics', (tester) async {
    final example = messageExamples.examples.singleWhere(
      (value) => value.title == 'Accessibility and status updates',
    );
    await tester.pumpWidget(host(example.builder));

    var status = tester.getSemantics(find.byType(DMessageStatus).first);
    expect(status.label, 'Sending');
    expect(status.flagsCollection.isLiveRegion, isTrue);
    await tester.tap(find.text('failed'));
    await tester.pump();
    status = tester.getSemantics(find.byType(DMessageStatus).first);
    expect(status.label, 'Failed to send');
    expect(status.flagsCollection.isLiveRegion, isTrue);
  });
}
