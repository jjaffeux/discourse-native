import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/d_button.dart';
import 'composer_galleries.dart';
import 'composer_images.dart';
import 'image_decode.dart';
import 'site_image.dart';

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

  final Key imageKey;
  final bool highlighted;
  final ValueChanged<Size>? onNaturalSize;
}

class ComposerImageGalleryPreview extends StatelessWidget {
  const ComposerImageGalleryPreview({
    super.key,
    required this.gallery,
    required this.items,
    this.siteUrl,
    this.highlighted = false,
    this.onEdit,
    this.onReorder,
    this.onReorderStarted,
    this.onReorderEnded,
    this.onLayoutHeight,
  });

  final ComposerImageGalleryBlock gallery;
  final List<ComposerImageGalleryItem> items;
  final String? siteUrl;
  final bool highlighted;
  final VoidCallback? onEdit;
  final void Function(ComposerImageBlock image, int newIndex)? onReorder;
  final ValueChanged<ComposerImageBlock>? onReorderStarted;
  final ValueChanged<ComposerImageBlock>? onReorderEnded;
  final ValueChanged<double>? onLayoutHeight;

  static const double tileExtent = 80;
  static const double gap = 6;
  static const double inset = 8;
  static const double verticalMargin = 4;

  static const int maximumGridColumns = 3;

  static double _tileStripWidth(int itemCount) =>
      itemCount == 0 ? 0 : tileExtent * itemCount + gap * (itemCount - 1);

  static int renderedGridColumnCount(int itemCount) {
    if (itemCount == 0) return 0;
    // Core renders two- and four-item galleries with two columns; all other
    // galleries use at most three columns on a wide viewport.
    if (itemCount == 2 || itemCount == 4) return 2;
    return math.min(itemCount, maximumGridColumns);
  }

  static double displayHeight(
    int itemCount, {
    ComposerGalleryMode mode = ComposerGalleryMode.grid,
    int? gridColumns,
  }) {
    final contentHeight = switch (mode) {
      ComposerGalleryMode.carousel => itemCount == 0 ? 0 : tileExtent,
      ComposerGalleryMode.grid => _gridHeight(
        itemCount,
        gridColumns ?? renderedGridColumnCount(itemCount),
      ),
    };
    return verticalMargin * 2 +
        inset * 2 +
        math.max(contentHeight, ComposerImageGalleryControl.extent);
  }

  static double _gridHeight(int itemCount, int columns) {
    if (itemCount == 0 || columns == 0) return 0;
    final rows = (itemCount / columns).ceil();
    return rows * tileExtent + (rows - 1) * gap;
  }

  static int _fittingGridColumnCount(int itemCount, double availableWidth) {
    final renderedColumns = renderedGridColumnCount(itemCount);
    if (renderedColumns == 0 || !availableWidth.isFinite) {
      return renderedColumns;
    }
    final fittingColumns = ((availableWidth + gap) / (tileExtent + gap))
        .floor()
        .clamp(1, renderedColumns);
    return math.min(renderedColumns, fittingColumns);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableTileWidth = math.max(
          0.0,
          constraints.maxWidth -
              inset * 2 -
              ComposerImageGalleryControl.extent -
              (items.isEmpty ? 0 : gap),
        );
        final gridColumns = _fittingGridColumnCount(
          items.length,
          availableTileWidth,
        );
        final height = displayHeight(
          items.length,
          mode: gallery.mode,
          gridColumns: gridColumns,
        );
        final reportHeight = onLayoutHeight;
        if (reportHeight != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => reportHeight(height),
          );
        }

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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (items.isNotEmpty) ...[
                        Expanded(
                          child: switch (gallery.mode) {
                            ComposerGalleryMode.grid => Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: _tileStripWidth(gridColumns),
                                child: Wrap(
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    for (final (index, item) in items.indexed)
                                      _galleryTile(item, index),
                                  ],
                                ),
                              ),
                            ),
                            ComposerGalleryMode.carousel =>
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: _tileStripWidth(items.length),
                                  height: tileExtent,
                                  child: Row(
                                    children: [
                                      for (final (index, item)
                                          in items.indexed) ...[
                                        if (index > 0)
                                          const SizedBox(width: gap),
                                        _galleryTile(item, index),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          },
                        ),
                        const SizedBox(width: gap),
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
      },
    );
  }

  Widget _galleryTile(ComposerImageGalleryItem item, int index) =>
      _ReorderableGalleryTile(
        item: item,
        index: index,
        siteUrl: siteUrl,
        onReorder: onReorder,
        onReorderStarted: onReorderStarted,
        onReorderEnded: onReorderEnded,
      );
}

class ComposerImageGalleryControl extends StatelessWidget {
  const ComposerImageGalleryControl({
    super.key,
    required this.imageCount,
    this.onEdit,
  });

  final int imageCount;
  final VoidCallback? onEdit;

  static const double extent = DButton.minimumDimension;

  @override
  Widget build(BuildContext context) {
    final count = '$imageCount ${imageCount == 1 ? 'image' : 'images'}';

    return MergeSemantics(
      child: Semantics(
        hint: '$count. Add or remove images.',
        child: DButton.iconOnly(
          onPressed: onEdit,
          tooltip: 'Gallery options',
          semanticLabel: 'Gallery options',
          variant: DButtonVariant.flat,
          icon: const Icon(Icons.tune),
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
    required this.onReorderStarted,
    required this.onReorderEnded,
  });

  final ComposerImageGalleryItem item;
  final int index;
  final String? siteUrl;
  final void Function(ComposerImageBlock image, int newIndex)? onReorder;
  final ValueChanged<ComposerImageBlock>? onReorderStarted;
  final ValueChanged<ComposerImageBlock>? onReorderEnded;

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
        onDragStarted: () => onReorderStarted?.call(item.image),
        onDragEnd: (_) => onReorderEnded?.call(item.image),
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
