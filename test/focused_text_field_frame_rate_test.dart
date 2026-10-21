import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

// Every rasterized frame re-runs each live glass backdrop on screen, so a
// focused field must not keep the display busy. The stock iOS caret fade is an
// animation that requests every vsync for as long as the field has focus.
void main() {
  final inputs = <String, Widget>{
    'DInput': DInput(hintText: 'Search'),
    'DTextarea': DTextarea(hintText: 'Reply'),
    'DComboboxInput': DCombobox<String>(
      options: const [DComboboxOption(value: 'a', label: 'Alpha')],
      anchor: const DComboboxInput<String>(),
      content: const DComboboxContent(children: [DComboboxList<String>()]),
    ),
    'DComboboxChipsInput': DCombobox<String>.multiple(
      options: const [DComboboxOption(value: 'a', label: 'Alpha')],
      anchor: const DComboboxChips<String>(input: DComboboxChipsInput()),
      content: const DComboboxContent(children: [DComboboxList<String>()]),
    ),
    'DInputOTP': DInputOTP(maxLength: 6),
  };

  for (final MapEntry(key: name, value: input) in inputs.entries) {
    testWidgets('focused $name stays idle between iOS caret blinks', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Center(child: SizedBox(width: 300, child: input)),
          ),
        ),
      );
      await tester.showKeyboard(find.byType(EditableText).first);
      // Focus may open a popup; only its steady state is measured.
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText).first).focusNode,
        isA<FocusNode>().having((node) => node.hasFocus, 'hasFocus', isTrue),
      );

      var busy = 0;
      for (var vsync = 0; vsync < 120; vsync++) {
        if (SchedulerBinding.instance.hasScheduledFrame) busy++;
        await tester.pump(const Duration(milliseconds: 1000 ~/ 60));
      }
      // Two seconds of a 60 Hz display: a blink is one frame per half period.
      expect(busy, lessThanOrEqualTo(6));
      expect(tester.takeException(), isNull);
    });
  }
}
