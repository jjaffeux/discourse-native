import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/message_native_review_main.dart' as review;

void main() {
  testWidgets('review fixture renders outgoing and incoming DM compositions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await review.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show DMs'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMessageTile), findsNWidgets(9));
    final rows = tester.widgetList<DMessage>(find.byType(DMessage));
    expect(rows.where((row) => row.align == DMessageAlign.end), hasLength(7));
    expect(rows.where((row) => row.align == DMessageAlign.start), hasLength(2));
    expect(find.byType(DMessageAvatar), findsNWidgets(9));
    expect(find.byType(DMessageHeader), findsNWidgets(2));
    await tester.tap(find.text('Use 1:1 DM'));
    await tester.pumpAndSettle();
    expect(find.byType(DMessageAvatar), findsNothing);
    expect(find.byType(DMessageHeader), findsNothing);
    expect(find.text('dm-notes.pdf'), findsOneWidget);
    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('Failed to send: Offline during review'), findsOneWidget);
    for (final label in [
      'Light / dark',
      'Plum palette',
      '360px',
      '200% text',
      'RTL',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('review fixture navigates and drives actual message callbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await review.main();
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Scroll preview down'));
    await tester.pump();
    expect(scrollable.position.pixels, 500);
    await tester.tap(find.byTooltip('Scroll preview up'));
    await tester.pump();
    expect(scrollable.position.pixels, 0);

    await tester.tap(find.text('Show production'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMessageTile), findsNWidgets(4));
    expect(find.byType(DMessage), findsNWidgets(4));
    expect(find.text('message-review.pdf'), findsOneWidget);
    await tester.tap(find.byKey(ChatMessageTile.threadPreviewKey(33)));
    await tester.pump();
    expect(find.text('Opened thread 33'), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel(
        'Jump to message from @olivia: The production tile keeps CookedHtml…',
      ),
    );
    await tester.pump();
    expect(find.text('Jumped to message 101'), findsOneWidget);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(find.byType(ChatMessageTile).first));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reply'));
    await tester.pump();
    expect(find.text('Reply requested for message 101'), findsOneWidget);
    await pointer.removePointer();

    for (final label in [
      'Light / dark',
      'Plum palette',
      '360px',
      '200% text',
      'RTL',
      'Reduced motion',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
