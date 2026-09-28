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
import '../diagnostics/surface_opening_trace.dart';
import '../models/composer_placement.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../plugin_api/composer_footer_layout.dart';
import '../plugin_api/composer_syntax.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'composer_autocomplete.dart';
import 'composer_block_surface.dart';
import 'composer_blockquote.dart';
import 'composer_blocks.dart';
import 'composer_clipboard.dart';
import 'composer_controller.dart';
import 'composer_details.dart';
import 'composer_discard.dart';
import 'composer_drop.dart';
import 'composer_drop_geometry.dart';
import 'composer_galleries.dart';
import 'composer_header.dart';
import 'composer_history_scope.dart';
import 'composer_images.dart';
import 'composer_link.dart';
import 'composer_list_editor.dart';
import 'composer_lists.dart';
import 'composer_marks.dart';
import 'composer_media_editing_coordinator.dart';
import 'composer_quotes.dart';
import 'composer_recipients.dart';
import 'composer_reply_context.dart';
import 'composer_selection_menu.dart';
import 'composer_slash_menu.dart';
import 'composer_suggestions.dart';
import 'composer_table.dart';
import 'composer_tag_removal_notice.dart';
import 'composer_todos.dart';
import 'composer_upload_attachment.dart';
import 'composer_upload_picker.dart';
import 'emoji_composer.dart';
import 'emoji_picker.dart';
import 'forum_theme_surfaces.dart';
import 'markdown_editing_controller.dart';
import 'markdown_highlight.dart';
import 'platform.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'topic_title.dart';

bool get _usesCommandModifier =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

SingleActivator _formattingShortcut(LogicalKeyboardKey key) => SingleActivator(
  key,
  meta: _usesCommandModifier,
  control: !_usesCommandModifier,
);

ComposerImagePicker _sitePhotoLibrary(
  BuildContext context,
  ComposerController composer,
) {
  final optimization =
      ShellScope.maybeRead(
        context,
      )?.siteConfigFor(composer.target.siteUrl).composerImageOptimization ??
      const ComposerImageOptimization();
  final limit = composer.simultaneousUploads;
  return () => pickComposerImages(optimization: optimization, limit: limit);
}

Color _composerToolForeground(BuildContext context) {
  final tokens = DTokens.of(context);
  return Color.lerp(tokens.background, tokens.foreground, .5)!;
}

DControlSize _composerToolbarSize(BuildContext context) =>
    context.isTouch ? DControlSize.large : DControlSize.toolbar;

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
    this.onExitFullScreen,
    this.pickFiles = pickComposerFiles,
    this.pickImages,
    this.readClipboardFiles = readComposerClipboardFiles,
  });

  final ComposerController composer;
  final double? height;
  final bool minimized;
  final VoidCallback? onMinimize;
  final VoidCallback? onRestore;
  final ComposerPlacement placement;
  final ValueChanged<ComposerPlacement>? onPlacementChanged;
  final VoidCallback? onExitFullScreen;
  final ComposerFilePicker pickFiles;

  /// Null offers the photo library under the site's optimisation policy.
  final ComposerImagePicker? pickImages;
  final ComposerClipboardFileReader readClipboardFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final mobile = context.isTouch;
    void openLink() => unawaited(
      showComposerLinkDialog(context: context, composer: composer.activeEditor),
    );
    composer.text.configureQuoteContentsResolver(
      (block) => controller.quoteContentsFor(composer.target, block),
      context: (controller, composer.target),
    );

    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        SurfaceOpeningTrace.mark('composer.build');
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

        final busy =
            composer.discarding ||
            composer.submitting ||
            composer.state == ComposerState.checking ||
            composer.loadingBody;
        final submitLabel = switch (composer) {
          _ when composer.canRecheck => 'Check again',
          _ when target.isEdit => 'Save',
          _ when target.isPrivateMessage => 'Send message',
          _ when target.isNewTopic => 'Create topic',
          _ when composer.whisper => 'Whisper',
          _ => 'Reply',
        };
        final VoidCallback? onSubmit = switch (composer) {
          _ when composer.canRecheck => () => controller.recheckComposer(
            composer: composer,
          ),
          _ when composer.canSubmit => () => controller.submitComposer(
            composer: composer,
          ),
          _ => null,
        };
        void discard() => unawaited(
          requestComposerDiscard(
            context: context,
            composer: composer,
            controller: controller,
          ),
        );

        final header = ComposerHeader(
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
          onExitFullScreen: onExitFullScreen,
          mobileSubmit: mobile && !minimized
              ? DButton.iconOnly(
                  key: const ValueKey('composer-submit'),
                  size: DButtonSize.toolbar,
                  icon: const DIcon(DIcons.plus),
                  variant: DButtonVariant.primary,
                  tooltip: submitLabel,
                  semanticLabel: submitLabel,
                  loading: busy,
                  onPressed: busy ? null : onSubmit,
                )
              : null,
          onDiscard: discard,
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
          decoration: BoxDecoration(
            color: ForumWindowBackground.surfaceColor(
              context,
              theme.shell.content,
            ),
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                  controller.submitComposer(composer: composer),
              const SingleActivator(
                LogicalKeyboardKey.enter,
                control: true,
              ): () =>
                  controller.submitComposer(composer: composer),
              const SingleActivator(
                LogicalKeyboardKey.escape,
              ): placement == ComposerPlacement.fullScreen
                  ? onExitFullScreen ?? close
                  : close,
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true): close,
              const SingleActivator(LogicalKeyboardKey.keyW, control: true):
                  close,
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                  composer.activeEditor.toggleMark(ComposerMark.bold),
              const SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
              ): () =>
                  composer.activeEditor.toggleMark(ComposerMark.bold),
              const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
                  composer.activeEditor.toggleMark(ComposerMark.italic),
              const SingleActivator(
                LogicalKeyboardKey.keyI,
                control: true,
              ): () =>
                  composer.activeEditor.toggleMark(ComposerMark.italic),
              const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
                  composer.activeEditor.toggleSelectedInlineCode,
              if (!_usesCommandModifier)
                const SingleActivator(LogicalKeyboardKey.keyE, control: true):
                    composer.activeEditor.toggleSelectedInlineCode,
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
                    if (!mobile || minimized) header,
                    if (!minimized)
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final fields = <Widget>[
                              if (target.mode == ComposerMode.reply &&
                                  constraints.maxHeight >= 80)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: math.min(
                                      140,
                                      math.max(48, constraints.maxHeight * 0.6),
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
                                ComposerRecipients(composer: composer),
                              if ((!mobile &&
                                      (target.isNewTopic ||
                                          target.editsTopicMetadata)) ||
                                  target.isTaxonomyEdit)
                                _TopicTaxonomy(composer: composer),
                              if (target.createsTopic ||
                                  target.editsTopicMetadata) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    10,
                                  ),
                                  child: DInput(
                                    key: const ValueKey('composer-topic-title'),
                                    controller: composer.title,
                                    borderless: true,
                                    size: DControlSize.large,
                                    readOnly: !composer.isEditing,
                                    semanticLabel: 'Title',
                                    style: theme.textTheme.titleMedium,
                                    hintText: 'Give your topic a title',
                                    textInputAction: TextInputAction.next,
                                  ),
                                ),
                                if (!mobile)
                                  const DSeparator(
                                    indent: 16,
                                    endIndent: 16,
                                    space: 1,
                                  ),
                                const SizedBox(height: 12),
                              ],
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
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ];
                            final content = Column(
                              children: [
                                if (mobile)
                                  ...fields
                                else if (fields.isNotEmpty)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight:
                                          constraints.maxHeight *
                                          (target.isTaxonomyEdit ? 1 : .6),
                                    ),
                                    child: DScrollArea(
                                      thumbVisibility: false,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: fields,
                                      ),
                                    ),
                                  ),
                                if (!target.isTaxonomyEdit) ...[
                                  _ComposerBodyLayout(
                                    scrollsWithTitle: mobile,
                                    child: Stack(
                                      fit: mobile
                                          ? StackFit.loose
                                          : StackFit.expand,
                                      children: [
                                        Padding(
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                mobile ? 16 : 4,
                                                2,
                                                mobile
                                                    ? 16
                                                    : 16 -
                                                          DScrollThumb
                                                              .containerInset,
                                                8,
                                              ),
                                          child: ComposerEditor(
                                            composer: composer,
                                            expands: !mobile,
                                            pickImages: pickImages,
                                            readClipboardFiles:
                                                readClipboardFiles,
                                            pickFiles: pickFiles,
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
                                              _ when target.isPrivateMessage =>
                                                'Write your message…',
                                              _ when target.isNewTopic =>
                                                'Write your topic…',
                                              _ when target.isEdit =>
                                                'Edit this post…',
                                              _
                                                  when target.replyToUsername !=
                                                      null =>
                                                'Reply to @${target.replyToUsername}…',
                                              _ => 'Write a reply…',
                                            },
                                            textStyle:
                                                theme.textTheme.bodyLarge,
                                            hintStyle: theme.textTheme.bodyLarge
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
                                              alignment: Alignment.bottomCenter,
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
                                ] else if (!mobile)
                                  const Spacer(),
                              ],
                            );
                            if (mobile) {
                              return _MobileComposerViewport(
                                header: header,
                                composer: composer,
                                child: content,
                              );
                            }
                            // The editor owns its viewport. A larger minimum
                            // height inside another scroller can hide its last
                            // line even at the editor's maximum scroll offset.
                            return content;
                          },
                        ),
                      ),
                    if (!minimized)
                      _ComposerBottom(
                        composer: composer,
                        mobile: mobile,
                        showTaxonomy:
                            mobile &&
                            !target.isTaxonomyEdit &&
                            (target.isNewTopic || target.editsTopicMetadata),
                        child: _Footer(
                          composer: composer,
                          onCancel: discard,
                          sideDocked: placement.isSide,
                          pickFiles: pickFiles,
                          pickImages: pickImages,
                          message:
                              error?.message ??
                              notice ??
                              composer.taxonomyValidationMessage ??
                              (composer.localDraftFailed
                                  ? "Couldn't save this draft on this device."
                                  : composer.draftStatus ==
                                            DraftStatus.failing ||
                                        composer.draftsGaveUp
                                  ? 'Not saved on the site — kept on this device only.'
                                  : null),
                          isError:
                              error != null ||
                              composer.localDraftFailed ||
                              composer.taxonomyValidationMessage != null,
                          announce: error != null || notice != null,
                          busy: busy,
                          label: submitLabel,
                          onSubmit: onSubmit,
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

/// The mobile title and growing editor share one viewport. The pinned sliver
/// paints its transparent header above content as the title scrolls behind it.
class _MobileComposerViewport extends StatefulWidget {
  const _MobileComposerViewport({
    required this.header,
    required this.composer,
    required this.child,
  });

  final Widget header;
  final ComposerController composer;
  final Widget child;

  @override
  State<_MobileComposerViewport> createState() =>
      _MobileComposerViewportState();
}

class _MobileComposerViewportState extends State<_MobileComposerViewport> {
  final _scroll = ScrollController();
  bool _hasContentBelow = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateOverflow);
  }

  void _updateOverflow() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final hasContentBelow = position.extentAfter > 2;
    if (_hasContentBelow != hasContentBelow) {
      setState(() => _hasContentBelow = hasContentBelow);
    }
  }

  void _scheduleOverflowUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverflow());
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    unawaited(
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_updateOverflow)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverflowUpdate();
    final headerExtent =
        DControlStyle.scaledHeight(
          DControlSize.regular,
          MediaQuery.textScalerOf(context),
          context: context,
        ) +
        16;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _scheduleOverflowUpdate();
        return false;
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => DScrollBar(
              controller: _scroll,
              showScrollbar: false,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: CustomScrollView(
                  key: const ValueKey('composer-mobile-scroll'),
                  controller: _scroll,
                  // Paint beneath the floating footer while keeping the viewport's
                  // reveal bounds above it, so the caret stays clear of the tools.
                  // The full sheet clips at the screen edge, allowing content
                  // to continue beneath a translucent system keyboard.
                  clipBehavior: Clip.none,
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _ComposerPinnedHeader(
                        extent: headerExtent,
                        child: widget.header,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: widget.composer.focus.requestFocus,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(
                              0,
                              constraints.maxHeight - headerExtent,
                            ),
                          ),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: ExcludeSemantics(
                excluding: !_hasContentBelow,
                child: ExcludeFocus(
                  excluding: !_hasContentBelow,
                  child: IgnorePointer(
                    ignoring: !_hasContentBelow,
                    child: AnimatedScale(
                      key: const ValueKey('composer-scroll-down-scale'),
                      scale: _hasContentBelow ? 1 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: DButton.iconOnly(
                        key: const ValueKey('composer-scroll-down'),
                        size: DControlSize.toolbar,
                        shape: DButtonShape.pill,
                        icon: const DIcon(DIcons.chevronDown),
                        tooltip: 'Scroll to bottom',
                        semanticLabel: 'Scroll to bottom',
                        variant: DButtonVariant.secondary,
                        onPressed: _scrollToBottom,
                      ),
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
}

class _ComposerPinnedHeader extends SliverPersistentHeaderDelegate {
  _ComposerPinnedHeader({required this.extent, required this.child});

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: DGradientBlur(key: ValueKey('composer-header-blur')),
        ),
        child,
      ],
    );
  }

  @override
  bool shouldRebuild(_ComposerPinnedHeader oldDelegate) =>
      extent != oldDelegate.extent || child != oldDelegate.child;
}

class _ComposerBottom extends StatelessWidget {
  const _ComposerBottom({
    required this.composer,
    required this.mobile,
    required this.showTaxonomy,
    required this.child,
  });

  final ComposerController composer;
  final bool mobile;
  final bool showTaxonomy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTaxonomy)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              key: const ValueKey('composer-taxonomy-scroll'),
              scrollDirection: Axis.horizontal,
              child: _TopicTaxonomy(composer: composer),
            ),
          ),
        if (composer.target.isPlugin && composer.uploads.isNotEmpty)
          ComposerUploadQueue(composer: composer),
        child,
      ],
    );
    if (!mobile) return content;

    // Taxonomy is one horizontally scrolling row with standard top padding.
    // Begin the blur at the controls' midpoint.
    final blurInset = showTaxonomy
        ? DSpacing.md +
              DControlStyle.scaledHeight(
                    DControlSize.toolbar,
                    MediaQuery.textScalerOf(context),
                    context: context,
                  ) /
                  2
        : 0.0;
    return Padding(
      padding: EdgeInsets.only(
        bottom: math.max(
          MediaQuery.viewInsetsOf(context).bottom,
          MediaQuery.paddingOf(context).bottom,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            top: blurInset,
            child: const DGradientBlur(
              key: ValueKey('composer-footer-blur'),
              edge: DGradientBlurEdge.bottom,
            ),
          ),
          content,
        ],
      ),
    );
  }
}

