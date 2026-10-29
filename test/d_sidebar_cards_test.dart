import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _controls = find.byKey(const ValueKey('controls'));
Finder _heading(String name) => find.byKey(ValueKey('heading-$name'));
Finder _trigger(String name) => find.byKey(ValueKey('trigger-$name'));

Future<void> _pump(WidgetTester tester, {double scale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(390, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: DSidebarProvider(
          mobileBreakpoint: 0,
          child: DSidebar(
            width: 390,
            collapsible: DSidebarCollapsible.none,
            child: DSidebarContent.slivers(
              header: DButton(
                key: const ValueKey('controls'),
                label: const Text('Search'),
                onPressed: () {},
              ),
              slivers: [
                for (final name in ['Forum', 'Categories', 'Tags'])
                  DCollapsible(
                    defaultOpen: true,
                    child: DSidebarGroup.sliver(
                      padding: EdgeInsets.zero,
                      header: DCollapsibleTrigger(
                        key: ValueKey('trigger-$name'),
                        child: DSidebarGroupLabel(
                          key: ValueKey('heading-$name'),
                          child: Text(name),
                        ),
                      ),
                      sliver: DCollapsibleContent.sliver(
                        sliver: DSidebarMenu.sliverBuilder(
                          itemCount: 12,
                          itemBuilder: (context, index) => DSidebarMenuButton(
                            key: ValueKey('$name-$index'),
                            onPressed: () {},
                            child: Text('$name destination $index'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'phone sidebar defaults are 40-point rows and 48-point headings',
    (tester) async {
      await _pump(tester);
      expect(tester.getSize(find.byKey(const ValueKey('Forum-0'))).height, 40);
      expect(tester.getSize(_heading('Forum')).height, 48);
      final controls = tester.getRect(_controls);
      final viewport = find.byType(CustomScrollView);
      final controller = tester.widget<CustomScrollView>(viewport).controller!;
      final top = controls.bottom + 6;
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getRect(_heading('Forum')).top, top);
      expect(tester.getRect(_controls), controls);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: controls.center,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(400));
      controller.jumpTo(520 + top);
      await tester.pumpAndSettle();
      expect(tester.getRect(_heading('Forum')).top, lessThan(top));
      expect(
        tester.getRect(_heading('Forum')).bottom,
        lessThanOrEqualTo(tester.getRect(_heading('Categories')).top),
      );
      controller.jumpTo(536 + top);
      await tester.pumpAndSettle();
      expect(tester.getRect(_heading('Categories')).top, top);
      controller.jumpTo(536);
      await tester.pumpAndSettle();
      await tester.tap(_trigger('Categories'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('Categories-0')).hitTestable(),
        findsNothing,
      );
      expect(tester.getRect(_heading('Tags')).top - top, 56);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone rich sidebar items use the existing 56-point row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: DItem(
              key: const ValueKey('conversation'),
              size: DItemSize.sm,
              shape: DItemShape.menu,
              selectionStyle: DItemSelectionStyle.sidebar,
              onPressed: () {},
              children: const [
                DItemContent(
                  children: [
                    DItemTitle(child: Text('Design')),
                    DItemDescription(child: Text('A new draft is ready')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('conversation'))).height,
      56,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large phone text preserves card disclosure and fixed controls', (
    tester,
  ) async {
    await _pump(tester, scale: 2);
    final controls = tester.getRect(_controls);
    final viewport = find.byType(CustomScrollView);
    await tester.drag(viewport, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(_controls), controls);
    expect(_trigger('Forum').hitTestable(), findsOneWidget);
    await tester.tap(_trigger('Forum'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('Forum-0')).hitTestable(), findsNothing);
    expect(_trigger('Categories').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
