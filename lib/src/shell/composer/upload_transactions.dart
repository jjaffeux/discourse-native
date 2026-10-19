part of 'controller.dart';

final class _ComposerUploadTransactions {
  _ComposerUploadTransactions({
    required this._editor,
    required this._uploader,
    required this._prepare,
    required this._acceptsImage,
    required this._acceptsFile,
    required this._simultaneousLimit,
  });

  final _ComposerUploadEditor _editor;
  final ComposerImageUploader? _uploader;
  final ComposerUploadPreparer? _prepare;
  final bool Function(String filename)? _acceptsImage;
  final bool Function(String filename)? _acceptsFile;
  final int _simultaneousLimit;
  bool _disposed = false;

  MarkdownEditingController get text => _editor.text;
  bool get _isDisposed => _disposed || _editor.isDisposed;

  final List<ComposerUploadItem> _uploads = [];
  final Map<int, _PendingComposerUpload> _pendingUploads = {};
  int _nextUploadId = 0;
  int _nextUploadBatch = 0;
  late final _uploadPlaceholders = ComposerUploadPlaceholders(this);
  bool _updatingUploadPlaceholders = false;

  ComposerUploadPlaceholders get uploadPlaceholders => _uploadPlaceholders;

  void _replaceUploadPlaceholder(
    int id,
    String replacement, {
    bool removeLine = false,
  }) {
    final marker = _uploadPlaceholders[id];
    if (marker == null) return;
    final start = text.text.indexOf(marker);
    if (start < 0) return;
    var end = start + marker.length;
    if (removeLine && end < text.text.length && text.text[end] == '\n') end++;
    final old = text.value;
    int move(int offset) => offset <= start
        ? offset
        : offset < end
        ? start + replacement.length
        : offset + replacement.length - (end - start);
    _updatingUploadPlaceholders = true;
    try {
      text.value = old.copyWith(
        text: old.text.replaceRange(start, end, replacement),
        selection: old.selection.isValid
            ? TextSelection(
                baseOffset: move(old.selection.baseOffset),
                extentOffset: move(old.selection.extentOffset),
              )
            : old.selection,
        composing: TextRange.empty,
      );
    } finally {
      _updatingUploadPlaceholders = false;
    }
  }

  List<ComposerUploadItem> get uploads => List.unmodifiable(_uploads);
  List<ComposerUploadResult> get completedUploads => List.unmodifiable(
    _uploads
        .where((upload) => upload.status == ComposerUploadStatus.completed)
        .map((upload) => upload.result)
        .nonNulls,
  );
  bool get hasActiveUploads => _uploads.any(
    (upload) =>
        upload.status == ComposerUploadStatus.processing ||
        upload.status == ComposerUploadStatus.uploading ||
        upload.status == ComposerUploadStatus.retrying,
  );

  // Admission only: uploads already owned by this draft must still settle or
  // be cancelled while a close/discard is in progress.
  bool get canUpload => _editor.isEditing && _uploader != null;

  void addFiles(
    Iterable<ComposerUploadFile> files,
    int offset, {
    ComposerImageGalleryBlock? gallery,
  }) {
    gallery = gallery == null
        ? _editor.galleryAt(offset)
        : _editor.resolveGallery(gallery);
    _addUploads(
      files,
      offset,
      gallery: gallery,
      imagesOnly: false,
      forceStandalone:
          gallery == null && _isInsideUnprojectedGridLikeBlock(offset),
    );
  }

  void addImages(Iterable<ComposerUploadFile> files, int offset) {
    final gallery = _editor.galleryAt(offset);
    _addUploads(
      files,
      offset,
      gallery: gallery,
      forceStandalone:
          gallery == null && _isInsideUnprojectedGridLikeBlock(offset),
    );
  }

