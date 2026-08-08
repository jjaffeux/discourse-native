import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../models/composer_upload.dart';
import '../models/topic.dart';
import '../plugins/poll/poll_composer_parser.dart';
import '../plugins/poll/poll_composer_pill.dart';
import '../plugins/poll/poll_plugin.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'composer_images.dart';
import 'composer_marks.dart';
import 'composer_suggestions.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

/// The reply composer, docked under the post stream.
///
/// A panel rather than a sheet, which is the other thing the shell offers: on a
/// desktop the whole point of replying is to keep reading the topic while you
/// write about it, and a modal sheet takes the topic away.
///
/// What is typed here is what gets posted. Discourse stores raw markdown, so
/// the field's text *is* the payload — there is no document model in between to
/// normalise, escape or lose anything.
class ComposerPanel extends StatelessWidget {
  const ComposerPanel({super.key, required this.composer});

  final ComposerController composer;

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
          height: target.isNewTopic || target.editsTopicMetadata
              ? topicComposerHeight
              : target.isTagsEdit
              ? 190
              : composerHeight,
          decoration: BoxDecoration(
            color: theme.shell.content,
            border: Border(top: BorderSide(color: theme.shell.divider)),
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
            },
            child: Column(
              children: [
                _Header(target: target, onClose: controller.closeComposer),
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
                  _Toolbar(composer: composer),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _ComposerEditor(
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
                  _UploadQueue(composer: composer),
                _Footer(
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
            child: Center(child: CircularProgressIndicator()),
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

class _ComposerEditor extends StatefulWidget {
  const _ComposerEditor({
    required this.composer,
    required this.hintText,
    required this.textStyle,
    required this.hintStyle,
  });

  final ComposerController composer;
  final String hintText;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;

  @override
  State<_ComposerEditor> createState() => _ComposerEditorState();
}

class _ComposerEditorState extends State<_ComposerEditor> {
  static const _menuWidth = 88.0;
  static const _menuHeight = 44.0;
  static const _menuGap = 4.0;

  final GlobalKey _stackKey = GlobalKey();
  Offset? _pointerDown;
  PollComposerBlock? _hoveredPoll;
  Timer? _hideTimer;
  bool _menuHovered = false;
  bool _dragging = false;
  ComposerImageBlock? _selectedImage;
  final TextEditingController _imageAlt = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.composer.text.imageScrollController = _scroll;
  }

  @override
  void didUpdateWidget(_ComposerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.composer, widget.composer)) return;
    if (identical(oldWidget.composer.text.imageScrollController, _scroll)) {
      oldWidget.composer.text.imageScrollController = null;
    }
    widget.composer.text.imageScrollController = _scroll;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _imageAlt.dispose();
    if (identical(widget.composer.text.imageScrollController, _scroll)) {
      widget.composer.text.imageScrollController = null;
    }
    _scroll.dispose();
    super.dispose();
  }

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

  void _onHover(PointerHoverEvent event) {
    final block = widget.composer.text.collapsedPollAtGlobalPosition(
      event.position,
    );
    if (block != null) return _showMenuFor(block);
    if (!_menuHovered) _scheduleHide();
  }

  bool _onPillHover(PollComposerPillHoverNotification notification) {
    if (notification.hovering) {
      _showMenuFor(notification.block);
    } else if (!_menuHovered) {
      _scheduleHide();
    }
    return true;
  }

  void _showMenuFor(PollComposerBlock block) {
    _hideTimer?.cancel();
    if (_hoveredPoll?.start != block.start ||
        _hoveredPoll?.source != block.source) {
      setState(() => _hoveredPoll = block);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _menuHovered || _hoveredPoll == null) return;
      setState(() => _hoveredPoll = null);
    });
  }

  void _hideMenu() {
    _hideTimer?.cancel();
    _menuHovered = false;
    if (_hoveredPoll != null && mounted) {
      setState(() => _hoveredPoll = null);
    }
  }

  void _onFieldTap() {
    final pointer = _pointerDown;
    _pointerDown = null;
    if (pointer == null) return;
    final image = widget.composer.text.collapsedImageAtGlobalPosition(pointer);
    if (image != null) {
      _selectImage(image);
      return;
    }
    if (_selectedImage != null) setState(() => _selectedImage = null);
    final block = widget.composer.text.collapsedPollAtGlobalPosition(pointer);
    if (block == null) return;

    _hideMenu();
    widget.composer.text.expandPollAsRaw(block);
    widget.composer.focus.requestFocus();
  }

  void _selectImage(ComposerImageBlock image) {
    _hideMenu();
    widget.composer.text.suppressCollapsedCaretForImage(image);
    _imageAlt.text = image.alt;
    setState(() => _selectedImage = image);
  }

