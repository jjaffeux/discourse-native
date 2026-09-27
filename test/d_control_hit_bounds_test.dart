import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controls = <String, Widget Function(VoidCallback)>{
    'Button': (activate) => DButton.iconOnly(
      density: DButtonDensity.compactToolbar,
      tooltip: 'Button',
      icon: const Icon(Icons.add),
      onPressed: activate,
    ),
    'Toggle': (activate) => DToggle(
      size: DControlSize.segment,
      semanticLabel: 'Toggle',
      onPressedChanged: (_) => activate(),
      child: const Text('Tab'),
    ),
    'Switch': (activate) =>
        DSwitch(semanticLabel: 'Switch', onChanged: (_) => activate()),
    'Checkbox': (activate) => DCheckbox.defaultValue(
      semanticLabel: 'Checkbox',
      onChanged: (_) => activate(),
    ),
    'Inline checkbox': (activate) => DCheckbox.defaultValue(
      inline: true,
      semanticLabel: 'Inline checkbox',
      onChanged: (_) => activate(),
    ),
    'Radio': (activate) => DRadioGroup<int>(
      onChanged: (_) => activate(),
      child: const DRadioGroupItem<int>(value: 1, semanticLabel: 'Radio'),
    ),
    'Badge': (activate) => DBadge.action(
      semanticLabel: 'Badge',
      onPressed: activate,
      child: const Text('Tag'),
    ),
  };
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final entry in controls.entries) {
      testWidgets(
        '${entry.key} only responds inside its artwork on $platform',
        (tester) async {
          var activations = 0;
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light.copyWith(platform: platform),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 240,
                      height: 100,
                      child: Center(child: entry.value(() => activations++)),
                    ),
                  ),
                ),
              ),
            );
            final artwork = entry.key == 'Radio'
                ? find.byWidgetPredicate(
                    (widget) =>
                        widget is Container &&
                        widget.constraints ==
                            const BoxConstraints.tightFor(
                              width: 16,
                              height: 16,
                            ),
                  )
                : find.byType(AnimatedContainer).first;
            final bounds = tester.getRect(artwork);
            final node = tester.getSemantics(
              find.bySemanticsLabel(entry.key).last,
            );
            expect(node.rect.size, bounds.size);
            for (final outside in [
              bounds.centerLeft - const Offset(1, 0),
              bounds.centerRight + const Offset(1, 0),
              bounds.topCenter - const Offset(0, 1),
              bounds.bottomCenter + const Offset(0, 1),
            ]) {
              await tester.tapAt(outside);
              await tester.pump();
              expect(activations, 0, reason: 'Tap outside $bounds at $outside');
            }
            await tester.tapAt(bounds.center);
            await tester.pump();
            expect(activations, 1);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
