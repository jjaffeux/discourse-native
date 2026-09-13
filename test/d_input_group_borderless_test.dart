import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('surrounding surface preserves editor geometry and selection', (
    tester,
  ) async {
    final text = TextEditingController(text: 'community');
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    var borderless = false;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: StatefulBuilder(
                builder: (context, setState) {
                  change = setState;
                  return DInputGroup(
                    borderless: borderless,
                    children: [
                      DInputGroupInput(
                        controller: text,
                        focusNode: focus,
                        semanticLabel: 'Search',
                      ),
                      const DInputGroupAddon(
                        alignment: DInputGroupAddonAlignment.inlineStart,
                        child: Icon(Icons.search),
                      ),
                      DInputGroupAddon(
                        alignment: DInputGroupAddonAlignment.inlineEnd,
                        child: DInputGroupButton.icon(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear',
                          onPressed: text.clear,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    text.selection = const TextSelection(baseOffset: 7, extentOffset: 2);
    final editor = find.byType(EditableText);
    final before = tester.getRect(editor);
    change(() => borderless = true);
    await tester.pump();
    expect(tester.getRect(editor), before);
    expect(focus.hasFocus, isTrue);
    expect(text.selection, const TextSelection(baseOffset: 7, extentOffset: 2));
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(text.text, isEmpty);
    change(() => borderless = false);
    await tester.pumpAndSettle();
    expect(tester.getRect(editor), before);
    expect(tester.takeException(), isNull);
  });
}
