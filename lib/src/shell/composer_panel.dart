import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../data/composer_geometry_store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/composer_upload.dart';
import '../models/topic.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'composer_autocomplete.dart';
import 'composer_clipboard.dart';
import 'composer_controller.dart';
import 'composer_discard.dart';
import 'composer_drop.dart';
import 'composer_galleries.dart';
import 'composer_images.dart';
import 'composer_link.dart';
import 'composer_marks.dart';
import 'composer_media_editing_coordinator.dart';
import 'composer_quotes.dart';
import 'composer_suggestions.dart';
import 'composer_upload_picker.dart';
import 'emoji_composer.dart';
import 'emoji_picker.dart';
import 'image_decode.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'topic_category_picker.dart';
import 'topic_tag_picker.dart';
import 'topic_taxonomy_fields.dart';

const double _composerPanelRadius = 22;

class ComposerPanel extends StatelessWidget {
  const ComposerPanel({
    super.key,
    required this.composer,
    this.height,
    this.onMove,
    this.onMoveEnd,
    this.pickImages = pickComposerImages,
    this.readClipboardImages = readComposerClipboardImages,
  });

  final ComposerController composer;
  final double? height;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onMoveEnd;
  final ComposerImagePicker pickImages;
  final ComposerClipboardImageReader readClipboardImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    composer.text.configureQuoteContentsResolver(
      (block) => controller.quoteContentsFor(composer.target, block),
      context: (controller, composer.target),
    );

    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        final target = composer.target;
        final error = composer.error;
        final notice = composer.notice;
        void close() => unawaited(
          closeComposerFromPanel(
            context: context,
            composer: composer,
            controller: controller,
          ),
        );

