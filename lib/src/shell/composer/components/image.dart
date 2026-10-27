import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../../theme/d_icons.dart';
import '../../../theme/d_native_icons.dart';
import '../../image_decode.dart';
import '../../server_image.dart';
import '../../shell_scope.dart';
import '../../site_image.dart';
import '../../skeleton_fill.dart';
import '../media_editing_coordinator.dart';
import '../source_projection.dart';
import 'gallery_source.dart';
import 'image_source.dart';

List<InlineSpan> buildComposerImageSpans({
  required String source,
  required ComposerImageBlock image,
  required TextStyle baseStyle,
  required Key imageKey,
  required String? url,
  required String? siteUrl,
  required bool highlighted,
  required bool trailingCaretLine,
  required ValueChanged<Size> onNaturalSize,
  required VoidCallback? onDragStarted,
  required VoidCallback onDragEnded,
}) => [
  WidgetSpan(
    alignment: PlaceholderAlignment.top,
    style: baseStyle,
    child: KeyedSubtree(
      key: imageKey,
      child: ComposerImagePreview(
        image: image,
        url: url,
        siteUrl: siteUrl,
        highlighted: highlighted,
        onNaturalSize: onNaturalSize,
        onDragStarted: onDragStarted,
        onDragEnded: onDragEnded,
      ),
    ),
  ),
  ...composerCollapsedBlockSourceTail(
    source: source,
    start: image.start,
    end: image.end,
    baseStyle: baseStyle,
    trailingCaretLine: trailingCaretLine,
  ),
];

class ComposerImagePreview extends StatelessWidget {
  const ComposerImagePreview({
    super.key,
    required this.image,
    required this.url,
    required this.onNaturalSize,
    this.siteUrl,
    this.highlighted = false,
    this.onDragStarted,
    this.onDragEnded,
  });

  final ComposerImageBlock image;
  final String? url;
  final String? siteUrl;
  final void Function(Size size) onNaturalSize;
  final bool highlighted;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  static Size displaySize(ComposerImageBlock image) {
    final sourceSize =
        safeImageLayoutSize(
          image.width?.toDouble(),
          image.height?.toDouble(),
        ) ??
        const Size(360, 360 / (16 / 9));
    final sourceWidth = sourceSize.width;
    final sourceHeight = sourceSize.height;
    final suppliedScale = image.scale;
    final scale =
        suppliedScale != null && suppliedScale >= 1 && suppliedScale <= 100
        ? suppliedScale / 100
        : 1.0;
    final bound = [
      460 / sourceWidth,
      190 / sourceHeight,
      1.0,
    ].reduce((a, b) => a < b ? a : b);
    return Size(
      (sourceWidth * bound * scale).clamp(0.0, 460.0),
      (sourceHeight * bound * scale).clamp(0.0, 190.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = displaySize(image);
    // Repository bytes can be measured without a full-size image stream.
    // Keep the network fallback's shared measurement/display request intact.
    final boundedDecode =
        image.hasDimensions ||
        (siteUrl != null && ShellScope.maybeIdentityOf(context) != null);
    final source = url;
    final borderRadius = BorderRadius.circular(8);
    final border = Border.all(
      color: highlighted
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.outlineVariant,
      width: highlighted ? 2 : 1,
    );

    final preview = Semantics(
      image: true,
      label: image.alt.isEmpty ? context.l10n.image : image.alt,
      selected: highlighted,
      child: Container(
        width: size.width,
        height: size.height,
        // Reserve the selected stroke's full inset in both states. Letting
        // the one-pixel idle border define this padding makes the image itself
        // shrink and grow whenever selection changes.
        padding: const EdgeInsets.all(2),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: borderRadius,
          border: border,
        ),
        child: ClipRRect(
          borderRadius: borderRadius.subtract(BorderRadius.circular(2)),
          child: source == null
              ? _ImageFallback(label: image.alt)
              : SiteImage(
                  url: source,
                  siteUrl: siteUrl,
                  fit: BoxFit.cover,
                  cacheWidth: boundedDecode
                      ? imagePhysicalPixels(context, size.width)
                      : null,
                  cacheHeight: boundedDecode
                      ? imagePhysicalPixels(context, size.height)
                      : null,
                  onNaturalSize: image.hasDimensions ? null : onNaturalSize,
                  excludeFromSemantics: true,
                  loadingBuilder: (context) => DSkeletonRegion(
                    semanticsLabel: context.l10n.loading,
                    color: skeletonFill(context, on: SkeletonSurface.panel),
                    child: const DSkeleton(),
                  ),
                  errorBuilder: (_, _, _) => _ImageFallback(label: image.alt),
                ),
        ),
      ),
    );
    if (onDragStarted == null) return preview;
    return Draggable<ComposerImageBlock>(
      data: image,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnded?.call(),
      feedback: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.9, child: preview),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: preview),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: preview),
    );
  }
}