  void addImagesToGallery(
    Iterable<ComposerUploadFile> files,
    ComposerImageGalleryBlock gallery,
  ) {
    if (!canUpload) return;
    final queued = files.toList();
    if (queued.isEmpty) return;
    final current = _editor.resolveGallery(gallery);
    if (current != null) {
      _addUploads(queued, current.contentEnd, gallery: current);
      return;
    }

    // A picker can outlive the projection which opened it. The files have
    // already been chosen at this point, so a stale widget must not turn that
    // choice into a no-op. Keep the upload, but do not silently create a new
    // gallery in place of one the author changed or removed.
    _editor.showNotice(
      appL10n.thatGalleryChangedSoTheImagesWillBeAddedOutsideIt,
    );
    _addUploads(
      queued,
      _formerGalleryMemberSequenceEnd(gallery) ??
          gallery.start.clamp(0, text.text.length),
      forceStandalone: true,
    );
  }

  void _addUploads(
    Iterable<ComposerUploadFile> files,
    int offset, {
    ComposerImageGalleryBlock? gallery,
    bool forceStandalone = false,
    bool imagesOnly = true,
  }) {
    if (!canUpload) return;
    final all = files.toList();
    final validator = imagesOnly ? _acceptsImage : _acceptsFile;
    final valid = all
        .where((file) => validator?.call(file.name) ?? true)
        .toList();
    final rejected = all.length - valid.length;
    if (rejected > 0) {
      final purpose = imagesOnly ? appL10n.forImages : '';
      _editor.showNotice(
        rejected == 1
            ? appL10n.thatFileTypeIsNotAllowedOnThisSite((purpose).toString())
            : appL10n.fileTypesAreNotAllowedOnThisSite(
                (rejected).toString(),
                (purpose).toString(),
              ),
      );
    }
    if (valid.isEmpty) return;
    if (_simultaneousLimit > 0 && valid.length > _simultaneousLimit) {
      final kind = imagesOnly ? 'image' : 'file';
      final limit = _simultaneousLimit == 1
          ? appL10n.one((kind).toString())
          : '$_simultaneousLimit ${kind}s';
      _editor.showNotice(appL10n.uploadAtMostAtATime((limit).toString()));
      return;
    }

    if (valid.any((file) => !SiteConfig.isImageFilename(file.name))) {
      // Mixed drops stay together, outside image-only galleries.
      // The native caret can also land inside a projected gallery's tags.
      gallery ??= !_editor.usesInlineSlots
          ? null
          : text.galleryBlocks
                .where((block) => offset > block.start && offset < block.end)
                .firstOrNull;
      offset = gallery?.end ?? offset;
      gallery = null;
      forceStandalone = true;
    }

    final batch = _nextUploadBatch++;
    final insertsMarkdown =
        _editor.disposition != ComposerUploadDisposition.retainAttachment;
    final galleryTarget = gallery == null
        ? null
        : _galleryUploadTargetFor(gallery);
    final destination = gallery != null
        ? _ComposerUploadDestination.gallery
        : !forceStandalone &&
              insertsMarkdown &&
              _editor.usesInlineSlots &&
              _editor.autoGridEnabled &&
              valid.length >= 3
        ? _ComposerUploadDestination.newGallery
        : _ComposerUploadDestination.standalone;
    final anchor = (gallery?.contentEnd ?? offset).clamp(0, text.text.length);
    final added = <int>[];
    for (var order = 0; order < valid.length; order++) {
      final id = _nextUploadId++;
      final file = valid[order];
      _pendingUploads[id] = _PendingComposerUpload(
        batch: batch,
        order: order,
        anchor: anchor,
        launchAnchor: anchor,
        destination: destination,
        launchDestination: destination,
        galleryTarget: galleryTarget,
      );
      _uploads.add(
        ComposerUploadItem(
          id: id,
          file: file,
          progress: 0,
          status: ComposerUploadStatus.uploading,
        ),
      );
      added.add(id);
      if (_editor.usesInlineSlots) _uploadPlaceholders.add(id);
    }
    if (_editor.usesInlineSlots) {
      final at = gallery?.end ?? anchor;
      final markers = added.map((id) => _uploadPlaceholders[id]!).join('\n');
      _updatingUploadPlaceholders = true;
      try {
        _insertAt(at, _imageBlockInsertion(text.text, at, markers));
      } finally {
        _updatingUploadPlaceholders = false;
      }
      for (final id in added) {
        if (gallery == null) {
          _pendingUploads[id]!.anchor = text.text.indexOf(
            _uploadPlaceholders[id]!,
          );
        }
      }
    }
    for (final id in added) {
      _startUpload(id);
    }
    _editor.changed(affectsSubmission: true);
  }

