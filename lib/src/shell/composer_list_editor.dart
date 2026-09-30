import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/composer_upload.dart';
import '../plugin_api/composer_syntax.dart';
import 'composer_block_selection.dart';
import 'composer_controller.dart';
import 'composer_embedded_editor.dart';
import 'composer_galleries.dart';
import 'composer_list_source.dart';
import 'composer_lists.dart';
import 'composer_panel.dart';
import 'composer_todos.dart';
import 'composer_upload_placeholder.dart';
import 'markdown_highlight.dart';

ComposerSyntaxKind get composerListSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('core'),
  name: 'list-item',
  label: appL10n.list,
);

final class ComposerListPolicy implements ComposerSyntaxPolicy {
  const ComposerListPolicy(this.composer);
  final ComposerController composer;
  @override
  ComposerSyntaxKind get kind => composerListSyntaxKind;
  @override
  Object get projectionState =>
      (composer.isEditing, composer.text.todoReferenceMarkers);
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final item in composerListItems(
      source,
      referenceMarkers: composer.text.todoReferenceMarkers,
    ))
      // Wait for the separating space while a marker is being typed.
      if (item.source.length >= 2 &&
          item.contentStart > item.start + item.indent + item.marker.length)
        _ListProjection(composer, item),
  ];
}

final class _ListProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerParagraphSpacingProjection {
  _ListProjection(this.composer, this.item);
  final ComposerController composer;
  final ComposerListItem item;
  GlobalKey? _key;
  @override
  int get start => item.start;
  @override
  int get end => item.end;
  @override
  String get source => item.source;
  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      !document.composing.isCollapsed &&
      document.composing.start < item.contentStart &&
      document.composing.end > item.start;
  @override
  int caretAfter(String document) =>
      end +
      (document.startsWith('\r\n', end)
          ? 2
          : document.startsWith('\n', end)
          ? 1
          : 0);
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: caretAfter(document.text)),
        composing: TextRange.empty,
      );
  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    _key = context.pillKey;
    return [
      WidgetSpan(
        // The embedded editor owns its line spacing. Top alignment would add
        // the outer paragraph's ascent leading before the first line again.
        alignment: PlaceholderAlignment.middle,
        style: context.baseStyle,
        child: ComposerBlockSelection(
          selected: context.highlighted,
          child: ComposerListItemEditor(
            key: context.pillKey,
            composer: composer,
            item: item,
            scrollController: context.scrollController,
          ),
        ),
      ),
      TextSpan(
        text:
            composer is ComposerListBodyController &&
                end == item.document.length
            ? '\u200b'
            : '\n',
        style: context.baseStyle.copyWith(color: Colors.transparent),
      ),
      TextSpan(
        text: source.substring(2),
        semanticsLabel: '',
        style: const TextStyle(
          fontSize: 0,
          height: 0,
          letterSpacing: 0,
          color: Colors.transparent,
        ),
      ),
    ];
  }

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {
    if (_key?.currentState case final _ComposerListItemEditorState state) {
      state.body.requestFocus();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!editor.isEditing) return;
    final value = editor.value;
    if (end > value.text.length || value.text.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: value.text,
      value: TextEditingValue(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}

/// The existing rich composer edits a source-mapped body beside a Native
/// checkbox or a text marker. Descendants remain in the item's content column.
class ComposerListItemEditor extends StatefulWidget {
  const ComposerListItemEditor({
    super.key,
    required this.composer,
    required this.item,
    this.scrollController,
  });
  final ComposerController composer;
  final ComposerListItem item;
  final ScrollController? scrollController;
  @override
  State<ComposerListItemEditor> createState() => _ComposerListItemEditorState();
}

class _ComposerListItemEditorState extends State<ComposerListItemEditor> {
  late final body = ComposerListBodyController(widget.composer, widget.item);
  bool _focusScheduled = false;
  @override
  void initState() {
    super.initState();
    widget.composer.text.addListener(_focusFromParent);
    widget.composer.focus.addListener(_focusFromParent);
    _focusFromParent();
  }

  @override
  void didUpdateWidget(ComposerListItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    body.updateItem(widget.item);
    _focusFromParent();
  }

  void _focusFromParent() {
    if (_focusScheduled ||
        !body.isEditing ||
        !widget.composer.focus.hasPrimaryFocus) {
      return;
    }
    final selection = widget.composer.value.selection;
    final item = body.item;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.start < item.contentStart ||
        selection.end > item.end) {
      return;
    }
    // Keyboard focus must reach the body before painting the parent's caret
    // beside its full-width projection. Only defer changes during build/layout.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _focusScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusScheduled = false;
        if (mounted) _focusFromParent();
      });
      return;
    }
    body.text.selection = TextSelection.collapsed(
      offset: item.body.localOffset(selection.start),
    );
    body.requestFocus();
  }

  @override
  void dispose() {
    widget.composer.text.removeListener(_focusFromParent);
    widget.composer.focus.removeListener(_focusFromParent);
    body.dispose();
    super.dispose();
  }

  bool get _isFirstNestedItem {
    final parent = widget.composer;
    return parent is ComposerListBodyController &&
        parent.item.children.firstOrNull?.start == widget.item.start;
  }

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.composer,
    scrollController: widget.scrollController,
    semanticLabel: context.l10n.item((widget.item.label).toString()),
    child: Padding(
      padding: widget.item.isTask
          ? EdgeInsets.only(
              // The parent's bottom padding follows its entire subtree, so
              // its first child needs its own gap from the parent's text.
              top: _isFirstNestedItem ? DSpacing.sm : 0,
              bottom: DSpacing.sm,
            )
          : EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.item.isTask)
            DCheckbox(
              inline: true,
              size: DControlStyle.isTouch(context)
                  ? DCheckboxSize.large
                  : DCheckboxSize.standard,
              inlineTextStyle:
                  context
                      .findAncestorWidgetOfExactType<ComposerEditor>()
                      ?.textStyle ??
                  Theme.of(context).textTheme.bodyLarge,
              value: widget.item.checked,
              readOnly: !body.isEditing,
              semanticLabel: widget.item.body.text.split('\n').first.isEmpty
                  ? context.l10n.toDo
                  : widget.item.body.text.split('\n').first,
              onChanged: (_) => body.toggle(),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(end: DSpacing.md),
              child: Text(
                widget.item.number != null ? '${widget.item.number}.' : '•',
                style: context
                    .findAncestorWidgetOfExactType<ComposerEditor>()
                    ?.textStyle,
              ),
            ),
          Expanded(
            child: ComposerRichBodyEditor(
              composer: body,
              label: context.l10n.listItemContent,
              hintText: widget.item.isTask
                  ? context.l10n.toDo
                  : context.l10n.list,
              enableBlockReordering: false,
              onKeyEvent: body.handleKey,
              onEmptyBackspace: body.deleteAtStart,
              onExit: body.exit,
            ),
          ),
        ],
      ),
    ),
  );
}