        return Container(
          key: const ValueKey('composer-frame'),
          height:
              height ??
              (target.createsTopic || target.editsTopicMetadata
                  ? topicComposerHeight
                  : target.isTaxonomyEdit
                  ? 190
                  : composerHeight),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.shell.content,
            borderRadius: BorderRadius.circular(_composerPanelRadius),
            border: Border.all(color: theme.shell.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  controller.submitComposer,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  controller.submitComposer,
              const SingleActivator(LogicalKeyboardKey.escape): close,
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                  composer.toggleMark(ComposerMark.bold),
              const SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
              ): () =>
                  composer.toggleMark(ComposerMark.bold),
              const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
                  composer.toggleMark(ComposerMark.italic),
              const SingleActivator(
                LogicalKeyboardKey.keyI,
                control: true,
              ): () =>
                  composer.toggleMark(ComposerMark.italic),
              const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
                  composer.toggleSelectedInlineCode,
              const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () =>
                  unawaited(
                    showComposerLinkDialog(
                      context: context,
                      composer: composer,
                    ),
                  ),
              ...PluginScope.of(
                context,
              ).registry.composerShortcuts(context, composer),
            },
            child: FocusScope(
              canRequestFocus: !composer.discarding,
              descendantsAreFocusable: !composer.discarding,
              descendantsAreTraversable: !composer.discarding,
              child: AbsorbPointer(
                absorbing: composer.discarding,
                child: Column(
                  children: [
                    _Header(
                      composer: composer,
                      onClose: close,
                      closeTooltip: composer.canSaveDraft
                          ? 'Save and close'
                          : 'Close composer',
                      onMove: onMove,
                      onMoveEnd: onMoveEnd,
                    ),
                    if (target.isPrivateMessage)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                        child: InputDecorator(
                          key: const ValueKey(
                            'composer-private-message-recipients',
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'To',
                          ),
                          child: Text(target.targetRecipients!),
                        ),
                      ),
                    if (target.createsTopic || target.editsTopicMetadata)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                        child: TextField(
                          controller: composer.title,
                          readOnly: composer.discarding,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Title',
                          ),
                        ),
                      ),
                    if (target.isNewTopic ||
                        target.editsTopicMetadata ||
                        target.isTaxonomyEdit)
                      _TopicTaxonomy(composer: composer),
                    if (!target.isTaxonomyEdit) ...[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          child: ComposerEditor(
                            composer: composer,
                            pickImages: pickImages,
                            readClipboardImages: readClipboardImages,
                            onSuggestionAction:
                                ({
                                  required context,
                                  required composer,
                                  required suggestion,
                                  anchor,
                                }) async {
                                  if (suggestion.action !=
                                      ComposerSuggestionAction
                                          .openEmojiPicker) {
                                    return;
                                  }
                                  await openEmojiPickerForTopicComposer(
                                    context: context,
                                    composer: composer,
                                    initialQuery:
                                        composer.autocomplete.trigger?.query ??
                                        suggestion.value,
                                    anchor: anchor,
                                  );
                                },
                            hintText: switch (target) {
                              _ when composer.loadingBody =>
                                'Loading that post…',
                              _ when target.isPrivateMessage =>
                                'Write your message…',
                              _ when target.isNewTopic => 'Write your topic…',
                              _ when target.isEdit => 'Edit this post…',
                              _ when target.replyToUsername != null =>
                                'Reply to @${target.replyToUsername}…',
                              _ => 'Write a reply…',
                            },
                            textStyle: theme.textTheme.bodyMedium,
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    if (composer.uploads.isNotEmpty)
                      ComposerUploadQueue(composer: composer),
                    _Footer(
                      composer: composer,
                      pickImages: pickImages,
                      message:
                          error?.message ??
                          notice ??
                          composer.taxonomyValidationMessage ??
                          (composer.localDraftFailed
                              ? "Couldn't save this draft on this device."
                              : composer.draftStatus == DraftStatus.failing ||
                                    composer.draftsGaveUp
                              ? 'Not saved on the site — kept on this device only.'
                              : null),
                      isError:
                          error != null ||
                          composer.localDraftFailed ||
                          composer.taxonomyValidationMessage != null,
                      busy:
                          composer.discarding ||
                          composer.submitting ||
                          composer.state == ComposerState.checking ||
                          composer.loadingBody,
                      label: switch (composer) {
                        _ when composer.canRecheck => 'Check again',
                        _ when target.isEdit => 'Save',
                        _ when target.isPrivateMessage => 'Send message',
                        _ when target.isNewTopic => 'Create topic',
                        _ => 'Reply',
                      },
                      onSubmit: switch (composer) {
                        _ when composer.canRecheck =>
                          controller.recheckComposer,
                        _ when composer.canSubmit => controller.submitComposer,
                        _ => null,
                      },
                      discardLabel: target.isEdit ? 'Cancel edit' : 'Discard',
                      onDiscard: () => unawaited(
                        requestComposerDiscard(
                          context: context,
                          composer: composer,
                          controller: controller,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class FloatingComposerPanel extends StatefulWidget {
  const FloatingComposerPanel({
    super.key,
    required this.composer,
    this.geometryStore = const ComposerGeometryStore(),
  });

  final ComposerController composer;
  final ComposerGeometryStore geometryStore;

  @override
  State<FloatingComposerPanel> createState() => _FloatingComposerPanelState();
}

class _FloatingComposerPanelState extends State<FloatingComposerPanel> {
  static const double _inset = 16;
  static const double _defaultWidth = 760;
  static const double _minimumWidth = 360;
  static const double _minimumReplyHeight = 180;
  static const double _minimumTopicHeight = 300;
  static const double _edgeHandleExtent = 16;
  static const double _cornerHandleExtent =
      _edgeHandleExtent + _composerPanelRadius;
  static const Duration _geometryRestoreDeadline = Duration(milliseconds: 100);

  Size? _size;
  Offset? _position;
  ComposerGeometryPreference? _restoredPreference;
  bool _geometryLoaded = false;
  bool _geometryChanged = false;
  Future<void> _pendingGeometryWrite = Future.value();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreGeometry());
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!_geometryLoaded) return const SizedBox.shrink();

      final bounds = Size(constraints.maxWidth, constraints.maxHeight);
      final geometry = _geometryFor(bounds);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          // The panel inset leaves room for resize targets centered over the
          // frame, so the painted border itself activates the resize cursor.
          Positioned(
            left: geometry.position.dx - _edgeHandleExtent,
            top: geometry.position.dy - _edgeHandleExtent,
            width: geometry.size.width + _edgeHandleExtent * 2,
            height: geometry.size.height + _edgeHandleExtent * 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: _edgeHandleExtent,
                  top: _edgeHandleExtent,
                  width: geometry.size.width,
                  height: geometry.size.height,
                  child: ComposerPanel(
                    composer: widget.composer,
                    height: geometry.size.height,
                    onMove: (delta) => _move(delta, bounds),
                    onMoveEnd: () => _persistGeometry(bounds),
                  ),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-top'),
                  cursor: SystemMouseCursors.resizeUpDown,
                  top: _edgeHandleExtent / 2,
                  left: _cornerHandleExtent,
                  right: _cornerHandleExtent,
                  height: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, top: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-bottom'),
                  cursor: SystemMouseCursors.resizeUpDown,
                  bottom: _edgeHandleExtent / 2,
                  left: _cornerHandleExtent,
                  right: _cornerHandleExtent,
                  height: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, bottom: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-left'),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  top: _cornerHandleExtent,
                  bottom: _cornerHandleExtent,
                  left: _edgeHandleExtent / 2,
                  width: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, left: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-right'),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  top: _cornerHandleExtent,
                  bottom: _cornerHandleExtent,
                  right: _edgeHandleExtent / 2,
                  width: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, right: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _cornerResizeHandle(
                  key: const ValueKey('composer-resize-top-left'),
                  cursor: _cornerResizeCursor(
                    macOS: SystemMouseCursors.resizeLeft,
                    otherwise: SystemMouseCursors.resizeUpLeftDownRight,
                  ),
                  top: true,
                  left: true,
                  onResize: (delta) =>
                      _resize(delta, bounds, top: true, left: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _cornerResizeHandle(
                  key: const ValueKey('composer-resize-top-right'),
                  cursor: _cornerResizeCursor(
                    macOS: SystemMouseCursors.resizeRight,
                    otherwise: SystemMouseCursors.resizeUpRightDownLeft,
                  ),
                  top: true,
                  left: false,
                  onResize: (delta) =>
                      _resize(delta, bounds, top: true, right: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _cornerResizeHandle(
                  key: const ValueKey('composer-resize-bottom-left'),
                  cursor: _cornerResizeCursor(
                    macOS: SystemMouseCursors.resizeLeft,
                    otherwise: SystemMouseCursors.resizeUpRightDownLeft,
                  ),
                  top: false,
                  left: true,
                  onResize: (delta) =>
                      _resize(delta, bounds, bottom: true, left: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _cornerResizeHandle(
                  key: const ValueKey('composer-resize-bottom-right'),
                  cursor: _cornerResizeCursor(
                    macOS: SystemMouseCursors.resizeRight,
                    otherwise: SystemMouseCursors.resizeUpLeftDownRight,
                  ),
                  top: false,
                  left: false,
                  onResize: (delta) =>
                      _resize(delta, bounds, bottom: true, right: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _resizeHandle({
    required Key key,
    required MouseCursor cursor,
    required ValueChanged<Offset> onResize,
    required VoidCallback onResizeEnd,
    double? top,
    double? right,
    double? bottom,
    double? left,
    double? width,
    double? height,
    Widget? child,
  }) => Positioned(
    top: top,
    right: right,
    bottom: bottom,
    left: left,
    width: width,
    height: height,
    child: _resizeRegion(
      key: key,
      cursor: cursor,
      onResize: onResize,
      onResizeEnd: onResizeEnd,
      child: child,
    ),
  );

  Widget _cornerResizeHandle({
    required Key key,
    required MouseCursor cursor,
    required bool top,
    required bool left,
    required ValueChanged<Offset> onResize,
    required VoidCallback onResizeEnd,
  }) => Positioned(
    top: top ? 0 : null,
    right: left ? null : 0,
    bottom: top ? null : 0,
    left: left ? 0 : null,
    width: _cornerHandleExtent,
    height: _cornerHandleExtent,
    child: SizedBox.expand(
      key: key,
      child: Stack(
        children: [
          Positioned(
            top: top ? _edgeHandleExtent / 2 : null,
            right: 0,
            bottom: top ? null : _edgeHandleExtent / 2,
            left: 0,
            height: _edgeHandleExtent,
            child: _resizeRegion(
              cursor: cursor,
              onResize: onResize,
              onResizeEnd: onResizeEnd,
            ),
          ),
          Positioned(
            top: 0,
            right: left ? null : _edgeHandleExtent / 2,
            bottom: 0,
            left: left ? _edgeHandleExtent / 2 : null,
            width: _edgeHandleExtent,
            child: _resizeRegion(
              cursor: cursor,
              onResize: onResize,
              onResizeEnd: onResizeEnd,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _resizeRegion({
    Key? key,
    required MouseCursor cursor,
    required ValueChanged<Offset> onResize,
    required VoidCallback onResizeEnd,
    Widget? child,
  }) => MouseRegion(
    cursor: cursor,
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onResize(details.delta),
      onPanEnd: (_) => onResizeEnd(),
      child: child,
    ),
  );

  MouseCursor _cornerResizeCursor({
    required MouseCursor macOS,
    required MouseCursor otherwise,
  }) => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? macOS
      : otherwise;

  _ComposerGeometry _geometryFor(Size bounds) {
    final horizontalInset = math.min(_inset, bounds.width / 2);
    final verticalInset = math.min(_inset, bounds.height / 2);
    final maximumWidth = math.max(0.0, bounds.width - horizontalInset * 2);
    final maximumHeight = math.max(0.0, bounds.height - verticalInset * 2);
    final minimumWidth = math.min(_minimumWidth, maximumWidth);
    final minimumHeight = math.min(_minimumHeight, maximumHeight);
    final wantedHeight = switch (widget.composer.target) {
      final target when target.createsTopic || target.editsTopicMetadata =>
        topicComposerHeight,
      final target when target.isTaxonomyEdit => 190.0,
      _ => composerHeight,
    };
    final restoredPreference = _restoredPreference;
    final size = Size(
      (_size?.width ??
              restoredPreference?.width ??
              math.min(_defaultWidth, maximumWidth))
          .clamp(minimumWidth, maximumWidth),
      (_size?.height ?? restoredPreference?.height ?? wantedHeight).clamp(
        minimumHeight,
        maximumHeight,
      ),
    );
    final defaultPosition = Offset(
      (bounds.width - size.width) / 2,
      bounds.height - size.height - verticalInset,
    );
    final maximumX = math.max(
      horizontalInset,
      bounds.width - size.width - horizontalInset,
    );
    final maximumY = math.max(
      verticalInset,
      bounds.height - size.height - verticalInset,
    );
    final restoredPosition = restoredPreference == null
        ? null
        : Offset(
            horizontalInset +
                (maximumX - horizontalInset) *
                    restoredPreference.horizontalPosition,
            verticalInset +
                (maximumY - verticalInset) *
                    restoredPreference.verticalPosition,
          );
    final wantedPosition = _position ?? restoredPosition ?? defaultPosition;
    return _ComposerGeometry(
      size: size,
      position: Offset(
        wantedPosition.dx.clamp(horizontalInset, maximumX),
        wantedPosition.dy.clamp(verticalInset, maximumY),
      ),
    );
  }

  void _move(Offset delta, Size bounds) {
    final geometry = _geometryFor(bounds);
    setState(() {
      _geometryChanged = true;
      _restoredPreference = null;
      _size = geometry.size;
      _position = geometry.position + delta;
    });
  }

  void _resize(
    Offset delta,
    Size bounds, {
    bool top = false,
    bool right = false,
    bool bottom = false,
    bool left = false,
  }) {
    final geometry = _geometryFor(bounds);
    var leftEdge = geometry.position.dx;
    var topEdge = geometry.position.dy;
    var rightEdge = leftEdge + geometry.size.width;
    var bottomEdge = topEdge + geometry.size.height;
    final maximumRight = bounds.width - math.min(_inset, bounds.width / 2);
    final maximumBottom = bounds.height - math.min(_inset, bounds.height / 2);
    final minimumLeft = math.min(_inset, bounds.width / 2);
    final minimumTop = math.min(_inset, bounds.height / 2);
    final minimumWidth = math.min(_minimumWidth, maximumRight - minimumLeft);
    final minimumHeight = math.min(_minimumHeight, maximumBottom - minimumTop);

    if (left) {
      leftEdge = (leftEdge + delta.dx).clamp(
        minimumLeft,
        rightEdge - minimumWidth,
      );
    }
    if (right) {
      rightEdge = (rightEdge + delta.dx).clamp(
        leftEdge + minimumWidth,
        maximumRight,
      );
    }
    if (top) {
      topEdge = (topEdge + delta.dy).clamp(
        minimumTop,
        bottomEdge - minimumHeight,
      );
    }
    if (bottom) {
      bottomEdge = (bottomEdge + delta.dy).clamp(
        topEdge + minimumHeight,
        maximumBottom,
      );
    }

    setState(() {
      _geometryChanged = true;
      _restoredPreference = null;
      _position = Offset(leftEdge, topEdge);
      _size = Size(rightEdge - leftEdge, bottomEdge - topEdge);
    });
  }

  Future<void> _restoreGeometry() async {
    // Restored geometry is optional presentation state. A platform preferences
    // channel that never answers must not leave a successfully opened composer
    // permanently represented by an empty overlay.
    final preference = await widget.geometryStore.read().timeout(
      _geometryRestoreDeadline,
      onTimeout: () => null,
    );
    if (!mounted) return;
    setState(() {
      if (!_geometryChanged) _restoredPreference = preference;
      _geometryLoaded = true;
    });
  }

  void _persistGeometry(Size bounds) {
    final geometry = _geometryFor(bounds);
    final horizontalInset = math.min(_inset, bounds.width / 2);
    final verticalInset = math.min(_inset, bounds.height / 2);
    final horizontalRange = math.max(
      0.0,
      bounds.width - geometry.size.width - horizontalInset * 2,
    );
    final verticalRange = math.max(
      0.0,
      bounds.height - geometry.size.height - verticalInset * 2,
    );
    final preference = ComposerGeometryPreference(
      width: geometry.size.width,
      height: geometry.size.height,
      horizontalPosition: horizontalRange == 0
          ? 0.5
          : ((geometry.position.dx - horizontalInset) / horizontalRange).clamp(
              0.0,
              1.0,
            ),
      verticalPosition: verticalRange == 0
          ? 1
          : ((geometry.position.dy - verticalInset) / verticalRange).clamp(
              0.0,
              1.0,
            ),
    );
    _pendingGeometryWrite = _pendingGeometryWrite.then(
      (_) => widget.geometryStore.write(preference),
    );
  }

  double get _minimumHeight {
    final target = widget.composer.target;
    return target.createsTopic || target.editsTopicMetadata
        ? _minimumTopicHeight
        : _minimumReplyHeight;
  }
}

class _ComposerGeometry {
  const _ComposerGeometry({required this.size, required this.position});

  final Size size;
  final Offset position;
}

class _TopicTaxonomy extends StatefulWidget {
  const _TopicTaxonomy({required this.composer});

  final ComposerController composer;

  @override
  State<_TopicTaxonomy> createState() => _TopicTaxonomyState();
}

class _TopicTaxonomyState extends State<_TopicTaxonomy> {
  final GlobalKey _categoryAnchorKey = GlobalKey();
  final GlobalKey _tagsAnchorKey = GlobalKey();
  bool _showingCategory = false;
  bool _showingTags = false;

  ComposerController get composer => widget.composer;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<
        ({
          List<TopicCategory> categories,
          TopicComposerCapabilities capabilities,
        })
      >(
        select: (controller) => (
          categories: controller.topicComposerCategories(
            composer.target.siteUrl,
          ),
          capabilities: controller.topicComposerCapabilities(
            composer.target.siteUrl,
          ),
        ),
        builder: (context, state, _) {
          final shell = ShellScope.read(context);
          final category = state.categories
              .where((item) => item.id == composer.categoryId)
              .firstOrNull;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (!composer.target.isTagsEdit)
                  SizedBox(
                    key: _categoryAnchorKey,
                    child: TopicPropertyRow(
                      key: const ValueKey('composer-category-property'),
                      label: 'Category',
                      child: TopicCategoryValue(
                        valueKey: const ValueKey('composer-category'),
                        label: category == null
                            ? 'Choose a category'
                            : shell.topicCategoryPathLabel(
                                category,
                                siteUrl: composer.target.siteUrl,
                              ),
                        color: category == null
                            ? null
                            : Color(category.colorValue),
                        colorKey: const ValueKey('composer-category-color'),
                        actionKey: const ValueKey('composer-category-action'),
                        tooltip: 'Choose category',
                        onTap: () => _pickCategory(context, shell),
                      ),
                    ),
                  ),
                if (state.capabilities.canTagTopics || composer.tags.isNotEmpty)
                  SizedBox(
                    key: _tagsAnchorKey,
                    child: TopicPropertyRow(
                      key: const ValueKey('composer-tags-property'),
                      label: 'Tags',
                      child: TopicTagsValue(
                        key: const ValueKey('composer-tags'),
                        tags: composer.tags,
                        tagKey: (tag) => ValueKey(('composer-tag', tag.name)),
                        addKey: const ValueKey('composer-add-tag'),
                        editTooltip: 'Choose tags',
                        onTap: () =>
                            _pickTags(context, shell, state.capabilities),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Future<void> _pickCategory(
    BuildContext context,
    ShellController shell,
  ) async {
    final anchorContext = _categoryAnchorKey.currentContext;
    if (_showingCategory || anchorContext == null) return;
    _showingCategory = true;
    try {
      final selected = await showTopicCategoryPicker(
        context: context,
        anchorContext: anchorContext,
        selectedCategoryId: composer.categoryId,
        search: (term) async => (await shell.searchTopicCategoriesForEditor(
          siteUrl: composer.target.siteUrl,
          term: term,
        )).where((category) => category.canCreateTopic).toList(),
        pathLabelFor: (category) => shell.topicCategoryPathLabel(
          category,
          siteUrl: composer.target.siteUrl,
        ),
      );
      if (!mounted || selected == null || selected == composer.categoryId) {
        return;
      }
      await shell.changeComposerCategory(composer, selected);
    } finally {
      _showingCategory = false;
    }
  }

  Future<void> _pickTags(
    BuildContext context,
    ShellController shell,
    TopicComposerCapabilities capabilities,
  ) async {
    final anchorContext = _tagsAnchorKey.currentContext;
    if (_showingTags || anchorContext == null) return;
    _showingTags = true;
    try {
      final selected = await showTopicTagPicker(
        context: context,
        anchorContext: anchorContext,
        selectedTags: composer.tags,
        capabilities: capabilities,
        search: (term) => shell.searchComposerTags(composer, term),
      );
      if (!mounted || selected == null) return;
      composer.setTags(selected);
    } finally {
      _showingTags = false;
    }
  }
}

class _SelectedPillInputFormatter extends TextInputFormatter {
  const _SelectedPillInputFormatter(this.isSelected);

  final bool Function() isSelected;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => isSelected() ? oldValue : newValue;
}

class _RenderedEmojiInputFormatter extends TextInputFormatter {
  const _RenderedEmojiInputFormatter({
    required this.endingAt,
    required this.startingAt,
  });

  final TextRange? Function(int offset) endingAt;
  final TextRange? Function(int offset) startingAt;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        oldValue.text.length != newValue.text.length + 1 ||
        (oldValue.isComposingRangeValid && !oldValue.composing.isCollapsed)) {
      return newValue;
    }

    final caret = selection.extentOffset;
    TextRange? emoji;
    if (caret > 0 &&
        newValue.text == oldValue.text.replaceRange(caret - 1, caret, '')) {
      emoji = endingAt(caret);
    } else if (caret < oldValue.text.length &&
        newValue.text == oldValue.text.replaceRange(caret, caret + 1, '')) {
      emoji = startingAt(caret);
    }
    if (emoji == null) return newValue;

    return TextEditingValue(
      text: oldValue.text.replaceRange(emoji.start, emoji.end, ''),
      selection: TextSelection.collapsed(offset: emoji.start),
    );
  }
}

class ComposerEditor extends StatefulWidget {
  const ComposerEditor({
    super.key,
    required this.composer,
    required this.hintText,
    required this.textStyle,
    required this.hintStyle,
    this.autofocus = true,
    this.enableDropTarget = true,
    this.expands = true,
    this.pickImages = pickComposerImages,
    this.readClipboardImages = readComposerClipboardImages,
    this.onSuggestionAction,
  });

  final ComposerController composer;
  final String hintText;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final bool autofocus;
  final bool enableDropTarget;
  final ComposerImagePicker pickImages;
  final ComposerClipboardImageReader readClipboardImages;

  final bool expands;
  final ComposerSuggestionActionHandler? onSuggestionAction;

  @override
  State<ComposerEditor> createState() => _ComposerEditorState();
}

class _ComposerEditorState extends State<ComposerEditor> {
  static const _menuWidth = 88.0;
  static const _menuHeight = 44.0;
  static const _menuGap = 4.0;
  static const _imageMenuPreferredWidth = 310.0;
  static const _imageMenuHeight = 98.0;
  static const _galleryMenuPreferredWidth = 280.0;
  static const _galleryMenuHeight = 52.0;

  final GlobalKey _stackKey = GlobalKey();
  ComposerQuoteBlock? _pointerDownQuote;
  ComposerSyntaxOccurrence? _pointerDownSyntax;
  ComposerSyntaxOccurrence? _pointerDownAfterBlockSyntax;
  Offset? _pointerDownPosition;
  int _pointerSequence = 0;
  bool _hoveringMention = false;
  bool _hoveringLink = false;
  final ScrollController _scroll = ScrollController();
  late final ComposerMediaEditingCoordinator _media;
  late final _ComposerSelectionOverlay _selectionOverlay;
  final ValueNotifier<int> _mediaLayoutRevision = ValueNotifier(0);
  bool _mediaLayoutRefreshScheduled = false;
  (double, double)? _lastImageMenuPosition;
  (double, double)? _lastGalleryMenuPosition;
  late final TextInputFormatter _selectedPillInputFormatter;
  late final TextInputFormatter _renderedEmojiInputFormatter;
  late final _ComposerPasteAction _pasteAction;

  @override
  void initState() {
    super.initState();
    _media = ComposerMediaEditingCoordinator(widget.composer)
      ..addListener(_scheduleMediaLayoutRefresh);
    _selectionOverlay = _ComposerSelectionOverlay(
      composer: widget.composer,
      scroll: _scroll,
      menuWidth: _menuWidth,
      isMounted: () => mounted,
      renderEditable: () => _renderEditable,
      overlayBox: () {
        if (!mounted) return null;
        final object = Overlay.of(context).context.findRenderObject();
        return object is RenderBox ? object : null;
      },
    );
    _selectedPillInputFormatter = _SelectedPillInputFormatter(
      () =>
          widget.composer.text.keyboardSelectedSyntax != null ||
          _media.hasSelectedMediaProjection,
    );
    _renderedEmojiInputFormatter = _RenderedEmojiInputFormatter(
      endingAt: (offset) => widget.composer.text.renderedEmojiEndingAt(offset),
      startingAt: (offset) =>
          widget.composer.text.renderedEmojiStartingAt(offset),
    );
    _pasteAction = _ComposerPasteAction(_pasteClipboardImages);
    widget.composer.text.imageScrollController = _scroll;
    _selectionOverlay.sync();
  }

  @override
  void didUpdateWidget(ComposerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.composer, widget.composer)) return;
    if (_pointerDownSyntax case final syntax?) {
      oldWidget.composer.text.releaseSyntaxPointerEdit(syntax);
    }
    if (_pointerDownAfterBlockSyntax case final syntax?) {
      oldWidget.composer.text.releaseSyntaxPointerEdit(syntax);
    }
    _pointerDownQuote = null;
    _pointerDownSyntax = null;
    _pointerDownAfterBlockSyntax = null;
    _pointerDownPosition = null;
    _hoveringMention = false;
    _hoveringLink = false;
    _lastImageMenuPosition = null;
    _lastGalleryMenuPosition = null;
    if (identical(oldWidget.composer.text.imageScrollController, _scroll)) {
      oldWidget.composer.text.imageScrollController = null;
    }
    _media.replaceComposer(widget.composer);
    _selectionOverlay.replaceComposer(widget.composer);
    widget.composer.text.imageScrollController = _scroll;
  }

  @override
  void dispose() {
    _releasePointerDownPillCollapse();
    if (identical(widget.composer.text.imageScrollController, _scroll)) {
      widget.composer.text.imageScrollController = null;
    }
    _media.removeListener(_scheduleMediaLayoutRefresh);
    _media.dispose();
    _selectionOverlay.dispose();
    _mediaLayoutRevision.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _pasteClipboardImages() async {
    return _media.pasteClipboardImages(widget.readClipboardImages);
  }

  Future<void> _pasteFromContextMenu(EditableTextState state) async {
    if (await _pasteClipboardImages()) {
      if (state.mounted) state.hideToolbar();
      return;
    }
    if (state.mounted) {
      await state.pasteText(SelectionChangedCause.toolbar);
    }
  }

  Widget _contextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    if (SystemContextMenu.isSupportedByField(editableTextState)) {
      final items = SystemContextMenu.getDefaultItems(editableTextState);
      final replacement = IOSSystemContextMenuItemCustom(
        title: WidgetsLocalizations.of(context).pasteButtonLabel,
        onPressed: () => unawaited(_pasteFromContextMenu(editableTextState)),
      );
      final paste = items.indexWhere(
        (item) => item is IOSSystemContextMenuItemPaste,
      );
      if (paste >= 0) {
        items[paste] = replacement;
      } else if (_canPasteImages) {
        final selectAll = items.indexWhere(
          (item) => item is IOSSystemContextMenuItemSelectAll,
        );
        items.insert(selectAll < 0 ? items.length : selectAll, replacement);
      }
      return SystemContextMenu.editableText(
        editableTextState: editableTextState,
        items: items,
      );
    }

    final items = editableTextState.contextMenuButtonItems.toList();
    final replacement = ContextMenuButtonItem(
      onPressed: () => unawaited(_pasteFromContextMenu(editableTextState)),
      type: ContextMenuButtonType.paste,
    );
    final paste = items.indexWhere(
      (item) => item.type == ContextMenuButtonType.paste,
    );
    if (paste >= 0) {
      items[paste] = replacement;
    } else if (_canPasteImages) {
      final selectAll = items.indexWhere(
        (item) => item.type == ContextMenuButtonType.selectAll,
      );
      items.insert(selectAll < 0 ? items.length : selectAll, replacement);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  bool get _canPasteImages =>
      widget.composer.imageUploader != null &&
      !widget.composer.loadingBody &&
      widget.composer.text.selection.isValid;

  void _scheduleMediaLayoutRefresh() {
    if (_mediaLayoutRefreshScheduled || !_media.value.hasSelectedMedia) return;
    _mediaLayoutRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mediaLayoutRefreshScheduled = false;
      if (mounted && _media.value.hasSelectedMedia) {
        _mediaLayoutRevision.value++;
      }
    });
  }

  void _updateEditorHover(Offset? globalPosition) {
    final text = widget.composer.text;
    text.updateSyntaxHoverAtGlobalPosition(globalPosition);
    final hoveringMention =
        globalPosition != null &&
        text.isMentionPillAtGlobalPosition(globalPosition);
    final hoveringLink =
        globalPosition != null &&
        text.collapsedSyntaxAtGlobalPosition(globalPosition)?.kind ==
            composerLinkSyntaxKind;
    if (_hoveringMention == hoveringMention && _hoveringLink == hoveringLink) {
      return;
    }
    setState(() {
      _hoveringMention = hoveringMention;
      _hoveringLink = hoveringLink;
    });
  }

  Widget _field() => MouseRegion(
    onHover: (event) => _updateEditorHover(event.position),
    onExit: (_) => _updateEditorHover(null),
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onEditorPointerDown,
      onPointerMove: _onEditorPointerMove,
      onPointerUp: _onEditorPointerUp,
      onPointerCancel: (_) => _cancelEditorPointer(),
      child: ComposerSuggestionField(
        composer: widget.composer,
        onAction: widget.onSuggestionAction,
        field: ClipRect(
          child: Focus(
            onKeyEvent: _onEditorKeyEvent,
            child: Actions(
              actions: {PasteTextIntent: _pasteAction},
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.composer.text,
                builder: (_, _, _) => TextField(
                  // Not decoration: a new key builds a new editable, and with it
                  // a new undo stack. It is the only way to stop undo reaching
                  // back into a reply that has already been sent.
                  key: ValueKey(widget.composer.fieldGeneration),
                  controller: widget.composer.text,
                  readOnly: widget.composer.discarding,
                  scrollController: _scroll,
                  focusNode: widget.composer.focus,
                  autofocus: widget.autofocus,
                  expands: widget.expands,
                  maxLines: null,
                  minLines: widget.expands ? null : 1,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    _selectedPillInputFormatter,
                    _renderedEmojiInputFormatter,
                    const ComposerQuoteInputFormatter(),
                    ...widget.composer.text.syntaxInputFormatters,
                  ],
                  contextMenuBuilder: _contextMenu,
                  showCursor:
                      !widget.composer.text.selectedProjectionHidesCursor,
                  onTapAlwaysCalled: true,
                  onTap: _activatePointerDownPill,
                  // TextField owns the deepest cursor region. Changing only the
                  // editor-level hover region leaves its text cursor in front.
                  mouseCursor: _hoveringMention || _hoveringLink
                      ? SystemMouseCursors.click
                      : null,
                  style: widget.textStyle,
                  // InputDecorator only gives the editable one text line when
                  // the TextField expands. The composer draws its hint separately
                  // so either viewport mode fills the available editor width.
                  decoration: null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  RenderEditable? get _renderEditable {
    final root = _stackKey.currentContext?.findRenderObject();
    if (root == null) return null;
    final pending = <RenderObject>[root];
    while (pending.isNotEmpty) {
      final object = pending.removeLast();
      if (object is RenderEditable) {
        return object;
      }
      final children = <RenderObject>[];
      object.visitChildren(children.add);
      for (var index = children.length - 1; index >= 0; index--) {
        pending.add(children[index]);
      }
    }
    return null;
  }

  void _moveDropCaret(Offset globalPosition) {
    final gallery = widget.composer.text.collapsedGalleryAtGlobalPosition(
      globalPosition,
    );
    if (gallery != null) {
      _media.updateDropTarget(gallery);
      widget.composer.focus.requestFocus();
      return;
    }
    _media.updateDropTarget(null);
    final editable = _renderEditable;
    if (editable == null) return;
    final position = editable.getPositionForPoint(globalPosition);
    widget.composer.text.selection = TextSelection.collapsed(
      offset: position.offset.clamp(0, widget.composer.text.text.length),
    );
    widget.composer.focus.requestFocus();
  }

  void _dropImages(DropDoneDetails details) {
    _moveDropCaret(details.globalPosition);
    if (dropContainsDirectory(details.files)) {
      widget.composer.showNotice('Folders cannot be uploaded here.');
    }
    final files = composerUploadFilesFromDrop(details.files);
    _media.dropImages(
      files,
      offset: widget.composer.text.selection.extentOffset,
    );
  }

  bool get _hasPointerDownPill =>
      _pointerDownQuote != null ||
      _media.hasPointerCapture ||
      _pointerDownSyntax != null ||
      _pointerDownAfterBlockSyntax != null;

  void _onEditorPointerDown(PointerDownEvent event) {
    _clearKeyboardPillSelection();
    _releasePointerDownPillCollapse();
    _pointerDownAfterBlockSyntax = null;
    _pointerSequence++;
    final position = event.position;
    _pointerDownPosition = position;
    _pointerDownQuote = widget.composer.text.collapsedQuoteAtGlobalPosition(
      position,
    );
    var image = _pointerDownQuote == null
        ? widget.composer.text.collapsedImageAtGlobalPosition(position)
        : null;
    var gallery = _pointerDownQuote == null && image == null
        ? widget.composer.text.collapsedGalleryAtGlobalPosition(position)
        : null;
    _pointerDownSyntax =
        _pointerDownQuote == null && image == null && gallery == null
        ? widget.composer.text.collapsedSyntaxAtGlobalPosition(position)
        : null;
    final hasDirectHit =
        _pointerDownQuote != null ||
        image != null ||
        gallery != null ||
        _pointerDownSyntax != null;
    _pointerDownAfterBlockSyntax = !hasDirectHit
        ? widget.composer.text.collapsedBlockSyntaxBeforeGlobalPosition(
            position,
          )
        : null;
    if (!hasDirectHit && _pointerDownAfterBlockSyntax == null) {
      final editable = _renderEditable;
      if (editable == null) return;
      final offset = editable.getPositionForPoint(position).offset;
      _pointerDownQuote = widget.composer.text.quoteAtOffset(offset);
      image = _pointerDownQuote == null
          ? widget.composer.text.collapsedImageAtOffset(offset)
          : null;
      final candidateGallery = _pointerDownQuote == null && image == null
          ? widget.composer.text.galleryAtOffset(offset)
          : null;
      gallery =
          candidateGallery != null &&
              widget.composer.text.isGalleryCollapsed(candidateGallery)
          ? candidateGallery
          : null;
      _pointerDownSyntax =
          _pointerDownQuote == null && image == null && gallery == null
          ? widget.composer.text.collapsedSyntaxAtOffset(offset)
          : null;
    }
    _media.capturePointer(image: image, gallery: gallery);
    _holdPointerDownPillCollapsed();
  }

  void _onEditorPointerMove(PointerMoveEvent event) {
    final start = _pointerDownPosition;
    if (!_hasPointerDownPill || start == null) return;
    if ((event.position - start).distance > kTouchSlop) {
      _cancelEditorPointer();
    }
  }

  void _onEditorPointerUp(PointerUpEvent _) {
    if (!_hasPointerDownPill) return;
    final sequence = _pointerSequence;
    // Defer until the editable's own pointer-up handlers have settled, but do
    // not wait for another frame: an idle desktop click may not produce one.
    scheduleMicrotask(() {
      if (!mounted || sequence != _pointerSequence || !_hasPointerDownPill) {
        return;
      }
      _activatePointerDownPill();
    });
  }

  void _cancelEditorPointer() {
    _pointerSequence++;
    _clearPointerDownPill();
  }

  void _holdPointerDownPillCollapsed() {
    final text = widget.composer.text;
    if ((_pointerDownSyntax ?? _pointerDownAfterBlockSyntax)
        case final syntax?) {
      text.keepSyntaxCollapsedForPointerEdit(syntax);
    }
  }

  void _releasePointerDownPillCollapse() {
    _media.cancelPointerCapture();
    final text = widget.composer.text;
    if (_pointerDownSyntax case final syntax?) {
      text.releaseSyntaxPointerEdit(syntax);
    }
    if (_pointerDownAfterBlockSyntax case final syntax?) {
      text.releaseSyntaxPointerEdit(syntax);
    }
  }

  void _clearPointerDownPill({bool releaseCollapse = true}) {
    if (releaseCollapse) _releasePointerDownPillCollapse();
    _pointerDownQuote = null;
    _pointerDownSyntax = null;
    _pointerDownAfterBlockSyntax = null;
    _pointerDownPosition = null;
  }

  void _activatePointerDownPill() {
    // `TextField.onTapAlwaysCalled` and the outer Listener can both settle the
    // same pointer sequence. Once the first activation clears its captured
    // position, a second callback must be inert rather than dismissing the
    // gallery or image it just selected.
    if (!_hasPointerDownPill && _pointerDownPosition == null) return;
    final quote = _pointerDownQuote;
    final media = _media.takePointerCapture();
    final image = media.image;
    final gallery = media.gallery;
    final syntax = _pointerDownSyntax;
    final afterBlockSyntax = _pointerDownAfterBlockSyntax;
    final position = _pointerDownPosition;
    _clearPointerDownPill(releaseCollapse: false);
    if (quote != null) {
      _media.dismissImage(requestFocus: false);
      _media.dismissGallery(requestFocus: false);
      if (position != null &&
          widget.composer.text.isQuoteRemoveAtGlobalPosition(quote, position)) {
        widget.composer.removeQuote(quote);
      } else {
        widget.composer.text.selection = TextSelection.collapsed(
          offset: quote.end,
        );
      }
      return;
    }
    if (image != null) {
      _media.selectImageForKeyboard(image);
      return;
    }
    if (gallery != null) {
      _media.selectGallery(gallery);
      return;
    }
    _media.dismissImage(requestFocus: false);
    _media.dismissGallery(requestFocus: false);
    if (afterBlockSyntax != null) {
      try {
        _moveCaretAfterSyntax(afterBlockSyntax);
      } finally {
        widget.composer.text.releaseSyntaxPointerEdit(afterBlockSyntax);
      }
      return;
    }
    if (syntax != null) {
      unawaited(_editSyntax(syntax));
    }
  }

  Future<void> _editSyntax(ComposerSyntaxOccurrence syntax) async {
    final text = widget.composer.text;
    text.keepSyntaxCollapsedForPointerEdit(syntax);
    text.selection = TextSelection.collapsed(
      offset: text.syntaxCaretAfter(syntax),
    );
    try {
      await syntax.projection.edit(context, widget.composer);
    } finally {
      if (mounted &&
          identical(widget.composer.text, text) &&
          _stillContains(text.text, syntax.start, syntax.end, syntax.source)) {
        text.selection = TextSelection.collapsed(
          offset: text.syntaxCaretAfter(syntax),
        );
      }
      text.releaseSyntaxPointerEdit(syntax);
    }
  }

  static bool _stillContains(String text, int start, int end, String source) =>
      start >= 0 &&
      end <= text.length &&
      start <= end &&
      text.substring(start, end) == source;

  Future<void> _addExistingImagesToSelectedGallery() async {
    await _media.chooseExistingImagesForSelectedGallery(
      (images) => showDialog<List<ComposerImageBlock>>(
        context: context,
        builder: (context) => _ExistingGalleryImagesDialog(images: images),
      ),
    );
  }

  KeyEventResult _onEditorKeyEvent(FocusNode _, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final hasModifier =
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed;
    final mediaResult = _media.handleKeyEvent(
      event,
      hasModifier: hasModifier,
      hasCommandModifier:
          keyboard.isMetaPressed ||
          keyboard.isControlPressed ||
          keyboard.isAltPressed,
    );
    if (mediaResult != null) {
      return mediaResult;
    }
    final selectedPill = _keyboardSelectedPill;
    if (selectedPill != null) {
      final isArrowPress = event is KeyDownEvent || event is KeyRepeatEvent;
      final isPlainHorizontalArrow =
          isArrowPress &&
          !hasModifier &&
          (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight);
      if (isPlainHorizontalArrow) {
        final moveLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
        _clearKeyboardPillSelection();
        if (moveLeft) {
          widget.composer.text.selection = TextSelection.collapsed(
            offset: _pillStart(selectedPill),
          );
        } else {
          _moveCaretAfterSyntax(selectedPill);
        }
        return KeyEventResult.handled;
      }
      final isPlainEnter =
          event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          !hasModifier;
      if (isPlainEnter) {
        _editPill(selectedPill);
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.backspace &&
          !hasModifier) {
        _clearKeyboardPillSelection();
        _removePill(selectedPill);
        return KeyEventResult.handled;
      }
      // The ancestor CallbackShortcuts (submit and, for non-image pills,
      // close) and focus traversal must stay reachable, so Escape, Tab and
      // modified chords pass through. Deletion chords are the exception:
      // released to the editing shortcuts they would word-delete into the
      // collapsed raw markup behind the pill.
      final isDeletion =
          event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete;
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.tab) {
        return KeyEventResult.ignored;
      }
      if ((keyboard.isMetaPressed ||
              keyboard.isControlPressed ||
              keyboard.isAltPressed) &&
          !isDeletion) {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final value = widget.composer.text.value;
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (value.isComposingRangeValid && !value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final caret = selection.extentOffset;
    final isPlainHorizontalArrow =
        !hasModifier &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight);
    if (isPlainHorizontalArrow) {
      final moveLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
      final pill = moveLeft
          ? _collapsedPillEndingAt(caret)
          : _collapsedPillStartingAt(caret);
      if (pill == null) return KeyEventResult.ignored;
      _selectPillForKeyboard(pill);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final deletes =
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete;
    if (deletes) {
      final boundarySyntax = event.logicalKey == LogicalKeyboardKey.backspace
          ? _collapsedPillEndingAt(caret)
          : _collapsedPillStartingAt(caret);
      if (boundarySyntax is ComposerSyntaxOccurrence &&
          boundarySyntax.projection.protectsAdjacentDelete) {
        _selectPillForKeyboard(boundarySyntax);
        return KeyEventResult.handled;
      }
    }
    for (final quote in widget.composer.text.quoteBlocks) {
      final removesQuote =
          (event.logicalKey == LogicalKeyboardKey.backspace &&
              quote.end == caret) ||
          (event.logicalKey == LogicalKeyboardKey.delete &&
              quote.start == caret);
      if (!removesQuote || !widget.composer.text.isQuoteCollapsed(quote)) {
        continue;
      }
      widget.composer.removeQuote(quote);
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    for (final syntax in widget.composer.text.syntaxBlocks) {
      if (syntax.end != caret ||
          syntax.projection.protectsAdjacentDelete ||
          !widget.composer.text.isSyntaxCollapsed(syntax)) {
        continue;
      }
      unawaited(
        Future.sync(() => syntax.projection.remove(context, widget.composer)),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  ComposerSyntaxOccurrence? get _keyboardSelectedPill =>
      widget.composer.text.keyboardSelectedSyntax;

  void _clearKeyboardPillSelection() {
    _media.clearKeyboardImageSelection();
    widget.composer.text.clearKeyboardPillSelection();
  }

  void _selectPillForKeyboard(Object pill) {
    if (pill case final ComposerImageBlock image) {
      _media.selectImageForKeyboard(image, moveCaretToEnd: false);
      return;
    }
    widget.composer.autocomplete.dismiss();
    widget.composer.text.selectPillForKeyboard(pill);
  }

  Object? _collapsedPillEndingAt(int caret) {
    final text = widget.composer.text;
    for (final image in text.imageBlocks) {
      if (image.end == caret && text.isImageCollapsed(image)) return image;
    }
    for (final syntax in text.syntaxBlocks) {
      if ((syntax.end == caret || text.syntaxCaretAfter(syntax) == caret) &&
          text.isSyntaxCollapsed(syntax)) {
        return syntax;
      }
    }
    return null;
  }

  Object? _collapsedPillStartingAt(int caret) {
    final text = widget.composer.text;
    for (final image in text.imageBlocks) {
      if (image.start == caret && text.isImageCollapsed(image)) return image;
    }
    for (final syntax in text.syntaxBlocks) {
      if (syntax.start == caret && text.isSyntaxCollapsed(syntax)) {
        return syntax;
      }
    }
    return null;
  }

  static int _pillStart(Object pill) => switch (pill) {
    ComposerSyntaxOccurrence syntax => syntax.start,
    _ => throw ArgumentError.value(pill, 'pill'),
  };

  void _moveCaretAfterSyntax(ComposerSyntaxOccurrence syntax) {
    final text = widget.composer.text;
    text.value = syntax.projection.moveCaretAfter(text.value);
  }

  void _editPill(Object pill) {
    switch (pill) {
      case ComposerImageBlock image:
        _media.selectImageForKeyboard(image);
        return;
      case ComposerSyntaxOccurrence syntax:
        unawaited(_editSyntax(syntax));
        return;
    }
    throw ArgumentError.value(pill, 'pill');
  }

  void _removePill(Object pill) {
    switch (pill) {
      case ComposerImageBlock image:
        _media.clearKeyboardImageSelection();
        widget.composer.removeImage(image);
        return;
      case ComposerSyntaxOccurrence syntax:
        unawaited(
          Future.sync(() => syntax.projection.remove(context, widget.composer)),
        );
        return;
    }
    throw ArgumentError.value(pill, 'pill');
  }

  (double, double)? _imageMenuPosition(
    BoxConstraints constraints,
    ComposerImageBlock? image,
  ) {
    if (image == null) {
      _lastImageMenuPosition = null;
      return null;
    }
    final stack = _stackKey.currentContext?.findRenderObject();
    final rect = widget.composer.text.collapsedImageGlobalRect(image);
    if (stack is! RenderBox || !stack.hasSize || rect == null) {
      return _lastImageMenuPosition;
    }
    final topLeft = stack.globalToLocal(rect.topLeft);
    final bottomRight = stack.globalToLocal(rect.bottomRight);
    final width = math.min(_imageMenuPreferredWidth, constraints.maxWidth);
    const height = _imageMenuHeight;
    final left = topLeft.dx.clamp(
      0.0,
      constraints.maxWidth > width ? constraints.maxWidth - width : 0.0,
    );
    var top = topLeft.dy - height - _menuGap;
    if (top < 0) top = bottomRight.dy + _menuGap;
    return _lastImageMenuPosition = (
      left,
      top.clamp(
        0.0,
        constraints.maxHeight > height ? constraints.maxHeight - height : 0.0,
      ),
    );
  }

  (double, double)? _galleryMenuPosition(
    BoxConstraints constraints,
    ComposerImageGalleryBlock? gallery,
  ) {
    if (gallery == null) {
      _lastGalleryMenuPosition = null;
      return null;
    }
    final stack = _stackKey.currentContext?.findRenderObject();
    final rect = widget.composer.text.collapsedGalleryGlobalRect(gallery);
    if (stack is! RenderBox || !stack.hasSize || rect == null) {
      return _lastGalleryMenuPosition;
    }
    final topLeft = stack.globalToLocal(rect.topLeft);
    final bottomRight = stack.globalToLocal(rect.bottomRight);
    final width = math.min(_galleryMenuPreferredWidth, constraints.maxWidth);
    const height = _galleryMenuHeight;
    final left = topLeft.dx.clamp(
      0.0,
      constraints.maxWidth > width ? constraints.maxWidth - width : 0.0,
    );
    var top = topLeft.dy - height - _menuGap;
    if (top < 0) top = bottomRight.dy + _menuGap;
    return _lastGalleryMenuPosition = (
      left,
      top.clamp(
        0.0,
        constraints.maxHeight > height ? constraints.maxHeight - height : 0.0,
      ),
    );
  }

  Widget _mediaOverlays(BoxConstraints constraints) {
    final state = _media.value;
    final imageMenuPosition = _imageMenuPosition(
      constraints,
      state.selectedImage,
    );
    final imageMenuWidth = math.min(
      _imageMenuPreferredWidth,
      constraints.maxWidth,
    );
    final galleryMenuPosition = _galleryMenuPosition(
      constraints,
      state.selectedGallery,
    );
    final galleryMenuWidth = math.min(
      _galleryMenuPreferredWidth,
      constraints.maxWidth,
    );
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (imageMenuPosition case (final left, final top))
            Positioned(
              left: left,
              top: top,
              child: _ImageComposerMenu(
                width: imageMenuWidth,
                image: state.selectedImage!,
                gallery: state.selectedImageGallery,
                alt: _media.imageAlt,
                onSaveAlt: _media.saveImageAlt,
                onScale: _media.scaleImage,
                onDelete: _media.deleteSelectedImage,
                onMoveOutsideGallery: _media.moveSelectedImageOutOfGallery,
                onDismiss: _media.dismissImage,
              ),
            ),
          if (galleryMenuPosition case (final left, final top))
            Positioned(
              left: left,
              top: top,
              child: _GalleryComposerMenu(
                width: galleryMenuWidth,
                gallery: state.selectedGallery!,
                hasStandaloneImages: state.hasStandaloneImages,
                pickingImages: state.pickingGalleryImages,
                onMode: _media.setSelectedGalleryMode,
                onUploadImages: () => unawaited(
                  _media.pickImagesForSelectedGallery(widget.pickImages),
                ),
                onAddExistingImages: () =>
                    unawaited(_addExistingImagesToSelectedGallery()),
                onUnwrap: _media.unwrapSelectedGallery,
                onDismiss: _media.dismissGallery,
              ),
            ),
          if (state.dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.06),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        state.dropGallery == null
                            ? 'Drop images to upload'
                            : 'Drop images into this gallery',
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => OverlayPortal(
      controller: _selectionOverlay.portal,
      overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
        valueListenable: _selectionOverlay.anchor,
        builder: (context, anchor, child) => CustomSingleChildLayout(
          delegate: AnchoredLayout(
            anchor: anchor,
            maxWidth: _menuWidth,
            gap: _menuGap,
            preferAbove: true,
          ),
          child: child!,
        ),
        child: _SelectionFormattingMenu(
          composer: widget.composer,
          onFocusChange: _selectionOverlay.focusChanged,
        ),
      ),
      child: DropTarget(
        enable: widget.enableDropTarget && !context.isTouch,
        onDragEntered: (details) {
          _moveDropCaret(details.globalPosition);
          _media.beginDrag();
        },
        onDragUpdated: (details) => _moveDropCaret(details.globalPosition),
        onDragExited: (_) => _media.cancelDrag(),
        onDragDone: _dropImages,
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.composer.text,
                builder: (context, value, _) => value.text.isEmpty
                    ? IgnorePointer(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(widget.hintText, style: widget.hintStyle),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (widget.expands) Positioned.fill(child: _field()) else _field(),
            ListenableBuilder(
              listenable: _media,
              builder: (context, _) => ValueListenableBuilder<int>(
                valueListenable: _mediaLayoutRevision,
                builder: (context, _, _) => _mediaOverlays(constraints),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Widget-bound selection geometry kept separate from composer state.
///
/// This helper intentionally schedules after layout; unlike application
/// controllers, it is owned and disposed by the editor State object.
final class _ComposerSelectionOverlay {
  _ComposerSelectionOverlay({
    required ComposerController composer,
    required this.scroll,
    required this.menuWidth,
    required this.isMounted,
    required this.renderEditable,
    required this.overlayBox,
  }) : _composer = composer,
       _lastQuoteSelection = composer.text.selection {
    _attach();
  }

  ComposerController _composer;
  final ScrollController scroll;
  final double menuWidth;
  final bool Function() isMounted;
  final RenderEditable? Function() renderEditable;
  final RenderBox? Function() overlayBox;

  final OverlayPortalController portal = OverlayPortalController();
  final ValueNotifier<Rect?> anchor = ValueNotifier(null);

  Object? _syncToken;
  bool _toolbarFocused = false;
  bool _normalizingQuoteSelection = false;
  bool _disposed = false;
  TextSelection _lastQuoteSelection;

  void _attach() {
    _composer.text.addListener(sync);
    _composer.focus.addListener(sync);
    scroll.addListener(sync);
  }

  void _detach() {
    _composer.text.removeListener(sync);
    _composer.focus.removeListener(sync);
    scroll.removeListener(sync);
  }

  void replaceComposer(ComposerController composer) {
    if (_disposed || identical(_composer, composer)) return;
    _detach();
    _composer = composer;
    _lastQuoteSelection = composer.text.selection;
    _normalizingQuoteSelection = false;
    _toolbarFocused = false;
    _syncToken = null;
    anchor.value = null;
    if (portal.isShowing) portal.hide();
    _attach();
    sync();
  }

  void focusChanged(bool focused) {
    if (_disposed || _toolbarFocused == focused) return;
    _toolbarFocused = focused;
    sync();
  }

  void sync() {
    if (_disposed) return;
    if (!_normalizingQuoteSelection) {
      final current = _composer.text.selection;
      final normalized = _composer.text.protectQuoteSelection(
        current,
        _lastQuoteSelection,
      );
      _lastQuoteSelection = normalized;
      if (normalized != current) {
        _normalizingQuoteSelection = true;
        _composer.text.selection = normalized;
        _normalizingQuoteSelection = false;
        return;
      }
    }

    final selection = _composer.text.selection;
    if (!_canFormatSelection(selection)) {
      _syncToken = null;
      anchor.value = null;
      if (portal.isShowing) portal.hide();
      return;
    }

    final token = Object();
    _syncToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !isMounted() || !identical(_syncToken, token)) {
        return;
      }
      final current = _composer.text.selection;
      if (!_canFormat(current)) {
        anchor.value = null;
        if (portal.isShowing) portal.hide();
        return;
      }

      final editable = renderEditable();
      final overlay = overlayBox();
      if (editable == null || overlay == null || !overlay.hasSize) {
        if (portal.isShowing) portal.hide();
        return;
      }
      final endpoints = editable.getEndpointsForSelection(current);
      if (endpoints.isEmpty) {
        if (portal.isShowing) portal.hide();
        return;
      }

      final points = [
        for (final endpoint in endpoints)
          editable.localToGlobal(endpoint.point, ancestor: overlay),
      ];
      final left = points.map((point) => point.dx).reduce(math.min);
      final right = points.map((point) => point.dx).reduce(math.max);
      final bottom = points.map((point) => point.dy).reduce(math.min);
      final lineHeight = editable.preferredLineHeight;
      anchor.value = Rect.fromLTWH(
        (left + right) / 2 - menuWidth / 2,
        bottom - lineHeight,
        menuWidth,
        lineHeight,
      );
      portal.show();
    });
  }

  bool _canFormat(TextSelection selection) =>
      (_composer.focus.hasFocus || _toolbarFocused) &&
      _canFormatSelection(selection);

  bool _canFormatSelection(TextSelection selection) =>
      selection.isValid &&
      !selection.isCollapsed &&
      !selectionTouchesComposerQuote(_composer.text.quoteBlocks, selection);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _syncToken = null;
    _detach();
    anchor.dispose();
  }
}

class _ComposerPasteAction extends Action<PasteTextIntent> {
  _ComposerPasteAction(this._pasteImages);

  final Future<bool> Function() _pasteImages;

  @override
  Object? invoke(PasteTextIntent intent) {
    final fallback = callingAction;
    return _invoke(intent, fallback);
  }

  Future<Object?> _invoke(
    PasteTextIntent intent,
    Action<PasteTextIntent>? fallback,
  ) async {
    if (await _pasteImages()) return null;
    return fallback?.invoke(intent);
  }

  @override
  bool isEnabled(PasteTextIntent intent) =>
      callingAction?.isEnabled(intent) ?? true;

  @override
  bool consumesKey(PasteTextIntent intent) =>
      callingAction?.consumesKey(intent) ?? true;
}

class _SelectionFormattingMenu extends StatelessWidget {
  const _SelectionFormattingMenu({
    required this.composer,
    required this.onFocusChange,
  });

  final ComposerController composer;
  final ValueChanged<bool> onFocusChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: onFocusChange,
      child: TextFieldTapRegion(
        child: Material(
          key: const ValueKey('composer-selection-toolbar'),
          color: theme.shell.floating,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: _ComposerEditorState._menuWidth,
            height: _ComposerEditorState._menuHeight,
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: theme.shell.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (mark, icon, label) in const [
                  (ComposerMark.bold, DIcons.bold, 'Bold'),
                  (ComposerMark.italic, DIcons.italic, 'Italic'),
                ])
                  IconButton(
                    onPressed: () {
                      composer.toggleMark(mark);
                      composer.focus.requestFocus();
                    },
                    icon: DIcon(icon, size: 18),
                    tooltip: label,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                    ),
                    color: theme.colorScheme.onSurface,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageComposerMenu extends StatelessWidget {
  const _ImageComposerMenu({
    required this.width,
    required this.image,
    required this.gallery,
    required this.alt,
    required this.onSaveAlt,
    required this.onScale,
    required this.onDelete,
    required this.onMoveOutsideGallery,
    required this.onDismiss,
  });

  final double width;
  final ComposerImageBlock image;
  final ComposerImageGalleryBlock? gallery;
  final TextEditingController alt;
  final VoidCallback onSaveAlt;
  final void Function(int scale) onScale;
  final VoidCallback onDelete;
  final VoidCallback onMoveOutsideGallery;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const scales = [50, 75, 100];
    final scale = scales.contains(image.scale) ? image.scale! : 100;
    final scaleIndex = scales.indexOf(scale);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onDismiss},
      child: Material(
        elevation: 5,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: _ComposerEditorState._imageMenuHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    if (gallery == null) ...[
                      IconButton(
                        onPressed: scaleIndex > 0
                            ? () => onScale(scales[scaleIndex - 1])
                            : null,
                        icon: const Icon(Icons.zoom_out, size: 18),
                        tooltip: 'Decrease image size',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                      Text('$scale%', style: theme.textTheme.labelMedium),
                      IconButton(
                        onPressed: scaleIndex < scales.length - 1
                            ? () => onScale(scales[scaleIndex + 1])
                            : null,
                        icon: const Icon(Icons.zoom_in, size: 18),
                        tooltip: 'Increase image size',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                    ] else
                      IconButton(
                        onPressed: onMoveOutsideGallery,
                        icon: const Icon(Icons.grid_off_outlined, size: 18),
                        tooltip: 'Move image outside gallery',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete image',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 44,
                  child: TextField(
                    controller: alt,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSaveAlt(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add image description',
                      suffixIconConstraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      suffixIcon: IconButton(
                        onPressed: onSaveAlt,
                        tooltip: 'Save alt text',
                        icon: const Icon(Icons.check, size: 16),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _GalleryAddChoice { upload, existing }

class _GalleryComposerMenu extends StatelessWidget {
  const _GalleryComposerMenu({
    required this.width,
    required this.gallery,
    required this.hasStandaloneImages,
    required this.pickingImages,
    required this.onMode,
    required this.onUploadImages,
    required this.onAddExistingImages,
    required this.onUnwrap,
    required this.onDismiss,
  });

  final double width;
  final ComposerImageGalleryBlock gallery;
  final bool hasStandaloneImages;
  final bool pickingImages;
  final ValueChanged<ComposerGalleryMode> onMode;
  final VoidCallback onUploadImages;
  final VoidCallback onAddExistingImages;
  final VoidCallback onUnwrap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onDismiss},
      child: TextFieldTapRegion(
        child: Material(
          key: const ValueKey('composer-gallery-toolbar'),
          elevation: 5,
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: _ComposerEditorState._galleryMenuHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(width, 220),
                height: _ComposerEditorState._galleryMenuHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      isSelected: gallery.mode == ComposerGalleryMode.grid,
                      onPressed: () => onMode(ComposerGalleryMode.grid),
                      icon: const Icon(Icons.grid_view_outlined, size: 18),
                      selectedIcon: const Icon(Icons.grid_view, size: 18),
                      tooltip: 'Grid gallery mode',
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                      ),
                    ),
                    IconButton(
                      isSelected: gallery.mode == ComposerGalleryMode.carousel,
                      onPressed: () => onMode(ComposerGalleryMode.carousel),
                      icon: const Icon(Icons.view_carousel_outlined, size: 18),
                      selectedIcon: const Icon(Icons.view_carousel, size: 18),
                      tooltip: 'Carousel gallery mode',
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                      ),
                    ),
                    PopupMenuButton<_GalleryAddChoice>(
                      enabled: !pickingImages,
                      tooltip: 'Add images to gallery',
                      padding: EdgeInsets.zero,
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        fixedSize: WidgetStatePropertyAll(Size.square(44)),
                      ),
                      icon: pickingImages
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 18,
                            ),
                      onSelected: (choice) {
                        switch (choice) {
                          case _GalleryAddChoice.upload:
                            onUploadImages();
                          case _GalleryAddChoice.existing:
                            onAddExistingImages();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _GalleryAddChoice.upload,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.upload_outlined),
                            title: Text('Upload new images'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _GalleryAddChoice.existing,
                          enabled: hasStandaloneImages,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.photo_library_outlined),
                            title: Text('Add existing draft images'),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: onUnwrap,
                      icon: const Icon(Icons.grid_off_outlined, size: 18),
                      tooltip: 'Remove gallery, keep images',
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExistingGalleryImagesDialog extends StatefulWidget {
  const _ExistingGalleryImagesDialog({required this.images});

  final List<ComposerImageBlock> images;

  @override
  State<_ExistingGalleryImagesDialog> createState() =>
      _ExistingGalleryImagesDialogState();
}

class _ExistingGalleryImagesDialogState
    extends State<_ExistingGalleryImagesDialog> {
  final Set<int> _selectedStarts = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add existing images'),
    content: SizedBox(
      width: 360,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.images.length,
          itemBuilder: (context, index) {
            final image = widget.images[index];
            final selected = _selectedStarts.contains(image.start);
            return CheckboxListTile(
              key: ValueKey('gallery-existing-image-${image.start}'),
              value: selected,
              controlAffinity: ListTileControlAffinity.leading,
              secondary: const Icon(Icons.image_outlined),
              title: Text(
                image.alt.isEmpty ? 'Image ${index + 1}' : image.alt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedStarts.add(image.start);
                  } else {
                    _selectedStarts.remove(image.start);
                  }
                });
              },
            );
          },
        ),
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: () => Navigator.pop(context),
      ),
      DButton(
        label: const Text('Add selected'),
        variant: DButtonVariant.primary,
        onPressed: _selectedStarts.isEmpty
            ? null
            : () => Navigator.pop(context, [
                for (final image in widget.images)
                  if (_selectedStarts.contains(image.start)) image,
              ]),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.composer,
    required this.onClose,
    required this.closeTooltip,
    this.onMove,
    this.onMoveEnd,
  });

  final ComposerController composer;
  final VoidCallback onClose;
  final String closeTooltip;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onMoveEnd;

  @override
  Widget build(BuildContext context) => ShellSelector<bool>(
    select: (controller) =>
        controller.currentUserFor(composer.target.siteUrl)?.whisperer == true,
    builder: (context, whisperer, _) => _buildHeader(context, whisperer),
  );

  Widget _buildHeader(BuildContext context, bool whisperer) {
    final theme = Theme.of(context);
    final target = composer.target;
    final replyTo = target.replyToUsername;
    final label = switch ((target.editingPostNumber, replyTo)) {
      _ when target.isPrivateMessage => 'Message ${target.targetRecipients}',
      _ when target.isNewTopic => 'Create a new topic',
      _ when target.isCategoryEdit => 'Edit topic category',
      _ when target.isTagsEdit => 'Edit topic tags',
      (final number?, _) => 'Edit post #$number',
      (_, final username?) => 'Reply to @$username',
      _ => 'Reply to ${target.topicTitle}',
    };
    final canToggleWhisper =
        whisperer &&
        target.mode == ComposerMode.reply &&
        !target.replyingToWhisper;

    final header = SizedBox(
      key: const ValueKey('composer-drag-handle'),
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(
          children: [
            if (canToggleWhisper)
              MenuAnchor(
                alignmentOffset: const Offset(0, 4),
                menuChildren: [
                  ListenableBuilder(
                    listenable: composer,
                    builder: (context, _) => Semantics(
                      toggled: composer.whisper,
                      child: MenuItemButton(
                        key: const ValueKey('composer-toggle-whisper'),
                        closeOnActivate: false,
                        onPressed: composer.toggleWhisper,
                        child: SizedBox(
                          width: 300,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Switch.adaptive(
                                key: const ValueKey('composer-whisper-switch'),
                                value: composer.whisper,
                                onChanged: composer.setWhisper,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Toggle whisper',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Whispers are only visible to allowed groups',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                builder: (context, menuController, _) => Semantics(
                  button: true,
                  label: 'Reply options',
                  expanded: menuController.isOpen,
                  child: InkWell(
                    key: const ValueKey('composer-reply-options'),
                    onTap: menuController.isOpen
                        ? menuController.close
                        : menuController.open,
                    child: DIcon(
                      composer.whisper ? DIcons.farEyeSlash : DIcons.reply,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              DIcon(
                composer.whisper
                    ? DIcons.farEyeSlash
                    : target.isPrivateMessage
                    ? DIcons.envelope
                    : target.isNewTopic
                    ? DIcons.plus
                    : target.isEdit
                    ? DIcons.pencil
                    : DIcons.reply,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                key: const ValueKey('composer-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const DIcon(DIcons.xmark, size: 18),
              tooltip: closeTooltip,
            ),
          ],
        ),
      ),
    );
    if (onMove == null) return header;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onMove!(details.delta),
        onPanEnd: (_) => onMoveEnd?.call(),
        child: header,
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.composer, required this.pickImages});

  final ComposerController composer;
  final ComposerImagePicker pickImages;

  @override
  Widget build(BuildContext context) => ShellSelector<int>(
    // Plugin creation capabilities arrive independently of composer text, so
    // select every input that can add or remove an action while this composer
    // is already open.
    select: (controller) => Object.hash(
      controller.siteConfigFor(composer.target.siteUrl),
      controller.freshCurrentUserFor(composer.target.siteUrl),
    ),
    builder: (context, _, _) => _buildToolbar(context),
  );

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final actions = registry.composerToolbar(context, composer);
    final emojiEnabled =
        !composer.target.isTaxonomyEdit &&
        ShellScope.read(
          context,
        ).siteConfigFor(composer.target.siteUrl).emojiEnabled;
    final uploadsEnabled = composer.imageUploader != null;
    if (!uploadsEnabled && !emojiEnabled && actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Wrap(
        children: [
          if (uploadsEnabled)
            _ComposerUploadButton(composer: composer, pickImages: pickImages),
          if (emojiEnabled)
            EmojiPickerAnchor(
              child: Builder(
                builder: (buttonContext) => IconButton(
                  key: const ValueKey('composer-emoji-picker'),
                  onPressed: composer.loadingBody
                      ? null
                      : () => unawaited(
                          openEmojiPickerForTopicComposer(
                            context: buttonContext,
                            composer: composer,
                          ),
                        ),
                  icon: const DIcon(DIcons.discourseEmojis, size: 18),
                  tooltip: 'Add emoji',
                  visualDensity: VisualDensity.compact,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final action in actions)
            IconButton(
              onPressed: action.onInvoke,
              icon: DIcon(action.icon, size: 18),
              tooltip: action.label,
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _ComposerUploadButton extends StatefulWidget {
  const _ComposerUploadButton({
    required this.composer,
    required this.pickImages,
  });

  final ComposerController composer;
  final ComposerImagePicker pickImages;

  @override
  State<_ComposerUploadButton> createState() => _ComposerUploadButtonState();
}

class _ComposerUploadButtonState extends State<_ComposerUploadButton> {
  bool _picking = false;

  Future<void> _pick() async {
    final composer = widget.composer;
    final selection = composer.text.selection;
    final offset = selection.isValid
        ? selection.extentOffset
        : composer.text.text.length;
    setState(() => _picking = true);
    try {
      final files = await widget.pickImages();
      if (!mounted || !identical(widget.composer, composer)) return;
      composer.addImages(files, offset);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'composer.pickImages',
        source: 'platform',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      if (mounted && identical(widget.composer, composer)) {
        composer.showNotice("Couldn't open the image picker.");
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
        if (identical(widget.composer, composer)) {
          composer.focus.requestFocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      key: const ValueKey('composer-upload'),
      onPressed: widget.composer.loadingBody || _picking
          ? null
          : () => unawaited(_pick()),
      icon: const DIcon(DIcons.upload, size: 18),
      tooltip: 'Upload images',
      visualDensity: VisualDensity.compact,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class ComposerUploadQueue extends StatelessWidget {
  const ComposerUploadQueue({super.key, required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 92),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: composer.uploads.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
        itemBuilder: (context, index) {
          final upload = composer.uploads[index];
          final failed = upload.status == ComposerUploadStatus.failed;
          final completed = upload.status == ComposerUploadStatus.completed;
          final thumbnail = completed ? upload.result : null;
          return SizedBox(
            height: failed ? 52 : 40,
            child: Row(
              children: [
                const SizedBox(width: 10),
                if (thumbnail != null)
                  _ComposerUploadThumbnail(
                    siteUrl: composer.target.siteUrl,
                    filename: upload.file.name,
                    uploadId: thumbnail.id,
                    url: thumbnail.previewUrl,
                  )
                else
                  Icon(
                    failed ? Icons.error_outline : Icons.image_outlined,
                    size: 18,
                    color: failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        upload.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                      if (failed)
                        Tooltip(
                          message:
                              upload.error ?? "Couldn't upload this image.",
                          child: Text(
                            upload.error ?? "Couldn't upload this image.",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        )
                      else if (!completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: LinearProgressIndicator(
                            value: upload.progress,
                            minHeight: 3,
                          ),
                        ),
                    ],
                  ),
                ),
                if (failed) ...[
                  IconButton(
                    onPressed: () => composer.retryUpload(upload.id),
                    icon: const Icon(Icons.refresh, size: 17),
                    tooltip: 'Retry upload',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () => composer.removeUpload(upload.id),
                    icon: const Icon(Icons.close, size: 17),
                    tooltip: 'Remove upload',
                    visualDensity: VisualDensity.compact,
                  ),
                ] else if (completed) ...[
                  IconButton(
                    onPressed: () => composer.removeUpload(upload.id),
                    icon: const Icon(Icons.close, size: 17),
                    tooltip: 'Remove upload',
                    visualDensity: VisualDensity.compact,
                  ),
                ] else ...[
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(upload.progress * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => composer.cancelUpload(upload.id),
                    icon: const Icon(Icons.close, size: 17),
                    tooltip: 'Cancel upload',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const SizedBox(width: 2),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComposerUploadThumbnail extends StatelessWidget {
  const _ComposerUploadThumbnail({
    required this.siteUrl,
    required this.filename,
    required this.uploadId,
    required this.url,
  });

  static const double size = 32;

  final String siteUrl;
  final String filename;
  final int uploadId;
  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.image_outlined,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SiteImage(
          key: ValueKey('composer-upload-thumbnail-$uploadId'),
          url: url,
          siteUrl: siteUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: imagePhysicalPixels(context, size),
          cacheHeight: imagePhysicalPixels(context, size),
          semanticLabel: 'Preview of $filename',
          loadingBuilder: (_) => SizedBox.square(
            dimension: size,
            child: Center(child: fallback),
          ),
          errorBuilder: (_, _, _) => SizedBox.square(
            dimension: size,
            child: Center(child: fallback),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.composer,
    required this.pickImages,
    required this.message,
    required this.isError,
    required this.busy,
    required this.label,
    required this.onSubmit,
    required this.discardLabel,
    required this.onDiscard,
  });

  final ComposerController composer;
  final ComposerImagePicker pickImages;
  final String? message;
  final bool isError;
  final bool busy;
  final String label;
  final VoidCallback? onSubmit;
  final String discardLabel;
  final VoidCallback onDiscard;

  static const double _stackedBreakpoint = 400;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = message == null
        ? const SizedBox.shrink()
        : Text(
            message!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          );
    final submit = FilledButton(
      onPressed: busy ? null : onSubmit,
      child: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            )
          : Text(label),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final toolbar = _Toolbar(composer: composer, pickImages: pickImages);
          final statusAndSubmit = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[status, const SizedBox(height: 4)],
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    DButton(
                      key: const ValueKey('composer-discard'),
                      label: Text(discardLabel),
                      onPressed: busy ? null : onDiscard,
                      variant: DButtonVariant.transparent,
                    ),
                    submit,
                  ],
                ),
              ),
            ],
          );
          final stacked =
              !composer.target.isTaxonomyEdit &&
              constraints.maxWidth < _stackedBreakpoint;
          return Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (!composer.target.isTaxonomyEdit) toolbar,
              if (stacked)
                statusAndSubmit
              else
                Expanded(child: statusAndSubmit),
            ],
          );
        },
      ),
    );
  }
}