@visibleForTesting
ImageProvider<Object> composerPreviewImageProvider(
  BuildContext context, {
  required String url,
  required Size logicalSize,
  required bool measureNaturalSize,
}) {
  final provider = serverImageProvider(url);
  if (measureNaturalSize ||
      !logicalSize.width.isFinite ||
      !logicalSize.height.isFinite ||
      logicalSize.width <= 0 ||
      logicalSize.height <= 0) {
    return provider;
  }
  return ResizeImage(
    provider,
    width: imagePhysicalPixels(context, logicalSize.width),
    height: imagePhysicalPixels(context, logicalSize.height),
    policy: ResizeImagePolicy.fit,
  );
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DIcon(DNativeIcons.image, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label.isEmpty ? context.l10n.image : label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ComposerMobileImageToolbar extends StatelessWidget {
  const ComposerMobileImageToolbar({
    super.key,
    required this.media,
    required this.historyControls,
  });

  final ComposerMediaEditingCoordinator media;
  final Widget historyControls;

  @override
  Widget build(BuildContext context) {
    final state = media.value;
    final image = state.selectedImage!;
    const scales = [50, 75, 100];
    final scale = scales.contains(image.scale) ? image.scale! : 100;
    final index = scales.indexOf(scale);
    return TapRegion(
      groupId: media,
      child: TextFieldTapRegion(
        child: DCard(
          key: const ValueKey('composer-image-toolbar'),
          spacing: DSpacing.sm,
          child: DCardContent(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DSpacing.controlGap,
              children: [
                DInput(
                  key: const ValueKey('composer-image-description'),
                  controller: media.imageAlt,
                  semanticLabel: context.l10n.imageDescription,
                  hintText: context.l10n.addImageDescription,
                  prefix: const DIcon(DIcons.pen),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => media.updateImageAlt(),
                  onSubmitted: (_) => media.dismissImage(),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: DSpacing.controlGap,
                  children: [
                    historyControls,
                    if (state.selectedImageGallery == null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DButton.iconOnly(
                            onPressed: index > 0
                                ? () => media.scaleImage(
                                    scales[index - 1],
                                    requestFocus: false,
                                  )
                                : null,
                            variant: DButtonVariant.ghost,
                            tooltip: context.l10n.decreaseImageSize,
                            icon: const DIcon(DIcons.minus),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DSpacing.xs,
                            ),
                            child: Text('$scale%'),
                          ),
                          DButton.iconOnly(
                            onPressed: index < scales.length - 1
                                ? () => media.scaleImage(
                                    scales[index + 1],
                                    requestFocus: false,
                                  )
                                : null,
                            variant: DButtonVariant.ghost,
                            tooltip: context.l10n.increaseImageSize,
                            icon: const DIcon(DIcons.plus),
                          ),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DSpacing.controlGap,
                      children: [
                        DButton(
                          onPressed: media.deleteSelectedImage,
                          variant: DButtonVariant.ghost,
                          foregroundColor: DTokens.of(context).destructive,
                          tooltip: context.l10n.deleteImage,
                          semanticLabel: context.l10n.deleteImage,
                          icon: const DIcon(DIcons.trashCan),
                          label: Text(context.l10n.removeImage),
                        ),
                        DButton.iconOnly(
                          onPressed: media.dismissImage,
                          variant: DButtonVariant.ghost,
                          tooltip: context.l10n.done,
                          icon: const DIcon(DIcons.check),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ComposerImageMenu extends StatelessWidget {
  const ComposerImageMenu({
    super.key,
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
                  tooltip: context.l10n.decreaseImageSize,
                  icon: const DIcon(DIcons.minus),
                ),
                Text('$scale%', style: Theme.of(context).textTheme.labelMedium),
                DButton.iconOnly(
                  onPressed: scaleIndex < scales.length - 1
                      ? () => onScale(scales[scaleIndex + 1])
                      : null,
                  variant: DButtonVariant.ghost,
                  tooltip: context.l10n.increaseImageSize,
                  icon: const DIcon(DIcons.plus),
                ),
              ],
              const Spacer(),
              DButton.iconOnly(
                onPressed: onDelete,
                variant: DButtonVariant.ghost,
                tooltip: context.l10n.deleteImage,
                icon: const DIcon(DIcons.trashCan),
              ),
            ],
          ),
          const SizedBox(height: DSpacing.xs),
          DInput(
            controller: alt,
            semanticLabel: context.l10n.imageDescription,
            hintText: context.l10n.addImageDescription,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSaveAlt(),
            suffix: DButton.iconOnly(
              onPressed: onSaveAlt,
              variant: DButtonVariant.ghost,
              tooltip: context.l10n.saveAltText,
              icon: const DIcon(DIcons.check),
            ),
          ),
        ],
      ),
    );
  }
}