class ComposerListBodyController extends ComposerController {
  ComposerListBodyController(this.parent, ComposerListItem item)
    : _item = item,
      super(
        parent.target,
        sharedHistory: parent.history,
        search: parent.autocomplete.search,
        onEmojiAccepted: parent.onEmojiAccepted,
        resolveEmoji: parent.text.resolveEmoji,
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

  TextEditingValue _formatInput(
    TextEditingValue before,
    TextEditingValue after,
  ) {
    if (!isEditing ||
        !_matches ||
        !before.composing.isCollapsed ||
        !after.composing.isCollapsed ||
        !before.selection.isValid ||
        !before.selection.isCollapsed) {
      return after;
    }
    final caret = before.selection.start;
    if (after.text != before.text.replaceRange(caret, caret, '\n') ||
        after.selection.extentOffset != caret + 1) {
      return after;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return after;
    if (before.text.trim().isEmpty && parent is ComposerListBodyController) {
      outdent();
      return before;
    }
    final code = markdownCodeRanges(before.text);
    if (code.contains(caret) || (caret > 0 && code.contains(caret - 1))) {
      return after;
    }
    final offset = _item.body.sourceOffset(caret);
    final value = parent.value.copyWith(
      selection: TextSelection.collapsed(offset: offset),
    );
    final newline = _item.newline;
    final emptyBoundary = before.text.trim().isEmpty && _needsParagraphBoundary
        ? newline
        : '';
    var next = _item.isTask
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
        : before.text.trim().isEmpty
        ? TextEditingValue(
            text: value.text.replaceRange(
              _item.start,
              _item.end,
              emptyBoundary,
            ),
            selection: TextSelection.collapsed(
              offset: _item.start + emptyBoundary.length,
            ),
          )
        : TextEditingValue(
            text: value.text.replaceRange(
              offset,
              offset,
              '$newline${_item.nextPrefix}',
            ),
            selection: TextSelection.collapsed(
              offset: offset + newline.length + _item.nextPrefix.length,
            ),
          );
    final lineStart = caret == 0
        ? 0
        : before.text.lastIndexOf('\n', caret - 1) + 1;
    if (caret == before.text.length &&
        lineStart > 0 &&
        before.text.trim().isNotEmpty &&
        before.text.substring(lineStart).trim().isEmpty) {
      // Uploads leave a continuation line ready for typing. Starting the next
      // item reuses that line instead of leaving an empty row behind.
      final breakStart = _item.body.sourceOffset(lineStart - 1);
      next = next.copyWith(
        text: next.text.replaceRange(breakStart, offset, ''),
        selection: TextSelection.collapsed(
          offset: next.selection.extentOffset - (offset - breakStart),
        ),
      );
    }
    _scheduleCommand(value.text, next);
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
    final start = _item.taskMarkerStart!;
    final value = parent.value;
    history.transact(
      () => parent.commitText(
        expectedText: value.text,
        value: value.copyWith(
          text: value.text.replaceRange(
            start,
            start + _item.taskMarker!.length,
            _item.checked ? '[ ]' : '[x]',
          ),
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

  void outdent() {
    if (!canOutdent) return;
    final outer = parent;
    if (outer is! ComposerListBodyController) return;
    final document = outer.parent;
    final value = document.value;
    final from = outer.item.body.sourceOffset(_item.start);
    final start = from == 0 ? 0 : value.text.lastIndexOf('\n', from - 1) + 1;
    final end = outer.item.body.sourceOffset(_item.end);
    final prefix = ' ' * outer.item.indent;
    final promoted = _item.source
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
    final caret = text.selection.isValid ? text.selection.extentOffset : 0;
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
