import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  DComboboxOption(value: 'utc', label: 'Etc/UTC'),
  DComboboxOption(value: 'la', label: 'America/Los Angeles'),
  DComboboxOption(value: 'tokyo', label: 'Asia/Tokyo'),
  DComboboxOption(value: 'disabled', label: 'Disabled', enabled: false),
];

Widget _selector({DComboboxValueChanged<String>? onChanged}) => SizedBox(
  width: 320,
  height: 240,
  child: DCombobox<String>.controlled(
    value: 'utc',
    options: _options,
    onChanged: onChanged ?? (_, _) {},
    anchor: const DComboboxInput<String>(
      autofocus: true,
      placeholder: 'Search timezones',
    ),
    content: const DComboboxContent.inline(
      semanticLabel: 'Timezones',
      children: [
        DComboboxEmpty<String>(child: Text('No matching timezones')),
        DComboboxList<String>(),
      ],
    ),
  ),
);

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('inline selected values leave search empty and results visible', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_selector()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Etc/UTC'), findsOneWidget);
    expect(find.text('America/Los Angeles'), findsOneWidget);
    expect(find.text('Asia/Tokyo'), findsOneWidget);
    expect(find.byType(DPopover), findsNothing);
    expect(find.byTooltip('Open suggestions'), findsNothing);
    await tester.enterText(find.byType(TextField), 'LOS ANGELES');
    await tester.pumpAndSettle();
    expect(find.text('Etc/UTC'), findsNothing);
    expect(find.text('America/Los Angeles'), findsOneWidget);
    expect(find.text('Asia/Tokyo'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not a timezone');
    await tester.pumpAndSettle();
    expect(find.text('No matching timezones'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline pointer and keyboard report one selection each', (
    tester,
  ) async {
    final selected = <(String?, DComboboxChangeReason)>[];
    await tester.pumpWidget(
      _app(
        _selector(onChanged: (value, reason) => selected.add((value, reason))),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('America/Los Angeles'));
    await tester.pumpAndSettle();
    expect(selected, [('la', DComboboxChangeReason.itemPress)]);
    await tester.enterText(find.byType(TextField), 'Tokyo');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, [
      ('la', DComboboxChangeReason.itemPress),
      ('tokyo', DComboboxChangeReason.keyboard),
    ]);
    expect(find.text('Asia/Tokyo'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Disabled');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.widgetWithText(DComboboxItem<String>, 'Disabled'));
    await tester.pump();
    expect(selected, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline Escape reaches the surrounding Native dialog once', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => DButton(
            label: const Text('Choose timezone'),
            onPressed: () async {
              result = await showDDialog<String>(
                context: context,
                builder: (_, dialog) => DDialogContent(
                  children: [
                    _selector(onChanged: (value, _) => dialog.close(value)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose timezone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tokyo');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DDialogContent), findsNothing);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