  void retryUpload(int id) {
    if (!canUpload) return;
    final index = _uploadIndex(id);
    final pending = _pendingUploads[id];
    if (index < 0 || pending == null) return;
    // A retry is a transition out of the terminal failed state. Starting one
    // for an already active row loses its abort trigger and lets two requests
    // race to decide which result is inserted.
    if (_uploads[index].status != ComposerUploadStatus.failed ||
        !_uploads[index].retryable ||
        !pending.failed) {
      return;
    }
    pending.abort = Completer<void>();
    pending.result = null;
    pending.failed = false;
    _uploads[index] = _uploads[index].copyWith(
      progress: 0,
      status: ComposerUploadStatus.retrying,
      clearError: true,
      clearResult: true,
    );
    _startUpload(id);
    _editor.changed(affectsSubmission: true);
  }

  void cancelUpload(int id) => _cancelUploads([id]);

  void _cancelUploads(Iterable<int> ids) {
    final cancelled = ids.toList();
    final batches = <int>{};
    // Retire the whole selection before flushing peers. A later completed
    // upload must not be inserted while its own deleted slot is still waiting
    // to be cancelled.
    for (final id in cancelled) {
      final pending = _pendingUploads.remove(id);
      if (pending != null) {
        batches.add(pending.batch);
        if (!pending.abort.isCompleted) pending.abort.complete();
        pending.releasePreparation();
      }
      _uploads.removeWhere((upload) => upload.id == id);
    }
    for (final id in cancelled) {
      _replaceUploadPlaceholder(id, '', removeLine: true);
    }
    for (final batch in batches) {
      _flushReadyUploads(batch);
    }
    _editor.changed(affectsSubmission: true);
  }

  void _startUpload(int id) {
    final uploader = _uploader;
    final pending = _pendingUploads[id];
    final index = _uploadIndex(id);
    if (uploader == null || pending == null || index < 0) return;
    final file = _uploads[index].file;
    unawaited(
      Future<ComposerUploadResult>.sync(() async {
        final prepare = _prepare;
        if (prepare != null && pending.prepared == null) {
          _uploads[index] = _uploads[index].copyWith(
            status: ComposerUploadStatus.processing,
          );
          _editor.changed();
          final prepared = await prepare(
            file,
            abortTrigger: pending.abort.future,
          );
          if (_isDisposed ||
              _pendingUploads[id] != pending ||
              pending.abort.isCompleted) {
            await prepared.dispose();
            throw ComposerUploadException(appL10n.uploadCancelled);
          }
          pending.prepared = prepared;
          final current = _uploadIndex(id);
          _uploads[current] = _uploads[current].copyWith(
            file: prepared.file,
            status: ComposerUploadStatus.uploading,
          );
          _editor.changed();
        }
        if (_isDisposed ||
            _pendingUploads[id] != pending ||
            pending.abort.isCompleted) {
          throw ComposerUploadException(appL10n.uploadCancelled);
        }
        return uploader(
          pending.prepared?.file ?? file,
          abortTrigger: pending.abort.future,
          onProgress: (progress) {
            if (_isDisposed || !_pendingUploads.containsKey(id)) return;
            final current = _uploadIndex(id);
            if (current < 0) return;
            final previous = _uploads[current].progress;
            _uploads[current] = _uploads[current].copyWith(
              progress: progress.clamp(previous, 1),
            );
            _editor.changed();
          },
        );
      }).then(
        (result) {
          if (_isDisposed || !_pendingUploads.containsKey(id)) return;
          pending.releasePreparation();
          pending.result = result;
          if (SiteConfig.isImageFilename(result.originalFilename)) {
            text.cacheImageUrl(result.shortUrl, result.previewUrl);
          }
          if (isComposerVideoFilename(result.originalFilename) ||
              isPdfAttachment(result.originalFilename, result.shortUrl)) {
            text.cacheImageUrl(result.shortUrl, result.url);
          }
          _flushReadyUploads(pending.batch);
        },
        onError: (Object error) {
          if (_isDisposed || !_pendingUploads.containsKey(id)) return;
          pending.failed = true;
          final current = _uploadIndex(id);
          if (current < 0) return;
          _uploads[current] = _uploads[current].copyWith(
            status: ComposerUploadStatus.failed,
            error: switch (error) {
              ComposerUploadException(:final displayMessage) => displayMessage,
              _ => appL10n.couldnTUpload((file.name).toString()),
            },
            retryable: switch (error) {
              ComposerUploadException(:final retryable) => retryable,
              _ => true,
            },
          );
          _flushReadyUploads(pending.batch);
          _editor.changed(affectsSubmission: true);
        },
      ),
    );
  }

