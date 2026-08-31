import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/composer_upload.dart';
import 'composer_clipboard.dart';
import 'composer_controller.dart';
import 'composer_galleries.dart';
import 'composer_images.dart';
import 'composer_upload_picker.dart';

@immutable
final class ComposerMediaEditingState {
  const ComposerMediaEditingState({
    this.selectedImage,
    this.selectedImageGallery,
    this.selectedGallery,
    this.dropGallery,
    this.dragging = false,
    this.pickingGalleryImages = false,
    this.hasStandaloneImages = false,
  });

  final ComposerImageBlock? selectedImage;
  final ComposerImageGalleryBlock? selectedImageGallery;
  final ComposerImageGalleryBlock? selectedGallery;
  final ComposerImageGalleryBlock? dropGallery;
  final bool dragging;
  final bool pickingGalleryImages;
  final bool hasStandaloneImages;

  bool get hasSelectedMedia => selectedImage != null || selectedGallery != null;
}

@immutable
final class ComposerMediaPointerCapture {
  const ComposerMediaPointerCapture({this.image, this.gallery});

  final ComposerImageBlock? image;
  final ComposerImageGalleryBlock? gallery;
}

/// Owns the composer's independently changing image and gallery editing state.
///
/// Rendering and hit testing stay in [ComposerEditor]. This coordinator owns
/// media identity, mutations, and asynchronous operation lifetimes so replacing
/// the composer cannot send a late platform result into the next draft.
final class ComposerMediaEditingCoordinator extends FrameSafeNotifier
    implements ValueListenable<ComposerMediaEditingState> {
  ComposerMediaEditingCoordinator(ComposerController composer)
    : _composer = composer {
    _editImageGallery = selectGallery;
    _reorderImageGallery = reorderGalleryImage;
    _bindComposer();
  }

  ComposerController _composer;
  ComposerController get composer => _composer;

  ComposerMediaEditingState _state = const ComposerMediaEditingState();

  @override
  ComposerMediaEditingState get value => _state;

  final TextEditingController imageAlt = TextEditingController();

  late final ValueChanged<ComposerImageGalleryBlock> _editImageGallery;
  late final void Function(ComposerImageGalleryBlock, ComposerImageBlock, int)
  _reorderImageGallery;

  ComposerImageBlock? _pointerImage;
  ComposerImageGalleryBlock? _pointerGallery;
  int _lifecycleGeneration = 0;
  int _pickerGeneration = 0;
  bool _reconciling = false;

  bool get hasPointerCapture =>
      _pointerImage != null || _pointerGallery != null;

  bool get hasSelectedMediaProjection =>
      _composer.text.keyboardSelectedImage != null ||
      _state.selectedGallery != null;

  void replaceComposer(ComposerController composer) {
    if (identical(_composer, composer) || isDisposed) return;
    _lifecycleGeneration++;
    _pickerGeneration++;
    _unbindComposer();
    _composer = composer;
    _state = const ComposerMediaEditingState();
    imageAlt.clear();
    _bindComposer();
    notifySafely();
  }

  void _bindComposer() {
    final text = _composer.text;
    text.addListener(_reconcileMediaIdentity);
    text.onEditImageGallery = _editImageGallery;
    text.onReorderImageGallery = _reorderImageGallery;
  }

  void _unbindComposer() {
    final text = _composer.text;
    text.removeListener(_reconcileMediaIdentity);
    if (identical(text.onEditImageGallery, _editImageGallery)) {
      text.onEditImageGallery = null;
    }
    if (identical(text.onReorderImageGallery, _reorderImageGallery)) {
      text.onReorderImageGallery = null;
    }
    text.clearKeyboardPillSelection();
    _releasePointerCapture();
    if (_state.selectedImage case final image?) {
      text.releaseImagePointerEdit(image);
    }
    if (_state.selectedGallery case final gallery?) {
      text.releaseGalleryPointerEdit(gallery);
    }
    _pointerImage = null;
    _pointerGallery = null;
  }

  void capturePointer({
    ComposerImageBlock? image,
    ComposerImageGalleryBlock? gallery,
  }) {
    if (isDisposed) return;
    cancelPointerCapture();
    _pointerImage = image;
    _pointerGallery = image == null ? gallery : null;
    final text = _composer.text;
    if (_pointerImage case final captured?) {
      text.keepImageCollapsedForPointerEdit(captured);
    } else if (_pointerGallery case final captured?) {
      text.keepGalleryCollapsedForPointerEdit(captured);
    }
  }

  ComposerMediaPointerCapture takePointerCapture() {
    final capture = ComposerMediaPointerCapture(
      image: _pointerImage,
      gallery: _pointerGallery,
    );
    _pointerImage = null;
    _pointerGallery = null;
    return capture;
  }

  void cancelPointerCapture() {
    if (isDisposed) return;
    _releasePointerCapture();
    _pointerImage = null;
    _pointerGallery = null;
  }

  void _releasePointerCapture() {
    final text = _composer.text;
    if (_pointerImage case final image?) {
      text.releaseImagePointerEdit(image);
    }
    if (_pointerGallery case final gallery?) {
      text.releaseGalleryPointerEdit(gallery);
    }
  }

  void selectImageForKeyboard(
    ComposerImageBlock image, {
    bool moveCaretToEnd = true,
  }) {
    if (isDisposed) return;
    dismissGallery(requestFocus: false);
    _clearSelectedImageState(clearKeyboardSelection: true);
    final text = _composer.text;
    if (moveCaretToEnd) {
      text.selection = TextSelection.collapsed(offset: image.end);
    }
    text.releaseImagePointerEdit(image);
    _composer.autocomplete.dismiss();
    text.selectPillForKeyboard(image);
    showImageMenu(image);
  }

  void showImageMenu(ComposerImageBlock image, {bool refreshAlt = true}) {
    if (isDisposed) return;
    dismissGallery(requestFocus: false);
    final selected = _state.selectedImage;
    if (selected != null && !_sameImage(selected, image)) {
      _composer.text.releaseImagePointerEdit(selected);
    }
    _composer.text.keepImageCollapsedForPointerEdit(image);
    if (refreshAlt) imageAlt.text = image.alt;
    _setState(
      selectedImage: image,
      selectedImageGallery: _composer.galleryForImage(image),
      selectedGallery: null,
      dropGallery: _state.dropGallery,
      dragging: _state.dragging,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
  }

  void saveImageAlt() {
    final image = _state.selectedImage;
    if (image == null || isDisposed) return;
    _composer.text.releaseImagePointerEdit(image);
    _clearSelectedImageState(clearKeyboardSelection: true);
    _composer.setImageAlt(image, imageAlt.text);
    _composer.focus.requestFocus();
  }

  void scaleImage(int scale) {
    final image = _state.selectedImage;
    if (image == null || isDisposed) return;
    _composer.text.releaseImagePointerEdit(image);
    _clearSelectedImageState(clearKeyboardSelection: true);
    _composer.setImageScale(image, scale);
    final resized = _composer.text.imageBlocks
        .where((candidate) => candidate.start == image.start)
        .firstOrNull;
    if (resized != null) {
      _composer.autocomplete.dismiss();
      _composer.text.selectPillForKeyboard(resized);
      showImageMenu(resized, refreshAlt: false);
    }
    _composer.focus.requestFocus();
  }

  void dismissImage({bool requestFocus = true}) {
    final image = _state.selectedImage;
    if (image == null || isDisposed) return;
    _composer.text.releaseImagePointerEdit(image);
    _clearSelectedImageState(clearKeyboardSelection: true);
    if (requestFocus) _composer.focus.requestFocus();
  }

  void deleteSelectedImage() {
    final image = _state.selectedImage;
    if (image == null || isDisposed) return;
    _composer.text.releaseImagePointerEdit(image);
    _clearSelectedImageState(clearKeyboardSelection: true);
    _composer.removeImage(image);
    _composer.focus.requestFocus();
  }

  void moveSelectedImageOutOfGallery() {
    final image = _state.selectedImage;
    if (image == null || isDisposed) return;
    final gallery = _composer.galleryForImage(image);
    if (gallery == null) return;
    _composer.text.releaseImagePointerEdit(image);
    _clearSelectedImageState(clearKeyboardSelection: true);
    _composer.moveImageOutOfGallery(gallery, image);
    _composer.focus.requestFocus();
  }

  void reorderGalleryImage(
    ComposerImageGalleryBlock gallery,
    ComposerImageBlock image,
    int newIndex,
  ) {
    if (isDisposed) return;
    _clearSelectedImageState(clearKeyboardSelection: true);
    _composer.reorderGalleryImage(gallery, image, newIndex);
    _composer.focus.requestFocus();
  }

  void clearKeyboardImageSelection() {
    if (isDisposed || _composer.text.keyboardSelectedImage == null) return;
    _clearSelectedImageState(clearKeyboardSelection: true);
  }

  void _clearSelectedImageState({required bool clearKeyboardSelection}) {
    final image = _state.selectedImage;
    final hadState = image != null || _state.selectedImageGallery != null;
    final wasReconciling = _reconciling;
    _reconciling = true;
    try {
      if (hadState) {
        _setState(
          selectedImage: null,
          selectedImageGallery: null,
          selectedGallery: _state.selectedGallery,
          dropGallery: _state.dropGallery,
          dragging: _state.dragging,
          pickingGalleryImages: _state.pickingGalleryImages,
        );
      }
      if (image != null) _composer.text.releaseImagePointerEdit(image);
      if (clearKeyboardSelection &&
          _composer.text.keyboardSelectedImage != null) {
        _composer.text.clearKeyboardPillSelection();
      }
    } finally {
      _reconciling = wasReconciling;
    }
  }

  void selectGallery(ComposerImageGalleryBlock gallery) {
    if (isDisposed) return;
    _clearSelectedImageState(clearKeyboardSelection: true);
    final selected = _state.selectedGallery;
    if (selected != null && !_sameGallery(selected, gallery)) {
      _composer.text.releaseGalleryPointerEdit(selected);
    }
    _composer.text.keepGalleryCollapsedForPointerEdit(gallery);
    _composer.text.selection = TextSelection.collapsed(offset: gallery.end);
    _setState(
      selectedImage: null,
      selectedImageGallery: null,
      selectedGallery: gallery,
      dropGallery: _state.dropGallery,
      dragging: _state.dragging,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
  }

  void dismissGallery({bool requestFocus = true}) {
    final selected = _state.selectedGallery;
    if (selected == null || isDisposed) return;
    final current = _resolveSelectedGallery(selected);
    _composer.text.releaseGalleryPointerEdit(selected);
    if (current != null && !_sameGallery(current, selected)) {
      _composer.text.releaseGalleryPointerEdit(current);
    }
    _setState(
      selectedImage: _state.selectedImage,
      selectedImageGallery: _state.selectedImageGallery,
      selectedGallery: null,
      dropGallery: _state.dropGallery,
      dragging: _state.dragging,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
    if (requestFocus) _composer.focus.requestFocus();
  }

  void setSelectedGalleryMode(ComposerGalleryMode mode) {
    final gallery = _state.selectedGallery;
    if (gallery == null || isDisposed) return;
    _composer.text.releaseGalleryPointerEdit(gallery);
    _composer.setGalleryMode(gallery, mode);
    _composer.focus.requestFocus();
  }

  void unwrapSelectedGallery() {
    final gallery = _state.selectedGallery;
    if (gallery == null || isDisposed) return;
    _composer.text.releaseGalleryPointerEdit(gallery);
    _setState(
      selectedImage: _state.selectedImage,
      selectedImageGallery: _state.selectedImageGallery,
      selectedGallery: null,
      dropGallery: _state.dropGallery,
      dragging: _state.dragging,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
    _composer.unwrapGallery(gallery);
    _composer.focus.requestFocus();
  }

  Future<void> pickImagesForSelectedGallery(
    ComposerImagePicker pickImages,
  ) async {
    final gallery = _state.selectedGallery;
    if (gallery == null || _state.pickingGalleryImages || isDisposed) return;
    final composer = _composer;
    final lifecycle = _lifecycleGeneration;
    final operation = ++_pickerGeneration;
    _setState(
      selectedImage: _state.selectedImage,
      selectedImageGallery: _state.selectedImageGallery,
      selectedGallery: gallery,
      dropGallery: _state.dropGallery,
      dragging: _state.dragging,
      pickingGalleryImages: true,
    );
    try {
      final files = await pickImages();
      if (!_isCurrent(composer, lifecycle) || operation != _pickerGeneration) {
        return;
      }
      composer.addImagesToGallery(files, gallery);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'composer.gallery.pickImages',
        source: 'platform',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      if (_isCurrent(composer, lifecycle) && operation == _pickerGeneration) {
        composer.showNotice("Couldn't open the image picker.");
      }
    } finally {
      if (_isCurrent(composer, lifecycle) && operation == _pickerGeneration) {
        _setState(
          selectedImage: _state.selectedImage,
          selectedImageGallery: _state.selectedImageGallery,
          selectedGallery: _state.selectedGallery,
          dropGallery: _state.dropGallery,
          dragging: _state.dragging,
          pickingGalleryImages: false,
        );
        composer.focus.requestFocus();
      }
    }
  }

  Future<void> chooseExistingImagesForSelectedGallery(
    Future<List<ComposerImageBlock>?> Function(List<ComposerImageBlock>)
    chooseImages,
  ) async {
    final gallery = _state.selectedGallery;
    if (gallery == null || isDisposed) return;
    final images = _composer.standaloneImages;
    if (images.isEmpty) return;
    final composer = _composer;
    final lifecycle = _lifecycleGeneration;
    final selected = await chooseImages(images);
    if (!_isCurrent(composer, lifecycle) ||
        selected == null ||
        selected.isEmpty) {
      return;
    }
    final current = _resolveSelectedGallery(gallery);
    if (_state.selectedGallery case final active?
        when _sameGallery(active, gallery) ||
            (current != null && _sameGallery(active, current))) {
      dismissGallery(requestFocus: false);
    }
    composer.addExistingImagesToGallery(gallery, selected);
    composer.focus.requestFocus();
  }

  Future<bool> pasteClipboardImages(
    ComposerClipboardImageReader readClipboardImages,
  ) async {
    final composer = _composer;
    if (isDisposed || composer.imageUploader == null || composer.loadingBody) {
      return false;
    }
    final lifecycle = _lifecycleGeneration;
    final selection = composer.text.selection;
    final offset = selection.isValid
        ? selection.extentOffset
        : composer.text.text.length;

    List<ComposerUploadFile> files;
    try {
      files = await readClipboardImages();
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'composer.readClipboardImages',
        source: 'platform',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      return !_isCurrent(composer, lifecycle);
    }
    if (!_isCurrent(composer, lifecycle)) return true;
    if (files.isEmpty) return false;

    composer.addImages(files, offset);
    composer.focus.requestFocus();
    return true;
  }

  void updateDropTarget(ComposerImageGalleryBlock? gallery) {
    if (isDisposed) return;
    _setState(
      selectedImage: _state.selectedImage,
      selectedImageGallery: _state.selectedImageGallery,
      selectedGallery: _state.selectedGallery,
      dropGallery: gallery,
      dragging: _state.dragging,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
  }

  void beginDrag() {
    if (isDisposed || _state.dragging) return;
    _setState(
      selectedImage: _state.selectedImage,
      selectedImageGallery: _state.selectedImageGallery,
      selectedGallery: _state.selectedGallery,
      dropGallery: _state.dropGallery,
      dragging: true,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
  }

  void cancelDrag() {
    if (isDisposed || (!_state.dragging && _state.dropGallery == null)) return;
    _setState(
      selectedImage: _state.selectedImage,
      selectedImageGallery: _state.selectedImageGallery,
      selectedGallery: _state.selectedGallery,
      dropGallery: null,
      dragging: false,
      pickingGalleryImages: _state.pickingGalleryImages,
    );
  }

  void dropImages(Iterable<ComposerUploadFile> files, {required int offset}) {
    if (isDisposed) return;
    final gallery = _state.dropGallery;
    cancelDrag();
    if (gallery != null) {
      _composer.addImagesToGallery(files, gallery);
    } else {
      _composer.addImages(files, offset);
    }
  }

  KeyEventResult? handleKeyEvent(
    KeyEvent event, {
    required bool hasModifier,
    required bool hasCommandModifier,
  }) {
    if (isDisposed) return null;
    _reconcileMediaIdentity();
    if (_state.selectedGallery case final gallery?) {
      final isKeyPress = event is KeyDownEvent || event is KeyRepeatEvent;
      if (isKeyPress && !hasModifier) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          dismissGallery();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final moveLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
          dismissGallery(requestFocus: false);
          _composer.text.selection = TextSelection.collapsed(
            offset: moveLeft ? gallery.start : gallery.end,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete) {
          return KeyEventResult.handled;
        }
      }
      final isDeletion =
          event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete;
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        return KeyEventResult.ignored;
      }
      if (hasCommandModifier && !isDeletion) return KeyEventResult.ignored;
      return KeyEventResult.handled;
    }

    final selectedImage = _composer.text.keyboardSelectedImage;
    if (selectedImage != null) {
      final isPlainEscape =
          event is KeyDownEvent &&
          !hasModifier &&
          event.logicalKey == LogicalKeyboardKey.escape;
      if (isPlainEscape) {
        clearKeyboardImageSelection();
        return KeyEventResult.handled;
      }
      final isArrowPress = event is KeyDownEvent || event is KeyRepeatEvent;
      final isPlainHorizontalArrow =
          isArrowPress &&
          !hasModifier &&
          (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight);
      if (isPlainHorizontalArrow) {
        final moveLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
        clearKeyboardImageSelection();
        _composer.text.selection = TextSelection.collapsed(
          offset: moveLeft ? selectedImage.start : selectedImage.end,
        );
        return KeyEventResult.handled;
      }
      final isPlainEnter =
          event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          !hasModifier;
      if (isPlainEnter) {
        showImageMenu(selectedImage);
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.backspace &&
          !hasModifier) {
        clearKeyboardImageSelection();
        _composer.removeImage(selectedImage);
        return KeyEventResult.handled;
      }
      final isDeletion =
          event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete;
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        return KeyEventResult.ignored;
      }
      if (hasCommandModifier && !isDeletion) return KeyEventResult.ignored;
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final value = _composer.text.value;
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    if (value.isComposingRangeValid && !value.composing.isCollapsed) {
      return null;
    }

    final caret = selection.extentOffset;
    final entersGalleryFromEnd =
        event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowUp;
    final entersGalleryFromStart =
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!hasModifier && (entersGalleryFromEnd || entersGalleryFromStart)) {
      final gallery = _composer.text.galleryBlocks
          .where(
            (candidate) =>
                _composer.text.isGalleryCollapsed(candidate) &&
                (entersGalleryFromEnd
                    ? candidate.end == caret
                    : candidate.start == caret),
          )
          .firstOrNull;
      if (gallery != null) {
        selectGallery(gallery);
        return KeyEventResult.handled;
      }
    }
    if (!hasModifier && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final image = _collapsedImageEndingAt(caret);
      if (image != null) {
        selectImageForKeyboard(image, moveCaretToEnd: false);
        return KeyEventResult.handled;
      }
    }
    final isPlainHorizontalArrow =
        !hasModifier &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight);
    if (isPlainHorizontalArrow) {
      final image = event.logicalKey == LogicalKeyboardKey.arrowLeft
          ? _collapsedImageEndingAt(caret)
          : _collapsedImageStartingAt(caret);
      if (image != null) {
        selectImageForKeyboard(image, moveCaretToEnd: false);
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent) return null;
    final deletes =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (deletes) {
      final gallery = _composer.text.galleryBlocks
          .where(
            (candidate) =>
                _composer.text.isGalleryCollapsed(candidate) &&
                (event.logicalKey == LogicalKeyboardKey.backspace
                    ? candidate.end == caret
                    : candidate.start == caret),
          )
          .firstOrNull;
      if (gallery != null) {
        selectGallery(gallery);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) return null;
    final image = _collapsedImageEndingAt(caret);
    if (image == null) return null;
    _composer.removeImage(image);
    return KeyEventResult.handled;
  }

  ComposerImageBlock? _collapsedImageEndingAt(int caret) => _composer
      .text
      .imageBlocks
      .where(
        (image) => image.end == caret && _composer.text.isImageCollapsed(image),
      )
      .firstOrNull;

  ComposerImageBlock? _collapsedImageStartingAt(int caret) => _composer
      .text
      .imageBlocks
      .where(
        (image) =>
            image.start == caret && _composer.text.isImageCollapsed(image),
      )
      .firstOrNull;

  void _reconcileMediaIdentity() {
    if (_reconciling || isDisposed || !_state.hasSelectedMedia) return;
    _reconciling = true;
    try {
      var selectedImage = _state.selectedImage;
      var selectedGallery = _state.selectedGallery;
      ComposerImageGalleryBlock? selectedImageGallery;

      if (selectedImage != null) {
        final current = _resolveSelectedImage(selectedImage);
        if (current == null) {
          _composer.text.releaseImagePointerEdit(selectedImage);
          selectedImage = null;
          if (_composer.text.keyboardSelectedImage != null) {
            _composer.text.clearKeyboardPillSelection();
          }
        } else {
          if (!_sameImage(current, selectedImage)) {
            _composer.text.releaseImagePointerEdit(selectedImage);
            _composer.text.keepImageCollapsedForPointerEdit(current);
          }
          selectedImage = current;
          selectedImageGallery = _composer.galleryForImage(current);
          if (_composer.text.keyboardSelectedImage == null) {
            _composer.text.selectPillForKeyboard(current);
          }
        }
      }

      if (selectedGallery != null) {
        final current = _resolveSelectedGallery(selectedGallery);
        if (current == null) {
          _composer.text.releaseGalleryPointerEdit(selectedGallery);
          selectedGallery = null;
        } else {
          if (!_sameGallery(current, selectedGallery)) {
            _composer.text.releaseGalleryPointerEdit(selectedGallery);
            _composer.text.keepGalleryCollapsedForPointerEdit(current);
          }
          selectedGallery = current;
        }
      }

      _setState(
        selectedImage: selectedImage,
        selectedImageGallery: selectedImageGallery,
        selectedGallery: selectedGallery,
        dropGallery: _state.dropGallery,
        dragging: _state.dragging,
        pickingGalleryImages: _state.pickingGalleryImages,
      );
    } finally {
      _reconciling = false;
    }
  }

  ComposerImageBlock? _resolveSelectedImage(ComposerImageBlock selected) {
    final images = _composer.text.imageBlocks;
    final exact = images
        .where((image) => _sameImage(image, selected))
        .firstOrNull;
    if (exact != null) return exact;
    final sameSource =
        images.where((image) => image.source == selected.source).toList()..sort(
          (left, right) => (left.start - selected.start).abs().compareTo(
            (right.start - selected.start).abs(),
          ),
        );
    if (sameSource.isNotEmpty) return sameSource.first;
    final sameUrl = images.where((image) => image.url == selected.url).toList();
    return sameUrl.length == 1 ? sameUrl.single : null;
  }

  ComposerImageGalleryBlock? _resolveSelectedGallery(
    ComposerImageGalleryBlock selected,
  ) {
    final galleries = _composer.text.galleryBlocks;
    if (galleries.isEmpty) return null;
    final exact = galleries
        .where((gallery) => _sameGallery(gallery, selected))
        .firstOrNull;
    if (exact != null) return exact;

    final sameSource =
        galleries.where((gallery) => gallery.source == selected.source).toList()
          ..sort(
            (left, right) => (left.start - selected.start).abs().compareTo(
              (right.start - selected.start).abs(),
            ),
          );
    if (sameSource.isNotEmpty) return sameSource.first;

    final selectedUrls = {for (final image in selected.images) image.url};
    if (selectedUrls.isNotEmpty) {
      final related = <(ComposerImageGalleryBlock, int)>[
        for (final gallery in galleries)
          (
            gallery,
            gallery.images
                .where((image) => selectedUrls.contains(image.url))
                .length,
          ),
      ]..removeWhere((candidate) => candidate.$2 == 0);
      related.sort((left, right) {
        final overlap = right.$2.compareTo(left.$2);
        if (overlap != 0) return overlap;
        return (left.$1.start - selected.start).abs().compareTo(
          (right.$1.start - selected.start).abs(),
        );
      });
      if (related.isNotEmpty) return related.first.$1;
    }

    return galleries
        .where((gallery) => gallery.start == selected.start)
        .firstOrNull;
  }

  bool _isCurrent(ComposerController composer, int lifecycle) =>
      !isDisposed &&
      identical(_composer, composer) &&
      _lifecycleGeneration == lifecycle;

  void _setState({
    required ComposerImageBlock? selectedImage,
    required ComposerImageGalleryBlock? selectedImageGallery,
    required ComposerImageGalleryBlock? selectedGallery,
    required ComposerImageGalleryBlock? dropGallery,
    required bool dragging,
    required bool pickingGalleryImages,
  }) {
    final hasStandaloneImages =
        selectedGallery != null && _composer.standaloneImages.isNotEmpty;
    final next = ComposerMediaEditingState(
      selectedImage: selectedImage,
      selectedImageGallery: selectedImageGallery,
      selectedGallery: selectedGallery,
      dropGallery: dropGallery,
      dragging: dragging,
      pickingGalleryImages: pickingGalleryImages,
      hasStandaloneImages: hasStandaloneImages,
    );
    if (_sameState(_state, next)) return;
    _state = next;
    notifySafely();
  }

  static bool _sameState(
    ComposerMediaEditingState left,
    ComposerMediaEditingState right,
  ) =>
      _sameNullableImage(left.selectedImage, right.selectedImage) &&
      _sameNullableGallery(
        left.selectedImageGallery,
        right.selectedImageGallery,
      ) &&
      _sameNullableGallery(left.selectedGallery, right.selectedGallery) &&
      _sameNullableGallery(left.dropGallery, right.dropGallery) &&
      left.dragging == right.dragging &&
      left.pickingGalleryImages == right.pickingGalleryImages &&
      left.hasStandaloneImages == right.hasStandaloneImages;

  static bool _sameNullableImage(
    ComposerImageBlock? left,
    ComposerImageBlock? right,
  ) => left == null ? right == null : right != null && _sameImage(left, right);

  static bool _sameNullableGallery(
    ComposerImageGalleryBlock? left,
    ComposerImageGalleryBlock? right,
  ) =>
      left == null ? right == null : right != null && _sameGallery(left, right);

  static bool _sameImage(ComposerImageBlock left, ComposerImageBlock right) =>
      left.start == right.start &&
      left.end == right.end &&
      left.source == right.source;

  static bool _sameGallery(
    ComposerImageGalleryBlock left,
    ComposerImageGalleryBlock right,
  ) =>
      left.start == right.start &&
      left.end == right.end &&
      left.source == right.source;

  @override
  void dispose() {
    if (isDisposed) return;
    _lifecycleGeneration++;
    _pickerGeneration++;
    _unbindComposer();
    imageAlt.dispose();
    super.dispose();
  }
}
