import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/application_component_catalogue.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/notification_dot_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BoxDecoration decoration(WidgetTester tester, Finder dot) =>
    tester
            .widget<DecoratedBox>(
              find.descendant(of: dot, matching: find.byType(DecoratedBox)),
            )
            .decoration
        as BoxDecoration;

void main() {
  test('notification dot is registered as an application extension', () {
    expect(
      applicationComponentCatalogue.map((entry) => entry.id),
      contains('notification-dot'),
    );
    expect(
      componentExamples['notification-dot'],
      same(notificationDotExamples),
    );
    final progress =
        jsonDecode(
              File('docs/component-library/progress.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      (progress['applicationComponents'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['id']),
      contains('notification-dot'),
    );
  });
  testWidgets('inline and ringed dots keep an 8px center at large text sizes', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Directionality(
              textDirection: direction,
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DNotificationDot(key: ValueKey('inline')),
                    DNotificationDot.overlay(key: ValueKey('overlay')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final inline = find.byKey(const ValueKey('inline'));
      final overlay = find.byKey(const ValueKey('overlay'));
      expect(tester.getSize(inline), const Size.square(8));
      expect(tester.getSize(overlay), const Size.square(12));
      expect(decoration(tester, inline).border, isNull);
      expect(
        decoration(tester, overlay).border!.dimensions,
        const EdgeInsets.all(2),
      );
      expect(decoration(tester, overlay).shape, BoxShape.circle);
    }
  });

  testWidgets('default colors follow live themes and overrides stay explicit', (
    tester,
  ) async {
    for (final theme in [
      AppTheme.light,
      AppTheme.dark,
      ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple)),
    ]) {
      final tokens = theme.extension<DTokens>() ?? DTokens.fromTheme(theme);
      await tester.pumpWidget(
        Theme(
          data: theme,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DNotificationDot.overlay(key: ValueKey('themed')),
                  DNotificationDot.overlay(
                    key: ValueKey('custom'),
                    color: Colors.orange,
                    ringColor: Colors.black,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final themed = decoration(tester, find.byKey(const ValueKey('themed')));
      expect(themed.color, tokens.primary);
      expect((themed.border! as Border).top.color, tokens.background);
      final custom = decoration(tester, find.byKey(const ValueKey('custom')));
      expect(custom.color, Colors.orange);
      expect((custom.border! as Border).top.color, Colors.black);
    }
  });

  testWidgets(
    'an overlapping dot does not intercept its button or duplicate semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: Stack(
                children: [
                  DButton.iconOnly(
                    tooltip: 'Chat, unread messages',
                    icon: const Icon(Icons.chat),
                    onPressed: () => taps++,
                  ),
                  const PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: DNotificationDot.overlay(),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.tapAt(tester.getCenter(find.byType(DNotificationDot)));
        await tester.pump();
        expect(taps, 1);
        expect(find.bySemanticsLabel('Chat, unread messages'), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(DButton)).label,
          'Chat, unread messages',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('a standalone dot announces its state without an action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: DNotificationDot(semanticLabel: 'Unread messages'),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(DNotificationDot)),
        isSemantics(label: 'Unread messages'),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('styleguide header clears and restores unread activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(builder: notificationDotExamples.examples[1].builder),
        ),
      ),
    );
    expect(find.byType(DNotificationDot), findsOneWidget);
    await tester.tap(find.byTooltip('Chat, unread messages'));
    await tester.pumpAndSettle();
    expect(find.byType(DNotificationDot), findsNothing);
    await tester.tap(find.text('Restore unread'));
    await tester.pumpAndSettle();
    expect(find.byType(DNotificationDot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
