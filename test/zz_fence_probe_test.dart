import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _doc(int fences) {
  final buffer = StringBuffer();
  for (var i = 0; i < fences; i++) {
    buffer.writeln('```dart');
    for (var line = 0; line < 20; line++) {
      buffer.writeln('final x$i$line = "value $i $line padding padding";');
    }
    buffer.writeln('```');
    buffer.writeln();
  }
  return buffer.toString();
}

void main() {
  testWidgets('many large fences settle', (tester) async {
    final controller = MarkdownEditingController(text: _doc(40));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TextField(controller: controller))),
    );
    for (var round = 0; round < 6; round++) {
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      // ignore: avoid_print
      print('round $round scans=${controller.scans}');
    }
  });
}
