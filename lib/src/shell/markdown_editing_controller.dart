import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart'
    show listEquals, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/media_pipeline.dart';
import '../models/composer_upload.dart';
import '../models/site_config.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/hashtag_kind.dart';
import '../theme/discourse_typography.dart';
import 'composer_block_selection.dart';
import 'composer_blockquote.dart';
import 'composer_blocks.dart';
import 'composer_galleries.dart';
import 'composer_image.dart';
import 'composer_image_gallery.dart';
import 'composer_images.dart';
import 'composer_inline_spans.dart';
import 'composer_link.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
import 'composer_source_projection.dart';
import 'composer_text_scaling.dart';
import 'composer_todos.dart';
import 'emoji.dart';
import 'hashtag.dart';
import 'markdown_highlight.dart';
import 'markdown_style.dart';
import 'mention.dart';
import 'syntax.dart';

class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({
    super.text,
    this.imageSiteUrl,
    this.resolveEmoji,
    this.pills,
    this.pluginHashtagPresentation,
    this.formatQuoteContents,
    this.syntaxPolicies = const [],
    this.resolveUploadUrls,
    this.enableMarkdownLinkify = true,
    List<String> markdownLinkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
    this.maxImageWidth = 690,
    this.maxImageHeight = 500,
    this.enableImageGalleries = true,
    this.enableTodos = true,
    this.enableBlockSeparators = false,
    this.protectComponentSource = false,
    @visibleForTesting
    SyntaxHighlightBatcher backgroundSyntaxHighlighterForTesting =
        highlightLinesBatchInBackground,
  }) : _backgroundSyntaxHighlighter = backgroundSyntaxHighlighterForTesting,
       _markdownLinkifyTlds = List.unmodifiable(markdownLinkifyTlds);

  final String? imageSiteUrl;

  final String Function(String name)? resolveEmoji;

  final ComposerPills? pills;

  final PluginHashtagPresentationResolver? pluginHashtagPresentation;

  final ComposerQuoteContentsFormatter? formatQuoteContents;
  ComposerQuoteContentsResolver? _quoteContentsResolver;
  Object? _quoteContentsResolverContext;

  final List<ComposerSyntaxPolicy> syntaxPolicies;
  final ComposerUploadUrlResolver? resolveUploadUrls;
  bool enableMarkdownLinkify;
  List<String> _markdownLinkifyTlds;
  List<String> get markdownLinkifyTlds => _markdownLinkifyTlds;
  final int maxImageWidth;
  final int maxImageHeight;

  final bool enableImageGalleries;
  final bool enableTodos;
  final bool enableBlockSeparators;

  /// Keeps recognized components atomic in rich composers, including during
  /// native selection and IME composition. Explicit raw Markdown mode bypasses
  /// this protection.
  final bool protectComponentSource;

  bool _rawMarkdown = false;

  /// Displays and edits every source character without component projection.
  bool get rawMarkdown => _rawMarkdown;

  set rawMarkdown(bool enabled) {
    if (_rawMarkdown == enabled) return;
    _rawMarkdown = enabled;
    _cachedSpan = null;
    _keyboardSelectedProjection = null;
    _keyboardSelectionDocument = null;
    _boundaryCaretProjection = null;
    _boundaryCaretOffset = null;
    _caretSuppressedSyntax = null;
    _hoveredSyntaxKey = null;
    _preserveSyntaxPointerSelection = false;
    _caretSuppressedImage = null;
    _caretSuppressedGallery = null;
    _collapsedSyntaxKeys = const {};
    _collapsedQuoteStarts = const {};
    _collapsedImageStarts = const {};
    _collapsedGalleryStarts = const {};
    _renderedEmojiDocument = null;
    _renderedEmojiRanges = const {};
    notifyListeners();
  }

  /// A list body keeps child blocks beside their surrounding prose without
  /// adding paragraph spacing to a single source newline.
  bool compactListSpacing = false;
  String? _separatorSource;
  List<TextRange> _separators = const [];
  List<TextRange> _blockGaps = const [];
  final _componentGapStarts = <int>{};
  final _spaceBeforeComponents = <int>{};
  final _spaceAfterComponents = <int>{};
  static final _paragraphBreak = RegExp(r'\r?\n[ \t]*\r?\n');
  static final _lineEnd = RegExp(r'[ \t]*(?:[\r\n]|$)');

  TextRange? _paragraphBreakAt(int offset) {
    final match = _paragraphBreak.matchAsPrefix(text, offset);
    return match == null ? null : TextRange(start: offset, end: match.end);
  }

  /// Structural spacing between blocks, including single-newline boundaries.
  List<TextRange> get blockGaps {
    if (rawMarkdown) return const [];
    _updateBlockGaps();
    return _blockGaps;
  }

  /// Required Markdown paragraph boundaries, excluding additional empty lines.
  List<TextRange> get blockSeparators {
    if (rawMarkdown) return const [];
    _updateBlockGaps();
    return _separators;
  }

  void _updateBlockGaps() {
    if (!enableBlockSeparators || _separatorSource == text) return;
    _separatorSource = text;
    final index = ComposerBlockIndex.parse(
      text,
      atoms: [
        for (final block in syntaxBlocks)
          if (block.projection is ComposerBlockSyntaxProjection &&
              block.projection is! ComposerParagraphSpacingProjection)
            ComposerBlockAtom(block.start, block.end),
        for (final block in quoteBlocks)
          ComposerBlockAtom(block.start, block.end),
        for (final block in galleryBlocks)
          ComposerBlockAtom(block.start, block.end),
        for (final block in imageBlocks)
          ComposerBlockAtom(block.start, block.end),
      ],
    );
    _separators = [
      for (final (i, block) in index.blocks.indexed)
        // Embedded components own their projected boundary carets and deletion.
        if (block.kind != ComposerBlockKind.component &&
            (i + 1 == index.blocks.length ||
                (index.blocks[i + 1].kind != ComposerBlockKind.component &&
                    // Removing an extra blank line before a nested row must
                    // leave its required leading newline intact.
                    !(compactListSpacing && _isListRow(index.blocks[i + 1])))))
          ?_paragraphBreakAt(block.end),
    ];
    _blockGaps = [
      for (final (i, block) in index.blocks.indexed)
        if (_paragraphBreakAt(block.end) case final separator?)
          separator
        else if (i + 1 < index.blocks.length &&
            !compactListSpacing &&
            // Mixed list rows share the same compact rhythm.
            !(_isListRow(index.blocks[i + 1]) && _isListRow(block)))
          if (text.startsWith('\r\n', block.end))
            TextRange(start: block.end, end: block.end + 2)
          else if (text.startsWith('\n', block.end))
            TextRange(start: block.end, end: block.end + 1),
    ];
    _componentGapStarts.clear();
    _spaceBeforeComponents.clear();
    _spaceAfterComponents.clear();
    if (compactListSpacing) return;
    final componentStarts = index.atoms.map((atom) => atom.start).toSet();
    for (final (i, block) in index.blocks.indexed) {
      final next = i + 1 < index.blocks.length ? index.blocks[i + 1] : null;
      final end = next?.start ?? text.length;
      final gap = text.substring(block.end, end);
      if (gap != '\n' &&
          gap != '\r\n' &&
          _paragraphBreakAt(block.end) == null) {
        continue;
      }
      if (componentStarts.contains(block.start)) {
        _spaceAfterComponents.add(block.start);
      } else if (next != null && componentStarts.contains(next.start)) {
        _spaceBeforeComponents.add(next.start);
      } else {
        continue;
      }
      _componentGapStarts.add(block.end);
    }
  }

  bool _isSingleLineBreak(TextRange range) =>
      range.end - range.start == (text.startsWith('\r\n', range.start) ? 2 : 1);

  bool _isListRow(ComposerBodyBlock block) =>
      block.kind == ComposerBlockKind.list ||
      block.kind == ComposerBlockKind.todo;

  ValueChanged<TextEditingValue>? onTodoChanged;
  String? _todoSource;
  List<ComposerTodo> _todos = const [];
  Set<String> _todoReferenceMarkers = const {};
  Set<String> get todoReferenceMarkers => _todoReferenceMarkers;
  set todoReferenceMarkers(Set<String> value) {
    if (setEquals(_todoReferenceMarkers, value)) return;
    _todoReferenceMarkers = value;
    _todoSource = null;
    _syntaxScanned = null;
    _cachedSpan = null;
  }

  List<ComposerTodo> get todos {
    if (!enableTodos) return const [];
    if (_todoSource != text) {
      _todoSource = text;
      _todos = List.unmodifiable(
        composerTodos(
          text,
          codeRanges: _codeRangesFor(text),
          referenceMarkers: todoReferenceMarkers,
        ),
      );
    }
    return _todos;
  }

  bool _todosReadOnly = false;
  bool _completedProse = false;
  set completedProse(bool value) {
    if (_completedProse == value) return;
    _completedProse = value;
    _cachedSpan = null;
  }

  set todosReadOnly(bool value) {
    if (_todosReadOnly == value) return;
    _todosReadOnly = value;
    _cachedSpan = null;
  }

  final SyntaxHighlightBatcher _backgroundSyntaxHighlighter;

  void updateMarkdownLinkify({
    required bool enabled,
    required List<String> tlds,
  }) {
    if (enableMarkdownLinkify == enabled &&
        listEquals(_markdownLinkifyTlds, tlds)) {
      return;
    }
    enableMarkdownLinkify = enabled;
    _markdownLinkifyTlds = List.unmodifiable(tlds);
    _syntaxScanned = null;
    _cachedSpan = null;
    artworkArrived();
  }

  String? _imageScanned;
  List<ComposerImageBlock> _imageBlocks = const [];
  Set<int> _collapsedImageStarts = const {};
  ComposerImageBlock? _caretSuppressedImage;
  Object? _keyboardSelectedProjection;
  String? _keyboardSelectionDocument;
  Object? _boundaryCaretProjection;
  int? _boundaryCaretOffset;
  final Map<int, GlobalKey> _imageKeys = {};
  final Map<String, String> _imageUrls = {};
  final Set<String> _resolvingImageUrls = {};
  final Set<String> _failedImageUrls = {};
  final Map<String, Size> _naturalImageSizes = {};
  ScrollController? _imageScrollController;
  ScrollController? get imageScrollController => _imageScrollController;

  ValueChanged<ComposerImageGalleryBlock>? onEditImageGallery;

  void Function(ComposerImageGalleryBlock, ComposerImageBlock, int)?
  onReorderImageGallery;

  String? _galleryScanned;
  List<ComposerImageGalleryBlock> _galleryBlocks = const [];
  Set<int> _collapsedGalleryStarts = const {};
  ComposerImageGalleryBlock? _caretSuppressedGallery;
  ComposerImageBlock? _draggedGalleryImage;
  final Map<int, GlobalKey> _galleryKeys = {};

  @override
  set value(TextEditingValue newValue) {
    if (rawMarkdown) {
      super.value = newValue;
      return;
    }
    final current = super.value;
    if (protectComponentSource &&
        newValue.text == current.text &&
        newValue.isComposingRangeValid &&
        !newValue.composing.isCollapsed) {
      final composing = newValue.composing;
      final ranges = [
        for (final block in syntaxBlocks)
          if (block.projection is! ComposerParagraphSpacingProjection)
            (block.start, block.end),
        for (final block in quoteBlocks) (block.start, block.end),
        for (final block in galleryBlocks) (block.start, block.end),
        for (final block in imageBlocks) (block.start, block.end),
      ];
      if (ranges.any(
        (range) => composing.start < range.$2 && composing.end > range.$1,
      )) {
        newValue = newValue.copyWith(composing: TextRange.empty);
      }
    }
    if (current.text.contains('<')) {
      newValue = normalizeComposerTagEdit(
        current,
        newValue,
        _runsFor(current.text),
      );
    }
    if (current.selection.isValid &&
        current.selection.isCollapsed &&
        newValue.selection.isCollapsed &&
        current.composing.isCollapsed &&
        newValue.composing.isCollapsed &&
        current.text.length > newValue.text.length) {
      final caret = current.selection.extentOffset;
      final removedLength = current.text.length - newValue.text.length;
      for (final separator in blockSeparators) {
        final deleted = caret == separator.end
            ? caret - removedLength
            : caret == separator.start
            ? caret
            : -1;
        if (deleted >= separator.start &&
            deleted + removedLength <= separator.end &&
            newValue.text ==
                current.text.replaceRange(
                  deleted,
                  deleted + removedLength,
                  '',
                )) {
          newValue = newValue.copyWith(
            text: current.text.replaceRange(separator.start, separator.end, ''),
            selection: TextSelection.collapsed(offset: separator.start),
          );
          break;
        }
      }
    }
    if (newValue.text == current.text &&
        newValue.selection.isValid &&
        newValue.selection.isCollapsed &&
        newValue.composing.isCollapsed) {
      final offset = newValue.selection.extentOffset;
      for (final separator in blockGaps) {
        final gapWraps =
            _isSingleLineBreak(separator) &&
            !_componentGapStarts.contains(separator.start);
        if (offset > separator.start && offset < separator.end) {
          final before = offset < current.selection.extentOffset;
          newValue = newValue.copyWith(
            selection: TextSelection.collapsed(
              offset: before ? separator.start : separator.end,
              affinity: before && gapWraps
                  ? TextAffinity.upstream
                  : TextAffinity.downstream,
            ),
          );
          break;
        }
        if (offset == separator.start && gapWraps) {
          newValue = newValue.copyWith(
            selection: TextSelection.collapsed(
              offset: offset,
              affinity: TextAffinity.upstream,
            ),
          );
          break;
        }
      }
    }
    // Desktop text fields update selection on pointer-down, before an
    // embedded editor can win the gesture. Its click must not select the
    // enclosing document's hidden source or activate a whole block.
    if (_preserveSyntaxPointerSelection && newValue.text == current.text) {
      return;
    }
    if (newValue.text == current.text &&
        newValue.selection.isValid &&
        newValue.composing.isCollapsed) {
      newValue = _normalizeAtomicSelection(newValue);
    }
    if (newValue.text != current.text ||
        !newValue.selection.isCollapsed ||
        newValue.selection.extentOffset != _boundaryCaretOffset) {
      if (_boundaryCaretProjection != null) _cachedSpan = null;
      _boundaryCaretProjection = null;
      _boundaryCaretOffset = null;
    }
    final wasSelectedBlock =
        _keyboardSelectedProjection != null && !current.selection.isCollapsed;
    if (newValue.text != current.text) {
      _keyboardSelectedProjection = null;
      _keyboardSelectionDocument = null;
      if (_caretSuppressedSyntax case final syntax?) {
        if (!_stillContainsSyntax(newValue.text, syntax)) {
          _caretSuppressedSyntax = null;
          _preserveSyntaxPointerSelection = false;
        }
      }
    } else if (_keyboardSelectedProjection != null &&
        _keyboardSelectionDocument == current.text) {
      newValue = current;
    } else if (_caretSuppressedSyntax case final syntax?
        when syntax.projection.protectsAdjacentDelete &&
            _stillContainsSyntax(current.text, syntax) &&
            syntax.projection.needsRawSource(
              newValue,
              suppressCollapsedCaret: false,
            )) {
      // EditableText turns consecutive clicks into word and paragraph ranges
      // on pointer-down. Keep that transient native selection out of the
      // collapsed projection.
      newValue = newValue.copyWith(
        selection: TextSelection.collapsed(
          offset: syntax.projection.caretAfter(current.text),
        ),
        composing: TextRange.empty,
      );
    }
    // A block's first source position paints in front of its widget, not in
    // an editable paragraph. Select its complete range unless a keyboard
    // command explicitly placed a boundary caret there. Retain selection when
    // an upload slot is replaced by its finished component.
    if (_keyboardSelectedProjection == null &&
        _boundaryCaretProjection == null &&
        newValue.selection.isValid &&
        (newValue.selection.isCollapsed ||
            (newValue.text != current.text && wasSelectedBlock)) &&
        newValue.composing.isCollapsed) {
      final block = _blockStartingAt(
        newValue.copyWith(
          selection: TextSelection.collapsed(offset: newValue.selection.start),
        ),
      );
      if (block != null) {
        final (start, end) = _blockRange(block);
        if (newValue.selection.isCollapsed || newValue.selection.end == end) {
          _keyboardSelectedProjection = block;
          _keyboardSelectionDocument = newValue.text;
          newValue = newValue.copyWith(
            selection: TextSelection(baseOffset: start, extentOffset: end),
          );
        }
      }
    }
    super.value = newValue;
  }

  TextEditingValue _normalizeAtomicSelection(TextEditingValue document) {
    var selection = document.selection;
    for (final block in _syntaxBlocksFor(document.text)) {
      final atomic = block.projection is ComposerAtomicSelectionProjection;
      if (block.projection is ComposerParagraphSpacingProjection) continue;
      final needsRawSource = block.projection.needsRawSource(
        document,
        suppressCollapsedCaret: false,
      );
      if (atomic
          ? !protectComponentSource && needsRawSource
          : !protectComponentSource || !needsRawSource) {
        continue;
      }
      bool inside(int offset) => offset > block.start && offset < block.end;
      // Only the nested editor can edit this source. Native arrows and drag
      // selection must not strand a caret or a range inside hidden Markdown.
      if (selection.isCollapsed) {
        if (inside(selection.extentOffset)) {
          selection = TextSelection.collapsed(
            offset:
                !atomic &&
                    selection.extentOffset - block.start >
                        block.end - selection.extentOffset
                ? componentContentEnd(block)
                : block.start,
          );
          break;
        }
      } else if (atomic) {
        final forward = selection.baseOffset < selection.extentOffset;
        selection = selection.copyWith(
          baseOffset: inside(selection.baseOffset)
              ? (forward ? block.start : block.end)
              : selection.baseOffset,
          extentOffset: inside(selection.extentOffset)
              ? (forward ? block.end : block.start)
              : selection.extentOffset,
        );
      }
    }
    return document.copyWith(selection: selection);
  }

  bool _isSyntaxHighlighted(ComposerSyntaxOccurrence block) =>
      isPillSelectedForKeyboard(block) ||
      (block.projection is ComposerAtomicSelectionProjection &&
          selection.isValid &&
          !selection.isCollapsed &&
          selection.start <= block.start &&
          selection.end >= block.end);

  Object? _blockStartingAt(TextEditingValue document) {
    final offset = document.selection.extentOffset;
    for (final syntax in _syntaxBlocksFor(document.text)) {
      if (syntax.start > offset) break;
      if (syntax.start <= offset &&
          offset < syntax.end &&
          syntax.projection is ComposerBlockSyntaxProjection) {
        return syntax.start == offset &&
                !syntax.projection.needsRawSource(
                  document,
                  suppressCollapsedCaret: false,
                )
            ? syntax
            : null;
      }
    }
    for (final quote in _quoteBlocksFor(document.text)) {
      if (quote.start <= offset && offset < quote.end) {
        return quote.start == offset ? quote : null;
      }
    }
    for (final gallery in _galleryBlocksFor(document.text)) {
      if (gallery.start <= offset && offset < gallery.end) {
        return gallery.start == offset ? gallery : null;
      }
    }
    for (final image in _imageBlocksFor(document.text)) {
      if (image.start == offset) return image;
    }
    return null;
  }

  static (int, int) _blockRange(Object block) => switch (block) {
    ComposerSyntaxOccurrence block => (block.start, block.end),
    ComposerQuoteBlock block => (block.start, block.end),
    ComposerImageGalleryBlock block => (block.start, block.end),
    ComposerImageBlock block => (block.start, block.end),
    _ => throw ArgumentError.value(block, 'block'),
  };

  /// Rendered components whose source must be edited as one unit.
  Iterable<Object> get collapsedComponents sync* {
    if (rawMarkdown) return;
    yield* syntaxBlocks.where(
      (block) =>
          block.projection is! ComposerParagraphSpacingProjection &&
          isSyntaxCollapsed(block),
    );
    yield* quoteBlocks.where(isQuoteCollapsed);
    yield* galleryBlocks.where(isGalleryCollapsed);
    yield* imageBlocks.where(isImageCollapsed);
  }

  /// The collapsed component separated from the caret by a structural gap.
  Object? get blockBeforeCaret {
    if (!selection.isValid ||
        !selection.isCollapsed ||
        (!protectComponentSource && !value.composing.isCollapsed) ||
        keyboardSelectedProjection != null) {
      return null;
    }
    final caret = selection.extentOffset;
    final candidates = <Object>[
      ...syntaxBlocks.where(
        (block) =>
            block.projection is ComposerBlockSyntaxProjection &&
            isSyntaxCollapsed(block),
      ),
      ...quoteBlocks.where(isQuoteCollapsed),
      ...galleryBlocks.where(isGalleryCollapsed),
      ...imageBlocks.where(isImageCollapsed),
    ];
    for (final block in candidates) {
      final (start, end) = _blockRange(block);
      var contentEnd = end;
      while (contentEnd > start &&
          (text[contentEnd - 1] == '\n' || text[contentEnd - 1] == '\r')) {
        contentEnd--;
      }
      if (caret <= contentEnd) continue;
      final gap = text.substring(contentEnd, caret);
      final isBlockGap = blockGaps.any(
        (range) => range.start == contentEnd && range.end == caret,
      );
      if (gap.isNotEmpty &&
          gap != '\n' &&
          gap != '\r\n' &&
          !isBlockGap &&
          !(caret == end && gap.trim().isEmpty)) {
        continue;
      }
      return block;
    }
    return null;
  }

  /// Removes the line after a collapsed component and selects it for deletion.
  bool selectBlockBeforeCaret() {
    final block = blockBeforeCaret;
    if (block == null) return false;
    final caret = selection.extentOffset;
    final (start, end) = _blockRange(block);
    var contentEnd = end;
    while (contentEnd > start &&
        (text[contentEnd - 1] == '\n' || text[contentEnd - 1] == '\r')) {
      contentEnd--;
    }
    final gap = text.substring(contentEnd, caret);
    final isBlockGap = blockGaps.any(
      (range) => range.start == contentEnd && range.end == caret,
    );
    // Selecting the leading boundary resolves the component again after the
    // edit, so projections whose range includes a newline stay up to date.
    final lineIsEmpty =
        caret == text.length || text[caret] == '\n' || text[caret] == '\r';
    value = TextEditingValue(
      text: lineIsEmpty && gap.isNotEmpty
          ? text.replaceRange(
              isBlockGap ? contentEnd : caret - (gap.endsWith('\r\n') ? 2 : 1),
              caret,
              '',
            )
          : text,
      selection: TextSelection.collapsed(offset: start),
    );
    return true;
  }

  /// A caret explicitly placed beside a component, on its rendered line.
  Object? get boundaryCaretProjection => _boundaryCaretProjection;

  void moveCaretBesideComponent(Object component, {required bool before}) {
    clearKeyboardPillSelection();
    _boundaryCaretProjection = component;
    _boundaryCaretOffset = before
        ? _blockRange(component).$1
        : componentContentEnd(component);
    _cachedSpan = null;
    value = value.copyWith(
      selection: TextSelection.collapsed(offset: _boundaryCaretOffset!),
      composing: TextRange.empty,
    );
  }

  /// The boundary after the component, excluding consumed line separators.
  int componentContentEnd(Object component) {
    final (start, end) = _blockRange(component);
    return start + text.substring(start, end).trimRight().length;
  }

  /// The preceding ordinary text position, skipping a complete grapheme.
  int caretBeforeBlock(int start) {
    final offset = start.clamp(0, text.length);
    if (offset == 0) return 0;
    return offset - text.substring(0, offset).characters.last.length;
  }

  set imageScrollController(ScrollController? value) {
    if (identical(_imageScrollController, value)) return;
    _imageScrollController = value;
    artworkArrived();
  }

  Rect _editorPaintRect(RenderBox renderObject) {
    final scroll = _imageScrollController;
    final scrollOffset = scroll != null && scroll.hasClients
        ? scroll.offset
        : 0.0;
    // RenderEditable applies its viewport offset while painting inline
    // children, but omits it from their local-to-global transform. Account for
    // that difference only when querying projected-component geometry; moving
    // the child itself would apply the scroll twice on screen.
    // WidgetSpan scales the entire component. Transform both corners so its
    // hit targets and block bounds include the scaled width and height.
    return Rect.fromPoints(
      renderObject.localToGlobal(Offset.zero),
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero)),
    ).shift(Offset(0, -scrollOffset));
  }

  List<ComposerImageBlock> get imageBlocks =>
      List.unmodifiable(_imageBlocksFor(text));

  ComposerImageBlock? imageAtOffset(int offset) =>
      imageAtComposerOffset(_imageBlocksFor(text), offset);

  List<ComposerImageGalleryBlock> get galleryBlocks =>
      List.unmodifiable(_galleryBlocksFor(text));

  ComposerImageGalleryBlock? galleryAtOffset(int offset) =>
      galleryAtComposerOffset(_galleryBlocksFor(text), offset);

  bool isGalleryCollapsed(ComposerImageGalleryBlock gallery) =>
      _collapsedGalleryStarts.contains(gallery.start);

  bool isImageCollapsed(ComposerImageBlock image) =>
      _collapsedImageStarts.contains(image.start);

  ComposerImageBlock? get keyboardSelectedImage =>
      _keyboardSelectionDocument == text &&
          _keyboardSelectedProjection is ComposerImageBlock
      ? _keyboardSelectedProjection as ComposerImageBlock
      : null;

  ComposerSyntaxOccurrence? get keyboardSelectedSyntax =>
      _keyboardSelectionDocument == text &&
          _keyboardSelectedProjection is ComposerSyntaxOccurrence
      ? _keyboardSelectedProjection as ComposerSyntaxOccurrence
      : null;

  Object? get keyboardSelectedProjection =>
      _keyboardSelectionDocument == text ? _keyboardSelectedProjection : null;

  /// A whole component uses its own border instead of the document range fill.
  bool get selectionHasComponentOutline =>
      keyboardSelectedProjection != null ||
      (!rawMarkdown &&
          selection.isValid &&
          !selection.isCollapsed &&
          syntaxBlocks.any(
            (block) =>
                block.projection is ComposerAtomicSelectionProjection &&
                isSyntaxCollapsed(block) &&
                selection.start == block.start &&
                selection.end == block.end,
          ));

  bool get selectedProjectionHidesCursor =>
      _caretSuppressedImage != null ||
      _caretSuppressedGallery != null ||
      keyboardSelectedProjection != null;

  void selectPillForKeyboard(Object projection) {
    if (rawMarkdown) return;
    if (projection is! ComposerImageBlock &&
        projection is! ComposerSyntaxOccurrence &&
        projection is! ComposerQuoteBlock &&
        projection is! ComposerImageGalleryBlock) {
      for (final occurrence in _syntaxBlocksFor(text)) {
        if (identical(occurrence.projection, projection) ||
            occurrence.projection == projection) {
          projection = occurrence;
          break;
        }
      }
    }
    if (projection is! ComposerImageBlock &&
        projection is! ComposerSyntaxOccurrence &&
        projection is! ComposerQuoteBlock &&
        projection is! ComposerImageGalleryBlock) {
      throw ArgumentError.value(projection, 'projection');
    }
    if (_keyboardSelectionDocument == text &&
        _sameProjection(_keyboardSelectedProjection, projection)) {
      return;
    }
    _boundaryCaretProjection = null;
    _boundaryCaretOffset = null;
    _keyboardSelectedProjection = projection;
    _keyboardSelectionDocument = text;
    artworkArrived();
  }

  void clearKeyboardPillSelection() {
    if (_keyboardSelectedProjection == null) return;
    _keyboardSelectedProjection = null;
    _keyboardSelectionDocument = null;
    artworkArrived();
  }

  bool isPillSelectedForKeyboard(Object projection) =>
      _keyboardSelectionDocument == text &&
      _sameProjection(_keyboardSelectedProjection, projection);

  void keepImageCollapsedForPointerEdit(ComposerImageBlock image) {
    if (_sameProjection(_caretSuppressedImage, image)) return;
    _caretSuppressedImage = image;
    artworkArrived();
  }

  void releaseImagePointerEdit(ComposerImageBlock image) {
    if (!_sameProjection(_caretSuppressedImage, image)) return;
    _caretSuppressedImage = null;
    artworkArrived();
  }

  void keepGalleryCollapsedForPointerEdit(ComposerImageGalleryBlock gallery) {
    if (_sameProjection(_caretSuppressedGallery, gallery)) return;
    _caretSuppressedGallery = gallery;
    artworkArrived();
  }

  void releaseGalleryPointerEdit(ComposerImageGalleryBlock gallery) {
    if (!_sameProjection(_caretSuppressedGallery, gallery)) return;
    _caretSuppressedGallery = null;
    artworkArrived();
  }

  ComposerImageBlock? collapsedImageAtOffset(int offset) {
    final image = imageAtOffset(offset);
    if (image == null ||
        offset <= image.start ||
        offset >= image.end ||
        !isImageCollapsed(image)) {
      return null;
    }
    return image;
  }

  ComposerImageBlock? collapsedImageAtGlobalPosition(Offset globalPosition) {
    for (final image in _imageBlocksFor(text)) {
      if (!isImageCollapsed(image)) continue;
      final rect = collapsedImageGlobalRect(image);
      if (rect?.contains(globalPosition) == true) return image;
    }
    return null;
  }

  Rect? collapsedImageGlobalRect(ComposerImageBlock image) {
    if (!isImageCollapsed(image)) return null;
    final renderObject = _imageKeys[image.start]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return _editorPaintRect(renderObject);
  }

  ComposerImageGalleryBlock? collapsedGalleryAtGlobalPosition(
    Offset globalPosition,
  ) {
    for (final gallery in _galleryBlocksFor(text)) {
      if (!isGalleryCollapsed(gallery)) continue;
      final rect = collapsedGalleryGlobalRect(gallery);
      if (rect?.contains(globalPosition) == true) return gallery;
    }
    return null;
  }

  Rect? collapsedGalleryGlobalRect(ComposerImageGalleryBlock gallery) {
    if (!isGalleryCollapsed(gallery)) return null;
    final renderObject = _galleryKeys[gallery.start]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return _editorPaintRect(renderObject);
  }

  void cacheImageUrl(String shortUrl, String url) {
    if (_imageUrls[shortUrl] == url) return;
    _imageUrls[shortUrl] = url;
    _failedImageUrls.remove(shortUrl);
    artworkArrived();
  }

  String? resolvedUploadUrl(String url) =>
      url.startsWith('upload://') ? _imageUrls[url] : url;

  String? resolvedImageUrl(ComposerImageBlock image) =>
      resolvedUploadUrl(image.url);

  Size? naturalImageSize(ComposerImageBlock image) =>
      _naturalImageSizes[image.url];

  List<ComposerImageBlock> _imageBlocksFor(String source) {
    if (_imageScanned == source) return _imageBlocks;
    _imageScanned = source;
    final blocks = parseComposerImages(
      source,
      codeRanges: _codeRangesFor(source),
    );
    _retainPillKeys(_imageKeys, _imageBlocks, blocks, (block) => block.start);
    return _imageBlocks = blocks;
  }

  List<ComposerImageGalleryBlock> _galleryBlocksFor(String source) {
    if (!enableImageGalleries) return const [];
    if (_galleryScanned == source) return _galleryBlocks;
    _galleryScanned = source;
    final parsed = parseComposerImageGalleries(
      source,
      codeRanges: _codeRangesFor(source),
    );
    // The gallery parser is deliberately standalone and therefore discovers
    // its own image objects. Canonicalise those members to this controller's
    // image scan so every public lookup, keyboard selection, and tile hit-test
    // returns the same [ComposerImageBlock] instance.
    final imagesByRange = {
      for (final image in _imageBlocksFor(source))
        (image.start, image.end): image,
    };
    final blocks = [
      for (final gallery in parsed)
        ComposerImageGalleryBlock(
          start: gallery.start,
          end: gallery.end,
          contentStart: gallery.contentStart,
          contentEnd: gallery.contentEnd,
          source: gallery.source,
          mode: gallery.mode,
          images: List.unmodifiable([
            for (final image in gallery.images)
              imagesByRange[(image.start, image.end)] ?? image,
          ]),
        ),
    ];
    _retainPillKeys(
      _galleryKeys,
      _galleryBlocks,
      blocks,
      (block) => block.start,
    );
    return _galleryBlocks = blocks;
  }

  String? _syntaxScanned;
  List<ComposerSyntaxOccurrence> _syntaxBlocks = const [];
  Set<String> _collapsedSyntaxKeys = const {};
  ComposerSyntaxOccurrence? _caretSuppressedSyntax;
  bool _preserveSyntaxPointerSelection = false;
  String? _hoveredSyntaxKey;
  final Map<String, GlobalKey> _syntaxPillKeys = {};

  List<ComposerSyntaxOccurrence> get syntaxBlocks =>
      List.unmodifiable(_syntaxBlocksFor(text));

  List<TextInputFormatter> get syntaxInputFormatters {
    final formatters = <TextInputFormatter>[];
    for (final policy in syntaxPolicies) {
      final formatter = policy.inputFormatter;
      if (formatter != null) formatters.add(formatter);
    }
    return formatters;
  }

  ComposerSyntaxOccurrence? syntaxAtOffset(int offset) {
    for (final block in _syntaxBlocksFor(text)) {
      if (offset >= block.start && offset < block.end) return block;
    }
    return null;
  }

  bool isSyntaxCollapsed(ComposerSyntaxOccurrence block) =>
      _collapsedSyntaxKeys.contains(_syntaxKey(block));

  bool isSyntaxHovered(ComposerSyntaxOccurrence block) =>
      _hoveredSyntaxKey == _syntaxKey(block);

  void updateSyntaxHoverAtGlobalPosition(Offset? globalPosition) {
    final hovered = globalPosition == null
        ? null
        : collapsedSyntaxAtGlobalPosition(globalPosition);
    final key = hovered == null ? null : _syntaxKey(hovered);
    if (_hoveredSyntaxKey == key) return;
    _hoveredSyntaxKey = key;
    artworkArrived();
  }

  int syntaxCaretAfter(ComposerSyntaxOccurrence block) =>
      block.projection.caretAfter(text);

  void keepSyntaxCollapsedForPointerEdit(
    ComposerSyntaxOccurrence block, {
    bool preserveSelection = false,
  }) {
    _preserveSyntaxPointerSelection = preserveSelection;
    if (_sameProjection(_caretSuppressedSyntax, block)) return;
    _caretSuppressedSyntax = block;
    artworkArrived();
  }

  void releaseSyntaxPointerEdit(ComposerSyntaxOccurrence block) {
    if (!_sameProjection(_caretSuppressedSyntax, block)) return;
    _preserveSyntaxPointerSelection = false;
    _caretSuppressedSyntax = null;
    artworkArrived();
  }

  ComposerSyntaxOccurrence? collapsedSyntaxAtOffset(int offset) {
    final block = syntaxAtOffset(offset);
    return block != null && offset > block.start && isSyntaxCollapsed(block)
        ? block
        : null;
  }

  ComposerSyntaxOccurrence? collapsedSyntaxAtGlobalPosition(
    Offset globalPosition,
  ) {
    for (final block in _syntaxBlocksFor(text)) {
      if (!isSyntaxCollapsed(block)) continue;
      final rect = collapsedSyntaxGlobalRect(block);
      if (rect?.contains(globalPosition) == true) return block;
    }
    return null;
  }

  ComposerSyntaxOccurrence? collapsedBlockSyntaxBeforeGlobalPosition(
    Offset globalPosition, {
    int? sourceOffset,
  }) {
    for (final block in _syntaxBlocksFor(text)) {
      if (!block.projection.protectsAdjacentDelete ||
          !isSyntaxCollapsed(block)) {
        continue;
      }
      final rect = collapsedSyntaxGlobalRect(block);
      if (rect != null &&
          ((globalPosition.dx >= rect.right &&
                  globalPosition.dy >= rect.top &&
                  globalPosition.dy < rect.bottom) ||
              // The structural gap below a component is padding inside its
              // placeholder, so a point there resolves to the block's start.
              (globalPosition.dy >= rect.bottom &&
                  sourceOffset != null &&
                  sourceOffset >= block.start &&
                  sourceOffset <= block.end))) {
        return block;
      }
    }
    return null;
  }

  Rect? collapsedSyntaxGlobalRect(ComposerSyntaxOccurrence block) {
    if (!isSyntaxCollapsed(block)) return null;
    final renderObject = _syntaxPillKeys[_syntaxKey(block)]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return _editorPaintRect(renderObject);
  }

  List<ComposerSyntaxOccurrence> _syntaxBlocksFor(String source) {
    if (_syntaxScanned == source) return _syntaxBlocks;
    final linkPolicy = ComposerLinkSyntaxPolicy(
      enableLinkify: enableMarkdownLinkify,
      linkifyTlds: _markdownLinkifyTlds,
    );
    final blocks = <ComposerSyntaxOccurrence>[
      for (final projection in linkPolicy.parseWithCodeRanges(
        source,
        _codeRangesFor(source),
      ))
        ComposerSyntaxOccurrence(linkPolicy, projection),
      for (final policy in syntaxPolicies)
        for (final projection in policy.parse(source))
          ComposerSyntaxOccurrence(policy, projection),
    ];
    blocks.sort((a, b) {
      final position = a.start.compareTo(b.start);
      return position != 0 ? position : b.end.compareTo(a.end);
    });
    // An embedded editor owns the complete block, including links and other
    // recognized syntax inside its cells. Do not expose those as separate
    // keyboard or pointer targets behind the table.
    int? interactiveEnd;
    blocks.removeWhere((block) {
      if (interactiveEnd != null && block.start < interactiveEnd!) return true;
      interactiveEnd = block.projection is ComposerInteractiveSyntaxProjection
          ? block.end
          : null;
      return false;
    });
    final live = {for (final block in blocks) _syntaxKey(block): block};
    final previous = _syntaxScanned;
    final delta = previous == null ? 0 : source.length - previous.length;
    var unchangedTail = 0;
    if (previous != null && delta != 0) {
      while (unchangedTail < previous.length &&
          unchangedTail < source.length &&
          previous[previous.length - unchangedTail - 1] ==
              source[source.length - unchangedTail - 1]) {
        unchangedTail++;
      }
    }
    final tailStart = (previous?.length ?? source.length) - unchangedTail;
    final retained = <String, GlobalKey>{};
    for (final held in _syntaxBlocks) {
      final oldKey = _syntaxKey(held);
      // A wider task marker must not recreate editors later in the document.
      // Reuse their keys in the unchanged suffix, including during undo/redo.
      final key = held.start >= tailStart
          ? '${held.kind.id}:${held.start + delta}'
          : oldKey;
      final next = live[key];
      if (_sameProjection(held, next) ||
          (held.projection is ComposerInteractiveSyntaxProjection &&
              next?.projection is ComposerInteractiveSyntaxProjection &&
              (key == oldKey || held.source == next?.source))) {
        if (_syntaxPillKeys[oldKey] case final pillKey?) {
          retained[key] = pillKey;
        }
      }
    }
    _syntaxPillKeys
      ..clear()
      ..addAll(retained);
    _syntaxScanned = source;
    return _syntaxBlocks = blocks;
  }

  static String _syntaxKey(ComposerSyntaxOccurrence block) =>
      '${block.kind.id}:${block.start}';

  String? _quoteScanned;
  List<ComposerQuoteBlock> _quoteBlocks = const [];
  Set<int> _collapsedQuoteStarts = const {};
  final Map<int, GlobalKey> _quoteKeys = {};
  final Map<int, GlobalKey> _quoteRemoveKeys = {};
  final Map<int, String> _displayedQuoteContents = {};

  void configureQuoteContentsResolver(
    ComposerQuoteContentsResolver? resolver, {
    required Object? context,
  }) {
    if (_quoteContentsResolverContext == context) return;
    _quoteContentsResolver = resolver;
    _quoteContentsResolverContext = context;
    _displayedQuoteContents.clear();
    _cachedSpan = null;
  }

  List<ComposerQuoteBlock> get quoteBlocks =>
      List.unmodifiable(_quoteBlocksFor(text));

  ComposerQuoteBlock? quoteAtOffset(int offset) =>
      quoteAtComposerOffset(_quoteBlocksFor(text), offset);

  bool isQuoteCollapsed(ComposerQuoteBlock block) =>
      _collapsedQuoteStarts.contains(block.start);

  ComposerQuoteBlock? collapsedQuoteAtGlobalPosition(Offset globalPosition) {
    for (final block in _quoteBlocksFor(text)) {
      if (!isQuoteCollapsed(block)) continue;
      final rect = collapsedQuoteGlobalRect(block);
      if (rect?.contains(globalPosition) == true) return block;
    }
    return null;
  }

  bool isQuoteRemoveAtGlobalPosition(
    ComposerQuoteBlock block,
    Offset globalPosition,
  ) {
    if (!isQuoteCollapsed(block)) return false;
    final renderObject = _quoteRemoveKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final rect = _editorPaintRect(renderObject);
    return rect.contains(globalPosition);
  }

  Rect? collapsedQuoteGlobalRect(ComposerQuoteBlock block) {
    if (!isQuoteCollapsed(block)) return null;
    final renderObject = _quoteKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return _editorPaintRect(renderObject);
  }

  TextSelection protectQuoteSelection(
    TextSelection selection,
    TextSelection previous,
  ) => quoteSafeSelection(_quoteBlocksFor(text), selection, previous);

  List<ComposerQuoteBlock> _quoteBlocksFor(String source) {
    if (_quoteScanned == source) return _quoteBlocks;
    _quoteScanned = source;
    final blocks = parseComposerQuotes(
      source,
      knownCodeRanges: _codeRangesFor(source),
    );
    _retainPillKeys(_quoteKeys, _quoteBlocks, blocks, (block) => block.start);
    _retainPillKeys(
      _quoteRemoveKeys,
      _quoteBlocks,
      blocks,
      (block) => block.start,
    );
    // Cleared rather than retained: this holds what a resolver said about the
    // block that *was* at each offset, and a quote whose contents changed
    // under a start that did not is exactly what it must not answer for.
    _displayedQuoteContents.clear();
    return _quoteBlocks = blocks;
  }

  String _displayedContentsFor(ComposerQuoteBlock block) =>
      _displayedQuoteContents.putIfAbsent(
        block.start,
        () =>
            _quoteContentsResolver?.call(block) ??
            formatQuoteContents?.call(block) ??
            block.contents,
      );

  int _artwork = 0;

  final Set<String> _loadingEmoji = {};

  String? _renderedEmojiDocument;
  Set<TextRange> _renderedEmojiRanges = const {};

  TextRange? renderedEmojiEndingAt(int offset) =>
      _renderedEmojiAt(offset, endsAt: true);

  TextRange? renderedEmojiStartingAt(int offset) =>
      _renderedEmojiAt(offset, endsAt: false);

  TextRange? _renderedEmojiAt(int offset, {required bool endsAt}) {
    if (_renderedEmojiDocument != text) return null;
    for (final range in _renderedEmojiRanges) {
      if ((endsAt ? range.end : range.start) == offset) return range;
    }
    return null;
  }

  bool _disposed = false;

  List<MarkdownRun>? _runs;
  String? _scanned;

  _CachedMarkdownSpan? _cachedSpan;

  @visibleForTesting
  int scans = 0;

  @visibleForTesting
  static const Duration fenceHighlightDebounce = Duration(milliseconds: 200);

  Timer? _fenceHighlightTimer;
  List<({String body, String? language})> _pendingFences = const [];
  int _fenceHighlightGeneration = 0;

  String? _parsedFenceSource;
  final Set<({String body, String? language})> _parsedFences = {};

  String? _codeRangesScanned;
  CodeRanges _codeRanges = CodeRanges.none;

  final Map<int, GlobalKey> _mentionPillKeys = {};

  bool isMentionPillAtGlobalPosition(Offset globalPosition) {
    for (final key in _mentionPillKeys.values) {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final rect = _editorPaintRect(renderObject);
      if (rect.contains(globalPosition)) return true;
    }
    return false;
  }

  CodeRanges _codeRangesFor(String source) {
    if (_codeRangesScanned == source) return _codeRanges;
    _codeRangesScanned = source;
    return _codeRanges = CodeRanges.of(_runsFor(source));
  }

  List<MarkdownRun> _runsFor(String source) {
    if (_scanned == source) return _runs!;
    scans++;
    _scanned = source;
    final deferred = <({String body, String? language})>[];
    final runs = scanMarkdown(
      source,
      deferHighlight: (body, language) =>
          deferred.add((body: body, language: language)),
    );
    final mentionStarts = {
      for (final run in runs)
        if (run.has(Md.mention)) run.start,
    };
    _mentionPillKeys.removeWhere((start, _) => !mentionStarts.contains(start));
    _scheduleFenceHighlight(source, deferred);
    return _runs = runs;
  }

  void _scheduleFenceHighlight(
    String source,
    List<({String body, String? language})> fences,
  ) {
    _fenceHighlightTimer?.cancel();
    _fenceHighlightTimer = null;
    final generation = ++_fenceHighlightGeneration;
    if (_parsedFenceSource != source) {
      _parsedFenceSource = source;
      _parsedFences.clear();
    }
    // Replaced wholesale on every scan, so a fence edited away mid-debounce is
    // never parsed on its way out.
    _pendingFences = [
      for (final fence in fences)
        if (!_parsedFences.contains(fence)) fence,
    ];
    if (_pendingFences.isEmpty) return;
    _fenceHighlightTimer = Timer(fenceHighlightDebounce, () {
      _fenceHighlightTimer = null;
      if (!_isCurrentFenceHighlight(source, generation)) return;

      final pendingFences = List.of(_pendingFences);
      final requests = <SyntaxHighlightRequest>{
        for (final fence in pendingFences)
          if (highlightNeedsParse(fence.body, fence.language))
            (source: fence.body, language: fence.language),
      }.toList(growable: false);
      unawaited(
        _highlightPendingFences(source, generation, pendingFences, requests),
      );
    });
  }

  Future<void> _highlightPendingFences(
    String source,
    int generation,
    List<({String body, String? language})> pendingFences,
    List<SyntaxHighlightRequest> requests,
  ) async {
    SyntaxHighlightBatch highlighted = const [];
    try {
      if (requests.isNotEmpty) {
        highlighted = await _backgroundSyntaxHighlighter(requests);
      }
    } catch (_) {
      // A worker failure leaves this generation plain, just like a grammar
      // failure. Do not make editing or future generations fail with it.
    }

    if (!_isCurrentFenceHighlight(source, generation)) return;
    if (highlighted.length == requests.length) {
      for (var index = 0; index < requests.length; index++) {
        final request = requests[index];
        cacheHighlightedLines(
          request.source,
          request.language,
          highlighted[index],
        );
      }
    }

    _parsedFences.addAll(pendingFences);
    _pendingFences = const [];
    _scanned = null;
    _runs = null;
    artworkArrived();
  }

  bool _isCurrentFenceHighlight(String source, int generation) =>
      !_disposed && text == source && generation == _fenceHighlightGeneration;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (rawMarkdown) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final source = value.text;
    if (source.isEmpty) {
      _renderedEmojiDocument = source;
      _renderedEmojiRanges = const {};
      _cachedSpan = null;
      // Match the neutral paragraph defaults below. The field's strut owns
      // leading, including while its Native placeholder is visible.
      return TextSpan(style: style?.copyWith(height: 1));
    }

    final theme = Theme.of(context);
    final base = style ?? const TextStyle();

    // The range an IME is still deciding about. Honoured rather than dropped:
    // without it a dead key on macOS and every CJK keystroke lose the underline
    // that says the character is not committed yet.
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : null;

    final runs = _runsFor(source);
    final todos = this.todos;

    final collapsedQuotes = _quoteBlocksFor(source);
    _collapsedQuoteStarts = {for (final block in collapsedQuotes) block.start};
    final quoteProjection = Object.hashAll(
      collapsedQuotes.map(
        (block) => Object.hash(
          block.start,
          block.end,
          block.title,
          _displayedContentsFor(block),
          isPillSelectedForKeyboard(block),
        ),
      ),
    );

    final locale = Localizations.localeOf(context);
    final syntaxBlocks = _syntaxBlocksFor(source);
    final collapsedSyntax = [
      for (final block in syntaxBlocks)
        if ((protectComponentSource &&
                block.projection is! ComposerParagraphSpacingProjection) ||
            isPillSelectedForKeyboard(block) ||
            !block.projection.needsRawSource(
              value,
              suppressCollapsedCaret: _sameProjection(
                _caretSuppressedSyntax,
                block,
              ),
            ))
          block,
    ];
    _collapsedSyntaxKeys = {
      for (final block in collapsedSyntax) _syntaxKey(block),
    };
    if (!_collapsedSyntaxKeys.contains(_hoveredSyntaxKey)) {
      _hoveredSyntaxKey = null;
    }
    final syntaxProjection = Object.hash(
      locale,
      Object.hashAll(
        syntaxPolicies.map(
          (policy) => Object.hash(policy.kind, policy.projectionState),
        ),
      ),
      Object.hashAll(
        collapsedSyntax.map(
          (block) => Object.hash(
            block.kind,
            block.start,
            block.end,
            block.source,
            _isSyntaxHighlighted(block),
            isSyntaxHovered(block),
          ),
        ),
      ),
    );

    final galleries = _galleryBlocksFor(source);
    // Galleries are atomic editor components. Native drag selection can still
    // cross their source offsets, but it must never replace the component with
    // its implementation Markdown.
    final collapsedGalleries = galleries;
    _collapsedGalleryStarts = {
      for (final gallery in collapsedGalleries) gallery.start,
    };
    final galleryImageStarts = {
      for (final gallery in galleries)
        for (final image in gallery.images) image.start,
    };

    final images = _imageBlocksFor(source);
    final collapsedImages = [
      for (final image in images)
        if (!galleryImageStarts.contains(image.start) &&
            (protectComponentSource ||
                !_imageNeedsRawSource(
                  image,
                  value,
                  suppressCollapsedCaret: _sameProjection(
                    _caretSuppressedImage,
                    image,
                  ),
                )))
          image,
    ];
    _collapsedImageStarts = {
      for (final image in collapsedImages) image.start,
      for (final gallery in collapsedGalleries)
        for (final image in gallery.images) image.start,
    };
    final imageProjection = Object.hashAll(
      collapsedImages.map(
        (image) => Object.hash(
          image.start,
          image.end,
          image.alt,
          image.width,
          image.height,
          image.scale,
          resolvedImageUrl(image),
          isPillSelectedForKeyboard(image),
        ),
      ),
    );
    final galleryProjection = Object.hashAll(
      collapsedGalleries.map(
        (gallery) => Object.hash(
          gallery.start,
          gallery.end,
          gallery.mode,
          isPillSelectedForKeyboard(gallery),
          Object.hashAll(
            gallery.images.map(
              (image) => Object.hash(
                image.start,
                image.end,
                image.alt,
                image.width,
                image.height,
                resolvedImageUrl(image),
                isPillSelectedForKeyboard(image),
              ),
            ),
          ),
        ),
      ),
    );

    // Which token, if any, the caret is in — the one thing about the selection
    // that changes what is drawn. Summarised rather than keyed on the
    // selection itself, so the ordinary caret move still costs nothing.
    final revealed = _revealedPill(runs, value.selection);
    final collapsedKeys = [
      for (final key in composerKeyboardRuns(runs))
        if (!(selection.isValid &&
                selection.isCollapsed &&
                selection.start >= key.first.start &&
                selection.start <= key.last.end) &&
            (composing == null ||
                composing.end <= key.first.start ||
                composing.start >= key.last.end))
          key,
    ];
    final keyboardProjection = Object.hashAll(
      collapsedKeys.map((runs) => runs.first.start),
    );

    // Moving the caret changes none of the rest, and returning the *same* span
    // rather than an equal one is what makes that free: `RenderEditable`'s
    // `text` setter compares by identity first and skips the relayout.
    final cached = _cachedSpan;
    if (cached != null &&
        cached.matches(
          source: source,
          style: base,
          theme: theme,
          composing: composing,
          revealed: revealed,
          artwork: _artwork,
          quoteProjection: quoteProjection,
          syntaxProjection: syntaxProjection,
          imageProjection: imageProjection,
          galleryProjection: galleryProjection,
          keyboardProjection: keyboardProjection,
        )) {
      return cached.span;
    }

    // What a repaint found it could not draw yet, asked about once at the end
    // rather than once per run — a paragraph pasted with forty hashtags is one
    // request, not forty.
    final unresolvedRefs = <String>{};
    final unresolvedNames = <String>{};
    final unresolvedImages = <String>{};
    final renderedEmojiRanges = <TextRange>{};

    final children = <InlineSpan>[];
    final completedTodos = todos
        .where((todo) => todo.checked)
        .toList(growable: false);

    void appendStyledRun(MarkdownRun run, bool completed) {
      final runBase = completed
          ? base.copyWith(
              color: DTokens.of(context).mutedForeground,
              decoration: TextDecoration.lineThrough,
            )
          : base;
      if (run.has(Md.hiddenTag) && !_overlapsComposing(run, composing)) {
        children.add(
          TextSpan(
            text: source.substring(run.start, run.end),
            style: hiddenComposerTagStyle,
            semanticsLabel: '',
          ),
        );
        return;
      }
      // A run the IME is still deciding about is never substituted: the
      // artwork path skips [_splitAt] entirely, so a placeholder over a
      // composing range would take its underline away and paint the
      // uncommitted characters invisibly.
      final artwork =
          run.start == revealed || _overlapsComposing(run, composing)
          ? null
          : _artworkFor(run, runBase, theme, unresolvedRefs, unresolvedNames);
      if (artwork != null) {
        if (run.has(Md.emoji)) {
          renderedEmojiRanges.add(TextRange(start: run.start, end: run.end));
        }
        children.addAll(artwork);
        return;
      }
      for (final piece in _splitAt(run, composing)) {
        final text = source.substring(piece.start, piece.end);
        final style = _styleFor(piece, runBase, theme, composing);
        final scripts = composerScriptSpans(text, piece, style);
        if (scripts != null) {
          children.addAll(scripts);
          continue;
        }
        children.add(TextSpan(text: text, style: style));
      }
    }

    void appendRun(MarkdownRun run) {
      if (_completedProse && !run.has(Md.codeBlock)) {
        appendStyledRun(run, true);
        return;
      }
      if (completedTodos.isEmpty) {
        appendStyledRun(run, false);
        return;
      }
      final cuts = <int>{run.start, run.end};
      for (final todo in completedTodos) {
        if (todo.contentStart > run.start && todo.contentStart < run.end) {
          cuts.add(todo.contentStart);
        }
        if (todo.end > run.start && todo.end < run.end) cuts.add(todo.end);
      }
      final offsets = cuts.toList()..sort();
      for (var index = 0; index < offsets.length - 1; index++) {
        final start = offsets[index];
        final end = offsets[index + 1];
        final completed = completedTodos.any(
          (todo) => start >= todo.contentStart && end <= todo.end,
        );
        appendStyledRun(
          MarkdownRun(start, end, run.mask, run.detail, run.token),
          completed,
        );
      }
    }

    // Runs and projection gaps advance in source order. Keep a run until its
    // end so projections can split it without losing the remaining text.
    var runIndex = 0;
    void appendMarkdown(int start, int end) {
      if (start >= end) return;
      for (; runIndex < runs.length; runIndex++) {
        final run = runs[runIndex];
        if (run.end <= start) continue;
        if (run.start >= end) break;
        appendRun(
          MarkdownRun(
            run.start < start ? start : run.start,
            run.end > end ? end : run.end,
            run.mask,
            run.detail,
            run.token,
          ),
        );
        if (run.end > end) break;
      }
    }

    final linePainter = TextPainter(
      text: TextSpan(text: ' ', style: base),
      strutStyle: StrutStyle.fromTextStyle(base, forceStrutHeight: false),
      textDirection: Directionality.of(context),
    )..layout();
    final paragraphLine = linePainter.computeLineMetrics().single;
    final paragraphGap = paragraphLine.height * .5;
    // A top-aligned widget receives the strut's leading above its artwork.
    // Include that same leading below it so visible block edges stay even.
    final componentTrailingLeading = linePainter
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .single
        .top;
    linePainter.dispose();

    final projections = <_SpanProjection>[
      for (final key in collapsedKeys)
        _SpanProjection(
          key.first.start,
          key.last.end,
          () => composerKeyboardSpans(source, key, base, theme),
        ),
      for (final separator in blockGaps)
        if (composing == null ||
            composing.end <= separator.start ||
            composing.start >= separator.end)
          _SpanProjection(
            separator.start,
            separator.end,
            () => [
              if (_componentGapStarts.contains(separator.start)) ...[
                // The component's padding owns the gap. Keep one line break
                // and hide only the required blank line, preserving offsets
                // and any additional empty paragraphs.
                TextSpan(text: '\n', style: base),
                if (separator.end - separator.start > 1)
                  TextSpan(
                    text: '\u200b' * (separator.end - separator.start - 1),
                    style: _hidden,
                  ),
              ] else if (_isSingleLineBreak(separator)) ...[
                // A full-width, zero-height placeholder occupies one strut
                // line between blocks without adding characters to Markdown.
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  style: base,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final caretMargin =
                          (context
                                  .findAncestorWidgetOfExactType<EditableText>()
                                  ?.cursorWidth ??
                              2) +
                          1;
                      return SizedBox(
                        width: (constraints.maxWidth - caretMargin).clamp(
                          0,
                          double.infinity,
                        ),
                        height: 0,
                      );
                    },
                  ),
                ),
                if (separator.end - separator.start > 1)
                  const TextSpan(text: '\u200b', style: _hidden),
              ] else if (!blockSeparators.contains(separator) ||
                  todos.any((todo) => todo.end == separator.start))
                // Embedded components and to-do rows retain their boundary
                // caret layout and explicit blank lines.
                TextSpan(
                  text: source.substring(separator.start, separator.end),
                  style: base,
                )
              else ...[
                // Keep one real line break and project the required blank line
                // as space below the previous paragraph. The full text strut stays
                // intact, including the caret in an empty trailing paragraph.
                WidgetSpan(
                  alignment: PlaceholderAlignment.belowBaseline,
                  baseline: TextBaseline.alphabetic,
                  style: base,
                  child: SizedBox(
                    width: 0,
                    height: paragraphLine.descent + paragraphGap,
                  ),
                ),
                if (separator.end - separator.start > 2)
                  TextSpan(
                    text: '\u200b' * (separator.end - separator.start - 2),
                    style: _hidden,
                  ),
                TextSpan(text: '\n', style: base),
              ],
            ],
            normalizeSource: false,
          ),
      for (final todo in todos)
        if (!collapsedSyntax.any(
              (block) =>
                  block.start <= todo.start && block.end >= todo.contentStart,
            ) &&
            (composing == null ||
                composing.end <= todo.start ||
                composing.start >= todo.contentStart))
          _SpanProjection(
            todo.start,
            todo.contentStart,
            () => [
              TextSpan(
                text: source.substring(todo.start, todo.contentStart - 1),
                style: _hidden,
                semanticsLabel: '',
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: ComposerTodoMarker(
                  checked: todo.checked,
                  label: source.substring(todo.contentStart, todo.end),
                  style: base,
                  onChanged: _todosReadOnly
                      ? null
                      : () {
                          if (_todosReadOnly ||
                              text != source ||
                              !value.composing.isCollapsed) {
                            return;
                          }
                          final markerEnd =
                              source.indexOf(']', todo.markerStart) + 1;
                          final next = toggleComposerTodo(
                            value,
                            markerStart: todo.markerStart,
                            markerEnd: markerEnd,
                            checked: todo.checked,
                          );
                          if (onTodoChanged case final change?) {
                            change(next);
                          } else {
                            value = next;
                          }
                        },
                ),
              ),
            ],
            normalizeSource: false,
          ),
      for (final prefix in composerBlockquotePrefixes(
        source,
        knownCodeRanges: CodeRanges.of(runs),
      ))
        if (composing == null ||
            composing.end <= prefix.start ||
            composing.start >= prefix.end)
          _SpanProjection(prefix.start, prefix.end, () {
            final marker = prefix.textInside(source);
            final lineEnd = source.indexOf('\n', prefix.end);
            return [
              TextSpan(
                text: marker.substring(0, marker.length - 1),
                style: _hidden,
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                style: base,
                child: ComposerBlockquoteMarker(
                  baseStyle: base,
                  depth: '>'.allMatches(marker).length,
                  range: TextRange(
                    start: prefix.start,
                    end: lineEnd == -1 ? source.length : lineEnd,
                  ),
                ),
              ),
            ];
          }, normalizeSource: false),
      for (final block in collapsedQuotes)
        _SpanProjection(
          block.start,
          block.contentEnd,
          () => _buildQuoteSpans(block, _displayedContentsFor(block), base),
        ),
      for (final block in collapsedSyntax)
        _SpanProjection(
          block.start,
          block.end,
          () => block.projection.buildCollapsedSpans(
            ComposerSyntaxRenderContext(
              baseStyle: base,
              siteUrl: imageSiteUrl,
              resolveUploadUrl: (url) {
                final resolved = resolvedUploadUrl(url);
                if (resolved == null) unresolvedImages.add(url);
                return resolved;
              },
              scrollController: _imageScrollController,
              locale: locale,
              pillKey: _syntaxPillKeys.putIfAbsent(
                _syntaxKey(block),
                () => GlobalKey(
                  debugLabel: '${block.kind.id}-pill-${block.start}',
                ),
              ),
              highlighted: _isSyntaxHighlighted(block),
              hovered: isSyntaxHovered(block),
              followedByLineBreak: syntaxCaretAfter(block) > block.end,
            ),
          ),
        ),
      for (final image in collapsedImages)
        _SpanProjection(
          image.start,
          image.end,
          () => _buildImageSpans(
            image,
            base,
            unresolvedImages,
            highlighted: isPillSelectedForKeyboard(image),
          ),
        ),
      for (final gallery in collapsedGalleries)
        _SpanProjection(
          gallery.start,
          gallery.end,
          () => _buildGallerySpans(gallery, base, unresolvedImages),
        ),
    ];
    projections.sort((a, b) {
      final position = a.start.compareTo(b.start);
      return position != 0 ? position : b.end.compareTo(a.end);
    });

    var sourceOffset = 0;
    for (final projection in projections) {
      if (projection.start < sourceOffset) continue;
      appendMarkdown(sourceOffset, projection.start);
      children.addAll(
        projection.normalizeSource
            ? normalizeCollapsedComponentSourceSpans(
                source: source.substring(projection.start, projection.end),
                spans: projection.build(),
                padding: EdgeInsets.only(
                  top: _spaceBeforeComponents.contains(projection.start)
                      ? paragraphGap
                      : 0,
                  bottom: _spaceAfterComponents.contains(projection.start)
                      ? paragraphGap + componentTrailingLeading
                      : 0,
                ),
                // Real separators end the component line. A selected component or
                // an explicit boundary caret also needs no virtual trailing line.
                suppressSyntheticLineBreaks:
                    source.startsWith('\n', projection.end) ||
                    source.startsWith('\r\n', projection.end) ||
                    (_boundaryCaretProjection != null &&
                        _blockRange(_boundaryCaretProjection!).$1 ==
                            projection.start) ||
                    (projection.end == source.length &&
                        keyboardSelectedProjection != null &&
                        _blockRange(keyboardSelectedProjection!).$1 ==
                            projection.start),
              )
            : projection.build(),
      );
      sourceOffset = projection.end;
    }
    appendMarkdown(sourceOffset, source.length);

    _renderedEmojiDocument = source;
    _renderedEmojiRanges = Set.unmodifiable(renderedEmojiRanges);

    // Keep paragraph defaults neutral: an embedded editor already includes its
    // own leading. Text runs retain the complete authoring style, including
    // line height, without adding that leading around a WidgetSpan as well.
    final content = TextSpan(style: base, children: children);
    final span =
        normalizeComposerTextScaling(
              (base.height ?? 1) > 1
                  ? TextSpan(
                      style: base.copyWith(height: 1),
                      children: [content],
                    )
                  : content,
            )
            as TextSpan;
    // Length, not contents: projected widgets flatten to `0xFFFC`, and image
    // tokens also lend some of their hidden characters to transparent line
    // breaks. What everything downstream depends on — the caret, hit testing,
    // word boundaries, select-all — is that an offset means the same position
    // in both, and Flutter neither asserts that nor converts between them when
    // it stops being true.
    assert(
      span.toPlainText(includeSemanticsLabels: false).length == source.length,
      'the painted text drifted from the source',
    );

    // After the span is built, not during: asking is a side effect, and the
    // answer arrives through [_artwork] and a repaint rather than here.
    if (unresolvedRefs.isNotEmpty || unresolvedNames.isNotEmpty) {
      pills?.resolve(unresolvedRefs, unresolvedNames);
    }
    if (unresolvedImages.isNotEmpty) _resolveImageUrls(unresolvedImages);

    _cachedSpan = _CachedMarkdownSpan(
      source: source,
      style: base,
      theme: theme,
      composing: composing,
      revealed: revealed,
      artwork: _artwork,
      quoteProjection: quoteProjection,
      syntaxProjection: syntaxProjection,
      imageProjection: imageProjection,
      galleryProjection: galleryProjection,
      keyboardProjection: keyboardProjection,
      span: span,
    );
    return span;
  }

  List<InlineSpan> _buildQuoteSpans(
    ComposerQuoteBlock block,
    String displayedContents,
    TextStyle base,
  ) {
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: base,
        child: KeyedSubtree(
          key: _quoteKeys.putIfAbsent(
            block.start,
            () => GlobalKey(debugLabel: 'composer-quote-${block.start}'),
          ),
          child: ComposerBlockSelection(
            selected: isPillSelectedForKeyboard(block),
            child: IgnorePointer(
              child: ComposerQuotePreview(
                block: block,
                contents: displayedContents,
                baseStyle: base,
                removeKey: _quoteRemoveKeys.putIfAbsent(
                  block.start,
                  () => GlobalKey(
                    debugLabel: 'composer-quote-remove-${block.start}',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ..._buildCollapsedBlockSourceTail(block.start, block.contentEnd, base),
    ];
  }

  List<InlineSpan> _buildImageSpans(
    ComposerImageBlock image,
    TextStyle base,
    Set<String> unresolved, {
    required bool highlighted,
  }) {
    final url = resolvedImageUrl(image);
    if (image.url.startsWith('upload://') && url == null) {
      unresolved.add(image.url);
    }
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: base,
        child: KeyedSubtree(
          key: _imageKeys.putIfAbsent(
            image.start,
            () => GlobalKey(debugLabel: 'composer-image-${image.start}'),
          ),
          child: ComposerImagePreview(
            image: image,
            url: url,
            siteUrl: imageSiteUrl,
            highlighted: highlighted,
            onDragStarted: onReorderImageGallery == null
                ? null
                : () => keepImageCollapsedForPointerEdit(image),
            onDragEnded: () {
              if (image.end <= text.length &&
                  text.substring(image.start, image.end) == image.source &&
                  selection.isCollapsed &&
                  selection.extentOffset > image.start &&
                  selection.extentOffset < image.end) {
                selection = TextSelection.collapsed(offset: image.end);
              }
              releaseImagePointerEdit(image);
            },
            onNaturalSize: (size) {
              if (_naturalImageSizes[image.url] == size) return;
              _naturalImageSizes[image.url] = size;
              artworkArrived();
            },
          ),
        ),
      ),
      ..._buildCollapsedBlockSourceTail(
        image.start,
        image.end,
        base,
        trailingCaretLine: _lineEnd.matchAsPrefix(text, image.end) == null,
      ),
    ];
  }

  List<InlineSpan> _buildGallerySpans(
    ComposerImageGalleryBlock gallery,
    TextStyle base,
    Set<String> unresolved,
  ) {
    final items = <ComposerImageGalleryItem>[];
    for (final image in gallery.images) {
      final url = resolvedImageUrl(image);
      if (image.url.startsWith('upload://') && url == null) {
        unresolved.add(image.url);
      }
      items.add(
        ComposerImageGalleryItem(
          image: image,
          url: url,
          imageKey: _imageKeys.putIfAbsent(
            image.start,
            () =>
                GlobalKey(debugLabel: 'composer-gallery-image-${image.start}'),
          ),
          highlighted: isPillSelectedForKeyboard(image),
          onNaturalSize: (size) {
            if (_naturalImageSizes[image.url] == size) return;
            _naturalImageSizes[image.url] = size;
            artworkArrived();
          },
        ),
      );
    }

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: base,
        child: KeyedSubtree(
          key: _galleryKeys.putIfAbsent(
            gallery.start,
            () => GlobalKey(
              debugLabel: 'composer-image-gallery-${gallery.start}',
            ),
          ),
          child: ComposerImageGalleryPreview(
            gallery: gallery,
            items: items,
            siteUrl: imageSiteUrl,
            highlighted:
                isPillSelectedForKeyboard(gallery) ||
                _sameProjection(_caretSuppressedGallery, gallery),
            onEdit: onEditImageGallery == null
                ? null
                : () => onEditImageGallery!(gallery),
            onReorder: onReorderImageGallery == null
                ? null
                : (image, newIndex) =>
                      onReorderImageGallery!(gallery, image, newIndex),
            onReorderStarted: _startGalleryImageDrag,
            onReorderEnded: (image) => _endGalleryImageDrag(gallery, image),
          ),
        ),
      ),
      ..._buildCollapsedBlockSourceTail(
        gallery.start,
        gallery.end,
        base,
        trailingCaretLine: _lineEnd.matchAsPrefix(text, gallery.end) == null,
      ),
    ];
  }

  List<InlineSpan> _buildCollapsedBlockSourceTail(
    int start,
    int end,
    TextStyle base, {
    bool trailingCaretLine = true,
  }) => [
    // End the WidgetSpan's intrinsic-height line with one source code unit.
    // A terminal image needs no extra caret line, even when unselected.
    // The remaining Markdown stays offset-preserving but layout-neutral, so
    // source length can never enlarge the component's editor hit region.
    TextSpan(
      text: trailingCaretLine ? '\n' : '\u200b',
      style: base.copyWith(color: const Color(0x00000000)),
    ),
    TextSpan(text: text.substring(start + 2, end), style: _hidden),
  ];

  void _startGalleryImageDrag(ComposerImageBlock image) {
    if (_sameProjection(_draggedGalleryImage, image)) return;
    _draggedGalleryImage = image;
    artworkArrived();
  }

  void _endGalleryImageDrag(
    ComposerImageGalleryBlock gallery,
    ComposerImageBlock image,
  ) {
    if (!_sameProjection(_draggedGalleryImage, image)) return;

    // EditableText can move its caret into a WidgetSpan's hidden source before
    // Draggable wins the pointer. A cancelled reorder has no source mutation
    // to move it back to a safe boundary, so settle it after the gallery.
    final current = _galleryBlocksFor(
      text,
    ).where((candidate) => _sameProjection(candidate, gallery)).firstOrNull;
    final selection = value.selection;
    if (current != null &&
        selection.isCollapsed &&
        selection.extentOffset > current.start &&
        selection.extentOffset < current.end) {
      value = value.copyWith(
        selection: TextSelection.collapsed(offset: current.end),
        composing: TextRange.empty,
      );
    }

    _draggedGalleryImage = null;
    artworkArrived();
  }

  void _resolveImageUrls(Set<String> urls) {
    final resolver = resolveUploadUrls;
    final fresh = urls
        .where((url) => !_failedImageUrls.contains(url))
        .where(_resolvingImageUrls.add)
        .toSet();
    if (resolver == null || fresh.isEmpty) return;
    unawaited(
      resolver(fresh).then(
        (resolved) {
          _resolvingImageUrls.removeAll(fresh);
          if (_disposed) return;
          for (final url in fresh) {
            final value = resolved[url];
            if (value != null) {
              _imageUrls[url] = value;
            } else {
              _failedImageUrls.add(url);
            }
          }
          artworkArrived();
        },
        onError: (_) {
          // Transport failures remain retryable. Notifying here would create a
          // rebuild/request loop while the site is unreachable.
          _resolvingImageUrls.removeAll(fresh);
          if (!_disposed) _artwork++;
        },
      ),
    );
  }

  static bool _imageNeedsRawSource(
    ComposerImageBlock image,
    TextEditingValue value, {
    bool suppressCollapsedCaret = false,
  }) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    if (selection.extentOffset == image.start ||
        selection.extentOffset == image.end) {
      return false;
    }
    return !suppressCollapsedCaret &&
        selection.extentOffset >= image.start &&
        selection.extentOffset < image.end;
  }

  void artworkArrived() {
    if (_disposed) return;
    _artwork++;
    notifyListeners();
  }

  static bool _sameProjection(Object? first, Object? second) =>
      switch ((first, second)) {
        (ComposerImageBlock a, ComposerImageBlock b) =>
          a.start == b.start && a.end == b.end && a.source == b.source,
        (ComposerSyntaxOccurrence a, ComposerSyntaxOccurrence b) => a.sameAs(b),
        (ComposerQuoteBlock a, ComposerQuoteBlock b) =>
          a.start == b.start && a.end == b.end && a.source == b.source,
        (ComposerImageGalleryBlock a, ComposerImageGalleryBlock b) =>
          a.start == b.start && a.end == b.end && a.source == b.source,
        _ => false,
      };

  static void _retainPillKeys<T>(
    Map<int, GlobalKey> keys,
    Iterable<T> previous,
    Iterable<T> next,
    int Function(T) startOf,
  ) {
    if (keys.isEmpty) return;
    final was = {for (final block in previous) startOf(block): block};
    final now = {for (final block in next) startOf(block): block};
    keys.removeWhere((start, _) => !_sameProjection(was[start], now[start]));
  }

  static bool _stillContainsSyntax(
    String source,
    ComposerSyntaxOccurrence block,
  ) =>
      block.start >= 0 &&
      block.end <= source.length &&
      block.start <= block.end &&
      source.substring(block.start, block.end) == block.source;

  List<InlineSpan>? _artworkFor(
    MarkdownRun run,
    TextStyle base,
    ThemeData theme,
    Set<String> unresolvedRefs,
    Set<String> unresolvedNames,
  ) {
    final token = run.token;
    if (token == null || run.length < 2) return null;

    if (run.has(Md.hashtag)) {
      return _hashtagPill(run, token, base, unresolvedRefs);
    }
    if (run.has(Md.mention)) {
      return _mentionPill(run, token, base, unresolvedNames);
    }

    final resolve = resolveEmoji;
    if (resolve == null || !run.has(Md.emoji)) return null;

    final url = resolve(token);
    final cache = MediaPipeline.instance.emoji;

    // Only ever substituted once the bytes are here, so the placeholder is
    // created at its final size and nothing reflows under the caret mid-word.
    // A name the site does not have 404s once, is remembered as a failure, and
    // stays text forever at no further cost.
    if (!cache.isCached(url)) {
      if (_loadingEmoji.add(url)) {
        unawaited(
          cache.load(url).then((_) {
            _loadingEmoji.remove(url);
            if (_disposed) return;
            artworkArrived();
            // Reassigning the same value repaints without advancing UndoHistory
            // or the typing and draft clocks, whose listeners ignore it.
          }),
        );
      }
      return null;
    }
    if (cache.cached(url) == null) return null;

    final size = (base.fontSize ?? DiscourseTypography.sm) * emojiScale;
    return [
      TextSpan(text: text.substring(run.start, run.end - 1), style: _hidden),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: base,
        child: EmojiImage(url: url, size: size, alt: ''),
      ),
    ];
  }

  List<InlineSpan>? _hashtagPill(
    MarkdownRun run,
    String ref,
    TextStyle base,
    Set<String> unresolved,
  ) {
    final found = pills?.hashtag(ref);
    if (found == null) {
      if (pills != null) unresolved.add(ref);
      return null;
    }

    final presentation = resolveHashtagPresentation(
      HashtagPresentationRequest(
        type: found.type,
        style: HashtagStyle.parse(found.styleType),
        icon: found.icon,
        emoji: found.emoji,
        colorValues: found.colorValues,
      ),
      pluginPresentation: pluginHashtagPresentation,
    );

    return _placeholder(
      run,
      base,
      HashtagPill(
        // The characters that are actually in the field, not the site's own
        // `Parent > Child`. What the composer draws is what will be posted;
        // the cooked post is where the real name belongs.
        label: text.substring(run.start, run.end),
        baseStyle: base,
        presentation: presentation,
        siteUrl: imageSiteUrl,
      ),
    );
  }

  List<InlineSpan>? _mentionPill(
    MarkdownRun run,
    String username,
    TextStyle base,
    Set<String> unresolved,
  ) {
    final real = pills?.mention(username);
    if (real == null) {
      if (pills != null) unresolved.add(username);
      return null;
    }
    if (!real) return null;

    return _placeholder(
      run,
      base,
      KeyedSubtree(
        key: _mentionPillKeys.putIfAbsent(
          run.start,
          () => GlobalKey(debugLabel: 'mention-pill-${run.start}'),
        ),
        child: MentionPill(
          label: text.substring(run.start, run.end),
          baseStyle: base,
        ),
      ),
    );
  }

  List<InlineSpan> _placeholder(MarkdownRun run, TextStyle base, Widget pill) {
    final hiddenEnd = run.end - 1;
    var hiddenText = text.substring(run.start, hiddenEnd);
    if (hiddenEnd > run.start &&
        text.codeUnitAt(hiddenEnd - 1) >= 0xD800 &&
        text.codeUnitAt(hiddenEnd - 1) <= 0xDBFF &&
        text.codeUnitAt(hiddenEnd) >= 0xDC00 &&
        text.codeUnitAt(hiddenEnd) <= 0xDFFF) {
      // The WidgetSpan replaces one UTF-16 unit. Keep the preceding hidden
      // unit for offset mapping without handing TextSpan a lone surrogate.
      hiddenText = '${text.substring(run.start, hiddenEnd - 1)}\u200b';
    }
    return [
      TextSpan(text: hiddenText, style: _hidden),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: base,
        child: IgnorePointer(child: pill),
      ),
    ];
  }

  static int _revealedPill(List<MarkdownRun> runs, TextSelection selection) {
    if (!selection.isValid || !selection.isCollapsed) return -1;

    for (final run in runs) {
      final inside = run.has(Md.emoji)
          ? selection.start < run.end && selection.end > run.start
          : selection.start <= run.end && selection.end >= run.start;
      if (!inside) continue;
      if (run.has(Md.emoji) || run.has(Md.mention) || run.has(Md.hashtag)) {
        return run.start;
      }
    }
    return -1;
  }

  static bool _overlapsComposing(MarkdownRun run, TextRange? composing) =>
      composing != null &&
      composing.start < run.end &&
      composing.end > run.start;

  TextStyle _styleFor(
    MarkdownRun run,
    TextStyle base,
    ThemeData theme,
    TextRange? composing,
  ) {
    final style = markdownStyle(run.mask, run.detail, base, theme);
    if (composing == null ||
        run.start < composing.start ||
        run.end > composing.end) {
      return style;
    }
    // Combined rather than replaced, so an underline over struck-through text
    // does not take the strikethrough away.
    return style.copyWith(
      decoration: TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        TextDecoration.underline,
      ]),
    );
  }

  static const TextStyle _hidden = TextStyle(
    fontSize: 0,
    color: Color(0x00000000),
    letterSpacing: 0,
    wordSpacing: 0,
  );

  @override
  void dispose() {
    _disposed = true;
    _fenceHighlightGeneration++;
    _fenceHighlightTimer?.cancel();
    _fenceHighlightTimer = null;
    super.dispose();
  }

  static List<MarkdownRun> _splitAt(MarkdownRun run, TextRange? composing) {
    if (composing == null) return [run];

    final cuts = <int>{
      run.start,
      run.end,
      if (composing.start > run.start && composing.start < run.end)
        composing.start,
      if (composing.end > run.start && composing.end < run.end) composing.end,
    }.toList()..sort();

    return [
      for (var i = 0; i < cuts.length - 1; i++)
        MarkdownRun(cuts[i], cuts[i + 1], run.mask, run.detail, run.token),
    ];
  }
}

