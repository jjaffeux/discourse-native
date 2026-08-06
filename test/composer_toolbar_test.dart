import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

/// The toolbar is one action with two implementations. The plain half is
/// covered by `toggleMarkdownMark` in composer_marks_test; this covers the
/// rich half and, more importantly, that both arrive back as markdown.
void main() {
  late ComposerController composer;
  late MutableDocument document;
  late MutableDocumentComposer documentComposer;
  late Editor editor;

  ComposerController open(String raw) {
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: 'a-real-topic',
        topicTitle: 'A real topic',
      ),
    );
    composer.text.text = raw;
    return composer;
  }

  void goRich() {
    expect(composer.canUseRichMode, isTrue);
    composer.toggleMode();
    expect(composer.mode, ComposerMode.rich);

    document = discourseMarkdownToDocument(composer.text.text);
    documentComposer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document,
      composer: documentComposer,
    );
    document.addListener(
      (_) =>
          composer.setRawFromRichEditor(discourseDocumentToMarkdown(document)),
    );
    composer.attachRichEditor(editor, documentComposer);
  }

  void selectAll() {
    final node = document.first as TextNode;
    documentComposer.setSelectionWithReason(
      DocumentSelection(
        base: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: node.text.length),
        ),
      ),
      SelectionReason.userInteraction,
    );
  }

  tearDown(() {
    composer.dispose();
  });

  test('marking up the document comes back as markdown', () {
    open('say hello');
    goRich();
    selectAll();

    composer.toggleMark(ComposerMark.bold);

    // The document changed, and the payload is still a String.
    expect(composer.text.text, '**say hello**');
  });

  test('unmarking takes it away again', () {
    open('**say hello**');
    goRich();
    selectAll();

    composer.toggleMark(ComposerMark.bold);

    expect(composer.text.text, 'say hello');
  });

  test('marks compose, as they do in the plain field', () {
    open('say hello');
    goRich();
    selectAll();

    composer.toggleMark(ComposerMark.bold);
    selectAll();
    composer.toggleMark(ComposerMark.italic);

    expect(composer.text.text, '***say hello***');
  });

  test('does nothing when the rich surface has no selection', () {
    open('say hello');
    goRich();

    composer.toggleMark(ComposerMark.bold);

    // Armed for what gets typed next rather than applied to nothing.
    expect(composer.text.text, 'say hello');
  });

  test('the plain field is marked up without any editor attached', () {
    open('say hello');
    composer.text.selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 9,
    );

    composer.toggleMark(ComposerMark.bold);

    expect(composer.text.text, 'say **hello**');
  });
}
