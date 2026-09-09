import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_catalogue.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_chrome.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
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
    for (final component in componentCatalogue) {
      expect(
        component.sectionDepths,
        anyOf(isEmpty, hasLength(component.sections.length)),
        reason: component.id,
      );
      expect(
        component.outline.map((section) => section.depth),
        everyElement(anyOf(0, 1)),
        reason: component.id,
      );
    }
    expect(
      componentCatalogue
          .singleWhere((component) => component.id == 'input-group')
          .outline
          .map((section) => (section.label, section.depth)),
      containsAllInOrder(const [
        ('Align', 0),
        ('inline-start', 1),
        ('inline-end', 1),
        ('block-start', 1),
        ('block-end', 1),
        ('Icon', 0),
        ('API Reference', 0),
        ('InputGroup', 1),
      ]),
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
    for (final component in components) {
      final id = component['id'] as String;
      final examples = componentExamples[id];
      expect(examples, isNotNull, reason: '$id must be registered');
      expect(
        examples!.status,
        ComponentStatus.implemented,
        reason: '$id must be accepted before final audit completion',
      );
      expect(examples.description.trim(), isNotEmpty, reason: id);
      expect(examples.notes.trim(), isNotEmpty, reason: id);
      expect(examples.examples, isNotEmpty, reason: id);
      expect(
        examples.examples.map((example) => example.title).toSet().length,
        examples.examples.length,
        reason: '$id example titles must be unique',
      );
      for (final example in examples.examples) {
        expect(example.title.trim(), isNotEmpty, reason: id);
        expect(example.description.trim(), isNotEmpty, reason: id);
        expect(example.code.trim(), isNotEmpty, reason: '$id/${example.title}');
      }
    }
    expect(
      componentExamples.keys.toSet().difference(
        components.map((entry) => entry['id'] as String).toSet(),
      ),
      {'foundations'},
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

  testWidgets(
    'every component renders its complete shadcn outline and every example',
    (tester) async {
      await _pump(tester, size: const Size(1400, 900));

      Finder keysStartingWith(String prefix) =>
          find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> && key.value.startsWith(prefix);
          });

      for (final component in componentCatalogue) {
        final componentButton = find.byKey(
          ValueKey('styleguide-component-${component.id}'),
        );
        tester.widget<DSidebarMenuButton>(componentButton).onPressed!();
        await tester.pump(const Duration(milliseconds: 1));

        final sections = component.outline
            .where((section) => section.label != 'Installation')
            .toList(growable: false);
        expect(
          keysStartingWith('styleguide-section-heading-'),
          findsNWidgets(sections.length),
          reason: '${component.id} must render every outline heading',
        );
        expect(
          keysStartingWith('styleguide-example-panel'),
          findsNWidgets(componentExamples[component.id]!.examples.length),
          reason: '${component.id} must render every registered example',
        );
        for (var index = 0; index < sections.length; index++) {
          expect(
            find.byKey(ValueKey('styleguide-section-$index')),
            findsOneWidget,
            reason: '${component.id}/${sections[index].label} needs a link',
          );
          expect(
            find.byKey(ValueKey('styleguide-section-heading-$index')),
            findsOneWidget,
            reason: '${component.id}/${sections[index].label} needs an anchor',
          );
        }
        expect(
          find.widgetWithText(StyleguideAction, 'Installation'),
          findsNothing,
          reason: component.id,
        );
        expect(tester.takeException(), isNull, reason: component.id);
      }
    },
  );

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
    expect(find.text('Delivery time'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'no such component',
    );
    await tester.pump();
    expect(find.text('No components match your search.'), findsOneWidget);
  });

  testWidgets(
    'page outline follows shadcn heading order and depth without Installation',
    (tester) async {
      await _pump(tester, size: const Size(1400, 900));
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'input group',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-component-input-group')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.widgetWithText(StyleguideAction, 'Installation'),
        findsNothing,
      );
      expect(find.widgetWithText(StyleguideAction, 'Usage'), findsOneWidget);
      expect(
        find.widgetWithText(StyleguideAction, 'Composition'),
        findsOneWidget,
      );
      expect(find.widgetWithText(StyleguideAction, 'Align'), findsOneWidget);
      expect(
        find.widgetWithText(StyleguideAction, 'inline-start'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(StyleguideAction, 'InputGroup'),
        findsOneWidget,
      );
      expect(
        tester
                .getTopLeft(
                  find.widgetWithText(StyleguideAction, 'inline-start'),
                )
                .dx -
            tester
                .getTopLeft(find.widgetWithText(StyleguideAction, 'Align'))
                .dx,
        32,
      );
      expect(
        find.widgetWithText(StyleguideAction, 'Default search'),
        findsNothing,
      );

      final detail = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('styleguide-detail-input-group')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(detail.position.maxScrollExtent, greaterThan(3000));
      await tester.tap(find.widgetWithText(StyleguideAction, 'Text'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<StyleguideAction>(
              find.widgetWithText(StyleguideAction, 'Text'),
            )
            .selected,
        isTrue,
      );
      expect(detail.position.pixels, greaterThan(0));
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('styleguide-section-heading-8')),
            )
            .dy,
        inInclusiveRange(0, 900),
      );

      await tester.tap(find.widgetWithText(StyleguideAction, 'Usage'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(detail.position.pixels, lessThan(800));
    },
  );

  testWidgets(
    'Attachment renders one continuous anchored document including API parts',
    (tester) async {
      await _pump(tester, size: const Size(1400, 900));
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'attachment',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-component-attachment')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      Finder keysStartingWith(String prefix) =>
          find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> && key.value.startsWith(prefix);
          });

      final reference = componentCatalogue.singleWhere(
        (component) => component.id == 'attachment',
      );
      expect(
        keysStartingWith('styleguide-section-heading-'),
        findsNWidgets(
          reference.sections
              .where((section) => section != 'Installation')
              .length,
        ),
      );
      expect(
        keysStartingWith('styleguide-example-panel'),
        findsNWidgets(componentExamples['attachment']!.examples.length),
      );
      expect(find.textContaining('DAttachmentGroup'), findsOneWidget);

      final apiLink = find.widgetWithText(StyleguideAction, 'AttachmentGroup');
      await tester.ensureVisible(apiLink);
      await tester.pump();
      await tester.tap(apiLink);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('styleguide-section-heading-22')),
            )
            .dy,
        inInclusiveRange(0, 900),
      );
    },
  );

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
      await tester.ensureVisible(scrollbar);
      await tester.pump();
      await tester.drag(preview, const Offset(-160, 0));
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
    await _pump(tester, size: const Size(1400, 900));
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-accordion')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('styleguide-example-viewport-accordion')),
          )
          .height,
      800,
    );

    final rtlIndex = await _chooseExample(tester, 'accordion', 'RTL');
    await _choose(tester, 'Viewport width', '360 px');
    await _choose(tester, 'Text scale', '200%');
    final viewport = tester.getRect(
      find.byKey(
        ValueKey(
          rtlIndex == 0
              ? 'styleguide-example-viewport-accordion'
              : 'styleguide-example-viewport-accordion-$rtlIndex',
        ),
      ),
    );
    final finalTrigger = tester.getRect(find.text('ما طرق الدفع المقبولة؟'));
    expect(finalTrigger.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('component pages omit redundant section controls', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1400, 900));
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-accordion')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('styleguide-Example')), findsNothing);
    expect(find.text('Implementation notes'), findsNothing);
  });

  testWidgets('Direction examples use the preview provider and retain edits', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1400, 900));
    await tester.enterText(
      find.byKey(const ValueKey('styleguide-search')),
      'useDirection',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('styleguide-component-direction')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('تسجيل الدخول إلى حسابك'), findsOneWidget);
    expect(find.text('Arabic (العربية)'), findsOneWidget);
    await _chooseExample(tester, 'direction', 'Live direction and editing');
    expect(find.text('Current direction: LTR'), findsOneWidget);
    final field = find.widgetWithText(DInput, 'Display name');
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
    await _chooseExample(
      tester,
      'direction',
      'Nested overrides and fixed content',
    );
    expect(find.text('URL island: LTR'), findsOneWidget);
    expect(find.text('Outer sibling: RTL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Typography preview controls retain rich action state and reset it',
    (tester) async {
      await _pump(tester, size: const Size(1400, 900));
      await tester.enterText(
        find.byKey(const ValueKey('styleguide-search')),
        'Inline code',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('styleguide-component-typography')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _chooseExample(
        tester,
        'typography',
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
      await tester.pump(const Duration(milliseconds: 300));
      final preview = find.byKey(const ValueKey('styleguide-preview'));
      final provider = find.descendant(
        of: preview,
        matching: find.byType(DSidebarProvider),
      );
      expect(tester.state<DSidebarProviderState>(provider).isMobile, false);
      final inbox = find.descendant(of: preview, matching: find.text('Inbox'));
      await tester.ensureVisible(preview);
      await tester.pump();
      await tester.tap(inbox);
      await tester.pump();
      expect(find.text('Inbox selected'), findsOneWidget);

      await _choose(tester, 'Viewport width', '360 px');
      expect(tester.state<DSidebarProviderState>(provider).isMobile, true);
      expect(inbox, findsNothing);
      final panel = find.byKey(const ValueKey('styleguide-example-panel'));
      final detail = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('styleguide-detail-sidebar')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      detail.position.jumpTo(
        (detail.position.pixels + tester.getTopLeft(panel).dy - 100).clamp(
          detail.position.minScrollExtent,
          detail.position.maxScrollExtent,
        ),
      );
      await tester.pump();
      expect(tester.getTopLeft(panel).dy, inInclusiveRange(0, 900));
      final trigger = find.descendant(
        of: preview,
        matching: find.byType(DSidebarTrigger),
      );
      await tester.ensureVisible(trigger);
      await tester.pump();
      await tester.tap(trigger);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Inbox selected'), findsOneWidget);
      tester.state<DSidebarProviderState>(provider).setOpenMobile(false);
      await tester.pump(const Duration(milliseconds: 300));
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
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(value).last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<int> _chooseExample(
  WidgetTester tester,
  String componentId,
  String title,
) async {
  expect(find.byKey(const ValueKey('styleguide-Example')), findsNothing);
  final examples = componentExamples[componentId]!.examples;
  final index = examples.indexWhere((example) => example.title == title);
  expect(index, greaterThanOrEqualTo(0), reason: '$componentId/$title');
  final heading = find.byKey(ValueKey('styleguide-example-title-$index'));
  if (heading.evaluate().isNotEmpty) {
    await tester.ensureVisible(heading);
  } else {
    await tester.ensureVisible(find.text(title).first);
  }
  await tester.pump(const Duration(milliseconds: 300));
  return index;
}