  void _flushReadyUploads(int batch) {
    while (true) {
      final waiting =
          _pendingUploads.entries
              .where((entry) => entry.value.batch == batch)
              .toList()
            ..sort((a, b) => a.value.order.compareTo(b.value.order));
      if (waiting.isEmpty) break;
      final first = waiting.where((entry) => !entry.value.failed).firstOrNull;
      if (first == null) break;
      final result = first.value.result;
      if (result == null) break;

      if (_editor.disposition == ComposerUploadDisposition.retainAttachment) {
        _pendingUploads.remove(first.key);
        final uploadIndex = _uploadIndex(first.key);
        if (uploadIndex >= 0) {
          _uploads[uploadIndex] = _uploads[uploadIndex].copyWith(
            progress: 1,
            status: ComposerUploadStatus.completed,
            result: result,
            clearError: true,
          );
        }
        continue;
      }

      final markdown = uploadFileMarkdown(result);
      final markerSelection = text.selection;
      final marker = _uploadPlaceholders[first.key];
      final markerStart = marker == null ? -1 : text.text.indexOf(marker);
      final markerSelected =
          text.keyboardSelectedSyntax?.start == markerStart &&
          markerSelection.start == markerStart &&
          !markerSelection.isCollapsed;
      if (markerStart >= 0) {
        if (first.value.destination == _ComposerUploadDestination.standalone) {
          // The slot itself owns ordering and both selection boundaries.
          // Replacing it atomically keeps a caret before the upload before
          // the finished image, even when completion races with typing.
          _pendingUploads.remove(first.key);
          _uploads.removeWhere((upload) => upload.id == first.key);
          _replaceUploadPlaceholder(first.key, markdown);
          continue;
        }
        final newGallery =
            first.value.destination == _ComposerUploadDestination.newGallery;
        _replaceUploadPlaceholder(first.key, '', removeLine: !newGallery);
        if (newGallery) first.value.anchor = markerStart;
      }
      final earlierFailed = waiting
          .where(
            (entry) =>
                entry.value.failed && entry.value.order < first.value.order,
          )
          .map((entry) => entry.value)
          .toList();
      var insertionOffset = first.value.anchor;
      var destination = first.value.destination;
      if (destination == _ComposerUploadDestination.newGallery &&
          _isInsideUnprojectedGridLikeBlock(insertionOffset)) {
        // The source can change while the picker/upload is open. Once the
        // anchor is surrounded by any grid-like raw block, creating another
        // wrapper would produce nested BBCode which neither composer can edit
        // losslessly.
        destination = _ComposerUploadDestination.standalone;
        for (final entry in waiting) {
          entry.value.destination = destination;
        }
      } else if (destination == _ComposerUploadDestination.gallery) {
        final currentGallery = _resolvePendingUploadGallery(first.value);
        if (currentGallery == null) {
          // The gallery may have been explicitly unwrapped, dissolved, or
          // changed into mixed raw content while an upload was in flight. Do
          // not recreate it behind the author's back.
          final target = first.value.galleryTarget;
          if (target == null) {
            for (final entry in waiting) {
              entry.value.destination = _ComposerUploadDestination.standalone;
            }
          } else {
            _demoteGalleryUploadTarget(
              target,
              fallbackAnchor: first.value.anchor,
            );
          }
          destination = _ComposerUploadDestination.standalone;
          insertionOffset = first.value.anchor;
        } else {
          insertionOffset = _galleryInsertionOffset(
            first.value,
            currentGallery,
          );
        }
      }

      final insertion = switch (destination) {
        _ComposerUploadDestination.newGallery => _galleryBlockInsertion(
          text.text,
          insertionOffset,
          markdown,
        ),
        _ComposerUploadDestination.gallery => _imageBlockInsertion(
          text.text,
          insertionOffset,
          markdown,
        ),
        _ComposerUploadDestination.standalone => _imageBlockInsertion(
          text.text,
          insertionOffset,
          markdown,
        ),
      };
      final earlierLaneUploads = _pendingUploads.values
          .where(
            (pending) =>
                pending.batch < first.value.batch &&
                _sameUploadLane(pending, first.value),
          )
          .toList();
      _pendingUploads.remove(first.key);
      _uploads.removeWhere((upload) => upload.id == first.key);
      _insertAt(insertionOffset, insertion);
      if (markerStart >= 0 &&
          markerStart == insertionOffset &&
          markerSelection.isValid) {
        final current = text.selection;
        text.clearKeyboardPillSelection();
        text.selection = markerSelected
            ? TextSelection.collapsed(offset: insertionOffset)
            : current.copyWith(
                baseOffset: markerSelection.baseOffset == markerStart
                    ? insertionOffset
                    : current.baseOffset,
                extentOffset: markerSelection.extentOffset == markerStart
                    ? insertionOffset
                    : current.extentOffset,
              );
      }

      // A later request is allowed to finish first, but it must not steal the
      // document slot reserved by an older request. Generic anchor movement
      // shifts those older slots after this insertion; restore the boundary
      // so an active upload or a retry still lands before the later result.
      for (final pending in earlierLaneUploads) {
        if (pending.anchor > insertionOffset) {
          pending.anchor = insertionOffset;
        }
      }

      if (destination == _ComposerUploadDestination.newGallery) {
        final beforeLength =
            insertionOffset > 0 && text.text[insertionOffset - 1] != '\n'
            ? 1
            : 0;
        final contentStart = insertionOffset + beforeLength + '[grid]\n'.length;
        final contentEnd = contentStart + markdown.length + 1;
        final created = _editor.galleryAt(contentStart);
        final target = created == null
            ? null
            : _PendingGalleryUploadTarget(created);
        for (final entry in _pendingUploads.entries.where(
          (entry) => entry.value.batch == batch,
        )) {
          entry.value.destination = _ComposerUploadDestination.gallery;
          entry.value.galleryTarget = target;
          entry.value.anchor = entry.value.order < first.value.order
              ? contentStart
              : contentEnd;
        }
      } else if (destination == _ComposerUploadDestination.gallery) {
        final target = first.value.galleryTarget;
        if (target != null) {
          final updated = _editor.galleryAt(insertionOffset);
          if (updated != null) target.gallery = updated;
        }
      }
      // A failed earlier item still owns the slot before what just landed. Its
      // anchor moved with the text insertion like every other pending upload;
      // put it back at the boundary so a later retry restores drop order.
      for (final pending in earlierFailed) {
        if (destination != _ComposerUploadDestination.newGallery) {
          // A failed slot in a newly-created gallery may already be anchored
          // before members inserted by an earlier flush. Never move it later
          // merely because another later result just arrived.
          if (pending.anchor > insertionOffset) {
            pending.anchor = insertionOffset;
          }
        }
      }
    }
    _editor.changed(affectsSubmission: true);
  }

