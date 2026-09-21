import 'package:discourse_native/src/shell/composer_edit_history.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController text;
  late ComposerEditHistory history;
  setUp(() {
    text = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'One\n\nTwo',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    history = ComposerEditHistory(text, beforeRestore: () {});
  });
  tearDown(() {
    history.dispose();
    text.dispose();
  });

  void edit(String source) => text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );

  test('two rapid transactions undo separately and retain the caret', () {
    final original = text.value;
    history.transact(() => edit('Two\n\nOne'));
    final first = text.value;
    history.transact(() => edit('One\n\nTwo'));
    expect(history.undo(), isTrue);
    expect(text.value, first);
    expect(history.undo(), isTrue);
    expect(text.value, original);
    expect(history.redo(), isTrue);
    expect(text.value, first);
  });

  test('typing either side of a move never joins the move undo entry', () {
    edit('One!\n\nTwo');
    history.transact(() => edit('Two\n\nOne!'));
    edit('Two?\n\nOne!');
    history.undo();
    expect(text.text, 'Two\n\nOne!');
    history.undo();
    expect(text.text, 'One!\n\nTwo');
    history.undo();
    expect(text.text, 'One\n\nTwo');
  });

  test('selection alone and no-op transactions do not dirty history', () {
    text.selection = const TextSelection.collapsed(offset: 1);
    expect(history.transact(() {}), isFalse);
    expect(history.canUndo, isFalse);
  });

  test(
    'composition blocks moves and undo, then records the completed input',
    () {
      text.value = const TextEditingValue(
        text: '候補',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      expect(history.transact(() => edit('wrong')), isFalse);
      expect(history.undo(), isFalse);
      text.value = text.value.copyWith(composing: TextRange.empty);
      expect(history.undo(), isTrue);
      expect(text.text, 'One\n\nTwo');
    },
  );

  test('new typing after undo discards redo', () {
    history.transact(() => edit('Changed'));
    history.undo();
    edit('Different');
    expect(history.canRedo, isFalse);
  });

  test('reset prevents undo from crossing document replacement', () {
    history.transact(() => edit('Changed'));
    edit('A new draft');
    history.reset();
    expect(history.undo(), isFalse);
    expect(text.text, 'A new draft');
  });
}
