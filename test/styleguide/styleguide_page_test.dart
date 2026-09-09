import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_catalogue.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'search accessibility is bounded to the field on desktop and mobile',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final width in [1200.0, 390.0]) {
          await _pump(tester, size: Size(width, 900));
          if (width < 900) {
            await tester.tap(
              find.byKey(const ValueKey('styleguide-navigation')),
            );
            await tester.pumpAndSettle();
          }
          final search = find.descendant(
            of: find.byKey(const ValueKey('styleguide-search')),
            matching: find.byType(TextField),
          );
          expect(tester.getSemantics(search).rect.size, tester.getSize(search));
          expect(tester.getSemantics(search).label, 'Search components...');
          expect(find.bySemanticsLabel('Foundations'), findsWidgets);
          await tester.enterText(search, 'Input');
          await tester.pumpAndSettle();
          final clear = find.bySemanticsLabel('Clear search');
          expect(clear, findsOneWidget);
          final clearNode = tester.getSemantics(clear);
          expect(clearNode.getSemanticsData().flagsCollection.isButton, isTrue);
          var ancestor = clearNode.parent;
          while (ancestor != null) {
            expect(
              ancestor.getSemanticsData().flagsCollection.isTextField,
              isFalse,
            );
            ancestor = ancestor.parent;
          }
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(search).controller!.text, isEmpty);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

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

      await _choose(tester, 'Viewport width', '1024 px');
      expect(tester.getSize(preview).width, 1024);
      expect(find.text('Actions: 1'), findsOneWidget);
      final scrollbar = find.byKey(
        const ValueKey('styleguide-preview-scrollbar'),
      );
      final track = tester.getRect(scrollbar);
      await tester.dragFrom(
        Offset(track.left + 100, track.bottom - 4),
        const Offset(160, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DScrollBar>(scrollbar).controller!.offset,
        greaterThan(0),
      );
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

      await tester.ensureVisible(
        find.byKey(const ValueKey('styleguide-reset')),
      );
      await tester.tap(find.byKey(const ValueKey('styleguide-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Actions: 0'), findsOneWidget);
    },
  );

  testWidgets('Accordion preview reserves its large-text content height', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-accordion')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('styleguide-example-viewport-accordion')),
          )
          .height,
      800,
    );

    await _choose(tester, 'Example', 'RTL');
    await _choose(tester, 'Viewport width', '360 px');
    await _choose(tester, 'Text scale', '200%');
    final viewport = tester.getRect(
      find.byKey(const ValueKey('styleguide-example-viewport-accordion')),
    );
    final finalTrigger = tester.getRect(find.text('ما طرق الدفع المقبولة؟'));
    expect(finalTrigger.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Direction examples use the preview provider and retain edits', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'useDirection',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-direction')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current direction: LTR'), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Display name');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Grace');
    await _settings(tester);
    await tester.scrollUntilVisible(
      find.text('Right to left'),
      -200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('styleguide-detail-direction')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Right to left'));
    await tester.pump();
    expect(find.text('Current direction: RTL'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'Grace',
    );
    await _choose(tester, 'Theme', 'Forest site');
    expect(find.text('Current direction: RTL'), findsOneWidget);
    await _choose(tester, 'Example', 'Nested overrides and fixed content');
    expect(find.text('URL island: LTR'), findsOneWidget);
    expect(find.text('Outer sibling: RTL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Typography preview controls retain rich action state and reset it',
    (tester) async {
      await _pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'Inline code',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-component-typography')),
      );
      await tester.pumpAndSettle();
      await _choose(
        tester,
        'Example',
        'Inline code, rich text and keyboard actions',
      );
      await tester.ensureVisible(find.text('Show details'));
      await tester.tap(find.text('Show details'));
      await tester.pump();
      // The preview has its own scrollable under the detail view's center.
      // Return the outer view to its settings without dragging the preview.
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('styleguide-detail-typography'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await _choose(tester, 'Theme', 'Plum site');
      await _choose(tester, 'Viewport width', '360 px');
      await _choose(tester, 'Text scale', '200%');
      await tester.tap(find.text('Right to left'));
      await tester.pump();
      expect(find.text('Hide details'), findsOneWidget);
      expect(
        find.text('Welcome messages can include a friendly introduction.'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('styleguide-reset')),
      );
      await tester.tap(find.byKey(const ValueKey('styleguide-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Show details'), findsOneWidget);
      expect(find.text('Details are hidden.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(1200, 800)]) {
    testWidgets(
      'search and navigation fit ${size.width}px at 200% system text',
      (tester) async {
        await _pump(tester, size: size, scale: 2);
        if (size.width < 900) {
          await tester.tap(find.byKey(const ValueKey('styleguide-navigation')));
          await tester.pumpAndSettle();
        }
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
    'documentation theme and code disclosure preserve the app preview',
    (tester) async {
      await _pump(tester);
      final preview = find.byKey(const ValueKey('styleguide-preview'));
      final hostTokens = DTokens.of(tester.element(preview));
      expect(find.byKey(const ValueKey('styleguide-Text scale')), findsNothing);
      expect(
        find.textContaining('Preview controls affect examples only'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(DButton, 'primary'));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-documentation-theme')),
      );
      await tester.pump();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('component-styleguide'))),
        ).brightness,
        Brightness.dark,
      );
      expect(
        DTokens.of(tester.element(preview)).background,
        hostTokens.background,
      );
      expect(Theme.of(tester.element(preview)).brightness, Brightness.light);
      final toggle = find.byKey(const ValueKey('styleguide-code-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(
        find.textContaining(
          "import 'package:discourse_native/discourse_ui.dart';",
        ),
        findsOneWidget,
      );
      expect(find.text('Actions: 1'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      expect(
        find.textContaining(
          "import 'package:discourse_native/discourse_ui.dart';",
        ),
        findsNothing,
      );
      expect(find.text('Actions: 1'), findsOneWidget);
    },
  );

  testWidgets(
    'resizing across the navigation breakpoint keeps the active sample',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(DButton, 'primary'));
      await tester.pump();
      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpAndSettle();
      expect(find.text('Actions: 1'), findsOneWidget);
      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpAndSettle();
      expect(find.text('Actions: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile Sidebar selection closes navigation and retains search', (
    tester,
  ) async {
    var closed = false;
    await _pump(
      tester,
      size: const Size(390, 800),
      onClose: () => closed = true,
    );
    final trigger = find.byKey(const ValueKey('styleguide-navigation'));
    expect(find.byType(DSidebar), findsOneWidget);
    expect(find.byKey(const ValueKey('styleguide-search')), findsNothing);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'avatar',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('styleguide-component-avatar')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('styleguide-detail-avatar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('styleguide-search')), findsNothing);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DInput>(find.byKey(const ValueKey('styleguide-search')))
          .controller!
          .text,
      'avatar',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('styleguide-search')), findsNothing);
    expect(closed, false);
  });

  testWidgets(
    'mobile search shortcut opens Sidebar and focuses its search field',
    (tester) async {
      await _pump(tester, size: const Size(390, 800));
      final action = find.widgetWithText(DButton, 'primary');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final search = tester.widget<DInput>(
        find.byKey(const ValueKey('styleguide-search')),
      );
      expect(search.focusNode!.hasFocus, true);
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'kbd',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('styleguide-component-kbd')),
        findsOneWidget,
      );
      expect(find.text('Actions: 1'), findsOneWidget);
    },
  );

  testWidgets(
    'search reveals a collapsed desktop Sidebar without resetting the preview',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.widgetWithText(DButton, 'primary'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('styleguide-navigation')));
      await tester.pumpAndSettle();
      expect(
        tester.state<DSidebarProviderState>(find.byType(DSidebarProvider)).open,
        false,
      );
      await tester.tap(find.byKey(const ValueKey('styleguide-search')));
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'card',
      );
      await tester.pumpAndSettle();
      expect(
        tester.state<DSidebarProviderState>(find.byType(DSidebarProvider)).open,
        true,
      );
      expect(
        find.byKey(const ValueKey('styleguide-component-card')),
        findsOneWidget,
      );
      expect(find.text('Actions: 1'), findsOneWidget);
    },
  );

  testWidgets(
    'Sidebar preview shows desktop navigation and retains selection on mobile',
    (tester) async {
      await _pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'sidebar',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-component-sidebar')),
      );
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('styleguide-preview'));
      final provider = find.descendant(
        of: preview,
        matching: find.byType(DSidebarProvider),
      );
      expect(tester.state<DSidebarProviderState>(provider).isMobile, false);
      final inbox = find.descendant(of: preview, matching: find.text('Inbox'));
      await tester.tap(inbox);
      await tester.pump();
      expect(find.text('Inbox selected'), findsOneWidget);

      await _choose(tester, 'Viewport width', '360 px');
      expect(tester.state<DSidebarProviderState>(provider).isMobile, true);
      expect(inbox, findsNothing);
      await tester.tap(
        find.descendant(of: preview, matching: find.byType(DSidebarTrigger)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Home selected'), findsOneWidget);
      expect(tester.state<DSidebarProviderState>(provider).openMobile, false);
      expect(tester.takeException(), isNull);
    },
  );

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

Future<void> _settings(WidgetTester tester) async {
  if (find.byKey(const ValueKey('styleguide-Text scale')).evaluate().isEmpty) {
    final settings = find.byKey(const ValueKey('styleguide-settings'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pump();
  }
}

Future<void> _choose(WidgetTester tester, String label, String value) async {
  if (label == 'Text scale') await _settings(tester);
  final choice = find.byKey(ValueKey('styleguide-$label'));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}
