import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/alert_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('action uses small Button and toggles local state', (
    tester,
  ) async {
    final example = alertExamples.examples.singleWhere(
      (item) => item.title == 'Action',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    expect(
      tester.widget<DButton>(find.byType(DButton)).size,
      DButtonSize.small,
    );
    await tester.tap(find.text('Enable'));
    await tester.pump();
    expect(find.text('Dark mode enabled'), findsOneWidget);
    await tester.tap(find.text('Disable'));
    await tester.pump();
    expect(find.text('Dark mode is now available'), findsOneWidget);
  });

  testWidgets('all actual examples fit narrow large-text RTL and dark themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      for (final example in alertExamples.examples) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('rich-content feedback uses the shared Toast scope', (
    tester,
  ) async {
    final example = alertExamples.examples.singleWhere(
      (item) => item.title == 'Rich content',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DToaster(
          child: Scaffold(body: Builder(builder: example.builder)),
        ),
      ),
    );

    await tester.tap(find.text('Copy example code'));
    await tester.pump();

    expect(find.text('Example code copied locally'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
