import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/emoji_cache.dart';
import '../models/composer_upload.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/hashtag_kind.dart';
import 'composer_galleries.dart';
import 'composer_image.dart';
import 'composer_image_gallery.dart';
import 'composer_images.dart';
import 'composer_pills.dart';
import 'composer_quotes.dart';
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
    this.maxImageWidth = 690,
    this.maxImageHeight = 500,
    this.enableImageGalleries = true,
  });

  final String? imageSiteUrl;

  final String Function(String name)? resolveEmoji;

  final ComposerPills? pills;

  final PluginHashtagPresentationResolver? pluginHashtagPresentation;

  final ComposerQuoteContentsFormatter? formatQuoteContents;
  ComposerQuoteContentsResolver? _quoteContentsResolver;
  Object? _quoteContentsResolverContext;

  final List<ComposerSyntaxPolicy> syntaxPolicies;
  final ComposerUploadUrlResolver? resolveUploadUrls;
  final int maxImageWidth;
  final int maxImageHeight;

  final bool enableImageGalleries;

  String? _imageScanned;
  List<ComposerImageBlock> _imageBlocks = const [];
  Set<int> _collapsedImageStarts = const {};
  ComposerImageBlock? _caretSuppressedImage;
  Object? _keyboardSelectedProjection;
  String? _keyboardSelectionDocument;
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
    final current = super.value;
    if (newValue.text != current.text) {
      _keyboardSelectedProjection = null;
      _keyboardSelectionDocument = null;
      if (_caretSuppressedSyntax case final syntax?) {
        if (!_stillContainsSyntax(newValue.text, syntax)) {
          _caretSuppressedSyntax = null;
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
    super.value = newValue;
  }

  set imageScrollController(ScrollController? value) {
    if (identical(_imageScrollController, value)) return;
    _imageScrollController = value;
    artworkArrived();
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

  void selectPillForKeyboard(Object projection) {
    if (projection is! ComposerImageBlock &&
        projection is! ComposerSyntaxOccurrence) {
      for (final occurrence in _syntaxBlocksFor(text)) {
        if (identical(occurrence.projection, projection) ||
            occurrence.projection == projection) {
          projection = occurrence;
          break;
        }
      }
    }
    if (projection is! ComposerImageBlock &&
        projection is! ComposerSyntaxOccurrence) {
      throw ArgumentError.value(projection, 'projection');
    }
    if (_keyboardSelectionDocument == text &&
        _sameProjection(_keyboardSelectedProjection, projection)) {
      return;
    }
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
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
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
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void cacheImageUrl(String shortUrl, String url) {
    if (_imageUrls[shortUrl] == url) return;
    _imageUrls[shortUrl] = url;
    _failedImageUrls.remove(shortUrl);
    artworkArrived();
  }

  String? resolvedImageUrl(ComposerImageBlock image) =>
      image.url.startsWith('upload://') ? _imageUrls[image.url] : image.url;

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

  void keepSyntaxCollapsedForPointerEdit(ComposerSyntaxOccurrence block) {
    if (_sameProjection(_caretSuppressedSyntax, block)) return;
    _caretSuppressedSyntax = block;
    artworkArrived();
  }

  void releaseSyntaxPointerEdit(ComposerSyntaxOccurrence block) {
    if (!_sameProjection(_caretSuppressedSyntax, block)) return;
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
    Offset globalPosition,
  ) {
    for (final block in _syntaxBlocksFor(text)) {
      if (!block.projection.protectsAdjacentDelete ||
          !isSyntaxCollapsed(block)) {
        continue;
      }
      final rect = collapsedSyntaxGlobalRect(block);
      if (rect != null &&
          globalPosition.dx >= rect.right &&
          globalPosition.dy >= rect.top &&
          globalPosition.dy < rect.bottom) {
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
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  List<ComposerSyntaxOccurrence> _syntaxBlocksFor(String source) {
    if (_syntaxScanned == source) return _syntaxBlocks;
    final blocks = <ComposerSyntaxOccurrence>[
      for (final policy in syntaxPolicies)
        for (final projection in policy.parse(source))
          ComposerSyntaxOccurrence(policy, projection),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final live = {for (final block in blocks) _syntaxKey(block): block};
    final held = {for (final block in _syntaxBlocks) _syntaxKey(block): block};
    _syntaxPillKeys.removeWhere(
      (key, _) => !_sameProjection(held[key], live[key]),
    );
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
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    return rect.inflate(4).contains(globalPosition);
  }

  Rect? collapsedQuoteGlobalRect(ComposerQuoteBlock block) {
    if (!isQuoteCollapsed(block)) return null;
    final renderObject = _quoteKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
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

  String? _parsedFenceSource;
  final Set<String> _parsedFences = {};

  String? _codeRangesScanned;
  CodeRanges _codeRanges = CodeRanges.none;

  final Map<int, GlobalKey> _mentionPillKeys = {};

  bool isMentionPillAtGlobalPosition(Offset globalPosition) {
    for (final key in _mentionPillKeys.values) {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
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
    if (_parsedFenceSource != source) {
      _parsedFenceSource = source;
      _parsedFences.clear();
    }
    // Replaced wholesale on every scan, so a fence edited away mid-debounce is
    // never parsed on its way out.
    _pendingFences = [
      for (final fence in fences)
        if (!_parsedFences.contains(fence.body)) fence,
    ];
    if (_pendingFences.isEmpty) return;
    _fenceHighlightTimer = Timer(fenceHighlightDebounce, () {
      _fenceHighlightTimer = null;
      if (_disposed) return;
      for (final fence in _pendingFences) {
        // For the side effect: the tokens land in the highlight cache, where
        // the rescan below finds them and takes the synchronous path.
        highlightLines(fence.body, fence.language);
        _parsedFences.add(fence.body);
      }
      _pendingFences = const [];
      _scanned = null;
      _runs = null;
      artworkArrived();
    });
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = value.text;
    if (source.isEmpty) {
      _renderedEmojiDocument = source;
      _renderedEmojiRanges = const {};
      _cachedSpan = null;
      return TextSpan(style: style);
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

    final collapsedQuotes = _quoteBlocksFor(source);
    _collapsedQuoteStarts = {for (final block in collapsedQuotes) block.start};
    final quoteProjection = Object.hashAll(
      collapsedQuotes.map(
        (block) => Object.hash(
          block.start,
          block.end,
          block.title,
          _displayedContentsFor(block),
        ),
      ),
    );

    final locale = Localizations.localeOf(context);
    final syntaxBlocks = _syntaxBlocksFor(source);
    final collapsedSyntax = [
      for (final block in syntaxBlocks)
        if (!block.projection.needsRawSource(
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
            isPillSelectedForKeyboard(block),
            isSyntaxHovered(block),
          ),
        ),
      ),
    );

    final galleries = _galleryBlocksFor(source);
    final collapsedGalleries = [
      for (final gallery in galleries)
        if (!_galleryNeedsRawSource(
          gallery,
          value,
          suppressCollapsedCaret:
              _sameProjection(_caretSuppressedGallery, gallery) ||
              gallery.images.any(
                (image) =>
                    _sameProjection(_caretSuppressedImage, image) ||
                    _sameProjection(_draggedGalleryImage, image) ||
                    isPillSelectedForKeyboard(image),
              ),
        ))
          gallery,
    ];
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
            !_imageNeedsRawSource(
              image,
              value,
              suppressCollapsedCaret: _sameProjection(
                _caretSuppressedImage,
                image,
              ),
            ))
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

    void appendRun(MarkdownRun run) {
      // A run the IME is still deciding about is never substituted: the
      // artwork path skips [_splitAt] entirely, so a placeholder over a
      // composing range would take its underline away and paint the
      // uncommitted characters invisibly.
      final artwork =
          run.start == revealed || _overlapsComposing(run, composing)
          ? null
          : _artworkFor(run, base, theme, unresolvedRefs, unresolvedNames);
      if (artwork != null) {
        if (run.has(Md.emoji)) {
          renderedEmojiRanges.add(TextRange(start: run.start, end: run.end));
        }
        children.addAll(artwork);
        return;
      }
      for (final piece in _splitAt(run, composing)) {
        children.add(
          TextSpan(
            text: source.substring(piece.start, piece.end),
            style: _styleFor(piece, base, theme, composing),
          ),
        );
      }
    }

    void appendMarkdown(int start, int end) {
      if (start >= end) return;
      for (final run in runs) {
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
      }
    }

    final projections = <_SpanProjection>[
      for (final block in collapsedQuotes)
        _SpanProjection(
          block.start,
          block.end,
          () => _buildQuoteSpans(block, _displayedContentsFor(block), base),
        ),
      for (final block in collapsedSyntax)
        _SpanProjection(
          block.start,
          block.end,
          () => block.projection.buildCollapsedSpans(
            ComposerSyntaxRenderContext(
              baseStyle: base,
              locale: locale,
              pillKey: _syntaxPillKeys.putIfAbsent(
                _syntaxKey(block),
                () => GlobalKey(
                  debugLabel: '${block.kind.id}-pill-${block.start}',
                ),
              ),
              highlighted: isPillSelectedForKeyboard(block),
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
    ]..sort((a, b) => a.start.compareTo(b.start));

    var sourceOffset = 0;
    for (final projection in projections) {
      if (projection.start < sourceOffset) continue;
      appendMarkdown(sourceOffset, projection.start);
      children.addAll(projection.build());
      sourceOffset = projection.end;
    }
    appendMarkdown(sourceOffset, source.length);

    _renderedEmojiDocument = source;
    _renderedEmojiRanges = Set.unmodifiable(renderedEmojiRanges);

    final span = TextSpan(style: base, children: children);
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
          child: IgnorePointer(
            child: _FollowEditorScroll(
              controller: _imageScrollController,
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
      TextSpan(
        // The WidgetSpan already contributes the quote's full height. One
        // transparent line break moves subsequent prose below it; reserving
        // that height again creates a quote-sized gap before the caret.
        text: '\n',
        style: TextStyle(
          color: const Color(0x00000000),
          fontFamily: base.fontFamily,
          fontFamilyFallback: base.fontFamilyFallback,
          fontSize: base.fontSize,
          height: base.height,
        ),
      ),
      TextSpan(
        text: text.substring(block.start + 2, block.end),
        style: _hidden,
      ),
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
    // RenderEditable paints tall WidgetSpans at full size but does not include
    // their height in its scroll extent. Project enough token characters as
    // transparent line breaks to reserve the same vertical space while keeping
    // one laid-out character for every raw Markdown character.
    final imageHeight = ComposerImagePreview.displaySize(image).height + 8;
    final lineHeight = (base.fontSize ?? 14) * (base.height ?? 1.4);
    final breaks = (imageHeight / lineHeight).ceil().clamp(
      1,
      image.end - image.start - 1,
    );
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: base,
        child: KeyedSubtree(
          key: _imageKeys.putIfAbsent(
            image.start,
            () => GlobalKey(debugLabel: 'composer-image-${image.start}'),
          ),
          child: IgnorePointer(
            child: _FollowEditorScroll(
              controller: _imageScrollController,
              child: ComposerImagePreview(
                image: image,
                url: url,
                siteUrl: imageSiteUrl,
                highlighted: highlighted,
                onNaturalSize: (size) {
                  if (_naturalImageSizes[image.url] == size) return;
                  _naturalImageSizes[image.url] = size;
                  artworkArrived();
                },
              ),
            ),
          ),
        ),
      ),
      TextSpan(
        text: List.filled(breaks, '\n').join(),
        style: TextStyle(
          color: const Color(0x00000000),
          fontFamily: base.fontFamily,
          fontFamilyFallback: base.fontFamilyFallback,
          fontSize: base.fontSize,
          height: base.height,
        ),
      ),
      TextSpan(
        text: text.substring(image.start + breaks + 1, image.end),
        style: _hidden,
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

    final galleryHeight = ComposerImageGalleryPreview.displayHeight(
      items.length,
    );
    final lineHeight = (base.fontSize ?? 14) * (base.height ?? 1.4);
    final breaks = (galleryHeight / lineHeight).ceil().clamp(
      1,
      gallery.end - gallery.start - 1,
    );

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: base,
        child: _FollowEditorScroll(
          controller: _imageScrollController,
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
              highlighted: _sameProjection(_caretSuppressedGallery, gallery),
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
      ),
      TextSpan(
        text: List.filled(breaks, '\n').join(),
        style: TextStyle(
          color: const Color(0x00000000),
          fontFamily: base.fontFamily,
          fontFamilyFallback: base.fontFamilyFallback,
          fontSize: base.fontSize,
          height: base.height,
        ),
      ),
      TextSpan(
        text: text.substring(gallery.start + breaks + 1, gallery.end),
        style: _hidden,
      ),
    ];
  }

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
    if (!selection.isValid) return false;
    if (selection.isCollapsed) {
      if (selection.extentOffset == image.start ||
          selection.extentOffset == image.end) {
        return false;
      }
      return !suppressCollapsedCaret &&
          selection.extentOffset >= image.start &&
          selection.extentOffset < image.end;
    }
    return selection.start < image.end && selection.end > image.start;
  }

  static bool _galleryNeedsRawSource(
    ComposerImageGalleryBlock gallery,
    TextEditingValue value, {
    bool suppressCollapsedCaret = false,
  }) {
    final selection = value.selection;
    if (!selection.isValid) return false;
    if (selection.isCollapsed) {
      if (selection.extentOffset == gallery.start ||
          selection.extentOffset == gallery.end) {
        return false;
      }
      return !suppressCollapsedCaret &&
          selection.extentOffset > gallery.start &&
          selection.extentOffset < gallery.end;
    }
    return selection.start < gallery.end && selection.end > gallery.start;
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
    final cache = EmojiCache.instance;

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

    final size = (base.fontSize ?? 14) * emojiScale;
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

  List<InlineSpan> _placeholder(MarkdownRun run, TextStyle base, Widget pill) =>
      [
        TextSpan(text: text.substring(run.start, run.end - 1), style: _hidden),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          style: base,
          child: IgnorePointer(child: pill),
        ),
      ];

  static int _revealedPill(List<MarkdownRun> runs, TextSelection selection) {
    if (!selection.isValid) return -1;

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

class _FollowEditorScroll extends StatelessWidget {
  const _FollowEditorScroll({required this.controller, required this.child});

  final ScrollController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scroll = controller;
    if (scroll == null) return child;
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, scroll.hasClients ? -scroll.offset : 0),
        child: child,
      ),
    );
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
      this.galleryProjection == galleryProjection;
}

class _SpanProjection {
  const _SpanProjection(this.start, this.end, this.build);

  final int start;
  final int end;
  final List<InlineSpan> Function() build;
}
