import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'composer_images.dart';
import 'image_decode.dart';
import 'shell_scope.dart';
import 'site_image.dart';

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
      label: image.alt.isEmpty ? 'Image' : image.alt,
      selected: highlighted,
      child: Container(
        width: size.width,
        height: size.height,
        margin: const EdgeInsets.symmetric(vertical: 4),
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
        child: source == null
            ? _ImageFallback(label: image.alt)
            : SiteImage(
                url: source,
                siteUrl: siteUrl,
                fit: BoxFit.contain,
                cacheWidth: boundedDecode
                    ? imagePhysicalPixels(context, size.width)
                    : null,
                cacheHeight: boundedDecode
                    ? imagePhysicalPixels(context, size.height)
                    : null,
                onNaturalSize: image.hasDimensions ? null : onNaturalSize,
                excludeFromSemantics: true,
                loadingBuilder: (_) => const Center(child: DSpinner()),
                errorBuilder: (_, _, _) => _ImageFallback(label: image.alt),
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
  final provider = NetworkImage(url);
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
            const Icon(Icons.image_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label.isEmpty ? 'Image' : label,
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
