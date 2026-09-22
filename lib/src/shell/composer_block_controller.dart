import 'package:flutter/widgets.dart';

import '../plugin_api/composer_syntax.dart';
import 'composer_blocks.dart';
import 'composer_edit_history.dart';
import 'markdown_editing_controller.dart';

/// Coordinates structural selection and verified commands around one editor.
class ComposerBlockController extends ChangeNotifier {
  ComposerBlockController({
    required this.text,
    required this.history,
    required this.canEdit,
    required this.notice,
  }) : _source = text.text,
       _lastValue = text.value {
    text.addListener(_changed);
  }

  final MarkdownEditingController text;
  final ComposerEditHistory history;
  final bool Function() canEdit;
  final ValueChanged<String> notice;
  final _snapshots = <String, ComposerBlockIndex>{};
  String _source;
  TextEditingValue _lastValue;
  int _revision = 0;
  ComposerBlockIndex? _index;
  ComposerBlockIndex? _pendingIndex;
  int? _selectedId;
  bool _arranging = false;

  bool get arranging => _arranging;
  int get revision => _revision;
  bool get enabled => canEdit() && !history.composing;
  ComposerBlockIndex get index => _index ??= _parse();
  ComposerBodyBlock? get selected => _selectedId == null
      ? index.atOffset(text.selection.extentOffset)
      : index.byId(_selectedId!) ?? index.atOffset(text.selection.extentOffset);

  ComposerBlockIndex _parse() => ComposerBlockIndex.parse(
    _source,
    revision: _revision,
    previous: _index,
    atoms: [
      for (final block in text.syntaxBlocks)
        if (block.projection is ComposerBlockSyntaxProjection)
          ComposerBlockAtom(block.start, block.end, label: block.kind.label),
      for (final block in text.quoteBlocks)
        ComposerBlockAtom(block.start, block.end, label: 'Quote'),
      for (final block in text.galleryBlocks)
        ComposerBlockAtom(block.start, block.end, label: 'Gallery'),
      for (final block in text.imageBlocks)
        ComposerBlockAtom(block.start, block.end, label: 'Image'),
    ],
  );

  void _remember(ComposerBlockIndex index) {
    _snapshots.remove(index.source);
    _snapshots[index.source] = index;
    if (_snapshots.length > ComposerEditHistory.maxEntries) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

  void _changed() {
    // Projection artwork also notifies during layout. Structural controls only
    // observe editing values, never rebuild in response to paint changes.
    if (text.value == _lastValue) return;
    _lastValue = text.value;
    if (text.text == _source) {
      if (!_arranging && _pendingIndex == null) _selectedId = null;
      notifyListeners();
      return;
    }
    if (_index case final previous?) _remember(previous);
    _source = text.text;
    _revision++;
    final pending = _pendingIndex;
    _index = pending?.source == _source
        ? pending!.withRevision(_revision)
        : _snapshots[_source]?.withRevision(_revision) ?? _parse();
    _remember(index);
    if (_selectedId != null && index.byId(_selectedId!) == null) {
      _selectedId = index.atOffset(text.selection.extentOffset)?.id;
    }
    notifyListeners();
  }

  void select(int id) {
    if (index.byId(id) == null || _selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  bool startArranging() {
    if (!enabled) return false;
    _selectedId = selected?.id;
    _arranging = true;
    notifyListeners();
    return true;
  }

  void finishArranging() {
    _arranging = false;
    notifyListeners();
  }

  bool canMoveTo(int gap) {
    final block = selected;
    return enabled && block != null && index.move(block.id, gap) != null;
  }

  bool moveTo(
    int gap, {
    int? offset,
    int? blockId,
    required int expectedRevision,
  }) {
    if (!enabled) return false;
    if (_revision != expectedRevision) {
      notice('The draft changed. Move the block again.');
      return false;
    }
    final id = blockId ?? selected?.id;
    if (id == null) return false;
    final move = index.move(id, gap, offset: offset);
    if (move == null) return false;
    final selection = text.selection;
    final mappedSelection = selection.isValid
        ? TextSelection(
            baseOffset: move.mapOffset(selection.baseOffset),
            extentOffset: move.mapOffset(selection.extentOffset),
            affinity: selection.affinity,
            isDirectional: selection.isDirectional,
          )
        : TextSelection.collapsed(offset: move.after.byId(id)!.start);
    _pendingIndex = move.after;
    _selectedId = id;
    try {
      return history.transact(() {
        text.clearKeyboardPillSelection();
        text.value = TextEditingValue(
          text: move.after.source,
          selection: mappedSelection,
        );
      });
    } finally {
      _pendingIndex = null;
    }
  }

  void reset() {
    _snapshots.clear();
    _index = null;
    _pendingIndex = null;
    _selectedId = null;
    _arranging = false;
    _source = text.text;
    _lastValue = text.value;
    _revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    text.removeListener(_changed);
    super.dispose();
  }
}
