import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/rich_composer_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

/// super_editor is a document editor first, so its defaults lay text out like a
/// page: a fixed-width column, centred, indented. A composer is a form field,
/// and the two modes have to sit in the same place or switching between them
/// throws the text across the panel.
void main() {
  testWidgets('lays text out like the plain field, not like a page', (
    tester,
  ) async {
    const width = 900.0;
    tester.view.physicalSize = const Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 300,
            child: RichComposerField(
              composer: ComposerController(
                const ComposerTarget(
                  siteUrl: 'https://meta.discourse.org',
                  topicId: 7,
                  slug: 'a-real-topic',
                  topicTitle: 'A real topic',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final text = tester.getRect(find.byType(TextComponent));
    // Left, and the full width: the default stylesheet would put a 640-wide
    // column at x=130 with a 24 indent, which is what left the caret sitting in
    // the middle of an empty composer.
    expect(text.left, 0);
    expect(text.width, width);
  });
}
