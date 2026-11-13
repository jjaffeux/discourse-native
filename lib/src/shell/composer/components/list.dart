import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/composer_upload.dart';
import '../controller.dart';
import '../markdown_highlight.dart';
import 'gallery_source.dart';
import 'list_formatting.dart';
import 'list_source.dart';
import 'todo.dart';
import 'upload.dart';

class ComposerListBodyController extends ComposerController {
  ComposerListBodyController(this.parent, ComposerListItem item)
    : _item = item,
      super(
        parent.target,
        sharedHistory: parent.history,
        search: parent.autocomplete.search,
        onEmojiAccepted: parent.onEmojiAccepted,
        resolveEmoji: parent.text.resolveEmoji,
        emojiChanges: parent.text.emojiChanges,
        pills: parent.text.pills,
        pluginHashtagPresentation: parent.text.pluginHashtagPresentation,
        formatQuoteContents: parent.text.formatQuoteContents,
        syntaxPolicies: [
          for (final policy in parent.text.syntaxPolicies)
            if (policy.kind.owner.value != 'core') policy,
        ],
        pluginStateReader: parent.pluginStateReader,
        imageUploader: parent.imageUploader,
        prepareUpload: parent.prepareUpload,
        resolveUploadUrls: parent.text.resolveUploadUrls,
        canUploadImage: parent.canUploadImage,
        canUploadFile: parent.canUploadFile,
        simultaneousUploads: parent.simultaneousUploads,
        enableAutoGridImages: parent.enableAutoGridImages,
        enableMarkdownLinkify: parent.text.enableMarkdownLinkify,
        markdownLinkifyTlds: parent.text.markdownLinkifyTlds,
        maxImageWidth: parent.text.maxImageWidth,
        maxImageHeight: parent.text.maxImageHeight,
      ) {
    text.compactListSpacing = true;
    text.value = TextEditingValue(
      text: item.body.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    text.completedProse = item.checked;
    text.todoReferenceMarkers = item.referenceMarkers;
    text.addListener(_write);
    parent.text.addListener(_read);
    parent.addListener(_parentStateChanged);
    focus.addListener(_activate);
  }
  final ComposerController parent;
  ComposerListItem _item;
  ComposerListItem get item => _item;
  bool _syncing = false;
  bool _retired = false;
  @override
  bool get isCurrent =>
      super.isCurrent && !_retired && parent.isCurrent && _matches;
  @override
  bool get isEditing => super.isEditing && parent.isEditing;
  @override
  bool get singleNewlineParagraphs => true;
  @override
  List<TextInputFormatter> get inputFormatters => [
    TextInputFormatter.withFunction(_formatInput),
  ];

  bool get _matches =>
      _item.end <= parent.text.text.length &&
      parent.text.text.substring(_item.start, _item.end) == _item.source;
  void _activate() {
    if (focus.hasPrimaryFocus) {
      parent.activateEmbeddedEditor(this);
      _write();
    }
  }

  @override
  void activateEmbeddedEditor(ComposerController? editor) {
    super.activateEmbeddedEditor(editor);
    parent.activateEmbeddedEditor(this);
  }

  void _parentStateChanged() {
    if (isDisposed) return;
    text.updateMarkdownLinkify(
      enabled: parent.text.enableMarkdownLinkify,
      tlds: parent.text.markdownLinkifyTlds,
    );
    updateEnableAutoGridImages(parent.enableAutoGridImages);
    notifyListeners();
  }

  void updateItem(ComposerListItem item) {
    _item = item;
    _retired = false;
    text.completedProse = item.checked;
    text.todoReferenceMarkers = item.referenceMarkers;
    _syncing = true;
    try {
      if (text.text != item.body.text) {
        final selection = parent.value.selection;
        text.value = TextEditingValue(
          text: item.body.text,
          selection: TextSelection.collapsed(
            offset: item.body.localOffset(selection.extentOffset),
          ),
        );
      }
    } finally {
      _syncing = false;
    }
  }

  void _read() {
    if (_syncing || isDisposed || _retired) return;
    final next = composerListItems(
      parent.text.text,
      referenceMarkers: parent.text.todoReferenceMarkers,
    ).where((item) => item.start == _item.start).firstOrNull;
    if (next == null) {
      _retired = true;
      return;
    }
    updateItem(next);
  }

  void _write() {
    if (_syncing || !isEditing || !_matches) return;
    final value = text.value;
    if (value.text == _item.body.text &&
        !focus.hasFocus &&
        identical(activeEditor, this)) {
      return;
    }
    final source = _item.body.replace(value.text);
    final nextDocument = parent.text.text.replaceRange(
      _item.start,
      _item.end,
      source,
    );
    final next = composerListItems(
      nextDocument,
      referenceMarkers: parent.text.todoReferenceMarkers,
    ).where((item) => item.start == _item.start).firstOrNull;
    if (next == null) return;
    final selection = value.selection;
    _syncing = true;
    try {
      final committed = parent.commitText(
        expectedText: parent.text.text,
        value: TextEditingValue(
          text: nextDocument,
          selection: selection.isValid
              ? TextSelection(
                  baseOffset: next.body.sourceOffset(selection.baseOffset),
                  extentOffset: next.body.sourceOffset(selection.extentOffset),
                  affinity: selection.affinity,
                  isDirectional: selection.isDirectional,
                )
              : parent.value.selection,
          composing: value.composing.isValid
              ? TextRange(
                  start: next.body.sourceOffset(value.composing.start),
                  end: next.body.sourceOffset(value.composing.end),
                )
              : TextRange.empty,
        ),
      );
      if (!committed) return;
      _item = next;
    } finally {
      _syncing = false;
    }
  }

  TextEditingValue _preserveChildBoundary(
    TextEditingValue before,
    TextEditingValue after,
  ) {
    final removed = before.text.length - after.text.length;
    if (removed <= 0 ||
        !after.selection.isValid ||
        !after.selection.isCollapsed) {
      return after;
    }
    final start = after.selection.start;
    final end = start + removed;
    if (end > before.text.length ||
        (before.selection.isCollapsed
            ? start != before.selection.start && end != before.selection.start
            : start != before.selection.start || end != before.selection.end) ||
        after.text != before.text.replaceRange(start, end, '')) {
      return after;
    }
    // The child's marker is hidden in its own editor. Its leading newline
    // must survive deletion of surrounding prose, even when that range also
    // includes the parent's entire first line. Body newlines are normalized.
    if (_item.children.any((child) => child.start == end) &&
        before.text[end - 1] == '\n') {
      if (start == end - 1) return before;
      return after.copyWith(
        text: before.text.replaceRange(start, end - 1, ''),
        composing: TextRange.empty,
      );
    }
    return after;
  }

  TextEditingValue _formatInput(
    TextEditingValue before,
    TextEditingValue after,
  ) {
    if (!isEditing ||
        !_matches ||
        !before.composing.isCollapsed ||
        !before.selection.isValid) {
      return after;
    }
    after = _preserveChildBoundary(before, after);
    if (!after.composing.isCollapsed) {
      return after;
    }
    final selection = before.selection;
    final caret = selection.start;
    if (after.text != before.text.replaceRange(caret, selection.end, '\n') ||
        !after.selection.isCollapsed ||
        after.selection.extentOffset != caret + 1) {
      return after;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return after;
    final code = markdownCodeRanges(before.text);
    if (code.contains(caret) || (caret > 0 && code.contains(caret - 1))) {
      return after;
    }
    // Apply Return to the body remaining after the selection is removed,
    // but commit both operations together so a single undo restores the text.
    final body = before.copyWith(
      text: before.text.replaceRange(caret, selection.end, ''),
      selection: TextSelection.collapsed(offset: caret),
    );
    if (body.text.trim().isEmpty && parent is ComposerListBodyController) {
      outdent(bodyValue: body);
      return before;
    }
    final offset = _item.body.sourceOffset(caret);
    final value = parent.value.copyWith(
      text: parent.text.text.replaceRange(
        offset,
        _item.body.sourceOffset(selection.end),
        '',
      ),
      selection: TextSelection.collapsed(offset: offset),
    );
    final item = selection.isCollapsed
        ? _item
        : composerListItems(
            value.text,
            referenceMarkers: parent.text.todoReferenceMarkers,
          ).where((item) => item.start == _item.start).firstOrNull;
    if (item == null) return after;
    final newline = item.newline;
    final emptyBoundary = body.text.trim().isEmpty && _needsParagraphBoundary
        ? newline
        : '';
    // Empty tasks and ordinary list items need the same paragraph boundary.
    var next = body.text.trim().isEmpty
        ? TextEditingValue(
            text: value.text.replaceRange(item.start, item.end, emptyBoundary),
            selection: TextSelection.collapsed(
              offset: item.start + emptyBoundary.length,
            ),
          )
        : item.isTask
        ? ComposerTodoInputFormatter(
            referenceMarkers: parent.text.todoReferenceMarkers,
          ).formatEditUpdate(
            value,
            TextEditingValue(
              text: value.text.replaceRange(offset, offset, newline),
              selection: TextSelection.collapsed(
                offset: offset + newline.length,
              ),
            ),
          )
        : TextEditingValue(
            text: value.text.replaceRange(
              offset,
              offset,
              '$newline${item.nextPrefix}',
            ),
            selection: TextSelection.collapsed(
              offset: offset + newline.length + item.nextPrefix.length,
            ),
          );
    final lineStart = caret == 0
        ? 0
        : body.text.lastIndexOf('\n', caret - 1) + 1;
    if (caret == body.text.length &&
        lineStart > 0 &&
        body.text.trim().isNotEmpty &&
        body.text.substring(lineStart).trim().isEmpty) {
      // Uploads leave a continuation line ready for typing. Starting the next
      // item reuses that line instead of leaving an empty row behind.
      final breakStart = item.body.sourceOffset(lineStart - 1);
      next = next.copyWith(
        text: next.text.replaceRange(breakStart, offset, ''),
        selection: TextSelection.collapsed(
          offset: next.selection.extentOffset - (offset - breakStart),
        ),
      );
    }
    _scheduleCommand(parent.text.text, next);
    return before;
  }

  void _scheduleCommand(String expected, TextEditingValue next) {
    // Finish the native input proposal, then build the new item before moving
    // focus. Focusing the parent before the item's editor mounts paints its
    // caret below the full-width list projection for one frame.
    scheduleMicrotask(() {
      if (!isEditing || parent.text.text != expected) return;
      history.transact(
        () => parent.commitText(expectedText: expected, value: next),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (parent.isEditing && parent.value == next) parent.requestFocus();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  bool get _needsParagraphBoundary {
    final previous = composerListItems(
      parent.text.text,
    ).where((item) => item.end < _item.start).lastOrNull;
    return previous != null &&
        parent.text.text.substring(previous.end, _item.start) == _item.newline;
  }

  void toggle() {
    if (!isEditing ||
        !_matches ||
        !text.value.composing.isCollapsed ||
        !_item.isTask) {
      return;
    }
    var start = _item.taskMarkerStart!;
    var end = start + _item.taskMarker!.length;
    var document = parent;
    // Toggle in document coordinates so a selection outside this subtree is
    // preserved, too. Body edits otherwise propagate their own local selection.
    while (document is ComposerListBodyController) {
      start = document.item.body.sourceOffset(start);
      end = document.item.body.sourceOffset(end);
      document = document.parent;
    }
    final value = document.value;
    history.transact(
      () => document.commitText(
        expectedText: value.text,
        value: toggleComposerTodo(
          value,
          markerStart: start,
          markerEnd: end,
          checked: _item.checked,
        ),
      ),
    );
  }

  void exit() {
    if (!parent.isCurrent) return;
    parent.text.selection = TextSelection.collapsed(offset: _item.end);
    parent.requestFocus();
  }

  bool setListKind({required bool ordered}) {
    if (!isEditing ||
        !_matches ||
        !text.selection.isValid ||
        text.text.substring(0, text.selection.extentOffset).contains('\n')) {
      return false;
    }
    _scheduleCommand(
      parent.text.text,
      insertComposerList(
        parent.value.copyWith(
          selection: TextSelection.collapsed(
            offset: _item.body.sourceOffset(text.selection.extentOffset),
          ),
        ),
        ordered: ordered,
      ),
    );
    return true;
  }

  bool setTodo() {
    if (!isEditing ||
        !_matches ||
        !text.selection.isValid ||
        !text.value.composing.isCollapsed) {
      return false;
    }
    if (_item.isTask) return true;

    // Convert the owning marker, even from a continuation line. Numbered
    // items first need their descendants reindented for the bullet's width.
    var value = parent.value.copyWith(
      selection: TextSelection.collapsed(offset: _item.contentStart),
    );
    if (_item.number != null) {
      value = insertComposerList(value, ordered: false);
    }
    value = insertComposerTodo(value);
    final updated = composerListItems(
      value.text,
      referenceMarkers: parent.text.todoReferenceMarkers,
    ).firstWhere((item) => item.start == _item.start);
    _scheduleCommand(
      parent.text.text,
      value.copyWith(
        selection: TextSelection.collapsed(
          offset: updated.body.sourceOffset(text.selection.extentOffset),
        ),
      ),
    );
    return true;
  }

  bool get _canChangeIndentation =>
      isEditing && isCurrent && !history.composing;

  bool get canOutdent =>
      _canChangeIndentation && parent is ComposerListBodyController;

  ComposerListItem? get _indentParent {
    if (!_canChangeIndentation) return null;
    final siblings = composerListItems(
      parent.text.text,
      referenceMarkers: parent.text.todoReferenceMarkers,
    );
    final index = siblings.indexWhere((item) => item.start == _item.start);
    if (index <= 0) return null;
    final previous = siblings[index - 1];
    if (!previous.closed ||
        previous.contentIndent <= _item.indent ||
        parent.text.text
            .substring(previous.end, _item.start)
            .trim()
            .isNotEmpty) {
      return null;
    }
    return previous;
  }

  bool get canIndent => _indentParent != null;

  void outdent({TextEditingValue? bodyValue}) {
    if (!canOutdent) return;
    final outer = parent;
    if (outer is! ComposerListBodyController) return;
    final document = outer.parent;
    final value = document.value;
    final from = outer.item.body.sourceOffset(_item.start);
    final start = from == 0 ? 0 : value.text.lastIndexOf('\n', from - 1) + 1;
    final end = outer.item.body.sourceOffset(_item.end);
    final prefix = ' ' * outer.item.indent;
    final source = bodyValue == null
        ? _item.source
        : _item.body.replace(bodyValue.text);
    final promoted = source
        .split(RegExp(r'\r?\n'))
        .map(
          (line) =>
              '$prefix${line.substring(line.length < _item.indent ? line.length : _item.indent)}',
        )
        .join(outer.item.newline);
    final promotedItem = composerListItems(
      promoted,
      referenceMarkers: parent.text.todoReferenceMarkers,
    ).first;
    final selection = bodyValue?.selection ?? text.selection;
    final caret = selection.isValid ? selection.extentOffset : 0;
    final next = TextEditingValue(
      text: value.text.replaceRange(start, end, promoted),
      selection: TextSelection.collapsed(
        offset: start + promotedItem.body.sourceOffset(caret),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isEditing || document.text.text != value.text) return;
      history.transact(
        () => document.commitText(expectedText: value.text, value: next),
      );
      document.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void indent() {
    final previous = _indentParent;
    if (previous == null) return;
    final prefix = ' ' * (previous.contentIndent - _item.indent);
    final indented = _item.source
        .split(RegExp(r'\r?\n'))
        .map((line) => '$prefix$line')
        .join(_item.newline);
    final caret = text.selection.isValid ? text.selection.extentOffset : 0;
    final sourceCaret = _item.body.sourceOffset(caret);
    final linesBeforeCaret = '\n'
        .allMatches(parent.text.text.substring(_item.start, sourceCaret))
        .length;
    _scheduleCommand(
      parent.text.text,
      TextEditingValue(
        text: parent.text.text.replaceRange(_item.start, _item.end, indented),
        selection: TextSelection.collapsed(
          offset: sourceCaret + prefix.length * (linesBeforeCaret + 1),
        ),
      ),
    );
  }

  void deleteAtStart() {
    if (!isEditing ||
        !_matches ||
        !text.value.composing.isCollapsed ||
        !text.selection.isCollapsed ||
        text.selection.start != 0) {
      return;
    }
    if (parent is ComposerListBodyController) {
      outdent();
      return;
    }
    final value = parent.value;
    final boundary = _needsParagraphBoundary ? _item.newline : '';
    _scheduleCommand(
      value.text,
      TextEditingValue(
        text: value.text.replaceRange(
          _item.start,
          _item.end,
          '$boundary${_item.body.text.replaceAll('\n', _item.newline)}',
        ),
        selection: TextSelection.collapsed(
          offset: _item.start + boundary.length,
        ),
      ),
    );
  }

  KeyEventResult handleKey(KeyEvent event) {
    final isHorizontalArrow =
        event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight;
    if ((event is! KeyDownEvent &&
            !(event is KeyRepeatEvent && isHorizontalArrow)) ||
        !isEditing ||
        !text.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final selection = text.selection;
    if ((keyboard.isMetaPressed || keyboard.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      var document = parent;
      while (document is ComposerListBodyController) {
        document = document.parent;
      }
      document.text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: document.text.text.length,
      );
      document.requestFocus();
      return KeyEventResult.handled;
    }
    if (keyboard.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        parent is ComposerListBodyController) {
      outdent();
      return KeyEventResult.handled;
    }
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (!keyboard.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      indent();
      return KeyEventResult.handled;
    }
    if (selection.isValid &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      final before = text.value;
      final next = _formatInput(
        before,
        TextEditingValue(
          text: before.text.replaceRange(selection.start, selection.end, '\n'),
          selection: TextSelection.collapsed(offset: selection.start + 1),
        ),
      );
      if (next != before) text.value = next;
      return KeyEventResult.handled;
    }
    if (selection.isCollapsed &&
        selection.start == 0 &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      deleteAtStart();
      return KeyEventResult.handled;
    }
    if (!keyboard.isShiftPressed &&
        selection.isCollapsed &&
        ((selection.start == 0 &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft) ||
            (selection.end == text.text.length &&
                event.logicalKey == LogicalKeyboardKey.arrowRight))) {
      final moveLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
      // Keep focus here when there is no following block to navigate to.
      if (!moveLeft && _item.end >= parent.text.text.length) {
        return KeyEventResult.handled;
      }
      final source = parent.text.text;
      final previousNewlineLength =
          _item.start >= 2 && source.startsWith('\r\n', _item.start - 2)
          ? 2
          : 1;
      var offset = moveLeft
          ? (_item.start - previousNewlineLength).clamp(0, source.length)
          : (_item.end + (source.startsWith('\r\n', _item.end) ? 2 : 1)).clamp(
              0,
              source.length,
            );
      if (!moveLeft) {
        for (final item in composerListItems(
          source,
          referenceMarkers: parent.text.todoReferenceMarkers,
        )) {
          if (item.start == offset &&
              item.contentStart >
                  item.start + item.indent + item.marker.length) {
            offset = item.contentStart;
            break;
          }
        }
      }
      parent.text.selection = TextSelection.collapsed(offset: offset);
      parent.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  ComposerUploadPlaceholders get uploadPlaceholders =>
      parent.uploadPlaceholders;
  @override
  List<ComposerUploadItem> get uploads => parent.uploads;
  @override
  Listenable get uploadChanges => parent.uploadChanges;
  @override
  bool get hasActiveUploads => parent.hasActiveUploads;
  @override
  void addFiles(
    Iterable<ComposerUploadFile> files,
    int offset, {
    ComposerImageGalleryBlock? gallery,
  }) {
    if (isEditing && _matches) {
      parent.addFiles(files, _item.body.sourceOffset(offset));
    }
  }

  @override
  void addImages(Iterable<ComposerUploadFile> files, int offset) {
    if (isEditing && _matches) {
      parent.addImages(files, _item.body.sourceOffset(offset));
    }
  }

  @override
  void retryUpload(int id) {
    if (canUpload) parent.retryUpload(id);
  }

  @override
  void cancelUpload(int id) {
    if (isEditing) parent.cancelUpload(id);
  }

  @override
  void removeUpload(int id) => cancelUpload(id);
  @override
  void showNotice(String? message) => parent.showNotice(message);
  @override
  void dispose() {
    text.removeListener(_write);
    parent.text.removeListener(_read);
    parent.removeListener(_parentStateChanged);
    focus.removeListener(_activate);
    parent.deactivateEmbeddedEditor(this);
    super.dispose();
  }
}
