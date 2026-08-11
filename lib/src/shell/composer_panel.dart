import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../data/composer_geometry_store.dart';
import '../models/composer_upload.dart';
import '../models/topic.dart';
import '../plugins/local_dates/local_date_composer_parser.dart';
import '../plugins/local_dates/local_dates_plugin.dart';
import '../plugins/poll/poll_composer_parser.dart';
import '../plugins/poll/poll_plugin.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'composer_controller.dart';
import 'composer_images.dart';
import 'composer_marks.dart';
import 'composer_quotes.dart';
import 'composer_suggestions.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

/// The contents of the floating reply composer.
///
/// A panel rather than a sheet, which is the other thing the shell offers: the
/// point of replying is to keep reading the topic while writing about it, and a
/// modal sheet takes the topic away. [FloatingComposerPanel] supplies its
/// normal window-like frame, positioning, and resize interactions.
///
/// What is typed here is what gets posted. Discourse stores raw markdown, so
/// the field's text *is* the payload — there is no document model in between to
/// normalise, escape or lose anything.
class ComposerPanel extends StatelessWidget {
  const ComposerPanel({
    super.key,
    required this.composer,
    this.height,
    this.onMove,
    this.onMoveEnd,
  });

  final ComposerController composer;
  final double? height;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onMoveEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);

    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        final target = composer.target;
        final error = composer.error;
        final notice = composer.notice;

        return Container(
          height:
              height ??
              (target.isNewTopic || target.editsTopicMetadata
                  ? topicComposerHeight
                  : target.isTagsEdit
                  ? 190
                  : composerHeight),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.shell.content,
            borderRadius: BorderRadius.circular(22),
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
              // Both, because the app runs on macOS and will run elsewhere.
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  controller.submitComposer,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  controller.submitComposer,
              const SingleActivator(LogicalKeyboardKey.escape):
                  controller.closeComposer,
              // A bold button with no Cmd+B is a strange thing on a desktop.
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
              if (controller
                  .siteConfigFor(composer.target.siteUrl)
                  .localDatesEnabled)
                const SingleActivator(
                  LogicalKeyboardKey.period,
                  shift: true,
                ): () =>
                    insertCurrentLocalDate(context, composer),
            },
            child: Column(
              children: [
                _Header(
                  target: target,
                  onClose: controller.closeComposer,
                  onMove: onMove,
                  onMoveEnd: onMoveEnd,
                ),
                if (target.isNewTopic || target.editsTopicMetadata)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: TextField(
                      controller: composer.title,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Title',
                      ),
                    ),
                  ),
                if (target.isNewTopic ||
                    target.editsTopicMetadata ||
                    target.isTagsEdit)
                  _TopicTaxonomy(composer: composer),
                if (!target.isTagsEdit) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: ComposerEditor(
                        composer: composer,
                        hintText: switch (target) {
                          _ when composer.loadingBody => 'Loading that post…',
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
                  // Only ever says something when there is something to say.
                  // "Draft saved" every two seconds is noise; not being saved
                  // is worth interrupting for, because it changes what closing
                  // the composer costs.
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
                      composer.submitting ||
                      composer.state == ComposerState.checking ||
                      composer.loadingBody,
                  // After a failure that could not be checked, the button
                  // stops offering to send and offers to look instead.
                  label: switch (composer) {
                    _ when composer.canRecheck => 'Check again',
                    _ when target.isEdit => 'Save',
                    _ when target.isNewTopic => 'Create topic',
                    _ => 'Reply',
                  },
                  onSubmit: switch (composer) {
                    _ when composer.canRecheck => controller.recheckComposer,
                    _ when composer.canSubmit => controller.submitComposer,
                    _ => null,
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A movable, resizable composer window constrained to its reading pane.
///
/// Position and size intentionally live here rather than in the shell
/// controller because they are presentation state, not draft state. The local
/// state keeps gestures immediate while [ComposerGeometryStore] restores the
/// user's last completed move or resize for each newly opened composer.
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
  static const double _edgeHandleExtent = 10;
  static const double _cornerHandleExtent = 22;
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
          Positioned(
            left: geometry.position.dx,
            top: geometry.position.dy,
            width: geometry.size.width,
            height: geometry.size.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
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
                  top: 0,
                  left: _cornerHandleExtent,
                  right: _cornerHandleExtent,
                  height: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, top: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-bottom'),
                  cursor: SystemMouseCursors.resizeUpDown,
                  bottom: 0,
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
                  left: 0,
                  width: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, left: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-right'),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  top: _cornerHandleExtent,
                  bottom: _cornerHandleExtent,
                  right: 0,
                  width: _edgeHandleExtent,
                  onResize: (delta) => _resize(delta, bounds, right: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-top-left'),
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  top: 0,
                  left: 0,
                  width: _cornerHandleExtent,
                  height: _cornerHandleExtent,
                  onResize: (delta) =>
                      _resize(delta, bounds, top: true, left: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-top-right'),
                  cursor: SystemMouseCursors.resizeUpRightDownLeft,
                  top: 0,
                  right: 0,
                  width: _cornerHandleExtent,
                  height: _cornerHandleExtent,
                  onResize: (delta) =>
                      _resize(delta, bounds, top: true, right: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-bottom-left'),
                  cursor: SystemMouseCursors.resizeUpRightDownLeft,
                  bottom: 0,
                  left: 0,
                  width: _cornerHandleExtent,
                  height: _cornerHandleExtent,
                  onResize: (delta) =>
                      _resize(delta, bounds, bottom: true, left: true),
                  onResizeEnd: () => _persistGeometry(bounds),
                ),
                _resizeHandle(
                  key: const ValueKey('composer-resize-bottom-right'),
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  bottom: 0,
                  right: 0,
                  width: _cornerHandleExtent,
                  height: _cornerHandleExtent,
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
    child: MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onResize(details.delta),
        onPanEnd: (_) => onResizeEnd(),
        child: child,
      ),
    ),
  );

  _ComposerGeometry _geometryFor(Size bounds) {
    final horizontalInset = math.min(_inset, bounds.width / 2);
    final verticalInset = math.min(_inset, bounds.height / 2);
    final maximumWidth = math.max(0.0, bounds.width - horizontalInset * 2);
    final maximumHeight = math.max(0.0, bounds.height - verticalInset * 2);
    final minimumWidth = math.min(_minimumWidth, maximumWidth);
    final minimumHeight = math.min(_minimumHeight, maximumHeight);
    final wantedHeight = switch (widget.composer.target) {
      final target when target.isNewTopic || target.editsTopicMetadata =>
        topicComposerHeight,
      final target when target.isTagsEdit => 190.0,
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
    return target.isNewTopic || target.editsTopicMetadata
        ? _minimumTopicHeight
        : _minimumReplyHeight;
  }
}

class _ComposerGeometry {
  const _ComposerGeometry({required this.size, required this.position});

  final Size size;
  final Offset position;
}

class _TopicTaxonomy extends StatelessWidget {
  const _TopicTaxonomy({required this.composer});

  final ComposerController composer;

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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (!composer.target.isTagsEdit)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _pickCategory(context, shell, state.categories),
                    icon: category == null
                        ? const DIcon(DIcons.folder, size: 15)
                        : Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Color(category.colorValue),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                    label: Text(category?.name ?? 'Category'),
                  ),
                if (!composer.target.isTagsEdit) const SizedBox(width: 8),
                if (state.capabilities.canTagTopics || composer.tags.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showShellSheet<void>(
                        context: context,
                        title: 'Tags',
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        builder: (_) => _TagPickerSheet(
                          composer: composer,
                          capabilities: state.capabilities,
                        ),
                      ),
                      icon: const DIcon(DIcons.tag, size: 15),
                      label: Text(
                        composer.tags.isEmpty
                            ? 'Tags'
                            : composer.tags.map((tag) => tag.name).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
    List<TopicCategory> all,
  ) async {
    final permitted = all.where((category) => category.canCreateTopic).toList();
    final permittedIds = permitted.map((category) => category.id).toSet();
    final allowed = <TopicCategory>[];
    final visited = <int>{};
    void appendChildren(int? parentId) {
      final children =
          permitted
              .where(
                (category) => parentId == null
                    ? category.parentCategoryId == null ||
                          !permittedIds.contains(category.parentCategoryId)
                    : category.parentCategoryId == parentId,
              )
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      for (final child in children) {
        if (!visited.add(child.id)) continue;
        allowed.add(child);
        appendChildren(child.id);
      }
    }

    appendChildren(null);
    final selected = await showShellSheet<int>(
      context: context,
      title: 'Choose category',
      padding: EdgeInsets.zero,
      builder: (sheetContext) => Column(
        children: [
          for (final category in allowed)
            ListTile(
              contentPadding: EdgeInsets.only(
                left: category.parentCategoryId == null ? 20 : 44,
                right: 16,
              ),
              leading: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(category.colorValue),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              title: Text(category.name),
              trailing: category.id == composer.categoryId
                  ? const DIcon(DIcons.check, size: 16)
                  : null,
              onTap: () => Navigator.pop(sheetContext, category.id),
            ),
        ],
      ),
    );
    if (selected != null) {
      await shell.changeComposerCategory(composer, selected);
    }
  }
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.composer, required this.capabilities});

  final ComposerController composer;
  final TopicComposerCapabilities capabilities;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  int _revision = 0;
  bool _searchRunning = false;
  ({int revision, String term})? _queuedSearch;
  TopicTagSearch _result = const TopicTagSearch();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queuedSearch = null;
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  Future<void> _search(String term) async {
    final revision = ++_revision;
    setState(() => _loading = true);
    if (_searchRunning) {
      _queuedSearch = (revision: revision, term: term);
      return;
    }
    await _runSearch(revision, term);
  }

  Future<void> _runSearch(int revision, String term) async {
    _searchRunning = true;
    try {
      final result = await ShellScope.read(
        context,
      ).searchComposerTags(widget.composer, term.trim());
      if (!mounted || revision != _revision) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _result = const TopicTagSearch(forbiddenMessage: "Couldn't load tags.");
        _loading = false;
      });
    } finally {
      _searchRunning = false;
      final queued = _queuedSearch;
      _queuedSearch = null;
      if (queued != null && mounted && queued.revision == _revision) {
        unawaited(_runSearch(queued.revision, queued.term));
      }
    }
  }

  bool _selected(TopicTag tag) => widget.composer.tags.any(
    (selected) => selected.id == tag.id || selected.name == tag.name,
  );

  void _toggle(TopicTag tag) {
    if (tag.disabled) return;
    final tags = [...widget.composer.tags];
    final index = tags.indexWhere(
      (selected) => selected.id == tag.id || selected.name == tag.name,
    );
    if (index >= 0) {
      tags.removeAt(index);
    } else {
      final maximum = widget.capabilities.maxTagsPerTopic;
      if (maximum != null && tags.length >= maximum) return;
      tags.add(tag);
    }
    widget.composer.setTags(tags);
    setState(() {});
  }

  TopicTag? get _newTag {
    if (!widget.capabilities.canCreateTag || _result.isForbidden) return null;
    final name = _query.text.trim();
    if (name.isEmpty ||
        widget.composer.tags.any(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        ) ||
        _result.results.any(
          (tag) => tag.name.toLowerCase() == name.toLowerCase(),
        )) {
      return null;
    }
    final maximumLength = widget.capabilities.maxTagLength;
    if (maximumLength != null && name.length > maximumLength) return null;
    final maximumTags = widget.capabilities.maxTagsPerTopic;
    if (maximumTags != null && widget.composer.tags.length >= maximumTags) {
      return null;
    }
    final source = widget.capabilities.tagsFilterRegexp;
    if (source != null && source.isNotEmpty) {
      try {
        var pattern = source;
        if (pattern.startsWith('/') && pattern.lastIndexOf('/') > 0) {
          pattern = pattern.substring(1, pattern.lastIndexOf('/'));
        }
        final match = RegExp(pattern).firstMatch(name);
        if (match == null || match.start != 0 || match.end != name.length) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }
    return TopicTag(name: name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newTag = _newTag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          onChanged: (value) {
            _changed(value);
            setState(() {});
          },
          onSubmitted: (_) {
            if (newTag != null) _toggle(newTag);
          },
          decoration: const InputDecoration(
            prefixIcon: DIcon(DIcons.magnifyingGlass, size: 17),
            hintText: 'Search tags',
          ),
        ),
        if (widget.composer.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.composer.tags)
                InputChip(label: Text(tag.name), onDeleted: () => _toggle(tag)),
            ],
          ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        else ...[
          if (_result.explanation case final message?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (newTag != null)
            ListTile(
              leading: const DIcon(DIcons.plus, size: 16),
              title: Text('Create “${newTag.name}”'),
              onTap: () => _toggle(newTag),
            ),
          for (final tag in _result.results)
            CheckboxListTile(
              value: _selected(tag),
              onChanged: tag.disabled ? null : (_) => _toggle(tag),
              title: Text(tag.name),
              subtitle: tag.disabledReason == null
                  ? null
                  : Text(tag.disabledReason!),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ],
    );
  }
}

/// The shared markdown editor used by topic and chat composers.
///
/// The surrounding composer decides its geometry and submission behavior. The
/// field keeps the writing technology in one place: markdown highlighting,
/// mention and emoji completion, rich inline pills, image drops, and the
/// selection formatting toolbar all behave identically wherever it is used.
class ComposerEditor extends StatefulWidget {
  const ComposerEditor({
    super.key,
    required this.composer,
    required this.hintText,
    required this.textStyle,
    required this.hintStyle,
    this.autofocus = true,
  });

  final ComposerController composer;
  final String hintText;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final bool autofocus;

  @override
  State<ComposerEditor> createState() => _ComposerEditorState();
}

class _ComposerEditorState extends State<ComposerEditor> {
  static const _menuWidth = 88.0;
  static const _menuHeight = 44.0;
  static const _menuGap = 4.0;

  final GlobalKey _stackKey = GlobalKey();
  final OverlayPortalController _selectionPortal = OverlayPortalController();
  final ValueNotifier<Rect?> _selectionAnchor = ValueNotifier(null);
  Object? _selectionSyncToken;
  ComposerQuoteBlock? _pointerDownQuote;
  ComposerImageBlock? _pointerDownImage;
  PollComposerBlock? _pointerDownPoll;
  LocalDateComposerBlock? _pointerDownLocalDate;
  Offset? _pointerDownPosition;
  int _pointerSequence = 0;
  bool _dragging = false;
  ComposerImageBlock? _selectedImage;
  final TextEditingController _imageAlt = TextEditingController();
  final ScrollController _scroll = ScrollController();
  TextSelection _lastQuoteSelection = const TextSelection.collapsed(offset: -1);
  bool _normalizingQuoteSelection = false;

  @override
  void initState() {
    super.initState();
    _lastQuoteSelection = widget.composer.text.selection;
    widget.composer.text.imageScrollController = _scroll;
    widget.composer.text.addListener(_syncSelectionToolbar);
    widget.composer.focus.addListener(_syncSelectionToolbar);
    _scroll.addListener(_syncSelectionToolbar);
    _syncSelectionToolbar();
  }

  @override
  void didUpdateWidget(ComposerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.composer, widget.composer)) return;
    oldWidget.composer.text.removeListener(_syncSelectionToolbar);
    oldWidget.composer.focus.removeListener(_syncSelectionToolbar);
    if (_pointerDownImage case final image?) {
      oldWidget.composer.text.releaseImagePointerEdit(image);
    }
    if (_pointerDownPoll case final poll?) {
      oldWidget.composer.text.releasePollPointerEdit(poll);
    }
    if (_pointerDownLocalDate case final date?) {
      oldWidget.composer.text.releaseLocalDatePointerEdit(date);
    }
    if (_selectedImage case final image?) {
      oldWidget.composer.text.releaseImagePointerEdit(image);
    }
    _pointerDownQuote = null;
    _pointerDownImage = null;
    _pointerDownPoll = null;
    _pointerDownLocalDate = null;
    _pointerDownPosition = null;
    _selectedImage = null;
    if (identical(oldWidget.composer.text.imageScrollController, _scroll)) {
      oldWidget.composer.text.imageScrollController = null;
    }
    widget.composer.text.imageScrollController = _scroll;
    _lastQuoteSelection = widget.composer.text.selection;
    widget.composer.text.addListener(_syncSelectionToolbar);
    widget.composer.focus.addListener(_syncSelectionToolbar);
    _syncSelectionToolbar();
  }

  @override
  void dispose() {
    _selectionSyncToken = null;
    _imageAlt.dispose();
    widget.composer.text.removeListener(_syncSelectionToolbar);
    widget.composer.focus.removeListener(_syncSelectionToolbar);
    _releasePointerDownPillCollapse();
    if (_selectedImage case final image?) {
      widget.composer.text.releaseImagePointerEdit(image);
    }
    _scroll.removeListener(_syncSelectionToolbar);
    if (identical(widget.composer.text.imageScrollController, _scroll)) {
      widget.composer.text.imageScrollController = null;
    }
    _selectionAnchor.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _syncSelectionToolbar() {
    if (!_normalizingQuoteSelection) {
      final current = widget.composer.text.selection;
      final normalized = widget.composer.text.protectQuoteSelection(
        current,
        _lastQuoteSelection,
      );
      _lastQuoteSelection = normalized;
      if (normalized != current) {
        _normalizingQuoteSelection = true;
        widget.composer.text.selection = normalized;
        _normalizingQuoteSelection = false;
        return;
      }
    }
    final selection = widget.composer.text.selection;
    if (!_canFormat(selection)) {
      _selectionSyncToken = null;
      _selectionAnchor.value = null;
      if (_selectionPortal.isShowing) _selectionPortal.hide();
      return;
    }

    final token = Object();
    _selectionSyncToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_selectionSyncToken, token)) return;
      final current = widget.composer.text.selection;
      if (!_canFormat(current)) {
        _selectionAnchor.value = null;
        if (_selectionPortal.isShowing) _selectionPortal.hide();
        return;
      }

      final editable = _renderEditable;
      final overlay = Overlay.of(context).context.findRenderObject();
      if (editable == null || overlay is! RenderBox || !overlay.hasSize) {
        if (_selectionPortal.isShowing) _selectionPortal.hide();
        return;
      }
      final endpoints = editable.getEndpointsForSelection(current);
      if (endpoints.isEmpty) {
        if (_selectionPortal.isShowing) _selectionPortal.hide();
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
      final center = (left + right) / 2;
      _selectionAnchor.value = Rect.fromLTWH(
        center - _menuWidth / 2,
        bottom - lineHeight,
        _menuWidth,
        lineHeight,
      );
      _selectionPortal.show();
    });
  }

  bool _canFormat(TextSelection selection) =>
      widget.composer.focus.hasFocus &&
      selection.isValid &&
      !selection.isCollapsed &&
      !selectionTouchesComposerQuote(
        widget.composer.text.quoteBlocks,
        selection,
      );

  RenderEditable? get _renderEditable {
    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    final root = _stackKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  void _moveDropCaret(Offset globalPosition) {
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
    if (details.files.any((item) => item is DropItemDirectory)) {
      widget.composer.showNotice('Folders cannot be uploaded here.');
    }
    final files = details.files
        .whereType<DropItemFile>()
        .map(
          (item) => ComposerUploadFile(
            name: item.name,
            length: () => _droppedFileLength(item),
            openRead: () => _openDroppedFile(item),
          ),
        )
        .toList();
    setState(() => _dragging = false);
    widget.composer.addDroppedImages(
      files,
      widget.composer.text.selection.extentOffset,
    );
  }

  Stream<List<int>> _openDroppedFile(DropItemFile item) async* {
    final bookmark = item.extraAppleBookmark;
    var scoped = false;
    if (bookmark != null && bookmark.isNotEmpty) {
      scoped = await DesktopDrop.instance.startAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    }
    try {
      yield* item.openRead();
    } finally {
      if (scoped) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark!,
        );
      }
    }
  }

  Future<int> _droppedFileLength(DropItemFile item) async {
    final bookmark = item.extraAppleBookmark;
    var scoped = false;
    if (bookmark != null && bookmark.isNotEmpty) {
      scoped = await DesktopDrop.instance.startAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    }
    try {
      return await item.length();
    } finally {
      if (scoped) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark!,
        );
      }
    }
  }

  bool get _hasPointerDownPill =>
      _pointerDownQuote != null ||
      _pointerDownImage != null ||
      _pointerDownPoll != null ||
      _pointerDownLocalDate != null;

  void _onEditorPointerDown(PointerDownEvent event) {
    _releasePointerDownPillCollapse();
    _pointerSequence++;
    final position = event.position;
    _pointerDownPosition = position;
    _pointerDownQuote = widget.composer.text.collapsedQuoteAtGlobalPosition(
      position,
    );
    _pointerDownImage = _pointerDownQuote == null
        ? widget.composer.text.collapsedImageAtGlobalPosition(position)
        : null;
    _pointerDownPoll = _pointerDownQuote == null && _pointerDownImage == null
        ? widget.composer.text.collapsedPollAtGlobalPosition(position)
        : null;
    _pointerDownLocalDate =
        _pointerDownQuote == null &&
            _pointerDownImage == null &&
            _pointerDownPoll == null
        ? widget.composer.text.collapsedLocalDateAtGlobalPosition(position)
        : null;
    if (!_hasPointerDownPill) {
      final editable = _renderEditable;
      if (editable == null) return;
      final offset = editable.getPositionForPoint(position).offset;
      _pointerDownQuote = widget.composer.text.quoteAtOffset(offset);
      _pointerDownImage = _pointerDownQuote == null
          ? widget.composer.text.collapsedImageAtOffset(offset)
          : null;
      _pointerDownPoll = _pointerDownQuote == null && _pointerDownImage == null
          ? widget.composer.text.collapsedPollAtOffset(offset)
          : null;
      _pointerDownLocalDate =
          _pointerDownQuote == null &&
              _pointerDownImage == null &&
              _pointerDownPoll == null
          ? widget.composer.text.collapsedLocalDateAtOffset(offset)
          : null;
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    if (_pointerDownImage case final image?) {
      text.keepImageCollapsedForPointerEdit(image);
    } else if (_pointerDownPoll case final poll?) {
      text.keepPollCollapsedForPointerEdit(poll);
    } else if (_pointerDownLocalDate case final date?) {
      text.keepLocalDateCollapsedForPointerEdit(date);
    }
  }

  void _releasePointerDownPillCollapse() {
    final text = widget.composer.text;
    if (_pointerDownImage case final image?) {
      text.releaseImagePointerEdit(image);
    }
    if (_pointerDownPoll case final poll?) {
      text.releasePollPointerEdit(poll);
    }
    if (_pointerDownLocalDate case final date?) {
      text.releaseLocalDatePointerEdit(date);
    }
  }

  void _clearPointerDownPill({bool releaseCollapse = true}) {
    if (releaseCollapse) _releasePointerDownPillCollapse();
    _pointerDownQuote = null;
    _pointerDownImage = null;
    _pointerDownPoll = null;
    _pointerDownLocalDate = null;
    _pointerDownPosition = null;
  }

  void _activatePointerDownPill() {
    final quote = _pointerDownQuote;
    final image = _pointerDownImage;
    final poll = _pointerDownPoll;
    final date = _pointerDownLocalDate;
    final position = _pointerDownPosition;
    _clearPointerDownPill(releaseCollapse: false);
    if (quote != null) {
      if (_selectedImage case final selected?) {
        widget.composer.text.releaseImagePointerEdit(selected);
        setState(() => _selectedImage = null);
      }
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
      _selectImage(image);
      return;
    }
    if (_selectedImage case final selected?) {
      widget.composer.text.releaseImagePointerEdit(selected);
      setState(() => _selectedImage = null);
    }
    if (poll != null) {
      unawaited(_editPoll(poll));
      return;
    }
    if (date != null) {
      unawaited(_editLocalDate(date));
    }
  }

  Future<void> _editPoll(PollComposerBlock poll) async {
    final text = widget.composer.text;
    text.keepPollCollapsedForPointerEdit(poll);
    text.selection = TextSelection.collapsed(offset: poll.end);
    try {
      await openPollComposer(context, widget.composer, block: poll);
    } finally {
      if (_stillContains(text.text, poll.start, poll.end, poll.source) &&
          !text.isPollExpanded(poll)) {
        text.selection = TextSelection.collapsed(offset: poll.end);
      }
      text.releasePollPointerEdit(poll);
    }
  }

  Future<void> _editLocalDate(LocalDateComposerBlock date) async {
    final text = widget.composer.text;
    text.keepLocalDateCollapsedForPointerEdit(date);
    text.selection = TextSelection.collapsed(offset: date.end);
    try {
      await openLocalDateComposer(context, widget.composer, block: date);
    } finally {
      if (_stillContains(text.text, date.start, date.end, date.source) &&
          !text.isLocalDateExpanded(date)) {
        text.selection = TextSelection.collapsed(offset: date.end);
      }
      text.releaseLocalDatePointerEdit(date);
    }
  }

  static bool _stillContains(String text, int start, int end, String source) =>
      start >= 0 &&
      end <= text.length &&
      start <= end &&
      text.substring(start, end) == source;

  void _selectImage(ComposerImageBlock image) {
    widget.composer.text.keepImageCollapsedForPointerEdit(image);
    widget.composer.text.selection = TextSelection.collapsed(offset: image.end);
    _imageAlt.text = image.alt;
    setState(() => _selectedImage = image);
    // If pointer-down already moved the caret into the image, the editable
    // needs one frame to project it again before its render box can anchor the
    // editor. Refresh the parent after that projection has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedImage?.start != image.start ||
          _selectedImage?.source != image.source) {
        return;
      }
      setState(() {});
    });
  }

  void _saveImageAlt() {
    final image = _selectedImage;
    if (image == null) return;
    widget.composer.text.releaseImagePointerEdit(image);
    widget.composer.setImageAlt(image, _imageAlt.text);
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  void _scaleImage(int scale) {
    final image = _selectedImage;
    if (image == null) return;
    widget.composer.text.releaseImagePointerEdit(image);
    widget.composer.setImageScale(image, scale);
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  void _dismissImage() {
    final image = _selectedImage;
    if (image == null) return;
    widget.composer.text.selection = TextSelection.collapsed(offset: image.end);
    widget.composer.text.releaseImagePointerEdit(image);
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  KeyEventResult _onEditorKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.backspace &&
            event.logicalKey != LogicalKeyboardKey.delete)) {
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
    for (final quote in widget.composer.text.quoteBlocks) {
      final removesQuote =
          (event.logicalKey == LogicalKeyboardKey.backspace &&
              quote.end == caret) ||
          (event.logicalKey == LogicalKeyboardKey.delete &&
              quote.start == caret);
      if (!removesQuote || !widget.composer.text.isQuoteCollapsed(quote)) {
        continue;
      }
      if (_selectedImage != null) setState(() => _selectedImage = null);
      widget.composer.removeQuote(quote);
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    for (final image in widget.composer.text.imageBlocks) {
      if (image.end != caret || !widget.composer.text.isImageCollapsed(image)) {
        continue;
      }
      if (_selectedImage case final selected?) {
        widget.composer.text.releaseImagePointerEdit(selected);
        setState(() => _selectedImage = null);
      }
      widget.composer.removeImage(image);
      return KeyEventResult.handled;
    }
    for (final poll in widget.composer.text.pollBlocks) {
      if (poll.end != caret || !widget.composer.text.isPollCollapsed(poll)) {
        continue;
      }
      unawaited(removePollComposer(context, widget.composer, poll));
      return KeyEventResult.handled;
    }
    for (final date in widget.composer.text.localDateBlocks) {
      if (date.end != caret ||
          !widget.composer.text.isLocalDateCollapsed(date)) {
        continue;
      }
      removeLocalDateComposer(context, widget.composer, date);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  (double, double)? _imageMenuPosition(BoxConstraints constraints) {
    final image = _selectedImage;
    final stack = _stackKey.currentContext?.findRenderObject();
    final rect = image == null
        ? null
        : widget.composer.text.collapsedImageGlobalRect(image);
    if (stack is! RenderBox || !stack.hasSize || rect == null) return null;
    final topLeft = stack.globalToLocal(rect.topLeft);
    final bottomRight = stack.globalToLocal(rect.bottomRight);
    const width = 310.0;
    const height = 92.0;
    final left = topLeft.dx.clamp(
      0.0,
      constraints.maxWidth > width ? constraints.maxWidth - width : 0.0,
    );
    var top = topLeft.dy - height - _menuGap;
    if (top < 0) top = bottomRight.dy + _menuGap;
    return (
      left,
      top.clamp(
        0.0,
        constraints.maxHeight > height ? constraints.maxHeight - height : 0.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final imageMenuPosition = _imageMenuPosition(constraints);
      return OverlayPortal(
        controller: _selectionPortal,
        overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
          valueListenable: _selectionAnchor,
          builder: (context, anchor, child) => CustomSingleChildLayout(
            delegate: AnchoredLayout(
              anchor: anchor,
              maxWidth: _menuWidth,
              gap: _menuGap,
              preferAbove: true,
            ),
            child: child!,
          ),
          child: _SelectionFormattingMenu(composer: widget.composer),
        ),
        child: DropTarget(
          enable: !context.isTouch,
          onDragEntered: (details) {
            _moveDropCaret(details.globalPosition);
            if (!_dragging) setState(() => _dragging = true);
          },
          onDragUpdated: (details) => _moveDropCaret(details.globalPosition),
          onDragExited: (_) {
            if (_dragging) setState(() => _dragging = false);
          },
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
                            child: Text(
                              widget.hintText,
                              style: widget.hintStyle,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onEditorPointerDown,
                  onPointerMove: _onEditorPointerMove,
                  onPointerUp: _onEditorPointerUp,
                  onPointerCancel: (_) => _cancelEditorPointer(),
                  child: ComposerSuggestionField(
                    composer: widget.composer,
                    field: ClipRect(
                      child: Focus(
                        onKeyEvent: _onEditorKeyEvent,
                        child: TextField(
                          // Not decoration: a new key builds a new editable, and
                          // with it a new undo stack. It is the only way to stop undo
                          // reaching back into a reply that has already been sent.
                          key: ValueKey(widget.composer.fieldGeneration),
                          controller: widget.composer.text,
                          scrollController: _scroll,
                          focusNode: widget.composer.focus,
                          autofocus: widget.autofocus,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: const [
                            ComposerQuoteInputFormatter(),
                          ],
                          onTapAlwaysCalled: true,
                          onTap: _activatePointerDownPill,
                          style: widget.textStyle,
                          // InputDecorator only gives the editable one text line
                          // even when the TextField expands. The composer draws
                          // its hint separately so this viewport fills the editor.
                          decoration: null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (imageMenuPosition case (final left, final top))
                Positioned(
                  left: left,
                  top: top,
                  child: _ImageComposerMenu(
                    image: _selectedImage!,
                    alt: _imageAlt,
                    onSaveAlt: _saveImageAlt,
                    onScale: _scaleImage,
                    onDismiss: _dismissImage,
                  ),
                ),
              if (_dragging)
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
                      child: const Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Drop images to upload'),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SelectionFormattingMenu extends StatelessWidget {
  const _SelectionFormattingMenu({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFieldTapRegion(
      child: Material(
        key: const ValueKey('composer-selection-toolbar'),
        color: theme.shell.floating,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: _ComposerEditorState._menuWidth,
          height: _ComposerEditorState._menuHeight,
          decoration: BoxDecoration(
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
                  visualDensity: VisualDensity.compact,
                  color: theme.colorScheme.onSurface,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageComposerMenu extends StatelessWidget {
  const _ImageComposerMenu({
    required this.image,
    required this.alt,
    required this.onSaveAlt,
    required this.onScale,
    required this.onDismiss,
  });

  final ComposerImageBlock image;
  final TextEditingController alt;
  final VoidCallback onSaveAlt;
  final void Function(int scale) onScale;
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
          width: 310,
          height: 92,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: scaleIndex > 0
                          ? () => onScale(scales[scaleIndex - 1])
                          : null,
                      icon: const Icon(Icons.zoom_out, size: 18),
                      tooltip: 'Decrease image size',
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$scale%', style: theme.textTheme.labelMedium),
                    IconButton(
                      onPressed: scaleIndex < scales.length - 1
                          ? () => onScale(scales[scaleIndex + 1])
                          : null,
                      icon: const Icon(Icons.zoom_in, size: 18),
                      tooltip: 'Increase image size',
                      visualDensity: VisualDensity.compact,
                    ),
                    const Spacer(),
                  ],
                ),
                SizedBox(
                  height: 34,
                  child: TextField(
                    controller: alt,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSaveAlt(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add image description',
                      suffixIcon: IconButton(
                        onPressed: onSaveAlt,
                        tooltip: 'Save alt text',
                        icon: const Icon(Icons.check, size: 16),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.target,
    required this.onClose,
    this.onMove,
    this.onMoveEnd,
  });

  final ComposerTarget target;
  final VoidCallback onClose;
  final ValueChanged<Offset>? onMove;
  final VoidCallback? onMoveEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyTo = target.replyToUsername;

    final header = SizedBox(
      key: const ValueKey('composer-drag-handle'),
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(
          children: [
            DIcon(
              target.isNewTopic
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
                switch ((target.editingPostNumber, replyTo)) {
                  _ when target.isNewTopic => 'Create a new topic',
                  _ when target.isTagsEdit => 'Edit topic tags',
                  (final number?, _) => 'Edit post #$number',
                  (_, final username?) => 'Reply to @$username',
                  _ => 'Reply to ${target.topicTitle}',
                },
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
              tooltip: 'Close composer',
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

/// Plugin-contributed composer actions.
///
/// Bold and italic live beside selected text in [ComposerEditor], keeping this
/// persistent row for actions that create richer blocks.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) => ShellSelector<(bool, bool)>(
    // Plugin creation capabilities arrive independently of composer text.
    // Select the fresh Poll capability so an already-open composer gains (or
    // keeps hiding) its contributed action as soon as the session answers.
    select: (controller) => (
      controller.canCreatePollFor(composer.target.siteUrl),
      controller.siteConfigFor(composer.target.siteUrl).localDatesEnabled,
    ),
    builder: (context, _, _) => _buildToolbar(context),
  );

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final actions = pluginRegistry.composerToolbar(context, composer);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Row(
        children: [
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

/// Upload progress shared by full-size and compact composers.
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
          return SizedBox(
            height: failed ? 52 : 40,
            child: Row(
              children: [
                const SizedBox(width: 10),
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
                      else
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.composer,
    required this.message,
    required this.isError,
    required this.busy,
    required this.label,
    required this.onSubmit,
  });

  final ComposerController composer;
  final String? message;
  final bool isError;
  final bool busy;
  final String label;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 14, 10),
      child: Row(
        children: [
          if (!composer.target.isTagsEdit) _Toolbar(composer: composer),
          Expanded(
            child: message == null
                ? const SizedBox.shrink()
                : Text(
                    message!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            // Disabled while anything is in flight, because there is no way to
            // take a second post back.
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }
}
