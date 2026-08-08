import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

/// `toggleMarkdownMark` itself is covered in composer_marks_test; this covers
/// the composer driving it, so a toolbar press ends up in the text that gets
/// posted.
void main() {
  late ComposerController composer;

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

  tearDown(() {
    composer.dispose();
  });

  test('marks up the selection', () {
    open('say hello');
    composer.text.selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 9,
    );

    composer.toggleMark(ComposerMark.bold);

    expect(composer.text.text, 'say **hello**');
  });

  test('marks compose', () {
    open('say hello');
    composer.text.selection = const TextSelection(
      baseOffset: 4,
      extentOffset: 9,
    );

    composer.toggleMark(ComposerMark.bold);
    composer.toggleMark(ComposerMark.italic);

    expect(composer.text.text, 'say ***hello***');
  });

  test('unmarking takes it away again', () {
    open('**say hello**');
    composer.text.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 13,
    );

    composer.toggleMark(ComposerMark.bold);

    expect(composer.text.text, 'say hello');
  });
}
