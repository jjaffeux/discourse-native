import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderEditable;
import 'package:flutter/services.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../models/composer_placement.dart';
import '../models/composer_upload.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../plugin_api/composer_footer_layout.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'composer_autocomplete.dart';
import 'composer_blockquote.dart';
import 'composer_clipboard.dart';
import 'composer_controller.dart';
import 'composer_discard.dart';
import 'composer_drop.dart';
import 'composer_galleries.dart';
import 'composer_header.dart';
import 'composer_images.dart';
import 'composer_link.dart';
import 'composer_marks.dart';
import 'composer_media_editing_coordinator.dart';
import 'composer_quotes.dart';
import 'composer_reply_context.dart';
import 'composer_suggestions.dart';
import 'composer_tag_removal_notice.dart';
import 'composer_upload_picker.dart';
import 'emoji_composer.dart';
import 'emoji_picker.dart';
import 'image_decode.dart';
import 'markdown_highlight.dart';
import 'platform.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'topic_title.dart';

bool get _usesCommandModifier =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

SingleActivator _formattingShortcut(LogicalKeyboardKey key) => SingleActivator(
  key,
  meta: _usesCommandModifier,
  control: !_usesCommandModifier,
);

class ComposerPanel extends StatelessWidget {
  const ComposerPanel({
    super.key,
    required this.composer,
    this.height,
    this.minimized = false,
    this.onMinimize,
    this.onRestore,
    this.placement = ComposerPlacement.right,
    this.onPlacementChanged,
    this.pickImages = pickComposerImages,
    this.readClipboardImages = readComposerClipboardImages,
  });