  void _saveImageAlt() {
    final image = _selectedImage;
    if (image == null) return;
    widget.composer.setImageAlt(image, _imageAlt.text);
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  void _scaleImage(int scale) {
    final image = _selectedImage;
    if (image == null) return;
    widget.composer.setImageScale(image, scale);
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  void _deleteImage() {
    final image = _selectedImage;
    if (image == null) return;
    widget.composer.removeImage(image);
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  void _dismissImage() {
    if (_selectedImage == null) return;
    setState(() => _selectedImage = null);
    widget.composer.focus.requestFocus();
  }

  void _editPoll() {
    final block = _hoveredPoll;
    if (block == null) return;
    _hideMenu();
    unawaited(openPollComposer(context, widget.composer, block: block));
  }

  void _removePoll() {
    final block = _hoveredPoll;
    if (block == null) return;
    _hideMenu();
    unawaited(removePollComposer(context, widget.composer, block));
  }

  (double, double)? _menuPosition(BoxConstraints constraints) {
    final block = _hoveredPoll;
    final stack = _stackKey.currentContext?.findRenderObject();
    final pillRect = block == null
        ? null
        : widget.composer.text.collapsedPollGlobalRect(block);
    if (stack is! RenderBox || !stack.hasSize || pillRect == null) return null;

    final pillTopLeft = stack.globalToLocal(pillRect.topLeft);
    final pillBottomRight = stack.globalToLocal(pillRect.bottomRight);
    final maxLeft = constraints.maxWidth > _menuWidth
        ? constraints.maxWidth - _menuWidth
        : 0.0;
    final left = pillTopLeft.dx.clamp(0.0, maxLeft);
    var top = pillTopLeft.dy - _menuHeight - _menuGap;
    if (top < 0) top = pillBottomRight.dy + _menuGap;
    final maxTop = constraints.maxHeight > _menuHeight
        ? constraints.maxHeight - _menuHeight
        : 0.0;
    return (left, top.clamp(0.0, maxTop));
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
      final menuPosition = _menuPosition(constraints);
      final imageMenuPosition = _imageMenuPosition(constraints);
      return DropTarget(
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
        child: NotificationListener<PollComposerPillHoverNotification>(
          onNotification: _onPillHover,
          child: MouseRegion(
            // Retained as a fallback for embedders that do not hit-test inline
            // children, and to close the menu when the pointer leaves the field.
            onHover: _onHover,
            onExit: (_) => _scheduleHide(),
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
                    onPointerDown: (event) => _pointerDown = event.position,
                    child: ComposerSuggestionField(
                      composer: widget.composer,
                      field: ClipRect(
                        child: TextField(
                          // Not decoration: a new key builds a new editable, and
                          // with it a new undo stack. It is the only way to stop undo
                          // reaching back into a reply that has already been sent.
                          key: ValueKey(widget.composer.fieldGeneration),
                          controller: widget.composer.text,
                          scrollController: _scroll,
                          focusNode: widget.composer.focus,
                          autofocus: true,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          onTapAlwaysCalled: true,
                          onTap: _onFieldTap,
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
                if (menuPosition case (final left, final top))
                  Positioned(
                    left: left,
                    top: top,
                    child: MouseRegion(
                      onEnter: (_) {
                        _hideTimer?.cancel();
                        _menuHovered = true;
                      },
                      onExit: (_) {
                        _menuHovered = false;
                        _scheduleHide();
                      },
                      child: _PollComposerMenu(
                        onEdit: _editPoll,
                        onRemove: _removePoll,
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
                      onRemove: _deleteImage,
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
        ),
      );
    },
  );
}

class _ImageComposerMenu extends StatelessWidget {
  const _ImageComposerMenu({
    required this.image,
    required this.alt,
    required this.onSaveAlt,
    required this.onScale,
    required this.onRemove,
    required this.onDismiss,
  });

  final ComposerImageBlock image;
  final TextEditingController alt;
  final VoidCallback onSaveAlt;
  final void Function(int scale) onScale;
  final VoidCallback onRemove;
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
                    IconButton(
                      onPressed: onRemove,
                      icon: const DIcon(DIcons.trashCan, size: 16),
                      tooltip: 'Remove image',
                      color: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
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

class _PollComposerMenu extends StatelessWidget {
  const _PollComposerMenu({required this.onEdit, required this.onRemove});

  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _ComposerEditorState._menuWidth,
        height: _ComposerEditorState._menuHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit poll',
              visualDensity: VisualDensity.compact,
              icon: const DIcon(DIcons.pencil, size: 16),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove poll',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.error,
              icon: const DIcon(DIcons.trashCan, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.target, required this.onClose});

  final ComposerTarget target;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyTo = target.replyToUsername;

    return SizedBox(
      height: shellHeaderHeight,
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
  }
}

/// The formatting actions.
///
/// One button per mark. What a mark means — which characters wrap the selection
/// — belongs in the composer, not in the button.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) => ShellSelector<bool>(
    // Plugin creation capabilities arrive independently of composer text.
    // Select the fresh Poll capability so an already-open composer gains (or
    // keeps hiding) its contributed action as soon as the session answers.
    select: (controller) =>
        controller.canCreatePollFor(composer.target.siteUrl),
    builder: (context, _, _) => _buildToolbar(context),
  );

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Row(
        children: [
          for (final (mark, icon, label) in const [
            (ComposerMark.bold, DIcons.bold, 'Bold'),
            (ComposerMark.italic, DIcons.italic, 'Italic'),
          ])
            IconButton(
              onPressed: () => composer.toggleMark(mark),
              icon: DIcon(icon, size: 18),
              tooltip: '$label  ${_shortcutHint(label)}',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          for (final plugin in sitePlugins)
            for (final action in plugin.composerToolbar(context, composer))
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

  static String _shortcutHint(String label) => label == 'Bold' ? '⌘B' : '⌘I';
}

class _UploadQueue extends StatelessWidget {
  const _UploadQueue({required this.composer});

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
    required this.message,
    required this.isError,
    required this.busy,
    required this.label,
    required this.onSubmit,
  });

  final String? message;
  final bool isError;
  final bool busy;
  final String label;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
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
          const SizedBox(width: 12),
          FilledButton(
            // Disabled while anything is in flight, because there is no way to
            // take a second post back.
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }
}
