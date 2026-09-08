import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_catalogue.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the styleguide accounts for every frozen catalogue entry', () {
    final snapshot =
        jsonDecode(
              File('docs/component-library/catalogue.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final components = (snapshot['components'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(componentReferenceDate, snapshot['referenceDate']);
    expect(
      componentCatalogue.map((entry) => [entry.id, entry.url, entry.sections]),
      components.map(
        (entry) => [
          entry['id'],
          entry['referenceUrl'],
          entry['documentedSections'],
        ],
      ),
    );
    final progress =
        jsonDecode(
              File('docs/component-library/progress.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final scheduled = (progress['components'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .toList();
    expect(
      scheduled.map((entry) => entry['id']),
      unorderedEquals(components.map((entry) => entry['id'])),
    );
    final available = <String>{};
    for (final entry in scheduled) {
      expect(
        available.containsAll(
          (entry['dependencies'] as List<dynamic>).cast<String>(),
        ),
        isTrue,
        reason: '${entry['id']} must follow its dependencies',
      );
      available.add(entry['id'] as String);
    }
  });

  testWidgets('search finds documented capabilities and reports no matches', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'snap points',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('styleguide-component-drawer')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('styleguide-component-drawer')));
    await tester.pump();
    expect(
      find.textContaining(
        'Its implementation and interactive examples are scheduled.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'no such component',
    );
    await tester.pump();
    expect(find.text('No components match your search.'), findsOneWidget);
  });

  testWidgets(
    'theme and viewport previews preserve example state and reset clears it',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(DButton, 'primary'));
      await tester.pump();
      expect(find.text('Actions: 1'), findsOneWidget);

      await _choose(tester, 'Theme', 'Plum site');
      final preview = find.byKey(const ValueKey('styleguide-preview'));
      expect(Theme.of(tester.element(preview)).brightness, Brightness.dark);
      expect(DTokens.of(tester.element(preview)).radius, 12);
      expect(find.text('Actions: 1'), findsOneWidget);

      await _choose(tester, 'Viewport width', '360 px');
      expect(tester.getSize(preview).width, 360);
      await _choose(tester, 'Text scale', '200%');
      expect(MediaQuery.textScalerOf(tester.element(preview)).scale(14), 28);
      await tester.tap(find.text('Right to left'));
      await tester.tap(find.text('Reduce motion'));
      await tester.pump();
      expect(Directionality.of(tester.element(preview)), TextDirection.rtl);
      expect(MediaQuery.disableAnimationsOf(tester.element(preview)), isTrue);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Reset example'));
      await tester.tap(find.text('Reset example'));
      await tester.pumpAndSettle();
      expect(find.text('Actions: 0'), findsOneWidget);
    },
  );

  for (final size in [const Size(320, 640), const Size(1200, 800)]) {
    testWidgets(
      'search and navigation fit ${size.width}px at 200% system text',
      (tester) async {
        await _pump(tester, size: size, scale: 2);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('styleguide-search')),
          'tooltip',
        );
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('styleguide-component-tooltip')),
          100,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('styleguide-component-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('styleguide-component-tooltip')),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('styleguide-close')), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Escape invokes the styleguide close action from keyboard focus',
    (tester) async {
      var closed = false;
      await _pump(tester, onClose: () => closed = true);
      await tester.tap(find.byKey(const ValueKey('styleguide-search')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, isTrue);
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 900),
  double scale = 1,
  VoidCallback? onClose,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ComponentStyleguidePage(onClose: onClose),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label, String value) async {
  final choice = find.byKey(ValueKey('styleguide-$label'));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}