class _ComposerBodyLayout extends StatelessWidget {
  const _ComposerBodyLayout({
    required this.scrollsWithTitle,
    required this.child,
  });

  final bool scrollsWithTitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => scrollsWithTitle
      ? ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120),
          child: child,
        )
      : Expanded(child: child);
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
          final parent = shell.categoryFor(
            category?.parentCategoryId,
            siteUrl: composer.target.siteUrl,
          );
          final rootCategory = parent ?? category;
          final subcategories = rootCategory == null
              ? const <TopicCategory>[]
              : state.categories
                    .where(
                      (item) =>
                          item.parentCategoryId == rootCategory.id &&
                          item.canCreateTopic,
                    )
                    .toList();
          bool canEdit() =>
              !composer.isDisposed &&
              composer.isEditing &&
              identical(shell.visibleComposer, composer);
          void selectCategory(TopicCategory? selected) {
            if (canEdit() &&
                selected != null &&
                selected.id != composer.categoryId) {
              unawaited(shell.changeComposerCategory(composer, selected.id));
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              DSpacing.lg,
              DSpacing.md,
              DSpacing.lg,
              context.isTouch ? DSpacing.controlGap : DSpacing.md,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: DSpacing.controlGap,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!composer.target.isTagsEdit)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: context.isTouch
                            ? math.max(0, MediaQuery.sizeOf(context).width - 32)
                            : double.infinity,
                      ),
                      key: const ValueKey('composer-category-action'),
                      child: TopicCategorySelector(
                        size: DButtonSize.toolbar,
                        key: ObjectKey(composer),
                        valueKey: const ValueKey('composer-category'),
                        siteUrl: composer.target.siteUrl,
                        categories: state.categories,
                        selected: rootCategory,
                        placeholder: 'Category',
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
                        onSelected: composer.isEditing ? selectCategory : null,
                      ),
                    ),
                  if (!composer.target.isTagsEdit &&
                      rootCategory != null &&
                      (subcategories.isNotEmpty || parent != null))
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: context.isTouch
                            ? math.max(0, MediaQuery.sizeOf(context).width - 32)
                            : double.infinity,
                      ),
                      key: const ValueKey('composer-subcategory-action'),
                      child: TopicCategorySelector(
                        size: DButtonSize.toolbar,
                        key: ValueKey((composer, rootCategory.id)),
                        keyPrefix: 'composer-subcategory',
                        valueKey: const ValueKey('composer-subcategory'),
                        siteUrl: composer.target.siteUrl,
                        categories: subcategories,
                        parent: rootCategory,
                        selected: parent == null ? null : category,
                        placeholder: 'Subcategories',
                        clearSelectionLabel: rootCategory.canCreateTopic
                            ? 'No subcategory'
                            : null,
                        onSelected: composer.isEditing
                            ? (selected) {
                                if (composer.categoryId == categoryId) {
                                  selectCategory(selected ?? rootCategory);
                                }
                              }
                            : null,
                      ),
                    ),
                  if (state.capabilities.canTagTopics ||
                      composer.tags.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: context.isTouch
                            ? math.max(0, MediaQuery.sizeOf(context).width - 32)
                            : double.infinity,
                      ),
                      key: const ValueKey('composer-add-tag'),
                      child: TopicTagSelector(
                        size: DButtonSize.toolbar,
                        key: ValueKey((composer, categoryId)),
                        valueKey: const ValueKey('composer-tags'),
                        selectedTags: composer.tags,
                        capabilities: state.capabilities,
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
  const _SelectedPillInputFormatter(this.isSelected, this.onDelete);

  final bool Function() isSelected;
  final VoidCallback onDelete;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!isSelected()) return newValue;
    final selection = oldValue.selection;
    if (selection.isValid &&
        !selection.isCollapsed &&
        newValue.text ==
            oldValue.text.replaceRange(selection.start, selection.end, '') &&
        newValue.composing.isCollapsed) {
      onDelete();
    }
    return oldValue;
  }
}

bool _startsNewParagraph(ComposerBlockIndex index, TextSelection selection) {
  if (!selection.isValid) return false;
  final block = index.atOffset(selection.start);
  if (block == null ||
      selection.start < block.start ||
      selection.end > block.end) {
    return false;
  }
  return block.kind == ComposerBlockKind.paragraph ||
      block.kind == ComposerBlockKind.heading ||
      (selection.isCollapsed &&
          selection.start == block.end &&
          block.movable &&
          (block.kind == ComposerBlockKind.divider ||
              block.kind == ComposerBlockKind.code));
}

class _ParagraphInputFormatter extends TextInputFormatter {
  const _ParagraphInputFormatter(this.composer);

  final ComposerController composer;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (HardwareKeyboard.instance.isShiftPressed ||
        !oldValue.composing.isCollapsed ||
        !newValue.composing.isCollapsed ||
        !_startsNewParagraph(composer.blocks.index, oldValue.selection)) {
      return newValue;
    }
    final selection = oldValue.selection;
    final newline = oldValue.text.contains('\r\n') ? '\r\n' : '\n';
    if (newValue.text !=
            oldValue.text.replaceRange(
              selection.start,
              selection.end,
              newline,
            ) ||
        newValue.selection !=
            TextSelection.collapsed(offset: selection.start + newline.length)) {
      return newValue;
    }
    return newValue.copyWith(
      text: oldValue.text.replaceRange(
        selection.start,
        selection.end,
        '$newline$newline',
      ),
      selection: TextSelection.collapsed(
        offset: selection.start + newline.length * 2,
      ),
    );
  }
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

/// A content region of the enclosing composer, with the same editing surface
/// and inputs. Formatting and insertion belong to the enclosing toolbar.
class ComposerRichBodyEditor extends StatelessWidget {
  const ComposerRichBodyEditor({
    super.key,
    required this.composer,
    required this.label,
    required this.hintText,
    required this.onExit,
    this.onKeyEvent,
    this.enableBlockReordering,
  });

  final ComposerController composer;
  final String label;
  final String hintText;
  final VoidCallback onExit;
  final KeyEventResult Function(KeyEvent)? onKeyEvent;
  final bool? enableBlockReordering;

