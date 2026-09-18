import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final (size, baseHeight, fontSize) in [
      (DControlSize.small, 24.0, 12.0),
      (DControlSize.regular, 28.0, 13.0),
      (DControlSize.large, 32.0, 14.0),
    ]) {
      final height = DControlStyle.scaledHeight(size, TextScaler.linear(scale));
      assert(scale != 1 || height == baseHeight);
      testWidgets(
        '${size.name} at $scale has the same height across controls',
        (tester) async {
          var presses = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 180,
                          child: DInput(key: const Key('input'), size: size),
                        ),
                        SizedBox(
                          width: 180,
                          child: DFileInput(
                            key: const Key('file'),
                            size: size,
                            onPick: () async => null,
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DInputGroup(
                            key: const Key('input-group'),
                            size: size,
                            children: [
                              const DInputGroupAddon(child: Text('@')),
                              DInputGroupInput(),
                            ],
                          ),
                        ),
                        DButton(
                          key: const Key('button'),
                          size: size,
                          label: const Text('Button'),
                          onPressed: () => presses++,
                        ),
                        DButton.iconOnly(
                          key: const Key('icon'),
                          size: size,
                          icon: const Icon(Icons.add),
                          tooltip: 'Icon',
                          onPressed: () => presses++,
                        ),
                        DSelect<String>(
                          key: const Key('select'),
                          size: size,
                          width: 140,
                          value: 'a',
                          entries: const [
                            DSelectOption(
                              value: 'a',
                              label: 'Alpha',
                              child: Text('Alpha'),
                            ),
                          ],
                          onChanged: (_) {},
                        ),
                        DDropdownMenu(
                          content: const DDropdownMenuContent(
                            children: [
                              DDropdownMenuItem(child: Text('Action')),
                            ],
                          ),
                          child: DDropdownMenuTrigger.button(
                            key: const Key('dropdown'),
                            size: size,
                            label: const Text('Menu'),
                          ),
                        ),
                        DToggle(
                          key: const Key('toggle'),
                          size: size,
                          child: const Text('Toggle'),
                        ),
                        DInputGroupButton(
                          key: const Key('addon'),
                          size: size,
                          label: const Text('Addon'),
                          onPressed: () => presses++,
                        ),
                        DInputGroupButton.icon(
                          key: const Key('addon-icon'),
                          size: size,
                          icon: const Icon(Icons.add),
                          tooltip: 'Addon icon',
                          onPressed: () => presses++,
                        ),
                        SizedBox(
                          width: 180,
                          child: DCombobox<String>(
                            options: const [
                              DComboboxOption(value: 'a', label: 'Alpha'),
                            ],
                            anchor: DComboboxInput<String>(
                              key: const Key('combobox'),
                              size: size,
                            ),
                            content: const DComboboxContent(
                              children: [DComboboxList<String>()],
                            ),
                          ),
                        ),
                        DTabs<String>(
                          children: [
                            DTabList<String>(
                              key: const Key('tab-list'),
                              size: size,
                              children: const [
                                DTabTrigger<String>(
                                  key: Key('tab'),
                                  value: 'a',
                                  child: Text('Tab'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        DMenubar(
                          children: [
                            DMenubarMenu(
                              trigger: DMenubarTrigger(
                                key: const Key('menubar'),
                                size: size,
                                child: const Text('File'),
                              ),
                              content: const DMenubarContent(
                                children: [DMenubarItem(child: Text('Open'))],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 180,
                          child: DSidebarMenuButton(
                            key: const Key('sidebar'),
                            size: size,
                            child: const Text('Sidebar'),
                            onPressed: () {},
                          ),
                        ),
                        DAttachmentAction(
                          key: const Key('attachment'),
                          size: size,
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove',
                          onPressed: () => presses++,
                        ),
                        DPaginationNext(
                          key: const Key('page'),
                          size: size,
                          onPressed: () => presses++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          for (final key in [
            'input',
            'file',
            'input-group',
            'button',
            'icon',
            'select',
            'dropdown',
            'toggle',
            'addon',
            'addon-icon',
            'combobox',
            'attachment',
            'page',
            'menubar',
            'sidebar',
          ]) {
            expect(
              tester.getSize(find.byKey(Key(key))).height,
              height,
              reason: key,
            );
          }
          for (final label in ['Button', 'Toggle', 'Menu', 'Sidebar']) {
            expect(
              DefaultTextStyle.of(
                tester.element(find.text(label)),
              ).style.fontSize,
              fontSize,
              reason: '$label inherits the ${size.name} typography preset',
            );
          }
          // Tabs inset their triggers; the list owns the shared minimum height.
          expect(
            tester.getSize(find.byKey(const Key('tab-list'))).height,
            greaterThanOrEqualTo(height),
          );
          expect(
            tester
                .getRect(find.byKey(const Key('tab-list')))
                .contains(tester.getCenter(find.byKey(const Key('tab')))),
            isTrue,
          );
          await tester.tap(find.byKey(const Key('button')));
          await tester.tap(find.byKey(const Key('icon')));
          expect(presses, 2);
          await tester.tap(find.byKey(const Key('dropdown')));
          await tester.pumpAndSettle();
          expect(find.text('Action'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