  final ComposerController composer;
  final double? height;
  final bool minimized;
  final VoidCallback? onMinimize;
  final VoidCallback? onRestore;
  final ComposerPlacement placement;
  final ValueChanged<ComposerPlacement>? onPlacementChanged;
  final ComposerImagePicker pickImages;
  final ComposerClipboardImageReader readClipboardImages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    void openLink() =>
        unawaited(showComposerLinkDialog(context: context, composer: composer));
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
          // The dock divider owns the boundary with adjacent containers.
          decoration: BoxDecoration(color: theme.shell.content),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                  controller.submitComposer(composer: composer),
              const SingleActivator(
                LogicalKeyboardKey.enter,
                control: true,
              ): () =>
                  controller.submitComposer(composer: composer),
              const SingleActivator(LogicalKeyboardKey.escape): close,
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true): close,
              const SingleActivator(LogicalKeyboardKey.keyW, control: true):
                  close,
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
              if (!_usesCommandModifier)
                const SingleActivator(LogicalKeyboardKey.keyE, control: true):
                    composer.toggleSelectedInlineCode,
              const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
                  openLink,
              if (!_usesCommandModifier)
                const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                    openLink,
              for (final binding in PluginScope.of(
                context,
              ).registry.composerShortcuts(context, composer).entries)
                binding.key: () {
                  if (composer.isEditing) binding.value();
                },
            },
            child: FocusScope(
              canRequestFocus: !composer.discarding,
              descendantsAreFocusable: !composer.discarding,
              descendantsAreTraversable: !composer.discarding,
              child: AbsorbPointer(
                absorbing: composer.discarding,
                child: Column(
                  children: [
                    ComposerHeader(
                      composer: composer,
                      minimized: minimized,
                      onClose: close,
                      closeTooltip: composer.canSaveDraft
                          ? 'Save and close'
                          : 'Close composer',
                      onMinimize: minimized ? null : onMinimize,
                      onRestore: minimized ? onRestore : null,
                      placement: placement,
                      onPlacementChanged: onPlacementChanged,
                    ),
                    if (!minimized)
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => DScrollArea(
                            thumbVisibility: false,
                            child: SizedBox(
                              height: math.max(
                                constraints.maxHeight,
                                MediaQuery.textScalerOf(context).scale(
                                  target.createsTopic ||
                                          target.editsTopicMetadata
                                      ? 320
                                      : 240,
                                ),
                              ),
                              child: Column(
                                children: [
                                  if (target.mode == ComposerMode.reply &&
                                      constraints.maxHeight >= 80)
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: math.min(
                                          140,
                                          math.max(
                                            48,
                                            constraints.maxHeight * 0.6,
                                          ),
                                        ),
                                      ),
                                      child: ComposerReplyContext(
                                        key: ValueKey((
                                          target.siteUrl,
                                          target.topicId,
                                          target.replyToPostNumber,
                                        )),
                                        target: target,
                                      ),
                                    ),
                                  if (target.isPrivateMessage)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        2,
                                        16,
                                        6,
                                      ),
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
                                  if (target.createsTopic ||
                                      target.editsTopicMetadata)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        2,
                                        16,
                                        8,
                                      ),
                                      child: DInput(
                                        key: const ValueKey(
                                          'composer-topic-title',
                                        ),
                                        controller: composer.title,
                                        readOnly: !composer.isEditing,
                                        labelText: 'Title',
                                        hintText: 'Give your topic a title',
                                        textInputAction: TextInputAction.next,
                                      ),
                                    ),
                                  if (target.isNewTopic ||
                                      target.editsTopicMetadata ||
                                      target.isTaxonomyEdit)
                                    _TopicTaxonomy(composer: composer),
                                  if (target.mode == ComposerMode.postEdit)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        8,
                                      ),
                                      child: DItem(
                                        key: const ValueKey(
                                          'composer-edit-context',
                                        ),
                                        variant: DItemVariant.muted,
                                        size: DItemSize.xs,
                                        children: [
                                          DItemContent(
                                            spacing: 3,
                                            children: [
                                              const DItemDescription(
                                                child: Text('Topic'),
                                              ),
                                              DItemTitle(
                                                maxLines: 2,
                                                child: TopicTitle(
                                                  target.topicTitle,
                                                  siteUrl: target.siteUrl,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (!target.isTaxonomyEdit) ...[
                                    _FormattingToolbar(composer: composer),
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              2,
                                              16,
                                              8,
                                            ),
                                            child: ComposerEditor(
                                              composer: composer,
                                              showSelectionToolbar: false,
                                              pickImages: pickImages,
                                              readClipboardImages:
                                                  readClipboardImages,
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
                                                          composer
                                                              .autocomplete
                                                              .trigger
                                                              ?.query ??
                                                          suggestion.value,
                                                      anchor: anchor,
                                                    );
                                                  },
                                              hintText: switch (target) {
                                                _ when composer.loadingBody =>
                                                  'Loading that post…',
                                                _
                                                    when target
                                                        .isPrivateMessage =>
                                                  'Write your message…',
                                                _ when target.isNewTopic =>
                                                  'Write your topic…',
                                                _ when target.isEdit =>
                                                  'Edit this post…',
                                                _
                                                    when target
                                                            .replyToUsername !=
                                                        null =>
                                                  'Reply to @${target.replyToUsername}…',
                                                _ => 'Write a reply…',
                                              },
                                              textStyle:
                                                  theme.textTheme.bodyLarge,
                                              hintStyle: theme
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                          if (composer.tagRemovalNotice
                                              case final message?)
                                            Positioned(
                                              left: 16,
                                              right: 16,
                                              bottom: 12,
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: ComposerTagRemovalNotice(
                                                  message: message,
                                                  onDismiss: composer
                                                      .dismissTagRemovalNotice,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ] else
                                    const Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!minimized && composer.uploads.isNotEmpty)
                      ComposerUploadQueue(composer: composer),
                    if (!minimized)
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
                          _ when composer.whisper => 'Whisper',
                          _ => 'Reply',
                        },
                        onSubmit: switch (composer) {
                          _ when composer.canRecheck =>
                            () =>
                                controller.recheckComposer(composer: composer),
                          _ when composer.canSubmit =>
                            () => controller.submitComposer(composer: composer),
                          _ => null,
                        },
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
          final categoryId = composer.categoryId;
          final category =
              state.categories
                  .where((item) => item.id == categoryId)
                  .firstOrNull ??
              shell.categoryFor(categoryId, siteUrl: composer.target.siteUrl);
          bool canEdit() =>
              !composer.isDisposed &&
              composer.isEditing &&
              identical(shell.visibleComposer, composer);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!composer.target.isTagsEdit)
                    SizedBox(
                      key: const ValueKey('composer-category-action'),
                      child: TopicCategorySelector(
                        key: ObjectKey(composer),
                        valueKey: const ValueKey('composer-category'),
                        siteUrl: composer.target.siteUrl,
                        categories: state.categories,
                        selected: category,
                        placeholder: 'Choose a category',
                        labelFor: (category) => shell.topicCategoryPathLabel(
                          category,
                          siteUrl: composer.target.siteUrl,
                        ),
                        search: (term) async =>
                            (await shell.searchTopicCategoriesForEditor(
                                  siteUrl: composer.target.siteUrl,
                                  term: term,
                                ))
                                .where((category) => category.canCreateTopic)
                                .toList(),
                        onSelected: composer.isEditing
                            ? (category) {
                                if (canEdit() &&
                                    category != null &&
                                    category.id != composer.categoryId) {
                                  unawaited(
                                    shell.changeComposerCategory(
                                      composer,
                                      category.id,
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                  if (state.capabilities.canTagTopics ||
                      composer.tags.isNotEmpty)
                    SizedBox(
                      key: const ValueKey('composer-add-tag'),
                      child: TopicTagSelector(
                        key: ValueKey((composer, categoryId)),
                        valueKey: const ValueKey('composer-tags'),
                        selectedTags: composer.tags,
                        capabilities: state.capabilities,
                        placeholder: 'Add tags',
                        search: (term) =>
                            shell.searchComposerTags(composer, term),
                        onChanged: composer.isEditing
                            ? (tags) {
                                if (canEdit() &&
                                    composer.categoryId == categoryId) {
                                  composer.setTags(tags);
                                }
                              }
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
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
        (oldValue.isComposingRangeValid && !oldValue.composing.isCollapsed)) {
      return newValue;
    }

    final caret = selection.extentOffset;
    final insertedLength = newValue.text.length - oldValue.text.length;
    if (insertedLength > 0 &&
        startingAt(caret) != null &&
        newValue.text.startsWith(oldValue.text.substring(0, caret)) &&
        newValue.text.substring(caret + insertedLength) ==
            oldValue.text.substring(caret)) {
      final inserted = newValue.text.substring(caret, caret + insertedLength);
      final lastCharacter = String.fromCharCode(inserted.runes.last);
      if (!isEmojiShortcodeBoundary(lastCharacter)) {
        return _insertEmojiBoundary(newValue, caret + insertedLength);
      }
    }

    if (oldValue.text.length != newValue.text.length + 1) return newValue;

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

  static TextEditingValue _insertEmojiBoundary(
    TextEditingValue value,
    int offset,
  ) {
    int shifted(int original) => original > offset ? original + 1 : original;

    final selection = value.selection;
    final composing = value.composing;
    return value.copyWith(
      text: value.text.replaceRange(offset, offset, ' '),
      selection: selection.isValid
          ? TextSelection(
              baseOffset: shifted(selection.baseOffset),
              extentOffset: shifted(selection.extentOffset),
              affinity: selection.affinity,
              isDirectional: selection.isDirectional,
            )
          : selection,
      composing: composing.isValid
          ? TextRange(
              start: shifted(composing.start),
              end: shifted(composing.end),
            )
          : composing,
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
    this.showSelectionToolbar = true,
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

  /// Topic composers expose persistent Native formatting actions instead.
  final bool showSelectionToolbar;
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
  static const _galleryMenuButtonExtent = DSpacing.touchTarget;
  static const _galleryMenuContentWidth = _galleryMenuButtonExtent * 4;
  static const _galleryMenuHeight = _galleryMenuButtonExtent;

  final GlobalKey _stackKey = GlobalKey();
  ComposerQuoteBlock? _pointerDownQuote;
  ComposerSyntaxOccurrence? _pointerDownSyntax;
  ComposerSyntaxOccurrence? _pointerDownAfterBlockSyntax;
  ComposerImageGalleryBlock? _gallerySelectedAtPointerDown;
  Offset? _pointerDownPosition;
  int _pointerSequence = 0;
  bool _hoveringMention = false;
  bool _hoveringLink = false;
  late final ScrollController _scroll;
  late final ComposerMediaEditingCoordinator _media;
  late final _ComposerSelectionOverlay _selectionOverlay;
  final ValueNotifier<int> _mediaLayoutRevision = ValueNotifier(0);
  bool _mediaLayoutRefreshScheduled = false;
  (double, double)? _lastImageMenuPosition;
  (double, double)? _lastGalleryMenuPosition;
  late final TextInputFormatter _selectedPillInputFormatter;
  late final TextInputFormatter _renderedEmojiInputFormatter;
  final _blockquoteInputFormatter = ComposerBlockquoteInputFormatter();
  int? _blockquoteFieldGeneration;
  late final _ComposerPasteAction _pasteAction;
  late final _quoteLineStartAction =
      _ComposerQuoteLineStartAction<ExtendSelectionToLineBreakIntent>(
        () => _editableTextState,
      );
  late final _quoteExpandLineStartAction =
      _ComposerQuoteLineStartAction<ExpandSelectionToLineBreakIntent>(
        () => _editableTextState,
      );

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _blockquoteFieldGeneration = widget.composer.fieldGeneration;
    widget.composer.text.addListener(_observeBlockquoteValue);
    _media = ComposerMediaEditingCoordinator(widget.composer)
      ..addListener(_scheduleMediaLayoutRefresh);
    _selectionOverlay = _ComposerSelectionOverlay(
      composer: widget.composer,
      scroll: _scroll,
      menuWidth: _menuWidth,
      showToolbar: () => widget.showSelectionToolbar,
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
    oldWidget.composer.text.removeListener(_observeBlockquoteValue);
    _blockquoteInputFormatter.reset();
    _blockquoteFieldGeneration = widget.composer.fieldGeneration;
    widget.composer.text.addListener(_observeBlockquoteValue);
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
  void reassemble() {
    super.reassemble();
    // Hot reload preserves the controller and its projected TextSpan cache.
    // Layout code can change while that span still contains the old component
    // reservation lines, so rebuild it before painting the reassembled editor.
    widget.composer.text.artworkArrived();
  }

  @override
  void dispose() {
    widget.composer.text.removeListener(_observeBlockquoteValue);
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
    _blockquoteInputFormatter.reset();
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
      widget.composer.canUpload && widget.composer.text.selection.isValid;

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
        field: Focus(
          onKeyEvent: _onEditorKeyEvent,
          child: Actions(
            actions: {
              PasteTextIntent: _pasteAction,
              ExtendSelectionToLineBreakIntent: _quoteLineStartAction,
              ExpandSelectionToLineBreakIntent: _quoteExpandLineStartAction,
            },
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.composer.text,
              builder: (_, _, _) => ComposerBlockquoteDecoration(
                repaint: Listenable.merge([widget.composer.text, _scroll]),
                child: ClipRect(
                  child: TextField(
                    // Not decoration: a new key builds a new editable, and with it
                    // a new undo stack. It is the only way to stop undo reaching
                    // back into a reply that has already been sent.
                    key: ValueKey(widget.composer.fieldGeneration),
                    controller: widget.composer.text,
                    readOnly: !widget.composer.isEditing,
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
                      const ComposerImageGalleryInputFormatter(),
                      const ComposerQuoteInputFormatter(),
                      ...widget.composer.text.syntaxInputFormatters,
                      _blockquoteInputFormatter,
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
                    // TextField's forced default strut discards a WidgetSpan's
                    // intrinsic height. Let every projected component define
                    // its paragraph line so its visual and hit-test bounds agree.
                    strutStyle: StrutStyle.fromTextStyle(
                      widget.textStyle ?? DefaultTextStyle.of(context).style,
                      forceStrutHeight: false,
                    ),
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
    ),
  );

  void _observeBlockquoteValue() {
    if (_blockquoteFieldGeneration != widget.composer.fieldGeneration) {
      _blockquoteInputFormatter.reset();
      _blockquoteFieldGeneration = widget.composer.fieldGeneration;
    }
    _blockquoteInputFormatter.observeValue(widget.composer.text.value);
  }

  RenderEditable? get _renderEditable => _editableTextState?.renderEditable;

  EditableTextState? get _editableTextState {
    final root = _stackKey.currentContext;
    if (root == null) return null;
    final pending = <Element>[root as Element];
    while (pending.isNotEmpty) {
      final element = pending.removeLast();
      if (element is StatefulElement && element.state is EditableTextState) {
        return element.state as EditableTextState;
      }
      final children = <Element>[];
      element.visitChildElements(children.add);
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

  void _dropFiles(DropDoneDetails details) {
    _moveDropCaret(details.globalPosition);
    if (dropContainsDirectory(details.files)) {
      widget.composer.showNotice('Folders cannot be uploaded here.');
    }
    final files = composerUploadFilesFromDrop(details.files);
    _media.dropFiles(
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
    _blockquoteInputFormatter.reset();
    _gallerySelectedAtPointerDown = _media.value.selectedGallery;
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
    final gallery = _pointerDownQuote == null && image == null
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
    _gallerySelectedAtPointerDown = null;
    _pointerDownPosition = null;
  }

  void _activatePointerDownPill() {
    if (!widget.composer.isEditing) {
      _cancelEditorPointer();
      return;
    }
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
    final selectedGallery = _gallerySelectedAtPointerDown;
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
      final togglesSelectedGallery =
          selectedGallery != null &&
          selectedGallery.start == gallery.start &&
          selectedGallery.end == gallery.end;
      if (togglesSelectedGallery) {
        _media.dismissGallery(requestFocus: false);
        widget.composer.text.releaseGalleryPointerEdit(gallery);
        return;
      }
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

  BuildContext _syntaxUiContext(ComposerSyntaxOccurrence syntax) =>
      syntax.kind.owner.value == 'core'
      ? context
      : PluginUiScope.contextFor(context, syntax.kind.owner);

  Future<void> _editSyntax(ComposerSyntaxOccurrence syntax) async {
    if (!widget.composer.isEditing) return;
    final text = widget.composer.text;
    text.keepSyntaxCollapsedForPointerEdit(syntax);
    text.selection = TextSelection.collapsed(
      offset: text.syntaxCaretAfter(syntax),
    );
    try {
      await syntax.projection.edit(_syntaxUiContext(syntax), widget.composer);
    } finally {
      if (mounted &&
          widget.composer.isEditing &&
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
    if (!widget.composer.isEditing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is KeyDownEvent &&
        (!isEnter ||
            keyboard.isMetaPressed ||
            keyboard.isControlPressed ||
            keyboard.isAltPressed)) {
      _blockquoteInputFormatter.reset();
    }
    final hasCommandModifier =
        keyboard.isMetaPressed || keyboard.isControlPressed;
    final isUndoOrRedo =
        event is KeyDownEvent &&
        ((hasCommandModifier && event.logicalKey == LogicalKeyboardKey.keyZ) ||
            (keyboard.isControlPressed &&
                event.logicalKey == LogicalKeyboardKey.keyY));
    if (isUndoOrRedo &&
        (_keyboardSelectedPill != null || _media.hasSelectedMediaProjection)) {
      // UndoHistory must be able to install its exact recorded value. A
      // selected projection makes _SelectedPillInputFormatter return the
      // current value instead, which violates that contract. Leave projection
      // mode before the shortcut reaches EditableText.
      _clearKeyboardPillSelection();
    }
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
      final movesBefore =
          isArrowPress &&
          !hasModifier &&
          (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowUp);
      final movesAfter =
          isArrowPress &&
          !hasModifier &&
          (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowDown);
      if (movesBefore || movesAfter) {
        _clearKeyboardPillSelection();
        if (movesBefore) {
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
    if (isEnter &&
        !widget.composer.discarding &&
        (keyboard.isShiftPressed || !widget.composer.autocomplete.isOpen) &&
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        value.composing.isCollapsed &&
        _blockquoteInputFormatter.isInQuote(value)) {
      final editable = _editableTextState;
      if (editable == null) return KeyEventResult.ignored;
      editable.userUpdateTextEditingValue(
        TextEditingValue(
          text: value.text.replaceRange(selection.start, selection.end, '\n'),
          selection: TextSelection.collapsed(offset: selection.start + 1),
        ),
        SelectionChangedCause.keyboard,
      );
      return KeyEventResult.handled;
    }
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
      final quoteOffset = composerBlockquoteArrowOffset(
        value,
        forward: !moveLeft,
      );
      if (quoteOffset != null) {
        final editable = _editableTextState;
        if (editable == null) return KeyEventResult.ignored;
        final nextSelection = TextSelection.collapsed(offset: quoteOffset);
        editable.bringIntoView(nextSelection.extent);
        editable.userUpdateTextEditingValue(
          value.copyWith(selection: nextSelection),
          SelectionChangedCause.keyboard,
        );
        return KeyEventResult.handled;
      }
      final emoji = moveLeft
          ? widget.composer.text.renderedEmojiEndingAt(caret)
          : widget.composer.text.renderedEmojiStartingAt(caret);
      if (emoji != null) {
        widget.composer.text.selection = TextSelection.collapsed(
          offset: moveLeft ? emoji.start : emoji.end,
        );
        return KeyEventResult.handled;
      }
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
        Future.sync(
          () => syntax.projection.remove(
            _syntaxUiContext(syntax),
            widget.composer,
          ),
        ),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  ComposerSyntaxOccurrence? get _keyboardSelectedPill =>
      widget.composer.text.keyboardSelectedSyntax;

  void _clearKeyboardPillSelection() {
    _media.clearKeyboardImageSelection();
    _media.dismissGallery(requestFocus: false);
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
    if (!widget.composer.isEditing) return;
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
    if (!widget.composer.isEditing) return;
    switch (pill) {
      case ComposerImageBlock image:
        _media.clearKeyboardImageSelection();
        widget.composer.removeImage(image);
        return;
      case ComposerSyntaxOccurrence syntax:
        unawaited(
          Future.sync(
            () => syntax.projection.remove(
              _syntaxUiContext(syntax),
              widget.composer,
            ),
          ),
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
    final width = math.min(_galleryMenuContentWidth, constraints.maxWidth);
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
    if (!widget.composer.isEditing) return const SizedBox.shrink();
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
      _galleryMenuContentWidth,
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
                canUpload: widget.composer.canUpload,
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
                            ? 'Drop files to upload'
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

  double _minimumLineHeight(BuildContext context) {
    final style = widget.textStyle ?? Theme.of(context).textTheme.bodyLarge!;
    // Empty paragraphs can include more strut leading than filled ones.
    // Reserve the empty line so a one-line draft does not move the toolbar.
    final painter = TextPainter(
      text: TextSpan(style: style),
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
      textDirection: DDirection.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
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
        onDragDone: _dropFiles,
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
            if (widget.expands)
              Positioned.fill(child: _field())
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: _minimumLineHeight(context),
                ),
                child: _field(),
              ),
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
    required this.showToolbar,
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
  final bool Function() showToolbar;
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
    _composer.addListener(sync);
    _composer.text.addListener(sync);
    _composer.focus.addListener(sync);
    scroll.addListener(sync);
  }

  void _detach() {
    _composer.removeListener(sync);
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
    if (!showToolbar() || !_canFormatSelection(selection)) {
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
      _composer.isEditing &&
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

class _ComposerQuoteLineStartAction<T extends DirectionalCaretMovementIntent>
    extends Action<T> {
  _ComposerQuoteLineStartAction(this._editable);

  final EditableTextState? Function() _editable;

  @override
  Object? invoke(T intent) {
    if (intent.forward) return callingAction?.invoke(intent);
    final editable = _editable();
    final before = editable?.widget.controller.value;
    // Let the native action choose the visual line and selection direction.
    final result = callingAction?.invoke(intent);
    if (editable == null || before == null) return result;
    final after = editable.widget.controller.value;
    final selection = composerBlockquoteLineStartSelection(before, after);
    if (selection != after.selection) {
      editable.bringIntoView(selection.extent);
      editable.userUpdateTextEditingValue(
        after.copyWith(selection: selection),
        SelectionChangedCause.keyboard,
      );
    }
    return result;
  }

  @override
  bool isEnabled(T intent) => callingAction?.isEnabled(intent) ?? false;

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;
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
                  DTooltip(
                    message: label,
                    labelTrigger: true,
                    child: IconButton(
                      onPressed: composer.isEditing
                          ? () {
                              if (!composer.isEditing) return;
                              composer.toggleMark(mark);
                              composer.focus.requestFocus();
                            }
                          : null,
                      icon: DIcon(icon, size: 18),
                      tooltip: '',
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
                      DTooltip(
                        message: 'Decrease image size',
                        labelTrigger: true,
                        child: IconButton(
                          onPressed: scaleIndex > 0
                              ? () => onScale(scales[scaleIndex - 1])
                              : null,
                          icon: const Icon(Icons.zoom_out, size: 18),
                          tooltip: '',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                        ),
                      ),
                      Text('$scale%', style: theme.textTheme.labelMedium),
                      DTooltip(
                        message: 'Increase image size',
                        labelTrigger: true,
                        child: IconButton(
                          onPressed: scaleIndex < scales.length - 1
                              ? () => onScale(scales[scaleIndex + 1])
                              : null,
                          icon: const Icon(Icons.zoom_in, size: 18),
                          tooltip: '',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                        ),
                      ),
                    ] else
                      DTooltip(
                        message: 'Move image outside gallery',
                        labelTrigger: true,
                        child: IconButton(
                          onPressed: onMoveOutsideGallery,
                          icon: const Icon(Icons.grid_off_outlined, size: 18),
                          tooltip: '',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                        ),
                      ),
                    const Spacer(),
                    DTooltip(
                      message: 'Delete image',
                      labelTrigger: true,
                      child: IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: '',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 44,
                  child: TextField(
                    style: Theme.of(context).textTheme.bodyMedium,
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
                      suffixIcon: DTooltip(
                        message: 'Save alt text',
                        labelTrigger: true,
                        child: IconButton(
                          onPressed: onSaveAlt,
                          tooltip: '',
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
    required this.canUpload,
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
  final bool canUpload;
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
                width: _ComposerEditorState._galleryMenuContentWidth,
                height: _ComposerEditorState._galleryMenuHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DToggleGroup<ComposerGalleryMode>(
                      values: [gallery.mode],
                      onChanged: (values) {
                        if (values case [final mode]) onMode(mode);
                      },
                      allowEmptySelection: false,
                      spacing: 0,
                      variant: DToggleVariant.standard,
                      semanticLabel: 'Gallery mode',
                      scrollable: false,
                      items: const [
                        DToggleGroupItem.iconOnly(
                          value: ComposerGalleryMode.grid,
                          semanticLabel: 'Grid gallery mode',
                          tooltip: 'Grid gallery mode',
                          icon: Icon(Icons.grid_view_outlined, size: 18),
                          selectedIcon: Icon(Icons.grid_view, size: 18),
                          visualStyle: DToggleVisualStyle(
                            constraints: BoxConstraints.tightFor(
                              width:
                                  _ComposerEditorState._galleryMenuButtonExtent,
                              height:
                                  _ComposerEditorState._galleryMenuButtonExtent,
                            ),
                          ),
                        ),
                        DToggleGroupItem.iconOnly(
                          value: ComposerGalleryMode.carousel,
                          semanticLabel: 'Carousel gallery mode',
                          tooltip: 'Carousel gallery mode',
                          icon: Icon(Icons.view_carousel_outlined, size: 18),
                          selectedIcon: Icon(Icons.view_carousel, size: 18),
                          visualStyle: DToggleVisualStyle(
                            constraints: BoxConstraints.tightFor(
                              width:
                                  _ComposerEditorState._galleryMenuButtonExtent,
                              height:
                                  _ComposerEditorState._galleryMenuButtonExtent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    DTooltip(
                      message: 'Add images to gallery',
                      labelTrigger: true,
                      child: PopupMenuButton<_GalleryAddChoice>(
                        enabled: !pickingImages,
                        tooltip: '',
                        padding: EdgeInsets.zero,
                        style: const ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.standard,
                          fixedSize: WidgetStatePropertyAll(
                            Size.square(
                              _ComposerEditorState._galleryMenuButtonExtent,
                            ),
                          ),
                        ),
                        icon: pickingImages
                            ? const SizedBox.square(
                                dimension: 18,
                                child: DSpinner(),
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
                          PopupMenuItem(
                            value: _GalleryAddChoice.upload,
                            enabled: canUpload,
                            child: const ListTile(
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
                    ),
                    DTooltip(
                      message: 'Remove gallery, keep images',
                      labelTrigger: true,
                      child: IconButton(
                        onPressed: onUnwrap,
                        icon: const Icon(Icons.grid_off_outlined, size: 18),
                        tooltip: '',
                        constraints: const BoxConstraints.tightFor(
                          width: _ComposerEditorState._galleryMenuButtonExtent,
                          height: _ComposerEditorState._galleryMenuButtonExtent,
                        ),
                        style: const ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.standard,
                        ),
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
            return DCheckbox(
              key: ValueKey('gallery-existing-image-${image.start}'),
              value: selected,

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

/// Exposes existing editor commands; source, selection and undo stay with the
/// live editor. These are actions, not a second formatting-state model.
class _FormattingToolbar extends StatelessWidget {
  const _FormattingToolbar({required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextFieldTapRegion(
        child: DButtonGroup(
          key: const ValueKey('composer-formatting'),
          semanticLabel: 'Formatting',
          children: [
            for (final (label, icon, mark, key) in [
              ('Bold', DIcons.bold, ComposerMark.bold, LogicalKeyboardKey.keyB),
              (
                'Italic',
                DIcons.italic,
                ComposerMark.italic,
                LogicalKeyboardKey.keyI,
              ),
              (
                'Inline code',
                DIcons.code,
                ComposerMark.inlineCode,
                LogicalKeyboardKey.keyE,
              ),
            ])
              DButton.iconOnly(
                key: ValueKey('composer-format-${mark.name}'),
                tooltip: label,
                shortcut: DShortcut(_formattingShortcut(key)),
                variant: DButtonVariant.ghost,
                size: DButtonSize.small,
                icon: DIcon(icon, size: 16),
                onPressed: composer.isEditing && !composer.loadingBody
                    ? () {
                        composer.toggleMark(mark);
                        composer.focus.requestFocus();
                      }
                    : null,
              ),
            DButton.iconOnly(
              key: const ValueKey('composer-format-link'),
              tooltip: 'Link',
              shortcut: DShortcut(_formattingShortcut(LogicalKeyboardKey.keyL)),
              variant: DButtonVariant.ghost,
              size: DButtonSize.small,
              icon: const DIcon(DIcons.link, size: 16),
              onPressed: composer.isEditing && !composer.loadingBody
                  ? () => unawaited(
                      showComposerLinkDialog(
                        context: context,
                        composer: composer,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.composer, required this.pickImages});

  final ComposerController composer;
  final ComposerImagePicker pickImages;

  @override
  Widget build(BuildContext context) => ShellSelector<int>(
    // Plugin creation capabilities arrive independently of composer text.
    select: (controller) => Object.hash(
      controller.siteConfigFor(composer.target.siteUrl),
      controller.freshCurrentUserFor(composer.target.siteUrl),
    ),
    builder: (context, _, _) => _buildToolbar(context),
  );

  Widget _buildToolbar(BuildContext context) {
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final actions = registry.composerToolbar(context, composer);
    final emojiEnabled =
        !composer.target.isTaxonomyEdit &&
        ShellScope.read(
          context,
        ).siteConfigFor(composer.target.siteUrl).emojiEnabled;
    final uploadsEnabled = composer.imageUploader != null;
    return _ComposerToolbarOverflow(
      children: [
        if (uploadsEnabled)
          _ComposerUploadButton(composer: composer, pickImages: pickImages),
        if (emojiEnabled)
          EmojiPickerAnchor(
            child: Builder(
              builder: (buttonContext) => DButton.iconOnly(
                key: const ValueKey('composer-emoji-picker'),
                tooltip: 'Add emoji',
                variant: DButtonVariant.transparent,
                size: DButtonSize.small,
                onPressed: !composer.isEditing
                    ? null
                    : () => unawaited(
                        openEmojiPickerForTopicComposer(
                          context: buttonContext,
                          composer: composer,
                        ),
                      ),
                icon: const DIcon(DIcons.discourseEmojis, size: 18),
              ),
            ),
          ),
        if (actions.isNotEmpty)
          DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'Insert',
              side: DPopoverSide.top,
              width: 240,
              children: [
                for (final action in actions)
                  DDropdownMenuItem(
                    onPressed: composer.isEditing ? action.onInvoke : null,
                    leading: DIcon(action.icon, size: 16),
                    trailing: switch (action.shortcut) {
                      final SingleActivator shortcut => DShortcutKeycaps(
                        shortcut: DShortcut(shortcut),
                      ),
                      _ => null,
                    },
                    child: Text(action.label),
                  ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => DButton.iconOnly(
                key: const ValueKey('composer-insert'),
                tooltip: 'Insert',
                hasPopup: true,
                expanded: trigger.open,
                focusNode: trigger.focusNode,
                variant: DButtonVariant.transparent,
                size: DButtonSize.small,
                onPressed: composer.isEditing ? trigger.toggle : null,
                icon: const DIcon(DIcons.circlePlus, size: 18),
              ),
            ),
          ),
      ],
    );
  }
}

class _ComposerToolbarOverflow extends StatefulWidget {
  const _ComposerToolbarOverflow({required this.children});

  final List<Widget> children;

  @override
  State<_ComposerToolbarOverflow> createState() =>
      _ComposerToolbarOverflowState();
}

class _ComposerToolbarOverflowState extends State<_ComposerToolbarOverflow> {
  final ScrollController _controller = ScrollController();
  bool _canScrollBackward = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateOverflow);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateOverflow)
      ..dispose();
    super.dispose();
  }

  void _scheduleOverflowUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverflow());
  }

  void _updateOverflow() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    final canScrollBackward = position.pixels > position.minScrollExtent + 2;
    final canScrollForward = position.pixels < position.maxScrollExtent - 2;
    if (_canScrollBackward == canScrollBackward &&
        _canScrollForward == canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBackward = canScrollBackward;
      _canScrollForward = canScrollForward;
    });
  }

  Future<void> _scrollByViewport(double direction) async {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + direction * position.viewportDimension)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverflowUpdate();
    final textDirection = DDirection.of(context);

    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        SingleChildScrollView(
          key: const ValueKey('composer-toolbar-scroll'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
        ),
        if (_canScrollBackward)
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: _ComposerToolbarScrollButton(
              key: const ValueKey('composer-toolbar-scroll-backward'),
              forward: false,
              textDirection: textDirection,
              onPressed: () => unawaited(_scrollByViewport(-1)),
            ),
          ),
        if (_canScrollForward)
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            child: _ComposerToolbarScrollButton(
              key: const ValueKey('composer-toolbar-scroll-forward'),
              forward: true,
              textDirection: textDirection,
              onPressed: () => unawaited(_scrollByViewport(1)),
            ),
          ),
      ],
    );
  }
}

class _ComposerToolbarScrollButton extends StatelessWidget {
  const _ComposerToolbarScrollButton({
    super.key,
    required this.forward,
    required this.textDirection,
    required this.onPressed,
  });

  final bool forward;
  final TextDirection textDirection;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pointsRight = forward == (textDirection == TextDirection.ltr);
    final fadeColor = theme.shell.content;

    return Container(
      width: 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: pointsRight ? Alignment.centerLeft : Alignment.centerRight,
          end: pointsRight ? Alignment.centerRight : Alignment.centerLeft,
          colors: [fadeColor.withValues(alpha: 0), fadeColor, fadeColor],
          stops: const [0, 0.55, 1],
        ),
      ),
      alignment: pointsRight ? Alignment.centerRight : Alignment.centerLeft,
      child: DButton.iconOnly(
        tooltip: forward
            ? 'Show more composer tools'
            : 'Show previous composer tools',
        onPressed: onPressed,
        icon: DIcon(
          pointsRight ? DIcons.chevronRight : DIcons.chevronLeft,
          size: 13,
        ),
        variant: DButtonVariant.transparent,
        size: DButtonSize.small,
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
    if (!composer.canUpload || _picking) return;
    final selection = composer.text.selection;
    final offset = selection.isValid
        ? selection.extentOffset
        : composer.text.text.length;
    setState(() => _picking = true);
    try {
      final files = await widget.pickImages();
      if (!mounted ||
          !identical(widget.composer, composer) ||
          !composer.canUpload) {
        return;
      }
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
      if (mounted &&
          identical(widget.composer, composer) &&
          composer.canUpload) {
        composer.showNotice("Couldn't open the image picker.");
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
        if (identical(widget.composer, composer) && composer.canUpload) {
          composer.focus.requestFocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    key: const ValueKey('composer-upload'),
    tooltip: 'Upload images',
    onPressed: !widget.composer.canUpload || _picking
        ? null
        : () => unawaited(_pick()),
    icon: const DIcon(DIcons.paperclip, size: 18),
    variant: DButtonVariant.transparent,
    size: DButtonSize.small,
  );
}

class ComposerUploadQueue extends StatelessWidget {
  const ComposerUploadQueue({super.key, required this.composer});

  final ComposerController composer;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 132),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: composer.uploads.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final upload = composer.uploads[index];
          final failed = upload.status == ComposerUploadStatus.failed;
          final completed = upload.status == ComposerUploadStatus.completed;
          final thumbnail = completed ? upload.result : null;
          final isImage = SiteConfig.isImageFilename(upload.file.name);
          final retrying = upload.status == ComposerUploadStatus.retrying;
          final description = failed
              ? upload.error ?? "Couldn't upload this image."
              : completed
              ? 'Uploaded'
              : '${retrying ? 'Retrying' : 'Uploading'} · ${(upload.progress * 100).round()}%';
          return DAttachment(
            width: double.infinity,
            state: failed
                ? DAttachmentState.error
                : completed
                ? DAttachmentState.done
                : retrying
                ? DAttachmentState.processing
                : DAttachmentState.uploading,
            liveRegion: !completed,
            children: [
              DAttachmentMedia(
                variant:
                    thumbnail != null &&
                        (isImage || thumbnail.thumbnailUrl != null)
                    ? DAttachmentMediaVariant.image
                    : DAttachmentMediaVariant.icon,
                child:
                    thumbnail != null &&
                        (isImage || thumbnail.thumbnailUrl != null)
                    ? _ComposerUploadThumbnail(
                        siteUrl: composer.target.siteUrl,
                        filename: upload.file.name,
                        uploadId: thumbnail.id,
                        url: thumbnail.previewUrl,
                      )
                    : failed
                    ? const Icon(Icons.error_outline)
                    : completed
                    ? Icon(isImage ? Icons.image_outlined : Icons.attach_file)
                    : const DSpinner(size: 16, semanticLabel: null),
              ),
              DAttachmentContent(
                children: [
                  DAttachmentTitle(child: Text(upload.file.name)),
                  DAttachmentDescription(
                    child: failed
                        ? DTooltip(
                            message: description,
                            child: Text(description),
                          )
                        : Text(description),
                  ),
                ],
              ),
              DAttachmentActions(
                children: [
                  if (failed)
                    DAttachmentAction(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Retry upload',
                      onPressed: composer.canUpload
                          ? () => composer.retryUpload(upload.id)
                          : null,
                    ),
                  DAttachmentAction(
                    icon: const Icon(Icons.close),
                    tooltip: completed || failed
                        ? 'Remove upload'
                        : 'Cancel upload',
                    onPressed: completed || failed
                        ? () => composer.removeUpload(upload.id)
                        : () => composer.cancelUpload(upload.id),
                  ),
                ],
              ),
            ],
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
  });

  final ComposerController composer;
  final ComposerImagePicker pickImages;
  final String? message;
  final bool isError;
  final bool busy;
  final String label;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => ShellSelector<int>(
    select: (controller) => Object.hash(
      controller.siteConfigFor(composer.target.siteUrl),
      controller.freshCurrentUserFor(composer.target.siteUrl),
    ),
    builder: (context, _, _) => _buildFooter(context),
  );

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final pluginControls = registry.composerFooter(context, composer);

    final draftMessage = !composer.canSaveDraft || composer.target.isEdit
        ? null
        : composer.draftPending || composer.draftStatus == DraftStatus.saving
        ? 'Saving draft…'
        : composer.draftStatus == DraftStatus.saved
        ? 'Draft saved'
        : null;
    final statusMessage = message ?? draftMessage;
    final status = statusMessage == null
        ? const SizedBox.shrink()
        : Text(
            statusMessage,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          );
    final toolbar = composer.target.isTaxonomyEdit
        ? null
        : _Toolbar(composer: composer, pickImages: pickImages);
    final controls = LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth <
            (300 + pluginControls.length * 120) *
                MediaQuery.textScalerOf(context).scale(14) /
                14;
        // Native image pickers outlive a resize, so the toolbar keeps its state.
        return ComposerFooterLayout(
          compact: compact,
          child: Row(
            children: [
              if (toolbar != null) Expanded(child: toolbar) else const Spacer(),
              for (final control in pluginControls)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: control,
                ),
              Theme(
                data: composer.whisper
                    ? theme.copyWith(
                        extensions: [
                          ...theme.extensions.values.where(
                            (extension) => extension is! DTokens,
                          ),
                          DTokens.of(context).copyWith(
                            colors: theme.colorScheme.copyWith(
                              primary: theme.colorScheme.tertiary,
                              onPrimary: theme.colorScheme.onTertiary,
                            ),
                          ),
                        ],
                      )
                    : theme,
                child: compact
                    ? DButton.iconOnly(
                        key: const ValueKey('composer-submit'),
                        tooltip: label,
                        semanticLabel: label,
                        onPressed: busy ? null : onSubmit,
                        loading: busy,
                        icon: DIcon(
                          composer.whisper
                              ? DIcons.farEyeSlash
                              : composer.target.isEdit
                              ? DIcons.check
                              : composer.target.isNewTopic
                              ? DIcons.farPenToSquare
                              : DIcons.reply,
                          size: 18,
                        ),
                      )
                    : DButton(
                        key: const ValueKey('composer-submit'),
                        onPressed: busy ? null : onSubmit,
                        loading: busy,
                        semanticLabel: label,
                        label: Text(label),
                      ),
              ),
            ],
          ),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (statusMessage != null) ...[
            Align(alignment: Alignment.centerRight, child: status),
            const SizedBox(height: 4),
          ],
          controls,
        ],
      ),
    );
  }
}