  @override
  Widget build(BuildContext context) {
    final enclosing = context.findAncestorWidgetOfExactType<ComposerEditor>();
    final style = enclosing?.textStyle ?? Theme.of(context).textTheme.bodyLarge;
    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): onExit,
          for (final modifier in [true, false]) ...{
            for (final (key, mark) in [
              (LogicalKeyboardKey.keyB, ComposerMark.bold),
              (LogicalKeyboardKey.keyI, ComposerMark.italic),
              (LogicalKeyboardKey.keyE, ComposerMark.inlineCode),
            ])
              SingleActivator(key, meta: modifier, control: !modifier): () =>
                  composer.activeEditor.toggleMark(mark),
            SingleActivator(
              LogicalKeyboardKey.keyL,
              meta: modifier,
              control: !modifier,
            ): () => unawaited(
              showComposerLinkDialog(
                context: context,
                composer: composer.activeEditor,
              ),
            ),
          },
        },
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: label,
          child: ComposerEditor(
            composer: composer,
            hintText: hintText,
            textStyle: style,
            hintStyle: style?.copyWith(
              color: DTokens.of(context).mutedForeground,
            ),
            autofocus: false,
            expands: false,
            showSelectionToolbar: enclosing?.showSelectionToolbar ?? true,
            enableDropTarget: enclosing?.enableDropTarget ?? true,
            enableBlockReordering:
                enableBlockReordering ??
                enclosing?.enableBlockReordering ??
                true,
            onKeyEvent: onKeyEvent,
            pickFiles: enclosing?.pickFiles ?? pickComposerFiles,
            pickImages: enclosing?.pickImages,
            readClipboardFiles:
                enclosing?.readClipboardFiles ?? readComposerClipboardFiles,
            onSuggestionAction: enclosing?.onSuggestionAction,
          ),
        ),
      ),
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
    this.enableBlockReordering = true,
    this.showSelectionToolbar = true,
    this.expands = true,
    this.pickFiles = pickComposerFiles,
    this.pickImages,
    this.readClipboardFiles = readComposerClipboardFiles,
    this.onSuggestionAction,
    this.slashActions,
    this.onKeyEvent,
  });

  final ComposerController composer;
  final String hintText;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final bool autofocus;
  final bool enableDropTarget;

  /// Enables block movement controls and Alt+Shift+Up/Down shortcuts.
  final bool enableBlockReordering;

  /// Topic composers expose persistent Native formatting actions instead.
  final bool showSelectionToolbar;
  final ComposerFilePicker pickFiles;

  /// Null offers the photo library under the site's optimisation policy.
  final ComposerImagePicker? pickImages;
  final ComposerClipboardFileReader readClipboardFiles;

  final bool expands;
  final ComposerSuggestionActionHandler? onSuggestionAction;
  final ComposerSlashActions? slashActions;

  /// Application shortcuts, after menu selection and before editor commands.
  final KeyEventResult Function(KeyEvent)? onKeyEvent;

  @override
  State<ComposerEditor> createState() => _ComposerEditorState();
}

class _ComposerEditorState extends State<ComposerEditor> {
  final _slashMenu = GlobalKey<ComposerSlashMenuState>();
  bool _pickingSlashFiles = false;
  _ComposerEditorState? _parentEditor;
  _ComposerEditorState? _nativeDropEditor;
  final _nestedEditors = <_ComposerEditorState>{};
  // Keep the desired column when a shorter line clamps the visible caret.
  ({_ComposerEditorState editor, TextEditingValue value, double x})?
  _verticalCaret;
  late final _verticalArrowAction = _ComposerVerticalArrowAction(
    _moveVertically,
  );
  static const _menuGap = 4.0;
  static const _imageMenuPreferredWidth = 310.0;
  double get _galleryMenuHeight => _GalleryComposerMenu.controlExtent(context);
  double get _galleryMenuContentWidth => _galleryMenuHeight * 4;

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
  ScrollPosition? _ancestorScroll;
  late final ComposerMediaEditingCoordinator _media;
  late final _ComposerSelectionOverlay _selectionOverlay;
  final ValueNotifier<int> _mediaLayoutRevision = ValueNotifier(0);
  final ValueNotifier<Offset?> _mediaDropPosition = ValueNotifier(null);
  double? _mediaDropIndicatorTop;
  bool _mediaLayoutRefreshScheduled = false;
  Rect? _lastImageMenuAnchor;
  (double, double)? _lastGalleryMenuPosition;
  late final TextInputFormatter _selectedPillInputFormatter;
  late final TextInputFormatter _renderedEmojiInputFormatter;
  final _blockquoteInputFormatter = ComposerBlockquoteInputFormatter();
  int? _blockquoteFieldGeneration;
  late final _ComposerPasteAction _pasteAction;
  late final _quoteLineStartAction =
      _ComposerLineStartAction<ExtendSelectionToLineBreakIntent>(
        () => _editableTextState,
      );
  late final _quoteExpandLineStartAction =
      _ComposerLineStartAction<ExpandSelectionToLineBreakIntent>(
        () => _editableTextState,
      );

  @override
  void initState() {
    super.initState();
    SurfaceOpeningTrace.mark('composer.editorMount');
    _scroll = ScrollController()..addListener(_scheduleMediaLayoutRefresh);
    _blockquoteFieldGeneration = widget.composer.fieldGeneration;
    widget.composer.text.addListener(_observeBlockquoteValue);
    _media = ComposerMediaEditingCoordinator(widget.composer)
      ..addListener(_scheduleMediaLayoutRefresh);
    _selectionOverlay = _ComposerSelectionOverlay(
      composer: widget.composer,
      scroll: _scroll,
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
          widget.composer.text.keyboardSelectedProjection != null ||
          _media.hasSelectedMediaProjection,
      () {
        final composer = widget.composer;
        final pill = _keyboardSelectedPill;
        if (pill == null) return;
        final source = composer.text.text;
        // Finish the native proposal before committing the component's removal.
        scheduleMicrotask(() {
          if (!mounted ||
              !identical(widget.composer, composer) ||
              composer.text.text != source ||
              !identical(_keyboardSelectedPill, pill)) {
            return;
          }
          _clearKeyboardPillSelection();
          _removePill(pill);
        });
      },
    );
    _renderedEmojiInputFormatter = _RenderedEmojiInputFormatter(
      endingAt: (offset) => widget.composer.text.renderedEmojiEndingAt(offset),
      startingAt: (offset) =>
          widget.composer.text.renderedEmojiStartingAt(offset),
    );
    _pasteAction = _ComposerPasteAction(_pasteClipboard);
    widget.composer.text.imageScrollController = _scroll;
    _selectionOverlay.sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ancestorScroll = widget.expands
        ? null
        : Scrollable.maybeOf(context)?.position;
    if (!identical(ancestorScroll, _ancestorScroll)) {
      _ancestorScroll?.removeListener(_ancestorScrolled);
      _ancestorScroll = ancestorScroll;
      _ancestorScroll?.addListener(_ancestorScrolled);
    }
    final parent = context.findAncestorStateOfType<_ComposerEditorState>();
    if (!identical(parent, _parentEditor)) {
      _parentEditor?._nestedEditors.remove(this);
      _parentEditor = parent;
      parent?._nestedEditors.add(this);
    }
  }

  void _ancestorScrolled() {
    _scheduleMediaLayoutRefresh();
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
    _lastImageMenuAnchor = null;
    _lastGalleryMenuPosition = null;
    _clearMediaDropIndicator();
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
    _ancestorScroll?.removeListener(_ancestorScrolled);
    _parentEditor?._nestedEditors.remove(this);
    _parentEditor?._scheduleMediaLayoutRefresh();
    if (identical(_parentEditor?._nativeDropEditor, this)) {
      _parentEditor?._nativeDropEditor = null;
    }
    widget.composer.text.removeListener(_observeBlockquoteValue);
    _releasePointerDownPillCollapse();
    if (identical(widget.composer.text.imageScrollController, _scroll)) {
      widget.composer.text.imageScrollController = null;
    }
    _media.removeListener(_scheduleMediaLayoutRefresh);
    _media.dispose();
    _selectionOverlay.dispose();
    _mediaLayoutRevision.dispose();
    _mediaDropPosition.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _pasteClipboard() async {
    final composer = widget.composer;
    final before = composer.text.value;
    bool isCurrent() =>
        mounted &&
        identical(widget.composer, composer) &&
        !composer.isDisposed &&
        composer.isEditing &&
        composer.text.value == before;

    if (await _media.pasteClipboardFiles(widget.readClipboardFiles)) {
      return true;
    }
    if (!isCurrent()) return true;
    if (!before.selection.isValid || before.selection.isCollapsed) return false;

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!isCurrent()) return true;
    final next = composerPastedLinkValue(before, clipboard?.text ?? '');
    if (next == null) return false;
    composer.history.transact(() {
      composer.commitText(expectedText: before.text, value: next);
    });
    return true;
  }

  Future<void> _pasteFromContextMenu(EditableTextState state) async {
    _blockquoteInputFormatter.reset();
    if (await _pasteClipboard()) {
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

  void _scheduleMediaLayoutRefresh({bool descendantHasMedia = false}) {
    final hasMedia = descendantHasMedia || _media.value.hasSelectedMedia;
    _parentEditor?._scheduleMediaLayoutRefresh(descendantHasMedia: hasMedia);
    if (_mediaLayoutRefreshScheduled ||
        (!hasMedia &&
            _mediaDropPosition.value == null &&
            _lastImageMenuAnchor == null &&
            _lastGalleryMenuPosition == null)) {
      return;
    }
    _mediaLayoutRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mediaLayoutRefreshScheduled = false;
      if (!mounted) return;
      // Block geometry traverses the editor, so measure after layout, never
      // while the overlay's widget subtree is being built.
      _mediaDropIndicatorTop = _mediaDropTop();
      _mediaLayoutRevision.value++;
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

  List<ComposerSlashAction> _slashActions(BuildContext context) {
    final composer = widget.composer;
    final shell = ShellScope.maybeRead(context);
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    return [
      for (final (label, icon, mark) in [
        ('Bold', DIcons.bold, ComposerMark.bold),
        ('Italic', DIcons.italic, ComposerMark.italic),
        ('Inline code', DIcons.code, ComposerMark.inlineCode),
      ])
        ComposerSlashAction(
          label: label,
          icon: icon,
          group: 'Formatting',
          onInvoke: () => composer.toggleMark(mark),
        ),
      ComposerSlashAction(
        label: 'Link',
        icon: DIcons.link,
        group: 'Formatting',
        onInvoke: () => unawaited(
          showComposerLinkDialog(context: context, composer: composer),
        ),
      ),
      for (var level = 1; level <= 4; level++)
        ComposerSlashAction(
          label: 'Heading $level',
          leadingText: 'H${const ['₁', '₂', '₃', '₄'][level - 1]}',
          hint: '#' * level,
          group: 'Formatting',
          keywords: ['h$level', 'heading$level'],
          onInvoke: () => composer.setHeading(level),
        ),
      if (!composer.target.isPlugin) ...[
        for (final ordered in [false, true])
          ComposerSlashAction(
            label: ordered ? 'Numbered list' : 'Bulleted list',
            icon: ordered ? null : DIcons.list,
            leadingText: ordered ? '1.' : null,
            hint: ordered ? '1.' : '-',
            keywords: ordered
                ? const ['ordered', 'number', 'ol']
                : const ['unordered', 'bullet', 'ul'],
            onInvoke: () {
              if (!composer.isEditing) return;
              if (composer is ComposerListBodyController &&
                  composer.setListKind(ordered: ordered)) {
                return;
              }
              composer.history.transact(() {
                composer.text.value = insertComposerList(
                  composer.text.value,
                  ordered: ordered,
                );
              });
            },
          ),
        ComposerSlashAction(
          label: 'To-do list',
          icon: DIcons.list,
          keywords: const ['todo', 'to-do', 'task', 'checklist', 'checkbox'],
          onInvoke: () {
            if (composer.isEditing) {
              composer.history.transact(() {
                composer.text.value = insertComposerTodo(composer.text.value);
              });
            }
          },
        ),
        ComposerSlashAction(
          label: 'Table',
          icon: DIcons.list,
          onInvoke: () => insertComposerTable(composer),
        ),
        ComposerSlashAction(
          label: 'Details',
          icon: DIcons.list,
          keywords: const ['summary', 'collapse'],
          onInvoke: () => insertComposerDetails(composer),
        ),
        if (composer.canUpload)
          ComposerSlashAction(
            label: 'Upload',
            icon: DIcons.paperclip,
            keywords: const ['image', 'file', 'attachment'],
            onInvoke: () => unawaited(_pickSlashFiles()),
          ),
        if (!composer.target.isTaxonomyEdit &&
            (shell?.siteConfigFor(composer.target.siteUrl).emojiEnabled ??
                false))
          ComposerSlashAction(
            label: 'Emoji',
            icon: DIcons.discourseEmojis,
            keywords: const ['reaction', 'smile'],
            onInvoke: () => unawaited(
              openEmojiPickerForTopicComposer(
                context: context,
                composer: composer,
              ),
            ),
          ),
      ],
      for (final action in registry.composerToolbar(context, composer))
        ComposerSlashAction(
          label: action.label,
          icon: action.icon,
          onInvoke: action.onInvoke,
        ),
      ...?widget.slashActions?.call(context),
    ];
  }

  Future<void> _pickSlashFiles() async {
    final composer = widget.composer;
    if (_pickingSlashFiles || !composer.canUpload) return;
    _pickingSlashFiles = true;
    final expected = composer.text.value;
    try {
      final files = await widget.pickFiles();
      if (mounted &&
          identical(widget.composer, composer) &&
          composer.canUpload &&
          composer.text.value == expected) {
        composer.addFiles(files, expected.selection.extentOffset);
      }
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'composer.pickFiles',
        source: 'platform',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      if (mounted && identical(widget.composer, composer)) {
        composer.showNotice("Couldn't open the file picker.");
      }
    } finally {
      _pickingSlashFiles = false;
      if (mounted &&
          identical(widget.composer, composer) &&
          composer.isEditing) {
        composer.focus.requestFocus();
      }
    }
  }

  Widget _field() {
    final field = Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Composer editor',
      traversalParentIdentifier: widget.composer,
      child: ComposerSlashMenu(
        key: _slashMenu,
        composer: widget.composer,
        actions: _slashActions,
        hintStyle: widget.hintStyle ?? widget.textStyle,
        renderEditable: () => _renderEditable,
        scroll: Listenable.merge([_scroll, _ancestorScroll]),
        child: ScrollConfiguration(
          behavior: widget.expands
              ? _ComposerEditorScrollBehavior(_scroll)
              : ScrollConfiguration.of(context),
          child: _textField(),
        ),
      ),
    );
    if (!widget.expands) return field;
    return DScrollBar(
      controller: _scroll,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 2),
        child: field,
      ),
    );
  }

