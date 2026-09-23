import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_events_review_main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final family in [
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
  });
  testWidgets('return from an empty month to a populated schedule', (
    tester,
  ) async {
    Future<void> settle() =>
        tester.pumpAndSettle(const Duration(milliseconds: 16));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MobileEventsReviewApp(controls: false, width: 320),
    );
    await settle();
    await tester.tap(find.byType(DSelect<EventCalendarView>));
    await settle();
    await tester.tap(find.text('Schedule'));
    await settle();
    await tester.tap(find.byTooltip('Next month'));
    await settle();
    await tester.tap(find.text('Today').hitTestable().first);
    await settle();
    expect(tester.takeException(), isNull);
    expect(find.text('Support escalations').hitTestable(), findsOneWidget);
  });
  testWidgets('render mobile event page variants', (tester) async {
    final output = Directory('/tmp/mobile-events-review')
      ..createSync(recursive: true);
    for (final dark in [true, false]) {
      for (final view in [
        EventCalendarView.month,
        EventCalendarView.schedule,
      ]) {
        for (final width in [390.0, 320.0]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          final name =
              '${dark ? 'dark' : 'light'}-${view.name}-${width.round()}';
          await tester.pumpWidget(
            MobileEventsReviewApp(
              key: ValueKey(name),
              initialView: view,
              dark: dark,
              controls: false,
              width: width,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          await tester.runAsync(() async {
            final layer =
                tester.binding.renderViews.single.debugLayer! as OffsetLayer;
            final image = await layer.toImage(
              Offset.zero & tester.view.physicalSize,
              pixelRatio: 2,
            );
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '${output.path}/$name.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    tester.view.reset();
  });
  testWidgets('render event loading skeletons', (tester) async {
    final output = Directory('/tmp/mobile-events-review')
      ..createSync(recursive: true);
    for (final dark in [true, false]) {
      for (final view in [
        EventCalendarView.month,
        EventCalendarView.schedule,
      ]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 844);
          final name = '${dark ? 'dark' : 'light'}-${view.name}-loading-$scale';
          await tester.pumpWidget(
            MobileEventsReviewApp(
              key: ValueKey(name),
              initialView: view,
              dark: dark,
              controls: false,
              width: 320,
              scale: scale,
              loading: true,
            ),
          );
          await tester.pump(const Duration(milliseconds: 32));
          expect(find.bySemanticsLabel('Loading events'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: name);
          await tester.runAsync(() async {
            final layer =
                tester.binding.renderViews.single.debugLayer! as OffsetLayer;
            final image = await layer.toImage(
              Offset.zero & tester.view.physicalSize,
              pixelRatio: 2,
            );
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '${output.path}/$name.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    tester.view.reset();
  });
}