class _CachedMarkdownSpan {
  const _CachedMarkdownSpan({
    required this.source,
    required this.style,
    required this.theme,
    required this.composing,
    required this.revealed,
    required this.artwork,
    required this.quoteProjection,
    required this.syntaxProjection,
    required this.imageProjection,
    required this.galleryProjection,
    required this.keyboardProjection,
    required this.span,
  });

  final String source;
  final TextStyle style;
  final ThemeData theme;
  final TextRange? composing;
  final int revealed;
  final int artwork;
  final int quoteProjection;
  final int syntaxProjection;
  final int imageProjection;
  final int galleryProjection;
  final int keyboardProjection;
  final TextSpan span;

  bool matches({
    required String source,
    required TextStyle style,
    required ThemeData theme,
    required TextRange? composing,
    required int revealed,
    required int artwork,
    required int quoteProjection,
    required int syntaxProjection,
    required int imageProjection,
    required int galleryProjection,
    required int keyboardProjection,
  }) =>
      this.source == source &&
      this.style == style &&
      identical(this.theme, theme) &&
      this.composing == composing &&
      this.revealed == revealed &&
      this.artwork == artwork &&
      this.quoteProjection == quoteProjection &&
      this.syntaxProjection == syntaxProjection &&
      this.imageProjection == imageProjection &&
      this.galleryProjection == galleryProjection &&
      this.keyboardProjection == keyboardProjection;
}

class _SpanProjection {
  const _SpanProjection(
    this.start,
    this.end,
    this.build, {
    this.normalizeSource = true,
  });

  // Inline quote markers must remain visible to the background painter;
  // they do not need a collapsed component's layout wrapper.
  final bool normalizeSource;
  final int start;
  final int end;
  final List<InlineSpan> Function() build;
}