  Widget _textField() => MouseRegion(
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
              ExtendSelectionVerticallyToAdjacentLineIntent:
                  _verticalArrowAction,
            },
            child: ListenableBuilder(
              listenable: Listenable.merge([
                widget.composer.text,
                widget.composer.focus,
              ]),
              builder: (_, _) => ComposerBlockquoteDecoration(
                reserveGutter: _parentEditor == null,
                repaint: Listenable.merge([widget.composer.text, _scroll]),
                child: ClipRect(
                  child: DefaultSelectionStyle.merge(
                    // Components paint their own outline. The native range
                    // includes hidden Markdown and would tint extra lines.
                    selectionColor:
                        widget.composer.text.keyboardSelectedProjection != null
                        ? Colors.transparent
                        : null,
                    child: DInput(
                      borderless: true,
                      hintText:
                          widget.composer.singleNewlineParagraphs &&
                              widget.composer.text.text.isEmpty
                          ? widget.hintText
                          : null,
                      // New documents also get a fresh native input session.
                      // ComposerController resets the shared source history.
                      key: ValueKey(widget.composer.fieldGeneration),
                      controller: widget.composer.text
                        ..todosReadOnly = !widget.composer.isEditing,
                      readOnly: !widget.composer.isEditing,
                      scrollController: _scroll,
                      focusNode: widget.composer.focus,
                      autofocus: widget.autofocus,
                      expands: widget.expands,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        _selectedPillInputFormatter,
                        _renderedEmojiInputFormatter,
                        const ComposerImageGalleryInputFormatter(),
                        const ComposerQuoteInputFormatter(),
                        ...widget.composer.text.syntaxInputFormatters,
                        _blockquoteInputFormatter,
                        if (widget.composer.text.enableTodos)
                          ComposerTodoInputFormatter(
                            referenceMarkers:
                                widget.composer.text.todoReferenceMarkers,
                          ),
                        if (context.isTouch &&
                            widget.composer.text.enableBlockSeparators &&
                            !widget.composer.singleNewlineParagraphs)
                          _ParagraphInputFormatter(widget.composer),
                        ...widget.composer.inputFormatters,
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
                    ),
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

  _ComposerEditorState get _listNavigationRoot {
    var editor = this;
    while (editor.widget.composer is ComposerListBodyController &&
        editor._parentEditor != null) {
      editor = editor._parentEditor!;
    }
    return editor;
  }

  Iterable<({_ComposerEditorState editor, int start, int end})>
  _caretBlocks() sync* {
    final text = widget.composer.text;
    final sourceBlocks = widget.composer.blocks.index.blocks;
    final blocks = [
      for (final block in sourceBlocks) (start: block.start, end: block.end),
      for (final line in RegExp(
        r'^[ \t\r]*$',
        multiLine: true,
      ).allMatches(text.text))
        if ((line.start == 0 || text.text[line.start - 1] == '\n') &&
            !sourceBlocks.any(
              (block) => line.start >= block.start && line.start <= block.end,
            ) &&
            !text.blockGaps.any(
              (gap) => line.start > gap.start && line.start < gap.end,
            ))
          (
            start: line.start,
            end: line.end - (line.group(0)!.endsWith('\r') ? 1 : 0),
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    for (final block in blocks) {
      final nested = _nestedEditors.where((editor) {
        final composer = editor.widget.composer;
        return composer is ComposerListBodyController &&
            composer.isCurrent &&
            composer.item.start == block.start;
      }).firstOrNull;
      if (nested != null) {
        // Navigate the rendered body instead of its hidden Markdown markers.
        yield* nested._caretBlocks();
      } else {
        yield (editor: this, start: block.start, end: block.end);
      }
    }
  }

  bool _moveVertically(bool forward) {
    final composer = widget.composer;
    final value = composer.value;
    final render = _renderEditable;
    if (!composer.focus.hasPrimaryFocus ||
        !composer.isEditing ||
        !value.composing.isCollapsed ||
        !value.selection.isValid ||
        !value.selection.isCollapsed ||
        render == null) {
      return false;
    }
    final root = _listNavigationRoot;
    if (!root._nestedEditors.any(
      (editor) => editor.widget.composer is ComposerListBodyController,
    )) {
      return false;
    }
    final blocks = root._caretBlocks().toList();
    final caret = value.selection.extent;
    final index = blocks.indexWhere(
      (block) =>
          identical(block.editor, this) &&
          caret.offset >= block.start &&
          caret.offset <= block.end,
    );
    if (index < 0) return false;
    final previous = root._verticalCaret;
    final x =
        previous != null &&
            identical(previous.editor, this) &&
            previous.value == value
        ? previous.x
        : render.localToGlobal(render.getLocalRectForCaret(caret).center).dx;
    var target = blocks[index];
    final run = render.startVerticalCaretMovement(caret);
    final moved = forward ? run.moveNext() : run.movePrevious();
    TextPosition position;
    if (moved &&
        run.current.offset >= target.start &&
        run.current.offset <= target.end) {
      position = run.current;
    } else {
      final next = index + (forward ? 1 : -1);
      if (next < 0 || next >= blocks.length) return false;
      target = blocks[next];
      position = TextPosition(
        offset: forward ? target.start : target.end,
        affinity: forward ? TextAffinity.downstream : TextAffinity.upstream,
      );
    }
    final editor = target.editor;
    final editable = editor._editableTextState;
    if (editable == null) return false;
    final component = editor._collapsedPillStartingAt(target.start);
    if (component != null &&
        editor.widget.composer.text.componentContentEnd(component) >=
            target.end) {
      editor._selectPillForKeyboard(component);
      editor.widget.composer.requestFocus();
      root._verticalCaret = null;
      return true;
    }
    final destination = editable.renderEditable;
    final y = destination
        .localToGlobal(destination.getLocalRectForCaret(position).center)
        .dy;
    final hit = destination.getPositionForPoint(Offset(x, y));
    final selection = TextSelection.fromPosition(
      TextPosition(
        offset: hit.offset.clamp(target.start, target.end),
        affinity: hit.affinity,
      ),
    );
    editable.userUpdateTextEditingValue(
      editor.widget.composer.value.copyWith(selection: selection),
      SelectionChangedCause.keyboard,
    );
    editor.widget.composer.requestFocus();
    editable.bringIntoView(selection.extent);
    root._verticalCaret = (
      editor: editor,
      value: editor.widget.composer.value,
      x: x,
    );
    return true;
  }

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
    final text = widget.composer.text;
    final gallery = text.collapsedGalleryAtGlobalPosition(globalPosition);
    if (gallery != null) {
      _clearMediaDropIndicator();
      _media.updateDropTarget(gallery);
      widget.composer.focus.requestFocus();
      return;
    }
    _media.updateDropTarget(null);
    final offset = _mediaDropOffset(globalPosition);
    if (offset == null) return;
    text.selection = TextSelection.collapsed(offset: offset);
    widget.composer.focus.requestFocus();
  }

  int? _imageDropOffset(Offset globalPosition) {
    final text = widget.composer.text;
    if (text.collapsedGalleryAtGlobalPosition(globalPosition) != null) {
      _clearMediaDropIndicator();
      return null;
    }
    return _mediaDropOffset(globalPosition);
  }

  ComposerDropGeometry get _dropGeometry => ComposerDropGeometry(
    widget.composer.blocks.index,
    _blockRect,
    emptyLineAt: _emptyLineAt,
  );

  int? _mediaDropOffset(Offset position) {
    final target = widget.composer.isEditing
        ? _dropGeometry.targetAt(position)
        : null;
    final offset = target == null
        ? (widget.composer.isEditing && widget.composer.text.text.trim().isEmpty
              ? 0
              : null)
        : target.offset ?? _dropGeometry.offsetAt(target.gap);
    _mediaDropPosition.value = offset == null ? null : position;
    _mediaDropIndicatorTop = _mediaDropTop();
    return offset;
  }

  void _clearMediaDropIndicator() {
    _mediaDropIndicatorTop = null;
    _mediaDropPosition.value = null;
  }

  double? _mediaDropTop() {
    final position = _mediaDropPosition.value;
    final stack = _stackKey.currentContext?.findRenderObject();
    if (position == null || stack is! RenderBox || !stack.hasSize) return null;
    var y = _dropGeometry.targetAt(position)?.y;
    if (y == null && widget.composer.text.text.trim().isEmpty) {
      final editable = _renderEditable;
      if (editable == null) return null;
      y = editable
          .localToGlobal(
            editable
                .getLocalRectForCaret(const TextPosition(offset: 0))
                .topLeft,
          )
          .dy;
    }
    if (y == null) return null;
    final top = stack.globalToLocal(Offset(0, y)).dy;
    return top >= 0 && top <= stack.size.height ? top : null;
  }

  void _moveImageDropCaret(Offset position) {
    final offset = _imageDropOffset(position);
    if (offset == null) return;
    widget.composer.text.selection = TextSelection.collapsed(offset: offset);
    widget.composer.focus.requestFocus();
  }

  void _dropFiles(DropDoneDetails details) {
    final target = _editorAt(details.globalPosition);
    if (!identical(target, this)) {
      target._dropFiles(details);
      _cancelNativeDrop();
      return;
    }
    _moveDropCaret(details.globalPosition);
    if (dropContainsDirectory(details.files)) {
      widget.composer.showNotice('Folders cannot be uploaded here.');
    }
    final files = composerUploadFilesFromDrop(details.files);
    _media.dropFiles(
      files,
      offset: widget.composer.text.selection.extentOffset,
    );
    _cancelNativeDrop();
  }

  _ComposerEditorState _editorAt(Offset position) {
    for (final nested in _nestedEditors) {
      if (!TickerMode.valuesOf(nested.context).enabled) continue;
      final render = nested._stackKey.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) continue;
      final origin = render.localToGlobal(Offset.zero);
      if ((origin & render.size).contains(position)) {
        return nested._editorAt(position);
      }
    }
    return this;
  }

  void _updateNativeDrop(Offset position) {
    final target = _editorAt(position);
    if (!identical(target, _nativeDropEditor)) {
      _nativeDropEditor?._media.cancelDrag();
      _nativeDropEditor?._clearMediaDropIndicator();
      _nativeDropEditor = target;
    }
    target._moveDropCaret(position);
    target._media.beginDrag();
  }

  void _cancelNativeDrop() {
    _nativeDropEditor?._media.cancelDrag();
    _nativeDropEditor?._clearMediaDropIndicator();
    _nativeDropEditor = null;
    _clearMediaDropIndicator();
  }

  bool get _hasPointerDownPill =>
      _pointerDownQuote != null ||
      _media.hasPointerCapture ||
      _pointerDownSyntax != null ||
      _pointerDownAfterBlockSyntax != null;

  void _onEditorPointerDown(PointerDownEvent event) {
    _listNavigationRoot._verticalCaret = null;
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
    if (_pointerDownSyntax?.projection is ComposerInteractiveSyntaxProjection) {
      _holdPointerDownPillCollapsed();
      return;
    }
    final hasDirectHit =
        _pointerDownQuote != null ||
        image != null ||
        gallery != null ||
        _pointerDownSyntax != null;
    _pointerDownAfterBlockSyntax = !hasDirectHit
        ? widget.composer.text.collapsedBlockSyntaxBeforeGlobalPosition(
            position,
            sourceOffset: _renderEditable?.getPositionForPoint(position).offset,
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
      text.keepSyntaxCollapsedForPointerEdit(
        syntax,
        preserveSelection:
            _pointerDownSyntax?.projection
                is ComposerInteractiveSyntaxProjection,
      );
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
    if (syntax?.projection is ComposerInteractiveSyntaxProjection) {
      widget.composer.text.releaseSyntaxPointerEdit(syntax!);
      return;
    }
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
        // A click in the structural gap below a component resolves natively
        // to the component's first source position, which selects the whole
        // block. That selection is the click's own by-product, not a choice
        // to keep, and would otherwise pin the caret on the block.
        _clearKeyboardPillSelection();
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
    if (syntax.projection is ComposerInteractiveSyntaxProjection) {
      _clearKeyboardPillSelection();
    }
    final text = widget.composer.text;
    if (!_stillContains(text.text, syntax.start, syntax.end, syntax.source)) {
      return;
    }
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
    if (_slashMenu.currentState?.handleKeyEvent(event) ==
        KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    // Embedded cell editors own their selection, deletion and text shortcuts.
    if (!widget.composer.focus.hasPrimaryFocus) return KeyEventResult.ignored;
    if (!widget.composer.isEditing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if ((!widget.composer.autocomplete.isOpen ||
            keyboard.isMetaPressed ||
            keyboard.isControlPressed) &&
        widget.onKeyEvent?.call(event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
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
    if (isUndoOrRedo) {
      _clearKeyboardPillSelection();
      if (keyboard.isShiftPressed ||
          event.logicalKey == LogicalKeyboardKey.keyY) {
        widget.composer.history.redo();
      } else {
        widget.composer.history.undo();
      }
      return KeyEventResult.handled;
    }
    if (widget.enableBlockReordering &&
        event is KeyDownEvent &&
        keyboard.isAltPressed &&
        keyboard.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      final blocks = widget.composer.blocks;
      final block = blocks.selected;
      if (block != null) {
        final position = blocks.index.blocks.indexOf(block);
        blocks.moveTo(
          position + (event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 2),
          expectedRevision: blocks.revision,
        );
      }
      return KeyEventResult.handled;
    }
    final hasModifier =
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed;
    final selectedComponent =
        _media.value.selectedGallery ?? _keyboardSelectedPill;
    final text = widget.composer.text;
    final boundaryComponent = text.boundaryCaretProjection;
    if (boundaryComponent != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        !hasModifier) {
      final before =
          text.selection.extentOffset == _pillStart(boundaryComponent);
      if ((before && event.logicalKey == LogicalKeyboardKey.arrowRight) ||
          (!before && event.logicalKey == LogicalKeyboardKey.arrowLeft)) {
        _selectPillForKeyboard(boundaryComponent);
        return KeyEventResult.handled;
      }
      if (isEnter && event is KeyDownEvent) {
        final offset = text.selection.extentOffset;
        final newline = text.text.contains('\r\n') ? '\r\n' : '\n';
        final insertion = '$newline$newline';
        text.value = TextEditingValue(
          text: text.text.replaceRange(offset, offset, insertion),
          selection: TextSelection.collapsed(
            offset: before ? offset : offset + insertion.length,
          ),
        );
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          ((!before && event.logicalKey == LogicalKeyboardKey.backspace) ||
              (before && event.logicalKey == LogicalKeyboardKey.delete))) {
        _removePill(boundaryComponent);
        return KeyEventResult.handled;
      }
    }
    if (selectedComponent != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        !hasModifier &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      _clearKeyboardPillSelection();
      text.moveCaretBesideComponent(
        selectedComponent,
        before: event.logicalKey == LogicalKeyboardKey.arrowLeft,
      );
      return KeyEventResult.handled;
    }
    if (selectedComponent != null &&
        event is KeyDownEvent &&
        isEnter &&
        !hasModifier) {
      final start = _pillStart(selectedComponent);
      final value = widget.composer.text.value;
      final newline = value.text.contains('\r\n') ? '\r\n' : '\n';
      _clearKeyboardPillSelection();
      widget.composer.text.value = TextEditingValue(
        text: value.text.replaceRange(start, start, '$newline$newline'),
        selection: TextSelection.collapsed(offset: start),
      );
      return KeyEventResult.handled;
    }
    if (selectedComponent == null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        !hasModifier &&
        text.selection.isValid &&
        text.selection.isCollapsed &&
        text.value.composing.isCollapsed) {
      final component = _collapsedPillEndingAt(text.selection.extentOffset);
      if (component != null &&
          text.componentContentEnd(component) == text.selection.extentOffset) {
        _removePill(component);
        return KeyEventResult.handled;
      }
    }
    if (selectedComponent == null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        !hasModifier &&
        widget.composer.text.selectBlockBeforeCaret()) {
      widget.composer.autocomplete.dismiss();
      return KeyEventResult.handled;
    }
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
            offset: switch (selectedPill) {
              ComposerSyntaxOccurrence(:final projection)
                  when projection is! ComposerBlockSyntaxProjection =>
                projection.start,
              _ => widget.composer.text.caretBeforeBlock(
                _pillStart(selectedPill),
              ),
            },
          );
        } else {
          _moveCaretAfterPill(selectedPill);
        }
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.delete) &&
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
    final isParagraphBreak = _startsNewParagraph(
      widget.composer.blocks.index,
      selection,
    );
    if (isEnter &&
        !widget.composer.discarding &&
        (keyboard.isShiftPressed || !widget.composer.autocomplete.isOpen) &&
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        value.composing.isCollapsed &&
        (isParagraphBreak ||
            widget.composer.singleNewlineParagraphs ||
            _blockquoteInputFormatter.isInQuote(value) ||
            widget.composer.text.todos.any(
              (todo) =>
                  selection.isCollapsed &&
                  selection.start >= todo.contentStart &&
                  selection.start <= todo.end,
            ))) {
      final editable = _editableTextState;
      if (editable == null) return KeyEventResult.ignored;
      final newline = value.text.contains('\r\n') ? '\r\n' : '\n';
      final insertion =
          isParagraphBreak &&
              !keyboard.isShiftPressed &&
              !widget.composer.singleNewlineParagraphs
          ? '$newline$newline'
          : newline;
      editable.userUpdateTextEditingValue(
        TextEditingValue(
          text: value.text.replaceRange(
            selection.start,
            selection.end,
            insertion,
          ),
          selection: TextSelection.collapsed(
            offset: selection.start + insertion.length,
          ),
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

    if (!hasModifier &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) &&
        _moveVertically(event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.handled;
    }

    final caret = selection.extentOffset;
    final isPlainHorizontalArrow =
        !hasModifier &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight);
    if (isPlainHorizontalArrow) {
      final moveLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
      for (final todo in text.todos) {
        final inPrefix = moveLeft
            ? caret >= todo.start && caret <= todo.contentStart
            : caret >= todo.start - 1 && caret < todo.contentStart;
        if (inPrefix) {
          text.selection = TextSelection.collapsed(
            offset: moveLeft && todo.start > 0
                ? todo.start - 1
                : todo.contentStart,
          );
          return KeyEventResult.handled;
        }
      }
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

  Object? get _keyboardSelectedPill =>
      widget.composer.text.keyboardSelectedProjection;

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
    for (final quote in text.quoteBlocks) {
      if ((quote.end == caret || text.componentContentEnd(quote) == caret) &&
          text.isQuoteCollapsed(quote)) {
        return quote;
      }
    }
    for (final gallery in text.galleryBlocks) {
      if (gallery.end == caret && text.isGalleryCollapsed(gallery)) {
        return gallery;
      }
    }
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
    for (final quote in text.quoteBlocks) {
      if (quote.start == caret && text.isQuoteCollapsed(quote)) return quote;
    }
    for (final gallery in text.galleryBlocks) {
      if (gallery.start == caret && text.isGalleryCollapsed(gallery)) {
        return gallery;
      }
    }
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
    ComposerQuoteBlock quote => quote.start,
    ComposerImageGalleryBlock gallery => gallery.start,
    ComposerImageBlock image => image.start,
    _ => throw ArgumentError.value(pill, 'pill'),
  };

  void _moveCaretAfterPill(Object pill) {
    if (pill case final ComposerSyntaxOccurrence syntax) {
      _moveCaretAfterSyntax(syntax);
      return;
    }
    final end = switch (pill) {
      ComposerQuoteBlock quote => quote.end,
      ComposerImageGalleryBlock gallery => gallery.end,
      ComposerImageBlock image => image.end,
      _ => throw ArgumentError.value(pill, 'pill'),
    };
    widget.composer.text.selection = TextSelection.collapsed(offset: end);
  }

  void _moveCaretAfterSyntax(ComposerSyntaxOccurrence syntax) {
    final text = widget.composer.text;
    text.value = syntax.projection.moveCaretAfter(text.value);
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
      case ComposerQuoteBlock quote:
        widget.composer.removeQuote(quote);
        return;
      case ComposerImageGalleryBlock gallery:
        widget.composer.removeGallery(gallery);
        return;
    }
    throw ArgumentError.value(pill, 'pill');
  }

  _ComposerEditorState? get _imageMenuEditor {
    if (!widget.composer.isEditing || !TickerMode.valuesOf(context).enabled) {
      return null;
    }
    for (final nested in _nestedEditors) {
      if (nested._imageMenuEditor case final editor?) return editor;
    }
    return _media.value.selectedImage == null ? null : this;
  }

  Rect? _imageMenuAnchor(_ComposerEditorState? editor) {
    final image = editor?._media.value.selectedImage;
    if (image == null) {
      _lastImageMenuAnchor = null;
      return null;
    }
    final stack = _stackKey.currentContext?.findRenderObject();
    final rect = editor!.widget.composer.text.collapsedImageGlobalRect(image);
    if (stack is! RenderBox || !stack.hasSize || rect == null) {
      return _lastImageMenuAnchor;
    }
    return _lastImageMenuAnchor = Rect.fromPoints(
      stack.globalToLocal(rect.topLeft),
      stack.globalToLocal(rect.bottomRight),
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
    final height = _galleryMenuHeight;
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
        stack.size.height > height ? stack.size.height - height : 0.0,
      ),
    );
  }

  Widget _mediaOverlays(BoxConstraints constraints) {
    if (!widget.composer.isEditing) return const SizedBox.shrink();
    final state = _media.value;
    // The enclosing composer owns image menus for all its content, outside
    // the nested editors' clipping and text semantics.
    final imageEditor = _parentEditor == null ? _imageMenuEditor : null;
    final imageMenuAnchor = _imageMenuAnchor(imageEditor);
    final galleryMenuPosition = _galleryMenuPosition(
      constraints,
      state.selectedGallery,
    );
    final galleryMenuWidth = math.min(
      _galleryMenuContentWidth,
      constraints.maxWidth,
    );
    final dropTop = _mediaDropIndicatorTop;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (imageMenuAnchor != null)
            Positioned.fromRect(
              rect: imageMenuAnchor,
              child: _imageMenu(imageEditor!),
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
                  _media.pickImagesForSelectedGallery(
                    widget.pickImages ??
                        _sitePhotoLibrary(context, widget.composer),
                  ),
                ),
                onAddExistingImages: () =>
                    unawaited(_addExistingImagesToSelectedGallery()),
                onUnwrap: _media.unwrapSelectedGallery,
                onDismiss: _media.dismissGallery,
              ),
            ),
          if (dropTop != null)
            Positioned(
              left: 0,
              right: 0,
              top: dropTop,
              child: const FractionalTranslation(
                translation: Offset(0, -.5),
                child: DDropIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageMenu(_ComposerEditorState editor) {
    final media = editor._media;
    final state = media.value;
    // Give the passive anchor its own native accessibility boundary so it
    // cannot merge with another editor overlay's traversal parent.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DPopover(
        key: ObjectKey(editor),
        open: true,
        focusContentOnOpen: false,
        restoreFocus: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        onOpenChange: (open, reason) {
          if (!open) {
            media.dismissImage(
              requestFocus: reason == DPopoverChangeReason.escape,
            );
          }
        },
        content: DPopoverContent(
          semanticLabel: 'Image controls',
          width: _imageMenuPreferredWidth,
          side: DPopoverSide.top,
          align: DPopoverAlign.start,
          child: _ImageComposerMenu(
            image: state.selectedImage!,
            gallery: state.selectedImageGallery,
            alt: media.imageAlt,
            onSaveAlt: media.saveImageAlt,
            onScale: media.scaleImage,
            onDelete: media.deleteSelectedImage,
          ),
        ),
        child: DPopoverAnchor(
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  double _minimumLineHeight(BuildContext context) {
    final style = widget.textStyle ?? Theme.of(context).textTheme.bodyLarge!;
    // Match MarkdownEditingController: the strut owns leading for empty and
    // populated paragraphs alike, so typing does not recenter the input.
    final painter = TextPainter(
      text: TextSpan(style: style.copyWith(height: 1)),
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
      textDirection: DDirection.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) => ComposerHistoryScope(
    composer: widget.composer,
    child: widget.enableBlockReordering && _parentEditor == null
        ? ComposerBlockSurface(
            composer: widget.composer,
            expands: widget.expands,
            blockRect: _blockRect,
            blockActionRect: _blockActionRect,
            lineHeight: _minimumLineHeight(context),
            emptyLineAt: _emptyLineAt,
            geometryChanges: _mediaLayoutRevision,
            editorScroll: () =>
                _ancestorScroll ??
                (_scroll.hasClients ? _scroll.position : null),
            child: _editorBody(),
          )
        : _editorBody(),
  );

  ComposerEmptyLine? _emptyLineAt(Offset? position) {
    final editable = _renderEditable;
    if (editable == null || !editable.hasSize) return null;
    final text = widget.composer.text;
    final offset = position == null
        ? text.selection.extentOffset.clamp(0, text.text.length)
        : editable.getPositionForPoint(position).offset;
    final start = offset == 0 ? 0 : text.text.lastIndexOf('\n', offset - 1) + 1;
    if (text.blockGaps.any(
      (separator) => start > separator.start && start < separator.end,
    )) {
      return null;
    }
    final next = text.text.indexOf('\n', offset);
    var end = next < 0 ? text.text.length : next;
    if (end > start && text.text[end - 1] == '\r') end--;
    if (text.text.substring(start, end).trim().isNotEmpty ||
        widget.composer.blocks.index.blocks.any(
          (block) => block.start <= start && block.end > start,
        )) {
      return null;
    }
    final rect = _lineRect(
      editable,
      start,
    ).shift(editable.localToGlobal(Offset.zero));
    if (position != null &&
        (position.dy < rect.top || position.dy > rect.bottom)) {
      return null;
    }
    return (range: TextRange(start: start, end: end), rect: rect);
  }

  Rect _lineRect(RenderEditable editable, int offset) {
    final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
    // Apple carets extend beyond the line. Keep that overhang out of the
    // block geometry, especially above the editor's first line.
    return Rect.fromCenter(
      center: caret.center,
      width: caret.width,
      height: editable.preferredLineHeight,
    );
  }

  Rect? _blockActionRect(ComposerBodyBlock block) {
    final editable = _renderEditable;
    if (editable == null || !editable.hasSize) return null;
    if (block.kind == ComposerBlockKind.todo) {
      for (final editor in _nestedEditors) {
        final composer = editor.widget.composer;
        final body = editor._renderEditable;
        final bounds = editor._stackKey.currentContext?.findRenderObject();
        if (composer is ComposerListBodyController &&
            composer.isCurrent &&
            composer.item.start == block.start &&
            body != null &&
            body.hasSize &&
            bounds is RenderBox &&
            bounds.hasSize) {
          // Empty carets include extra strut leading. Shape a text line so
          // the actions stay with both the placeholder and the typed text.
          final painter = TextPainter(
            text: TextSpan(
              text: ' ',
              style: editor._editableTextState!.widget.style,
            ),
            strutStyle: body.strutStyle,
            textDirection: body.textDirection,
            textScaler: body.textScaler,
          )..layout();
          final line = painter
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1),
              )
              .first
              .toRect();
          painter.dispose();
          return Rect.fromPoints(
            bounds.localToGlobal(line.topLeft),
            bounds.localToGlobal(line.bottomRight),
          );
        }
      }
      final todo = widget.composer.text.todos
          .where((todo) => todo.start == block.start)
          .firstOrNull;
      if (todo != null) {
        return _lineRect(
          editable,
          todo.contentStart,
        ).shift(editable.localToGlobal(Offset.zero));
      }
    }
    if (block.kind == ComposerBlockKind.paragraph ||
        block.kind == ComposerBlockKind.list) {
      return _lineRect(
        editable,
        block.start,
      ).shift(editable.localToGlobal(Offset.zero));
    }
    if (block.kind == ComposerBlockKind.heading) {
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: block.start, extentOffset: block.end),
      );
      if (boxes.isNotEmpty) {
        // Headings use their own first rendered line's font size and leading,
        // even when they wrap onto several lines.
        return boxes.first.toRect().shift(editable.localToGlobal(Offset.zero));
      }
    }
    final rect = _blockRect(block);
    return rect == null
        ? null
        : Rect.fromLTWH(
            rect.left,
            rect.top,
            rect.width,
            _minimumLineHeight(context),
          );
  }

  Rect? _blockRect(ComposerBodyBlock block) {
    final editable = _renderEditable;
    if (editable == null ||
        !editable.hasSize ||
        block.end > widget.composer.text.text.length) {
      return null;
    }
    final text = widget.composer.text;
    for (final syntax in text.syntaxBlocks) {
      if (syntax.start == block.start) {
        final rect = text.collapsedSyntaxGlobalRect(syntax);
        if (rect != null) return rect;
      }
    }
    for (final quote in text.quoteBlocks) {
      if (quote.start == block.start) {
        final rect = text.collapsedQuoteGlobalRect(quote);
        if (rect != null) return rect;
      }
    }
    for (final gallery in text.galleryBlocks) {
      if (gallery.start == block.start) {
        final rect = text.collapsedGalleryGlobalRect(gallery);
        if (rect != null) return rect;
      }
    }
    for (final image in text.imageBlocks) {
      if (image.start == block.start) {
        final rect = text.collapsedImageGlobalRect(image);
        if (rect != null) return rect;
      }
    }
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: block.start, extentOffset: block.end),
    );
    if (boxes.isEmpty) return null;
    var rect = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      rect = rect.expandToInclude(box.toRect());
    }
    // Selection boxes include the spacer below a paragraph's final baseline.
    // End the block at its text line so the insertion boundary shares the gap
    // equally with the following block, including when this block wraps.
    if (block.kind != ComposerBlockKind.todo &&
        text.blockSeparators.any((gap) => gap.start == block.end)) {
      final lastLine = _lineRect(editable, block.end - 1);
      rect = Rect.fromLTRB(
        rect.left,
        rect.top,
        rect.right,
        math.min(rect.bottom, lastLine.bottom),
      );
    }
    // Empty lines use the caret's line box. Include the same leading for a
    // populated block so typing its first character does not move the controls.
    rect = rect.expandToInclude(_lineRect(editable, block.start));
    return rect.shift(editable.localToGlobal(Offset.zero));
  }

  Widget _editorBody() => LayoutBuilder(
    builder: (context, constraints) {
      _scheduleMediaLayoutRefresh();
      return OverlayPortal(
        controller: _selectionOverlay.portal,
        overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
          valueListenable: _selectionOverlay.anchor,
          builder: (context, anchor, child) => anchor == null
              ? const SizedBox.shrink()
              : Positioned.fromRect(rect: anchor, child: child!),
          child: ComposerSelectionMenu(
            composer: widget.composer,
            onFocusChange: _selectionOverlay.focusChanged,
            onDismiss: _selectionOverlay.dismiss,
            onLink: () => unawaited(
              showComposerLinkDialog(
                context: this.context,
                composer: widget.composer,
              ),
            ),
          ),
        ),
        child: NativeDropTarget(
          enable:
              widget.enableDropTarget &&
              !context.isTouch &&
              _parentEditor == null,
          onDragEntered: (details) => _updateNativeDrop(details.globalPosition),
          onDragUpdated: (details) => _updateNativeDrop(details.globalPosition),
          onDragExited: (_) => _cancelNativeDrop(),
          onDragDone: _dropFiles,
          child: DDragRegion<ComposerImageBlock>(
            accepts: (_) => widget.composer.isEditing,
            onMove: (_, position) => _moveImageDropCaret(position),
            onLeave: _clearMediaDropIndicator,
            onDrop: (image, position) {
              final offset = _imageDropOffset(position);
              _clearMediaDropIndicator();
              if (offset != null) {
                _media.moveImageToOffset(image, offset);
              }
            },
            child: Stack(
              key: _stackKey,
              clipBehavior: Clip.none,
              children: [
                if (!widget.composer.singleNewlineParagraphs)
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
                  listenable: Listenable.merge([_media, _mediaDropPosition]),
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
    },
  );
}

class _ComposerEditorScrollBehavior extends MaterialScrollBehavior {
  const _ComposerEditorScrollBehavior(this.controller);

  final ScrollController controller;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (!identical(details.controller, controller)) {
      return super.buildScrollbar(context, child, details);
    }
    // The editor owns its scrollbar outside the quote decoration's gutter.
    // Embedded editors retain their own scroll decoration.
    return child;
  }
}

/// Widget-bound selection geometry kept separate from composer state.
///
/// This helper intentionally schedules after layout; unlike application
/// controllers, it is owned and disposed by the editor State object.
final class _ComposerSelectionOverlay {
  _ComposerSelectionOverlay({
    required ComposerController composer,
    required this.scroll,
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
  TextEditingValue? _dismissedValue;

  void dismiss() {
    if (_disposed) return;
    _dismissedValue = _composer.value;
    _syncToken = null;
    anchor.value = null;
    if (portal.isShowing) portal.hide();
  }

  void _attach() {
    _composer.addListener(sync);
    _composer.text.addListener(sync);
    _composer.focus.addListener(_editorFocusChanged);
    scroll.addListener(sync);
  }

  void _editorFocusChanged() {
    if (_composer.focus.hasFocus) SurfaceOpeningTrace.mark('composer.focus');
    sync();
  }

  void _detach() {
    _composer.removeListener(sync);
    _composer.text.removeListener(sync);
    _composer.focus.removeListener(_editorFocusChanged);
    scroll.removeListener(sync);
  }

  void replaceComposer(ComposerController composer) {
    if (_disposed || identical(_composer, composer)) return;
    _detach();
    _composer = composer;
    _lastQuoteSelection = composer.text.selection;
    _normalizingQuoteSelection = false;
    _toolbarFocused = false;
    _dismissedValue = null;
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
        left,
        bottom - lineHeight,
        math.max(1, right - left),
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
      _composer.value != _dismissedValue &&
      selection.isValid &&
      !selection.isCollapsed &&
      _composer.text.keyboardSelectedProjection == null &&
      !selectionTouchesComposerQuote(_composer.text.quoteBlocks, selection);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _syncToken = null;
    _detach();
    anchor.dispose();
  }
}

class _ComposerVerticalArrowAction
    extends Action<DirectionalCaretMovementIntent> {
  _ComposerVerticalArrowAction(this.move);

  final bool Function(bool forward) move;

  @override
  Object? invoke(DirectionalCaretMovementIntent intent) {
    if (intent.collapseSelection && move(intent.forward)) return null;
    return callingAction?.invoke(intent);
  }

  @override
  bool isEnabled(DirectionalCaretMovementIntent intent) =>
      callingAction?.isEnabled(intent) ?? false;

  @override
  bool consumesKey(DirectionalCaretMovementIntent intent) =>
      callingAction?.consumesKey(intent) ?? false;
}

class _ComposerLineStartAction<T extends DirectionalCaretMovementIntent>
    extends Action<T> {
  _ComposerLineStartAction(this._editable);

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
    var selection = composerBlockquoteLineStartSelection(before, after);
    if (editable.widget.controller case MarkdownEditingController(
      enableTodos: true,
    )) {
      selection = composerTodoLineStartSelection(
        before,
        after.copyWith(selection: selection),
      );
    }
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
  _ComposerPasteAction(this._paste);

  final Future<bool> Function() _paste;

  @override
  Object? invoke(PasteTextIntent intent) {
    final fallback = callingAction;
    return _invoke(intent, fallback);
  }

  Future<Object?> _invoke(
    PasteTextIntent intent,
    Action<PasteTextIntent>? fallback,
  ) async {
    if (await _paste()) return null;
    return fallback?.invoke(intent);
  }

  @override
  bool isEnabled(PasteTextIntent intent) =>
      callingAction?.isEnabled(intent) ?? true;

  @override
  bool consumesKey(PasteTextIntent intent) =>
      callingAction?.consumesKey(intent) ?? true;
}

class _ImageComposerMenu extends StatelessWidget {
  const _ImageComposerMenu({
    required this.image,
    required this.gallery,
    required this.alt,
    required this.onSaveAlt,
    required this.onScale,
    required this.onDelete,
  });

  final ComposerImageBlock image;
  final ComposerImageGalleryBlock? gallery;
  final TextEditingController alt;
  final VoidCallback onSaveAlt;
  final void Function(int scale) onScale;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const scales = [50, 75, 100];
    final scale = scales.contains(image.scale) ? image.scale! : 100;
    final scaleIndex = scales.indexOf(scale);
    return TextFieldTapRegion(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (gallery == null) ...[
                DButton.iconOnly(
                  onPressed: scaleIndex > 0
                      ? () => onScale(scales[scaleIndex - 1])
                      : null,
                  variant: DButtonVariant.ghost,
                  tooltip: 'Decrease image size',
                  icon: const Icon(Icons.zoom_out),
                ),
                Text('$scale%', style: Theme.of(context).textTheme.labelMedium),
                DButton.iconOnly(
                  onPressed: scaleIndex < scales.length - 1
                      ? () => onScale(scales[scaleIndex + 1])
                      : null,
                  variant: DButtonVariant.ghost,
                  tooltip: 'Increase image size',
                  icon: const Icon(Icons.zoom_in),
                ),
              ],
              const Spacer(),
              DButton.iconOnly(
                onPressed: onDelete,
                variant: DButtonVariant.ghost,
                tooltip: 'Delete image',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: DSpacing.xs),
          DInput(
            controller: alt,
            semanticLabel: 'Image description',
            hintText: 'Add image description',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSaveAlt(),
            suffix: DButton.iconOnly(
              onPressed: onSaveAlt,
              variant: DButtonVariant.ghost,
              tooltip: 'Save alt text',
              icon: const Icon(Icons.check),
            ),
          ),
        ],
      ),
    );
  }
}

enum _GalleryAddChoice { upload, existing }

class _GalleryComposerMenu extends StatelessWidget {
  static double controlExtent(BuildContext context) =>
      DControlStyle.scaledHeight(
        DControlSize.regular,
        MediaQuery.textScalerOf(context),
        context: context,
      );

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
            height: controlExtent(context),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: controlExtent(context) * 4,
                height: controlExtent(context),
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
                          visualStyle: DToggleVisualStyle(),
                        ),
                        DToggleGroupItem.iconOnly(
                          value: ComposerGalleryMode.carousel,
                          semanticLabel: 'Carousel gallery mode',
                          tooltip: 'Carousel gallery mode',
                          icon: Icon(Icons.view_carousel_outlined, size: 18),
                          selectedIcon: Icon(Icons.view_carousel, size: 18),
                          visualStyle: DToggleVisualStyle(),
                        ),
                      ],
                    ),
                    Builder(
                      builder: (menuContext) {
                        void onSelect(Object? choice) {
                          switch (choice) {
                            case _GalleryAddChoice.upload:
                              onUploadImages();
                            case _GalleryAddChoice.existing:
                              onAddExistingImages();
                          }
                        }

                        return Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: DDropdownMenu(
                            content: DDropdownMenuContent(
                              semanticLabel: 'Add images to gallery',
                              width: 280,
                              children: [
                                DDropdownMenuItem(
                                  onPressed: canUpload
                                      ? () => onSelect(_GalleryAddChoice.upload)
                                      : null,
                                  leading: const Icon(Icons.upload_outlined),
                                  child: const Text('Upload new images'),
                                ),
                                DDropdownMenuItem(
                                  onPressed: hasStandaloneImages
                                      ? () =>
                                            onSelect(_GalleryAddChoice.existing)
                                      : null,
                                  leading: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  child: const Text(
                                    'Add existing draft images',
                                  ),
                                ),
                              ],
                            ),
                            child: DDropdownMenuTrigger(
                              builder: (triggerContext, state) =>
                                  DButton.iconOnly(
                                    tooltip: 'Add images to gallery',
                                    variant: DButtonVariant.ghost,
                                    icon: pickingImages
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: DSpinner(),
                                          )
                                        : const Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 18,
                                          ),
                                    focusNode: state.focusNode,
                                    hasPopup: true,
                                    expanded: state.open,
                                    onPressed: !pickingImages
                                        ? state.toggle
                                        : null,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
                    DButton.iconOnly(
                      onPressed: onUnwrap,
                      variant: DButtonVariant.ghost,
                      tooltip: 'Remove gallery, keep images',
                      icon: const Icon(Icons.grid_off_outlined),
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
  Widget build(BuildContext context) {
    final composer = this.composer.activeEditor;
    return TextFieldTapRegion(
      child: Semantics(
        key: const ValueKey('composer-formatting'),
        container: true,
        label: 'Formatting',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
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
                variant: DButtonVariant.transparentBackground,
                foregroundColor: _composerToolForeground(context),
                size: _composerToolbarSize(context),
                icon: DIcon(icon),
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
              variant: DButtonVariant.transparentBackground,
              foregroundColor: _composerToolForeground(context),
              size: _composerToolbarSize(context),
              icon: const DIcon(DIcons.link),
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
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.composer,
    required this.pickFiles,
    required this.pickImages,
  });

  final ComposerController composer;
  final ComposerFilePicker pickFiles;
  final ComposerImagePicker? pickImages;

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
    final composer = this.composer.activeEditor;
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final actions = registry.composerToolbar(context, composer);
    final options = registry.composerOptions(context, composer);
    final emojiEnabled =
        !composer.target.isTaxonomyEdit &&
        ShellScope.read(
          context,
        ).siteConfigFor(composer.target.siteUrl).emojiEnabled;
    final uploadsEnabled = composer.imageUploader != null;
    return _ComposerToolbarOverflow(
      children: [
        _FormattingToolbar(composer: this.composer),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: DSeparator(orientation: Axis.vertical, length: 20),
        ),
        if (uploadsEnabled)
          _ComposerUploadButton(
            composer: composer,
            pickFiles: pickFiles,
            pickImages: pickImages,
          ),
        if (emojiEnabled)
          EmojiPickerAnchor(
            child: Builder(
              builder: (buttonContext) => DButton.iconOnly(
                key: const ValueKey('composer-emoji-picker'),
                tooltip: 'Add emoji',
                variant: DButtonVariant.transparentBackground,
                foregroundColor: _composerToolForeground(context),
                size: _composerToolbarSize(context),
                onPressed: !composer.isEditing
                    ? null
                    : () => unawaited(
                        openEmojiPickerForTopicComposer(
                          context: buttonContext,
                          composer: composer,
                        ),
                      ),
                icon: const DIcon(DIcons.farFaceSmile),
              ),
            ),
          ),
        if (!composer.target.isPlugin || actions.isNotEmpty)
          DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'Insert',
              side: DPopoverSide.top,
              width: 240,
              children: [
                if (!composer.target.isPlugin)
                  DDropdownMenuItem(
                    onPressed: composer.isEditing
                        ? () => insertComposerTable(composer)
                        : null,
                    child: const Text('Table'),
                  ),
                if (!composer.target.isPlugin)
                  DDropdownMenuItem(
                    onPressed: composer.isEditing
                        ? () => insertComposerDetails(composer)
                        : null,
                    child: const Text('Details'),
                  ),
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
                variant: DButtonVariant.transparentBackground,
                foregroundColor: _composerToolForeground(context),
                size: _composerToolbarSize(context),
                onPressed: composer.isEditing ? trigger.toggle : null,
                icon: const DIcon(DIcons.plus),
              ),
            ),
          ),
        if (options.isNotEmpty)
          DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'Composer options',
              side: DPopoverSide.top,
              align: DPopoverAlign.end,
              children: options,
            ),
            child: DDropdownMenuTrigger(
              builder: (context, trigger) => DButton.iconOnly(
                key: const ValueKey('composer-options'),
                tooltip: 'More',
                hasPopup: true,
                expanded: trigger.open,
                focusNode: trigger.focusNode,
                variant: DButtonVariant.transparentBackground,
                foregroundColor: _composerToolForeground(context),
                size: _composerToolbarSize(context),
                onPressed: composer.isEditing ? trigger.toggle : null,
                icon: const DIcon(DIcons.ellipsis),
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
      alignment: AlignmentDirectional.centerEnd,
      children: [
        SingleChildScrollView(
          key: const ValueKey('composer-toolbar-scroll'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: widget.children,
          ),
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
    final pointsRight = forward == (textDirection == TextDirection.ltr);
    final fadeColor = _composerFooterColor(context);

    return Container(
      width:
          DControlStyle.scaledHeight(
            _composerToolbarSize(context),
            MediaQuery.textScalerOf(context),
            context: context,
          ) +
          DSpacing.xs,
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
        icon: DIcon(pointsRight ? DIcons.chevronRight : DIcons.chevronLeft),
        variant: DButtonVariant.transparentBackground,
        foregroundColor: _composerToolForeground(context),
        size: _composerToolbarSize(context),
      ),
    );
  }
}

class _ComposerUploadButton extends StatefulWidget {
  const _ComposerUploadButton({
    required this.composer,
    required this.pickFiles,
    required this.pickImages,
  });

  final ComposerController composer;
  final ComposerFilePicker pickFiles;
  final ComposerImagePicker? pickImages;

  @override
  State<_ComposerUploadButton> createState() => _ComposerUploadButtonState();
}

class _ComposerUploadButtonState extends State<_ComposerUploadButton> {
  bool _picking = false;

  Future<void> _pick(ComposerFilePicker picker, {required bool photos}) async {
    final composer = widget.composer;
    if (!composer.canUpload || _picking) return;
    // The dialog takes focus, so a later selection is not where the user
    // asked for the files; later edits to the text still move that place.
    final selection = composer.text.selection;
    final measuredAgainst = composer.text.text;
    final offset = selection.isValid
        ? selection.extentOffset
        : measuredAgainst.length;
    setState(() => _picking = true);
    try {
      final files = await picker();
      if (!mounted ||
          !identical(widget.composer, composer) ||
          !composer.canUpload) {
        return;
      }
      composer.addFiles(files, composer.rebaseOffset(measuredAgainst, offset));
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: photos ? 'composer.pickImages' : 'composer.pickFiles',
        source: 'platform',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      if (mounted &&
          identical(widget.composer, composer) &&
          composer.canUpload) {
        composer.showNotice(
          photos
              ? "Couldn't open the photo library."
              : "Couldn't open the file picker.",
        );
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
  Widget build(BuildContext context) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: 'Upload',
      side: DPopoverSide.top,
      children: [
        DDropdownMenuItem(
          key: const ValueKey('composer-upload-files'),
          onPressed: widget.composer.canUpload && !_picking
              ? () => unawaited(_pick(widget.pickFiles, photos: false))
              : null,
          child: const Text('Files'),
        ),
        DDropdownMenuItem(
          key: const ValueKey('composer-upload-photos'),
          onPressed: widget.composer.canUpload && !_picking
              ? () => unawaited(
                  _pick(
                    widget.pickImages ??
                        _sitePhotoLibrary(context, widget.composer),
                    photos: true,
                  ),
                )
              : null,
          child: const Text('Photo Library'),
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, trigger) => DButton.iconOnly(
        key: const ValueKey('composer-upload'),
        tooltip: 'Upload',
        onPressed: !widget.composer.canUpload || _picking
            ? null
            : trigger.toggle,
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        icon: const DIcon(DIcons.paperclip),
        variant: DButtonVariant.transparentBackground,
        foregroundColor: _composerToolForeground(context),
        size: _composerToolbarSize(context),
      ),
    ),
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
          return ComposerUploadAttachment(
            composer: composer,
            upload: composer.uploads[index],
          );
        },
      ),
    );
  }
}

Color _composerFooterColor(BuildContext context) =>
    ForumWindowBackground.footerColor(
      context,
      DTokens.of(context).footerBackground,
    );

class _Footer extends StatelessWidget {
  const _Footer({
    required this.composer,
    required this.onCancel,
    required this.sideDocked,
    required this.pickFiles,
    required this.pickImages,
    required this.message,
    required this.isError,
    required this.announce,
    required this.busy,
    required this.label,
    required this.onSubmit,
  });

  final ComposerController composer;
  final VoidCallback onCancel;
  final bool sideDocked;
  final ComposerFilePicker pickFiles;
  final ComposerImagePicker? pickImages;
  final String? message;
  final bool isError;

  /// Whether [message] reports the outcome of something just done — a submit,
  /// a pick, a discard — which lands away from focus and must be spoken. A
  /// standing taxonomy requirement is not news, and a draft-save failure is
  /// already announced by the header.
  final bool announce;
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
    final tokens = DTokens.of(context);
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final pluginControls = registry.composerFooter(context, composer);

    final status = message == null
        ? const SizedBox.shrink()
        : Semantics(
            container: true,
            liveRegion: announce,
            child: Text(
              message!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
    final toolbar = composer.target.isTaxonomyEdit
        ? null
        : _Toolbar(
            composer: composer,
            pickFiles: pickFiles,
            pickImages: pickImages,
          );
    final controls = LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth <
            (620 + pluginControls.length * 120) *
                MediaQuery.textScalerOf(context).scale(14) /
                14;
        // Native image pickers outlive a resize, so the toolbar keeps its state.
        return ComposerFooterLayout(
          compact: compact,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (!context.isTouch)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              size: DButtonSize.action,
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
                                    ? DIcons.plus
                                    : DIcons.reply,
                              ),
                            )
                          : DButton(
                              key: const ValueKey('composer-submit'),
                              size: DButtonSize.action,
                              onPressed: busy ? null : onSubmit,
                              loading: busy,
                              semanticLabel: label,
                              icon: DIcon(
                                composer.whisper
                                    ? DIcons.farEyeSlash
                                    : composer.target.isEdit
                                    ? DIcons.check
                                    : composer.target.isNewTopic
                                    ? DIcons.plus
                                    : DIcons.reply,
                              ),
                              label: Text(label),
                            ),
                    ),
                    const SizedBox(width: 8),
                    DButton.iconOnly(
                      key: const ValueKey('composer-cancel'),
                      onPressed: onCancel,
                      variant: DButtonVariant.destructive,
                      shape: DButtonShape.pill,
                      size: DButtonSize.action,
                      backgroundColor: Color.lerp(
                        tokens.background,
                        tokens.destructive,
                        .25,
                      ),
                      interactiveBackgroundColor: Color.lerp(
                        tokens.background,
                        tokens.destructive,
                        .32,
                      ),
                      foregroundColor: Color.lerp(
                        tokens.foreground,
                        tokens.destructive,
                        .5,
                      ),
                      tooltip: 'Discard',
                      icon: const DIcon(DIcons.trashCan),
                    ),
                    for (final control in pluginControls)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: control,
                      ),
                  ],
                ),
              if (context.isTouch && pluginControls.isNotEmpty)
                Wrap(spacing: DSpacing.controlGap, children: pluginControls),
              if (toolbar != null)
                Flexible(
                  fit: FlexFit.tight,
                  child: context.isTouch
                      ? DCard(
                          key: const ValueKey('composer-toolbar-bar'),
                          variant: DCardVariant.capsule,
                          spacing: 0,
                          child: toolbar,
                        )
                      : toolbar,
                ),
            ],
          ),
        );
      },
    );

    return Container(
      key: const ValueKey('composer-footer'),
      decoration: BoxDecoration(
        color: context.isTouch ? null : _composerFooterColor(context),
        border: context.isTouch
            ? null
            : Border(top: BorderSide(color: tokens.footerBorder)),
      ),
      padding: EdgeInsets.fromLTRB(
        DSpacing.lg,
        context.isTouch ? 0 : 10,
        DSpacing.lg,
        10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null) ...[
            Align(alignment: AlignmentDirectional.centerStart, child: status),
            const SizedBox(height: 4),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: sideDocked && !context.isTouch
                  ? topicBottomBarHeight(context)
                  : 0,
            ),
            child: controls,
          ),
        ],
      ),
    );
  }
}