  static bool _sameUploadLane(
    _PendingComposerUpload left,
    _PendingComposerUpload right,
  ) {
    if (left.galleryTarget != null &&
        identical(left.galleryTarget, right.galleryTarget)) {
      return true;
    }
    if (left.launchDestination != right.launchDestination) return false;
    if (left.launchDestination == _ComposerUploadDestination.gallery) {
      return false;
    }
    return left.launchAnchor == right.launchAnchor ||
        left.anchor == right.anchor;
  }

  int _uploadIndex(int id) => _uploads.indexWhere((upload) => upload.id == id);

  void _insertAt(int offset, String insertion) {
    final old = text.value;
    final at = offset.clamp(0, old.text.length);
    final uploadAnchors = [
      for (final pending in _pendingUploads.values) (pending, pending.anchor),
    ];
    int move(int value) => value < at ? value : value + insertion.length;

    // A reused separator is outside the insertion, but typing should resume
    // after it. Keep pending upload anchors at the insertion boundary so later
    // results still land before that text, in upload order.
    final reusesLineBreak =
        !insertion.endsWith('\n') &&
        at < old.text.length &&
        old.text[at] == '\n';
    final caretAfter = at + insertion.length + (reusesLineBreak ? 1 : 0);
    text.value = old.copyWith(
      text: old.text.replaceRange(at, at, insertion),
      selection:
          !old.selection.isValid ||
              (old.selection.isCollapsed && old.selection.extentOffset == at)
          ? TextSelection.collapsed(offset: caretAfter)
          : TextSelection(
              baseOffset: move(old.selection.baseOffset),
              extentOffset: move(old.selection.extentOffset),
            ),
      composing: TextRange.empty,
    );
    // [_onTextChanged] has to infer an arbitrary edit from a before/after
    // diff. When an insertion starts with the same newline already at [at],
    // that inference can place the common prefix beyond the true boundary and
    // leave peer uploads behind. This call knows the exact edit, so restore
    // the unambiguous transform after the listener has run.
    for (final (pending, anchor) in uploadAnchors) {
      pending.anchor = move(anchor);
    }
  }

