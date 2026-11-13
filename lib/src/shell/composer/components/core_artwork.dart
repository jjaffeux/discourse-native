import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../../models/found_hashtag.dart';
import '../../../models/pdf_attachment_type.dart';
import '../../../plugin_api/composer_syntax.dart';
import '../../../plugin_api/hashtag_kind.dart';
import '../../hashtag.dart';
import '../../hashtag_presentation.dart';
import '../../inline_video.dart';
import '../../mention.dart';
import '../../skeleton_fill.dart';
import '../block_selection.dart';
import '../component_artwork.dart';
import '../controller.dart';
import '../upload_attachment.dart';
import 'code_editor.dart';
import 'code_source.dart';
import 'details_editor.dart';
import 'details_source.dart';
import 'document_body_controller.dart';
import 'document_body_editor.dart';
import 'gallery.dart';
import 'gallery_source.dart';
import 'image.dart';
import 'image_source.dart';
import 'link_dialog.dart';
import 'link_pill.dart';
import 'link_source.dart';
import 'list_item_editor.dart';
import 'list_source.dart';
import 'quote.dart';
import 'table_editor.dart';
import 'table_source.dart';
import 'todo_marker.dart';

/// The artwork a composer editor installs: each core component drawn with
/// the widget tree it owned before the controllers stopped importing it.
final class CoreComposerArtwork
    implements ComposerComponentArtwork<ComposerController> {
  const CoreComposerArtwork();

  @override
  Widget image({
    required ComposerImageBlock image,
    required String? url,
    required String? siteUrl,
    required bool highlighted,
    required ValueChanged<Size> onNaturalSize,
    required VoidCallback? onDragStarted,
    required VoidCallback onDragEnded,
  }) => ComposerImagePreview(
    image: image,
    url: url,
    siteUrl: siteUrl,
    highlighted: highlighted,
    onNaturalSize: onNaturalSize,
    onDragStarted: onDragStarted,
    onDragEnded: onDragEnded,
  );

  @override
  Widget gallery({
    required ComposerImageGalleryBlock gallery,
    required String? siteUrl,
    required bool highlighted,
    required String? Function(ComposerImageBlock image) resolveUrl,
    required Key Function(ComposerImageBlock image) imageKey,
    required bool Function(ComposerImageBlock image) imageHighlighted,
    required void Function(ComposerImageBlock image, Size size) onNaturalSize,
    required VoidCallback? onEdit,
    required void Function(ComposerImageBlock image, int index)? onReorder,
    required ValueChanged<ComposerImageBlock> onReorderStarted,
    required ValueChanged<ComposerImageBlock> onReorderEnded,
  }) => ComposerImageGalleryPreview(
    gallery: gallery,
    items: [
      for (final image in gallery.images)
        ComposerImageGalleryItem(
          image: image,
          url: resolveUrl(image),
          imageKey: imageKey(image),
          highlighted: imageHighlighted(image),
          onNaturalSize: (size) => onNaturalSize(image, size),
        ),
    ],
    siteUrl: siteUrl,
    highlighted: highlighted,
    onEdit: onEdit,
    onReorder: onReorder,
    onReorderStarted: onReorderStarted,
    onReorderEnded: onReorderEnded,
  );

  @override
  Widget quote({
    required ComposerQuoteBlock block,
    required String contents,
    required String? siteUrl,
    required TextStyle baseStyle,
    required GlobalKey removeKey,
    required bool selected,
    required VoidCallback? onRemove,
  }) => ComposerBlockSelection(
    selected: selected,
    child: IgnorePointer(
      child: ComposerQuotePreview(
        block: block,
        onRemove: onRemove,
        contents: contents,
        siteUrl: siteUrl,
        baseStyle: baseStyle,
        removeKey: removeKey,
      ),
    ),
  );

  @override
  Widget mention({required String label, required TextStyle baseStyle}) =>
      MentionPill(label: label, baseStyle: baseStyle);

  @override
  Widget hashtag({
    required String label,
    required FoundHashtag hashtag,
    required TextStyle baseStyle,
    required String? siteUrl,
    required PluginHashtagPresentationResolver? pluginPresentation,
  }) => HashtagPill(
    label: label,
    baseStyle: baseStyle,
    presentation: resolveHashtagPresentation(
      HashtagPresentationRequest(
        type: hashtag.type,
        style: HashtagStyle.parse(hashtag.styleType),
        icon: hashtag.icon,
        emoji: hashtag.emoji,
        colorValues: hashtag.colorValues,
      ),
      pluginPresentation: pluginPresentation,
    ),
    siteUrl: siteUrl,
  );

  @override
  Widget link({
    required Key key,
    required String anchor,
    required String url,
    required TextStyle baseStyle,
    required bool highlighted,
    required bool hovered,
    required String? siteUrl,
    required String? Function(String url)? resolveUploadUrl,
  }) => IgnorePointer(
    child: ComposerLinkPill(
      key: key,
      anchor: anchor,
      url: url,
      baseStyle: baseStyle,
      highlighted: highlighted,
      hovered: hovered,
      siteUrl: siteUrl,
      previewUrl: isPdfAttachment(anchor, url)
          ? resolveUploadUrl?.call(url)
          : null,
    ),
  );

  @override
  Future<void> editLink(
    BuildContext context,
    ComposerEditorHost editor,
    ComposerLinkBlock link,
  ) => showComposerLinkDialog(context: context, composer: editor, link: link);

  @override
  Widget keyboardKey({required String semanticLabel, required Widget child}) =>
      DKbd.child(semanticLabel: semanticLabel, child: child);

  @override
  Widget todoMarker({
    required bool checked,
    required String label,
    required TextStyle style,
    required VoidCallback? onChanged,
  }) => ComposerTodoMarker(
    checked: checked,
    label: label,
    style: style,
    onChanged: onChanged,
  );

  @override
  Widget codeBlock({
    required Key key,
    required ComposerController composer,
    required ComposerCodeBlock block,
    required bool highlighted,
    required VoidCallback? onSelect,
  }) => ComposerBlockSelection(
    selected: highlighted,
    onPressed: onSelect,
    child: ComposerCodeBlockEditor(key: key, composer: composer, block: block),
  );

  @override
  Widget details({
    required Key key,
    required ComposerController composer,
    required ComposerDetailsBlock block,
    required bool highlighted,
  }) => ComposerBlockSelection(
    selected: highlighted,
    child: ComposerDetailsEditor(key: key, composer: composer, block: block),
  );

  @override
  Widget table({
    required Key key,
    required ComposerController composer,
    required ComposerTableBlock table,
    required bool highlighted,
  }) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: (constraints.maxWidth - _caretMargin(context)).clamp(
        0,
        double.infinity,
      ),
      // WidgetSpan scales the whole table with the surrounding text.
      // Do not apply the inherited scaler again inside its controls.
      child: MediaQuery.withNoTextScaling(
        child: ComposerTableEditor(
          key: key,
          composer: composer,
          table: table,
          selected: highlighted,
        ),
      ),
    ),
  );

  @override
  Widget listItem({
    required Key key,
    required ComposerController composer,
    required ComposerListItem item,
    required bool highlighted,
    required ScrollController? scrollController,
  }) => ComposerBlockSelection(
    selected: highlighted,
    child: ComposerListItemEditor(
      key: key,
      composer: composer,
      item: item,
      scrollController: scrollController,
    ),
  );

  @override
  Widget upload({
    required Key key,
    required ComposerController composer,
    required int id,
    required bool highlighted,
  }) => ComposerBlockSelection(
    selected: highlighted,
    child: ListenableBuilder(
      key: key,
      listenable: composer.uploadChanges,
      builder: (context, _) {
        final upload = composer.uploads
            .where((upload) => upload.id == id)
            .firstOrNull;
        if (upload == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ComposerUploadAttachment(
            key: ValueKey('composer-inline-upload-$id'),
            composer: composer,
            upload: upload,
          ),
        );
      },
    ),
  );

  @override
  Widget video({
    required Key key,
    required String? url,
    required String title,
    required String? siteUrl,
    required bool highlighted,
  }) {
    final data = url == null
        ? null
        : InlineVideoData.fromUpload(
            url: url,
            title: title,
            siteUrl: siteUrl ?? '',
          );
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: math.min(
          (constraints.maxWidth - _caretMargin(context)).clamp(
            0,
            double.infinity,
          ),
          190 * (data?.aspectRatio ?? 16 / 9),
        ),
        child: MediaQuery.withNoTextScaling(
          child: ComposerBlockSelection(
            key: key,
            selected: highlighted,
            child: data == null
                ? DSkeletonRegion(
                    semanticsLabel: context.l10n.loading,
                    color: skeletonFill(context),
                    child: const DSkeleton(height: 190),
                  )
                : InlineVideo(
                    data: data,
                    siteUrl: siteUrl,
                    maximumHeight: 190,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget embeddedDocument({
    required Key key,
    required ComposerController parent,
    required ComposerDocumentBodyRange range,
    required ComposerDocumentBodyRange? Function(String document, int start)
    resolveRange,
    required String semanticLabel,
  }) => ComposerDocumentBodyEditor(
    key: key,
    parent: parent,
    range: range,
    resolveRange: resolveRange,
    semanticLabel: semanticLabel,
  );

  /// RenderEditable reserves a one-pixel gap plus the cursor width for text,
  /// but measures inline widgets against the full viewport.
  static double _caretMargin(BuildContext context) =>
      (context.findAncestorWidgetOfExactType<EditableText>()?.cursorWidth ??
          2) +
      1;
}
