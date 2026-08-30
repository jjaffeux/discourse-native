import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'composer_galleries.dart';
import 'composer_images.dart';
import 'image_decode.dart';
import 'site_image.dart';

/// One image rendered inside a composer gallery.
@immutable
class ComposerImageGalleryItem {
  const ComposerImageGalleryItem({
    required this.image,
    required this.url,
    required this.imageKey,
    required this.highlighted,
    this.onNaturalSize,
  });

  final ComposerImageBlock image;
  final String? url;

  /// The controller-owned key used to hit-test this image independently of
  /// the compound gallery widget.
  final Key imageKey;
  final bool highlighted;
  final ValueChanged<Size>? onNaturalSize;
}

/// The compact, editable-composer presentation of a `[grid]` block.
///
/// This deliberately differs from the cooked post's masonry presentation:
/// every tile is square and stable while the author edits around it. The raw
/// BBCode remains in the field; the editing controller accounts for its
/// code-unit length and uses this widget only as its visual projection.
class ComposerImageGalleryPreview extends StatelessWidget {
  const ComposerImageGalleryPreview({
    super.key,
    required this.gallery,
    required this.items,
    this.siteUrl,
    this.highlighted = false,
    this.onEdit,
    this.onReorder,
  });

  final ComposerImageGalleryBlock gallery;
  final List<ComposerImageGalleryItem> items;
  final String? siteUrl;
  final bool highlighted;
  final VoidCallback? onEdit;
  final void Function(ComposerImageBlock image, int newIndex)? onReorder;

  static const double tileExtent = 56;
  static const double gap = 6;
  static const double inset = 8;
  static const double verticalMargin = 4;
  // Three tiles fit inside the compact composer, keeping the common
  // three-image gallery to one visible row.
  static const int maxColumns = 3;

  static int columnCount(int itemCount) =>
      itemCount <= 0 ? 1 : math.min(itemCount, maxColumns);

  static Size _tileAreaSize(int itemCount) {
    if (itemCount == 0) return Size.zero;
    final columns = columnCount(itemCount);
    final rows = (itemCount / columns).ceil();
    return Size(
      tileExtent * columns + gap * (columns - 1),
      tileExtent * rows + gap * (rows - 1),
    );
  }

  /// The exact inline height used by the projection, including its margin.
  /// Keeping this independent of image decoding lets the editable reserve the
  /// same scroll height before and after the artwork arrives. The width is
  /// supplied by the editable so the gallery fills the composer.
  static double displayHeight(int itemCount) {
    final tiles = _tileAreaSize(itemCount);
    final tileSpacing = itemCount == 0 ? 0 : gap;
    return verticalMargin * 2 +
        inset * 2 +
        tiles.height +
        tileSpacing +
        ComposerImageGalleryControl.extent;
  }