  static String _imageBlockInsertion(
    String source,
    int offset,
    String markdown,
  ) {
    final at = offset.clamp(0, source.length);
    final before = at > 0 && source[at - 1] != '\n' ? '\n' : '';
    final after = at == source.length || source[at] != '\n' ? '\n' : '';
    final indent = composerListContinuationAt(source, at);
    return '$before$markdown$after'.replaceAll('\n', '\n$indent');
  }

  static String _galleryBlockInsertion(
    String source,
    int offset,
    String markdown,
  ) => _imageBlockInsertion(source, offset, '[grid]\n$markdown\n[/grid]');

  void disableAutomaticGalleries() {
    for (final pending in _pendingUploads.values) {
      if (pending.destination == _ComposerUploadDestination.newGallery) {
        pending.destination = _ComposerUploadDestination.standalone;
      }
    }
  }

  _PendingGalleryUploadTarget _galleryUploadTargetFor(
    ComposerImageGalleryBlock gallery,
  ) {
    final seen = <_PendingGalleryUploadTarget>{};
    for (final pending in _pendingUploads.values) {
      final target = pending.galleryTarget;
      if (target == null || target.demoted || !seen.add(target)) continue;
      final current = _editor.resolveGallery(
        target.gallery,
        anchor: pending.anchor,
      );
      if (current != null) {
        target.gallery = current;
        if (_sameComposerGallery(current, gallery)) return target;
      }
    }
    return _PendingGalleryUploadTarget(gallery);
  }

