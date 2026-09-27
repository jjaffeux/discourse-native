import 'package:flutter/services.dart';

import '../models/composer_upload.dart';
import 'composer_controller.dart';
import 'composer_details_blocks.dart';
import 'composer_galleries.dart';
import 'composer_upload_placeholder.dart';

/// A rich editor over one details body. The enclosing draft owns uploads and
/// submission; this controller owns only local selection and editing history.
class ComposerDetailsBodyController extends ComposerController {
  ComposerDetailsBodyController(this.parent, ComposerDetailsBlock block)
    : _block = block,
      super(
        parent.target,
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
      text: _localBody,
      selection: TextSelection.collapsed(offset: _localBody.length),
    );
    _copyImageUrls();
    text.addListener(_writeBody);
    parent.text.addListener(_readParent);
    parent.addListener(_parentStateChanged);
    focus.addListener(_activate);
  }

  final ComposerController parent;
  ComposerDetailsBlock _block;
  ComposerDetailsBlock get block => _block;
  bool _syncing = false;
  bool _retired = false;
  String get _localBody => _block.body.replaceAll('\r\n', '\n');

  bool get _matchesParent =>
      _block.end <= parent.text.text.length &&
      parent.text.text.substring(_block.start, _block.end) == _block.source;

  @override
  bool get isCurrent =>
      super.isCurrent && !_retired && parent.isCurrent && _matchesParent;
  @override
  bool get isEditing => super.isEditing && parent.isEditing;

  @override
  ComposerUploadPlaceholders get uploadPlaceholders =>
      parent.uploadPlaceholders;
  @override
  List<ComposerUploadItem> get uploads => parent.uploads;
  @override
  bool get hasActiveUploads => parent.hasActiveUploads;

  @override
  String get raw => uploadPlaceholders.strip(text.text).trim();

  void _activate() {
    if (focus.hasPrimaryFocus) parent.activateEmbeddedEditor(this);
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

  void _copyImageUrls() {
    for (final image in text.imageBlocks) {
      final resolved = parent.text.resolvedImageUrl(image);
      if (resolved != null) text.cacheImageUrl(image.url, resolved);
    }
  }

  void _readParent() {
    if (_syncing || isDisposed || _retired) return;
    if (_matchesParent) {
      _copyImageUrls();
      return;
    }
    final next = parseComposerDetails(
      parent.text.text,
    ).where((block) => block.start == _block.start).firstOrNull;
    // A removed/moved disclosure retires its async picker and editing host.
    if (next == null) {
      _retired = true;
      return;
    }
    updateBlock(next);
  }

  void updateBlock(ComposerDetailsBlock block) {
    _block = block;
    _syncing = true;
    try {
      if (text.text != _localBody) {
        text.value = _replaceBodyValue(text.value, _localBody);
      }
      _copyImageUrls();
    } finally {
      _syncing = false;
    }
  }

  void _writeBody() {
    if (_syncing || text.text == _localBody) return;
    if (!isEditing) {
      updateBlock(_block);
      return;
    }
    final current = parent.value;
    final source = _block.withBody(text.text);
    _syncing = true;
    try {
      if (!parent.commitText(
        expectedText: current.text,
        value: TextEditingValue(
          text: current.text.replaceRange(_block.start, _block.end, source),
          selection: TextSelection.collapsed(
            offset: _block.start + source.length,
          ),
        ),
      )) {
        return;
      }
      final next = parseComposerDetails(
        parent.text.text,
      ).where((block) => block.start == _block.start).firstOrNull;
      if (next == null) {
        _retired = true;
        parent.requestFocus();
      } else {
        _block = next;
      }
    } finally {
      _syncing = false;
    }
  }

  int _parentOffset(int offset) {
    // Uploads can introduce LF into a CRLF draft. Map the actual source,
    // rather than assuming every local newline has the same stored width.
    final body = _block.body;
    var sourceOffset = 0;
    for (var local = 0; local < offset && sourceOffset < body.length; local++) {
      if (body.startsWith('\r\n', sourceOffset)) sourceOffset++;
      sourceOffset++;
    }
    return _block.start + _block.bodyStart + sourceOffset;
  }

  bool _prepareUpload() {
    if (!canUpload) return false;
    if (!_block.source.contains('\n')) {
      final current = parent.value;
      final source = _block.withBody(text.text, multiline: true);
      if (!parent.commitText(
        expectedText: current.text,
        value: TextEditingValue(
          text: current.text.replaceRange(_block.start, _block.end, source),
          selection: TextSelection.collapsed(
            offset: _block.start + source.length,
          ),
        ),
      )) {
        return false;
      }
    }
    return isCurrent;
  }

  ComposerImageGalleryBlock? _parentGallery(
    ComposerImageGalleryBlock? gallery,
  ) {
    if (gallery == null) return null;
    return parent.text.galleryBlocks
        .where(
          (candidate) =>
              candidate.start == _parentOffset(gallery.start) &&
              candidate.source.replaceAll('\r\n', '\n') == gallery.source,
        )
        .firstOrNull;
  }

  @override
  void addFiles(
    Iterable<ComposerUploadFile> files,
    int offset, {
    ComposerImageGalleryBlock? gallery,
  }) {
    if (!_prepareUpload()) return;
    parent.addFiles(
      files,
      _parentOffset(offset),
      gallery: _parentGallery(gallery),
    );
  }

  @override
  void addImages(Iterable<ComposerUploadFile> files, int offset) {
    if (_prepareUpload()) parent.addImages(files, _parentOffset(offset));
  }

  @override
  void addImagesToGallery(
    Iterable<ComposerUploadFile> files,
    ComposerImageGalleryBlock gallery,
  ) {
    if (!_prepareUpload()) return;
    final target = _parentGallery(gallery);
    if (target != null) parent.addImagesToGallery(files, target);
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
  bool commit({
    required TextEditingValue expectedValue,
    required TextEditingValue value,
  }) => isEditing && super.commit(expectedValue: expectedValue, value: value);
  @override
  bool commitText({
    required String expectedText,
    required TextEditingValue value,
  }) => isEditing && super.commitText(expectedText: expectedText, value: value);

  @override
  void dispose() {
    parent.text.removeListener(_readParent);
    parent.removeListener(_parentStateChanged);
    parent.deactivateEmbeddedEditor(this);
    text.removeListener(_writeBody);
    focus.removeListener(_activate);
    super.dispose();
  }
}

TextEditingValue _replaceBodyValue(TextEditingValue before, String after) {
  var start = 0;
  var oldEnd = before.text.length;
  var newEnd = after.length;
  while (start < oldEnd &&
      start < newEnd &&
      before.text[start] == after[start]) {
    start++;
  }
  while (oldEnd > start &&
      newEnd > start &&
      before.text[oldEnd - 1] == after[newEnd - 1]) {
    oldEnd--;
    newEnd--;
  }
  int move(int offset) => offset < start
      ? offset
      : offset <= oldEnd
      ? newEnd
      : offset + newEnd - oldEnd;
  return TextEditingValue(
    text: after,
    selection: before.selection.isValid
        ? TextSelection(
            baseOffset: move(before.selection.baseOffset),
            extentOffset: move(before.selection.extentOffset),
            affinity: before.selection.affinity,
            isDirectional: before.selection.isDirectional,
          )
        : before.selection,
    composing:
        before.composing.isValid &&
            (before.composing.end <= start || before.composing.start >= oldEnd)
        ? TextRange(
            start: move(before.composing.start),
            end: move(before.composing.end),
          )
        : TextRange.empty,
  );
}
