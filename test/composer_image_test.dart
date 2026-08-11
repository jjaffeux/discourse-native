import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = 'before\n![A photo|640x480, 75%](upload://abc)\nafter';

  testWidgets('projects a bounded fallback without changing raw offsets', (
    tester,
  ) async {
    final requested = <String>[];
    final controller = MarkdownEditingController(
      text: source,
      resolveUploadUrls: (urls) async {
        requested.addAll(urls);
        return const {};
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );
    await tester.pump();

    expect(find.byType(ComposerImagePreview), findsOneWidget);
    expect(find.text('A photo'), findsOneWidget);
    expect(requested, ['upload://abc']);
    expect(controller.text, source);
    expect(
      controller
          .buildTextSpan(
            context: tester.element(find.byType(TextField)),
            style: const TextStyle(fontSize: 15),
            withComposing: true,
          )
          .toPlainText(includeSemanticsLabels: false)
          .length,
      source.length,
    );
    final size = tester.getSize(find.byType(ComposerImagePreview));
    expect(size.width, lessThanOrEqualTo(460));
    expect(size.height, lessThanOrEqualTo(200));

    final projected = controller.imageBlocks.single;
    expect(
      controller.collapsedImageAtOffset(projected.end - 1),
      same(projected),
    );
    expect(controller.collapsedImageAtOffset(projected.end), isNull);
  });

  testWidgets('reveals ordinary markdown when the caret enters the image', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: TextField(controller: controller, maxLines: null)),
      ),
    );
    final image = controller.imageBlocks.single;
    expect(find.byType(ComposerImagePreview), findsOneWidget);

    controller.selection = TextSelection.collapsed(offset: image.start + 4);
    await tester.pump();

    expect(find.byType(ComposerImagePreview), findsNothing);
    expect(controller.text, source);

    controller.selection = TextSelection.collapsed(offset: image.end);
    await tester.pump();

    expect(find.byType(ComposerImagePreview), findsOneWidget);
  });
}
