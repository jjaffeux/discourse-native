import 'dart:async';

import 'package:flutter/widgets.dart';

/// Source-owned history shared by typing and structural composer commands.
///
/// Selection-only changes do not create entries. Typing is coalesced; an
/// explicit transaction always has its own boundary, even between keystrokes.
/// The editor adapter must route keyboard and platform undo here as well.
class ComposerEditHistory extends ChangeNotifier {
  ComposerEditHistory(
    this.text, {
    required this.beforeRestore,
    bool deferUntilSession = false,
  }) : _last = text.value,
       _sessionStarted = !deferUntilSession {
    text.addListener(_changed);
  }

  final TextEditingController text;
  final VoidCallback beforeRestore;
  static const typingDelay = Duration(milliseconds: 500);
  static const maxEntries = 100;
  final _undo = <(TextEditingValue, TextEditingValue)>[];
  final _redo = <(TextEditingValue, TextEditingValue)>[];
  late TextEditingValue _last;
  TextEditingValue? _pendingBefore;
  TextEditingValue? _pendingAfter;
  Timer? _timer;
  bool _sessionStarted;
  bool _restoring = false;
  bool _transaction = false;

  bool get composing =>
      text.value.composing.isValid && !text.value.composing.isCollapsed;
  bool get canUndo =>
      !composing &&
      (_undo.isNotEmpty ||
          (_pendingBefore != null &&
              _pendingBefore!.text != _pendingAfter?.text));
  bool get canRedo => !composing && _redo.isNotEmpty;

  /// Establish the mounted editor's initial source as its history baseline.
  /// Later remounts retain history; explicit commands can start it headlessly.
  void startSession() {
    if (_sessionStarted) return;
    _sessionStarted = true;
    reset();
  }

  void _changed() {
    final before = _last;
    final after = text.value;
    if (before == after) return;
    _last = after;
    if (!_sessionStarted || _restoring || _transaction) return;
    if (before.text == after.text) {
      if (_pendingBefore != null && !composing) {
        _pendingAfter = after;
        if (before.selection != after.selection) flush();
        if (_pendingBefore != null) {
          _timer?.cancel();
          _timer = Timer(typingDelay, flush);
        }
      }
      if (before.composing != after.composing) notifyListeners();
      return;
    }
    _pendingBefore ??= before.copyWith(composing: TextRange.empty);
    _pendingAfter = after;
    _redo.clear();
    _timer?.cancel();
    if (!composing) _timer = Timer(typingDelay, flush);
    notifyListeners();
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (composing) return;
    final before = _pendingBefore;
    final after = _pendingAfter;
    _pendingBefore = _pendingAfter = null;
    if (before != null && after != null) _append(before, after);
  }

  void _append(TextEditingValue before, TextEditingValue after) {
    if (before.text == after.text) return;
    _undo.add((
      before.copyWith(composing: TextRange.empty),
      after.copyWith(composing: TextRange.empty),
    ));
    if (_undo.length > maxEntries) _undo.removeAt(0);
    _redo.clear();
  }

  bool transact(VoidCallback edit) {
    if (composing || _restoring || _transaction) return false;
    _sessionStarted = true;
    flush();
    final before = text.value;
    _transaction = true;
    try {
      edit();
    } finally {
      _transaction = false;
      _last = text.value;
      _append(before, _last);
      notifyListeners();
    }
    return before.text != text.text;
  }

  /// Applies [edit] as a correction of the current value rather than an edit
  /// of its own. A value restored by undo or redo that its owner must then
  /// normalise would otherwise become the newest entry, discarding redo and
  /// becoming the step the next undo restores, which normalises it again.
  /// While typing is pending, the correction ends that typed edit instead.
  void amend(VoidCallback edit) {
    final restoring = _restoring;
    _restoring = true;
    try {
      edit();
    } finally {
      _restoring = restoring;
      _last = text.value;
      if (_pendingBefore != null) _pendingAfter = _last;
    }
    notifyListeners();
  }

  bool undo() {
    if (composing) return false;
    flush();
    if (_undo.isEmpty) return false;
    final entry = _undo.removeLast();
    _redo.add(entry);
    _restore(entry.$1);
    return true;
  }

  bool redo() {
    if (composing || _redo.isEmpty) return false;
    final entry = _redo.removeLast();
    _undo.add(entry);
    _restore(entry.$2);
    return true;
  }

  void _restore(TextEditingValue value) {
    _restoring = true;
    try {
      beforeRestore();
      text.value = value;
    } finally {
      _restoring = false;
      _last = text.value;
    }
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _pendingBefore = _pendingAfter = null;
    _undo.clear();
    _redo.clear();
    _last = text.value;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    text.removeListener(_changed);
    super.dispose();
  }
}
