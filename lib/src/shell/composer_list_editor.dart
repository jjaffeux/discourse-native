import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/composer_upload.dart';
import '../plugin_api/composer_syntax.dart';
import 'composer_block_selection.dart';
import 'composer_controller.dart';
import 'composer_embedded_editor.dart';
import 'composer_galleries.dart';
import 'composer_list_source.dart';
import 'composer_panel.dart';
import 'composer_todos.dart';
import 'markdown_highlight.dart';

const composerListSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('core'),
  name: 'task-item',
  label: 'To-do',
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
      if (item.containsTasks) _ListProjection(composer, item),
  ];
}

final class _ListProjection implements ComposerInteractiveSyntaxProjection {
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
  }) => false;
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
        alignment: PlaceholderAlignment.top,
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
        text: '\n',
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
/// checkbox. Every descendant remains in the item's content column.
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
    if (_focusScheduled || !widget.composer.focus.hasPrimaryFocus) return;
    final selection = widget.composer.value.selection;
    final item = body.item;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.start < item.contentStart ||
        selection.end > item.end) {
      return;
    }
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted ||
          !body.isEditing ||
          !widget.composer.focus.hasPrimaryFocus) {
        return;
      }
      final selection = widget.composer.value.selection;
      if (!selection.isCollapsed ||
          selection.start < body.item.contentStart ||
          selection.end > body.item.end) {
        return;
      }
      body.text.selection = TextSelection.collapsed(
        offset: body.item.body.localOffset(selection.start),
      );
      body.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.composer.text.removeListener(_focusFromParent);
    widget.composer.focus.removeListener(_focusFromParent);
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.composer,
    scrollController: widget.scrollController,
    semanticLabel: widget.item.isTask ? 'To-do item' : 'List item',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.item.isTask)
          DCheckbox(
            alignment: AlignmentDirectional.topStart,
            value: widget.item.checked,
            readOnly: !body.isEditing,
            semanticLabel: widget.item.body.text.split('\n').first.isEmpty
                ? 'To-do'
                : widget.item.body.text.split('\n').first,
            onChanged: (_) => body.toggle(),
          )
        else
          Padding(
            padding: const EdgeInsetsDirectional.only(end: DSpacing.md),
            child: Text(
              RegExp(r'^\d').hasMatch(widget.item.marker)
                  ? widget.item.marker
                  : '•',
            ),
          ),
        Expanded(
          child: ComposerRichBodyEditor(
            composer: body,
            label: 'List item content',
            hintText: 'To-do',
            enableBlockReordering: false,
            onKeyEvent: body.handleKey,
            onExit: body.exit,
          ),
        ),
      ],
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
    if (next == null || !next.containsTasks) {
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
    final code = CodeRanges.of(scanMarkdown(before.text));
    if (code.contains(caret) || (caret > 0 && code.contains(caret - 1))) {
      return after;
    }
    final offset = _item.body.sourceOffset(caret);
    final value = parent.value.copyWith(
      selection: TextSelection.collapsed(offset: offset),
    );
    final newline = _item.newline;
    final next = _item.isTask
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
              '$newline${_item.itemPrefix}',
            ),
            selection: TextSelection.collapsed(
              offset: offset + newline.length + _item.itemPrefix.length,
            ),
          );
    _scheduleCommand(value.text, next);
    return before;
  }

  void _scheduleCommand(String expected, TextEditingValue next) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isEditing || parent.text.text != expected) return;
      history.transact(
        () => parent.commitText(expectedText: expected, value: next),
      );
      parent.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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

  void outdent() {
    if (!isEditing || !_matches) return;
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
    final next = TextEditingValue(
      text: value.text.replaceRange(start, end, promoted),
      selection: TextSelection.collapsed(
        offset:
            start +
            prefix.length +
            _item.contentStart -
            _item.start -
            _item.indent,
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

  KeyEventResult handleKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
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
    if (selection.isCollapsed &&
        selection.start == 0 &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final value = parent.value;
      _scheduleCommand(
        value.text,
        TextEditingValue(
          text: value.text.replaceRange(
            _item.start,
            _item.end,
            _item.body.text.replaceAll('\n', _item.newline),
          ),
          selection: TextSelection.collapsed(offset: _item.start),
        ),
      );
      return KeyEventResult.handled;
    }
    if (!keyboard.isShiftPressed &&
        selection.isCollapsed &&
        ((selection.start == 0 &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft) ||
            (selection.end == text.text.length &&
                event.logicalKey == LogicalKeyboardKey.arrowRight))) {
      parent.text.selection = TextSelection.collapsed(
        offset: selection.start == 0
            ? (_item.start - 1).clamp(0, parent.text.text.length)
            : (_item.end + _item.newline.length).clamp(
                0,
                parent.text.text.length,
              ),
      );
      parent.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Map<int, String> get uploadPlaceholders => parent.uploadPlaceholders;
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