  @override
  Widget build(BuildContext context) {
    final height = displayHeight(items.length);
    final tileArea = _tileAreaSize(items.length);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: verticalMargin),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label:
              'Image gallery, ${items.length} ${items.length == 1 ? 'image' : 'images'}',
          selected: highlighted,
          child: CustomPaint(
            foregroundPainter: _GalleryBorder(
              color: highlighted ? scheme.primary : scheme.outlineVariant,
              highlighted: highlighted,
            ),
            child: Container(
              width: double.infinity,
              height: height - verticalMargin * 2,
              padding: const EdgeInsets.all(inset),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isNotEmpty) ...[
                    SizedBox(
                      width: tileArea.width,
                      height: tileArea.height,
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final (index, item) in items.indexed)
                            _ReorderableGalleryTile(
                              item: item,
                              index: index,
                              siteUrl: siteUrl,
                              onReorder: onReorder,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: gap),
                  ],
                  ComposerImageGalleryControl(
                    key: const ValueKey('composer-gallery-control'),
                    imageCount: items.length,
                    onEdit: onEdit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gallery-level target that opens membership and layout controls.
///
/// Keeping this target on its own line after every keyed image tile makes
/// direct and editor-level hit-testing unambiguous.
class ComposerImageGalleryControl extends StatelessWidget {
  const ComposerImageGalleryControl({
    super.key,
    required this.imageCount,
    this.onEdit,
  });

  final int imageCount;
  final VoidCallback? onEdit;

  static const double extent = 40;

  @override
  Widget build(BuildContext context) {
    final count = '$imageCount ${imageCount == 1 ? 'image' : 'images'}';

    return MergeSemantics(
      child: Semantics(
        hint: '$count. Add or remove images.',
        child: TextButton(
          onPressed: onEdit,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, extent),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Gallery options'),
        ),
      ),
    );
  }
}

class _ReorderableGalleryTile extends StatelessWidget {
  const _ReorderableGalleryTile({
    required this.item,
    required this.index,
    required this.siteUrl,
    required this.onReorder,
  });

  final ComposerImageGalleryItem item;
  final int index;
  final String? siteUrl;
  final void Function(ComposerImageBlock image, int newIndex)? onReorder;

  @override
  Widget build(BuildContext context) => DragTarget<ComposerImageBlock>(
    onWillAcceptWithDetails: (details) =>
        onReorder != null &&
        (details.data.start != item.image.start ||
            details.data.end != item.image.end),
    onAcceptWithDetails: (details) => onReorder?.call(details.data, index),
    builder: (context, candidates, _) {
      final tile = ComposerImageGalleryTile(
        item: item,
        siteUrl: siteUrl,
        dropTarget: candidates.isNotEmpty,
      );
      if (onReorder == null) return tile;
      return Draggable<ComposerImageBlock>(
        data: item.image,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            child: Opacity(
              opacity: 0.9,
              child: ComposerImageGalleryTile(
                item: ComposerImageGalleryItem(
                  image: item.image,
                  url: item.url,
                  imageKey: UniqueKey(),
                  highlighted: false,
                ),
                siteUrl: siteUrl,
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: tile),
      );
    },
  );
}

/// A square, independently keyed image within a composer gallery.
class ComposerImageGalleryTile extends StatelessWidget {
  const ComposerImageGalleryTile({
    super.key,
    required this.item,
    this.siteUrl,
    this.dropTarget = false,
  });

  final ComposerImageGalleryItem item;
  final String? siteUrl;
  final bool dropTarget;

  @override
  Widget build(BuildContext context) {
    final image = item.image;
    final source = item.url;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(6);

    return KeyedSubtree(
      key: item.imageKey,
      child: Semantics(
        image: true,
        label: image.alt.isEmpty ? 'Image' : image.alt,
        selected: item.highlighted,
        child: Container(
          width: ComposerImageGalleryPreview.tileExtent,
          height: ComposerImageGalleryPreview.tileExtent,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: radius,
            border: Border.all(
              color: item.highlighted || dropTarget
                  ? scheme.primary
                  : scheme.outlineVariant,
              width: item.highlighted || dropTarget ? 2 : 1,
            ),
          ),
          child: source == null
              ? ExcludeSemantics(
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 22,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : SiteImage(
                  url: source,
                  siteUrl: siteUrl,
                  width: ComposerImageGalleryPreview.tileExtent,
                  height: ComposerImageGalleryPreview.tileExtent,
                  fit: BoxFit.cover,
                  cacheWidth: imagePhysicalPixels(
                    context,
                    ComposerImageGalleryPreview.tileExtent,
                  ),
                  cacheHeight: imagePhysicalPixels(
                    context,
                    ComposerImageGalleryPreview.tileExtent,
                  ),
                  onNaturalSize: image.hasDimensions
                      ? null
                      : item.onNaturalSize,
                  excludeFromSemantics: true,
                  loadingBuilder: (_) => const Center(
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                  errorBuilder: (_, _, _) => ExcludeSemantics(
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _GalleryBorder extends CustomPainter {
  const _GalleryBorder({required this.color, required this.highlighted});

  final Color color;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlighted ? 2.5 : 1.5;

    if (highlighted) {
      canvas.drawPath(path, paint);
      return;
    }

    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var offset = 0.0;
      while (offset < metric.length) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + dash, metric.length)),
          paint,
        );
        offset += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_GalleryBorder oldDelegate) =>
      oldDelegate.color != color || oldDelegate.highlighted != highlighted;
}