  int? _formerGalleryMemberSequenceEnd(ComposerImageGalleryBlock captured) {
    if (captured.images.isEmpty) return null;
    final current = text.imageBlocks;
    final matches = <int>[];
    for (
      var start = 0;
      start + captured.images.length <= current.length;
      start++
    ) {
      var matchesSequence = true;
      for (var index = 0; index < captured.images.length; index++) {
        final candidate = current[start + index];
        if (candidate.source != captured.images[index].source ||
            (index > 0 &&
                text.text
                    .substring(current[start + index - 1].end, candidate.start)
                    .trim()
                    .isNotEmpty)) {
          matchesSequence = false;
          break;
        }
      }
      if (matchesSequence) {
        matches.add(current[start + captured.images.length - 1].end);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  ComposerImageGalleryBlock? _resolvePendingUploadGallery(
    _PendingComposerUpload pending,
  ) {
    final target = pending.galleryTarget;
    if (target == null) return _editor.galleryAt(pending.anchor);
    if (target.demoted) return null;
    final current = _editor.resolveGallery(
      target.gallery,
      anchor: pending.anchor,
    );
    if (current != null) target.gallery = current;
    return current;
  }

  int _galleryInsertionOffset(
    _PendingComposerUpload pending,
    ComposerImageGalleryBlock gallery,
  ) {
    final anchor = pending.anchor;
    if (anchor >= gallery.contentStart &&
        anchor <= gallery.contentEnd &&
        !gallery.images.any(
          (image) => anchor > image.start && anchor < image.end,
        )) {
      return anchor;
    }
    return gallery.contentEnd;
  }

  List<_PendingComposerUpload> _pendingUploadsForGallery(
    ComposerImageGalleryBlock gallery,
  ) {
    final affected = <_PendingComposerUpload>[];
    for (final pending in _pendingUploads.values) {
      if (pending.destination != _ComposerUploadDestination.gallery) continue;
      final current = _resolvePendingUploadGallery(pending);
      if (current != null && _sameComposerGallery(current, gallery)) {
        affected.add(pending);
      }
    }
    return affected;
  }

  void _retargetPendingGalleryUploads(
    Iterable<_PendingComposerUpload> affected,
    ComposerImageGalleryBlock? updated, {
    required int fallbackAnchor,
  }) {
    final direct = affected.toSet();
    if (direct.isEmpty) return;
    final targets = <_PendingGalleryUploadTarget>{};
    for (final pending in direct) {
      final target = pending.galleryTarget;
      if (target != null) targets.add(target);
    }
    final anchor = (updated?.contentEnd ?? fallbackAnchor).clamp(
      0,
      text.text.length,
    );
    for (final target in targets) {
      if (updated == null) {
        target.demoted = true;
      } else {
        target.gallery = updated;
      }
    }
    for (final pending in _pendingUploads.values) {
      if (!direct.contains(pending) &&
          (pending.galleryTarget == null ||
              !targets.contains(pending.galleryTarget))) {
        continue;
      }
      pending.anchor = anchor;
      pending.destination = updated == null
          ? _ComposerUploadDestination.standalone
          : _ComposerUploadDestination.gallery;
    }
  }

  void _demoteGalleryUploadTarget(
    _PendingGalleryUploadTarget target, {
    required int fallbackAnchor,
  }) {
    target.demoted = true;
    final anchor = fallbackAnchor.clamp(0, text.text.length);
    for (final pending in _pendingUploads.values) {
      if (!identical(pending.galleryTarget, target)) continue;
      pending.destination = _ComposerUploadDestination.standalone;
      pending.anchor = anchor;
    }
  }

  bool _isInsideUnprojectedGridLikeBlock(int offset) {
    if (!_editor.usesInlineSlots) return false;
    final source = text.text;
    if (source.isEmpty || !source.toLowerCase().contains('[grid')) {
      return false;
    }
    final at = offset.clamp(0, source.length);
    final code = markdownCodeRanges(source);
    final images = parseComposerImages(source, codeRanges: code);
    final openings = <int>[];
    final marker = RegExp(r'\[(/?)grid\b', caseSensitive: false);
    var imageIndex = 0;

    bool isEscaped(int start) {
      var backslashes = 0;
      for (
        var index = start - 1;
        index >= 0 && source[index] == r'\';
        index--
      ) {
        backslashes++;
      }
      return backslashes.isOdd;
    }

    bool rangeContains(int start, int end, {required bool closed}) =>
        at > start && (closed ? at < end : at <= end);

    for (final match in marker.allMatches(source)) {
      while (imageIndex < images.length &&
          images[imageIndex].end <= match.start) {
        imageIndex++;
      }
      final insideImage =
          imageIndex < images.length &&
          images[imageIndex].start <= match.start &&
          match.start < images[imageIndex].end;
      if (code.contains(match.start) || insideImage || isEscaped(match.start)) {
        continue;
      }
      final newline = source.indexOf('\n', match.end);
      final bracket = source.indexOf(']', match.end);
      final complete = bracket >= 0 && (newline < 0 || bracket < newline);
      final closing = match.group(1) == '/';
      if (!closing) {
        openings.add(match.start);
        continue;
      }
      if (!complete || openings.isEmpty) continue;
      final start = openings.removeLast();
      if (rangeContains(start, bracket + 1, closed: true)) return true;
    }
    for (final start in openings) {
      if (rangeContains(start, source.length, closed: false)) return true;
    }
    return false;
  }

  _GalleryUploadEdit captureGalleryEdit(ComposerImageGalleryBlock gallery) =>
      _GalleryUploadEdit(this, _pendingUploadsForGallery(gallery));

  void documentChanged(String before, String after) {
    // Let EditableText finish applying its exact undo value before removing
    // slots whose requests have already settled. No stale token is saved.
    // Stripping amends the restored value: as an edit of its own it would
    // discard redo and be the step the next undo restores, slot and all.
    if (!_updatingUploadPlaceholders && _editor.usesInlineSlots) {
      scheduleMicrotask(() {
        if (_isDisposed) return;
        final settled = [
          for (final slot in _uploadPlaceholders.find(text.text))
            if (!_pendingUploads.containsKey(slot.id)) slot.id,
        ];
        if (settled.isEmpty) return;
        _editor.amendHistory(() {
          for (final id in settled) {
            _replaceUploadPlaceholder(id, '', removeLine: true);
          }
        });
      });
    }
    _moveUploadAnchors(before, after);
    if (!_updatingUploadPlaceholders) {
      final removed = _pendingUploads.keys.where((id) {
        final marker = _uploadPlaceholders[id];
        return marker != null && !text.text.contains(marker);
      }).toList();
      if (removed.isNotEmpty) _cancelUploads(removed);
    }
  }

  void _moveUploadAnchors(String before, String after) {
    if (_pendingUploads.isEmpty || before == after) return;
    final edit = _TextEdit.between(before, after);
    for (final pending in _pendingUploads.values) {
      pending.anchor = edit.move(pending.anchor);
    }
  }

  void replaceCompleted(Iterable<ComposerUploadResult> uploads) {
    clear();
    for (final upload in uploads) {
      _uploads.add(
        ComposerUploadItem(
          id: _nextUploadId++,
          file: ComposerUploadFile(
            name: upload.originalFilename,
            length: () async => 0,
            openRead: () => const Stream<List<int>>.empty(),
          ),
          progress: 1,
          status: ComposerUploadStatus.completed,
          result: upload,
        ),
      );
    }
  }

  void clear() {
    for (final pending in _pendingUploads.values) {
      if (!pending.abort.isCompleted) pending.abort.complete();
      pending.releasePreparation();
    }
    _pendingUploads.clear();
    _uploads.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}

final class _GalleryUploadEdit {
  _GalleryUploadEdit(this._owner, this._affected);

  final _ComposerUploadTransactions _owner;
  final List<_PendingComposerUpload> _affected;

  void complete(
    ComposerImageGalleryBlock? updated, {
    required int fallbackAnchor,
  }) => _owner._retargetPendingGalleryUploads(
    _affected,
    updated,
    fallbackAnchor: fallbackAnchor,
  );
}

class _PendingComposerUpload {
  _PendingComposerUpload({
    required this.batch,
    required this.order,
    required this.anchor,
    required this.launchAnchor,
    required this.destination,
    required this.launchDestination,
    required this.galleryTarget,
  });

  final int batch;
  final int order;
  int anchor;
  final int launchAnchor;
  _ComposerUploadDestination destination;
  final _ComposerUploadDestination launchDestination;
  _PendingGalleryUploadTarget? galleryTarget;
  Completer<void> abort = Completer<void>();
  ComposerUploadResult? result;
  bool failed = false;
  PreparedComposerUpload? prepared;

  void releasePreparation() {
    final owned = prepared;
    prepared = null;
    if (owned != null) unawaited(owned.dispose());
  }
}

class _PendingGalleryUploadTarget {
  _PendingGalleryUploadTarget(this.gallery);

  ComposerImageGalleryBlock gallery;
  bool demoted = false;
}

enum _ComposerUploadDestination { standalone, newGallery, gallery }
