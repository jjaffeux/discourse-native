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
    this.onEdit,
  });

  final ComposerImageGalleryBlock gallery;
  final List<ComposerImageGalleryItem> items;
  final String? siteUrl;
  final VoidCallback? onEdit;

  static const double tileExtent = 56;
  static const double gap = 6;
  static const double inset = 8;
  static const double verticalMargin = 4;
  // Three tiles plus the gallery control fit inside the compact 280px
  // composer, keeping the common three-image gallery to one visible row.
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

  /// The exact inline size used by the projection, including its margin.
  /// Keeping this independent of image decoding lets the editable reserve the
  /// same scroll height before and after the artwork arrives.
  static Size displaySize(int itemCount) {
    final tiles = _tileAreaSize(itemCount);
    final contentWidth =
        tiles.width +
        (itemCount == 0 ? 0 : gap) +
        ComposerImageGalleryControl.extent;
    final contentHeight = math.max(
      tiles.height,
      ComposerImageGalleryControl.extent,
    );
    return Size(
      inset * 2 + contentWidth,
      verticalMargin * 2 + inset * 2 + contentHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = displaySize(items.length);
    final tileArea = _tileAreaSize(items.length);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          // Let EditableText receive pointer events over the gallery artwork.
          // It uses the independently keyed tile bounds to select a member.
          // The edit control is overlaid below and remains directly tappable.
          Positioned.fill(
            child: IgnorePointer(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                label:
                    'Image gallery, ${items.length} ${items.length == 1 ? 'image' : 'images'}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: verticalMargin),
                  child: CustomPaint(
                    foregroundPainter: _DashedGalleryBorder(
                      color: scheme.outlineVariant,
                    ),
                    child: Container(
                      width: size.width,
                      height: size.height - verticalMargin * 2,
                      padding: const EdgeInsets.all(inset),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
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
                                  for (final item in items)
                                    ComposerImageGalleryTile(
                                      item: item,
                                      siteUrl: siteUrl,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: gap),
                          ],
                          const SizedBox.square(
                            dimension: ComposerImageGalleryControl.extent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: inset,
            top: verticalMargin + inset,
            child: ComposerImageGalleryControl(
              key: const ValueKey('composer-gallery-control'),
              imageCount: items.length,
              onEdit: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}

/// The gallery-level target that opens membership and layout controls.
///
/// Keeping this target outside every keyed image tile makes direct and
/// editor-level hit-testing unambiguous. [onEdit] also gives assistive
/// technologies a real activation action instead of a button-shaped label.
class ComposerImageGalleryControl extends StatelessWidget {
  const ComposerImageGalleryControl({
    super.key,
    required this.imageCount,
    this.onEdit,
  });

  final int imageCount;
  final VoidCallback? onEdit;

  static const double extent = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = '$imageCount ${imageCount == 1 ? 'image' : 'images'}';

    return MergeSemantics(
      child: Semantics(
        label: 'Edit image gallery',
        hint: '$count. Add or remove images.',
        child: IconButton(
          onPressed: onEdit,
          constraints: const BoxConstraints.tightFor(
            width: extent,
            height: extent,
          ),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(extent),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: scheme.primaryContainer.withValues(alpha: 0.45),
            disabledBackgroundColor: scheme.primaryContainer.withValues(
              alpha: 0.45,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          icon: SizedBox.square(
            dimension: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 22,
                  color: scheme.onPrimaryContainer,
                ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Icon(
                    Icons.edit,
                    size: 12,
                    color: scheme.onPrimaryContainer,
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

/// A square, independently keyed image within a composer gallery.
class ComposerImageGalleryTile extends StatelessWidget {
  const ComposerImageGalleryTile({super.key, required this.item, this.siteUrl});

  final ComposerImageGalleryItem item;
  final String? siteUrl;

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
              color: item.highlighted ? scheme.primary : scheme.outlineVariant,
              width: item.highlighted ? 2 : 1,
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

class _DashedGalleryBorder extends CustomPainter {
  const _DashedGalleryBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

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
  bool shouldRepaint(_DashedGalleryBorder oldDelegate) =>
      oldDelegate.color != color;
}
