import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../foundation/diagnostic_errors.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_html.dart';
import 'lightbox.dart';
import 'site_url.dart';

/// Renders `[grid]` galleries — the mosaic, and the carousel.
///
/// The server barely participates: `discourse-markdown-it`'s `image-grid`
/// feature turns `[grid]…[/grid]` into nothing more than
/// `<div class="d-image-grid" data-mode="grid|carousel">` around the images.
/// Every bit of the layout is the client's doing, in `lib/columns.js` and
/// `components/image-carousel`, so left to [HtmlWidget] a grid is a plain
/// vertical stack of images.
///
/// The two modes share only their markup:
///
/// * **grid** is masonry — [ImageGridMosaic].
/// * **carousel** is one image at a time on a snapping track —
///   [ImageGridCarousel].
enum ImageGridMode {
  grid,
  carousel;

  /// `data-mode`, which the markdown rule already narrowed to these two and
  /// defaults to `grid`.
  static ImageGridMode from(String? value) =>
      value == 'carousel' ? ImageGridMode.carousel : ImageGridMode.grid;
}

/// One thing in a grid. Usually an image, but a grid holds whatever it was
/// written around.
class ImageGridItem {
  const ImageGridItem({
    required this.element,
    required this.anchor,
    required this.image,
    required this.declared,
    required this.intrinsic,
  });

  /// The item as the post wrote it, for the fallback path.
  final dom.Element element;

  /// `a.lightbox`, when this item has one. Images too small to be lightboxed
  /// still land in a grid, so this is not a given — `lib/columns.js` has the
  /// same case in `_wrapDirectImage`.
  final dom.Element? anchor;

  final LightboxImage? image;

  /// The `width`/`height` the markup declares on the `img`, which is the size
  /// Discourse resized it to.
  final Size? declared;

  /// The size out of `.informations`, which is the size it was uploaded at.
  final Size? intrinsic;

  bool get isLightbox => anchor != null && image != null;

  /// A bare `<img>` that never got a lightbox, for the tile to draw directly.
  String? get plainSrc {
    if (isLightbox) return null;
    final img = element.localName == 'img'
        ? element
        : _descendant(element, (e) => e.localName == 'img');
    final src = img?.attributes['src'];
    return (src == null || src.isEmpty) ? null : src;
  }

  /// How tall this item is at unit width — `img.height / img.width`, the number
  /// `_distributeEvenly` accumulates per column. Anything that is not a sized
  /// image counts as square, exactly as it does there.
  double get mosaicHeightUnit {
    final size = declared;
    if (size == null || size.width <= 0) return 1;
    return size.height / size.width;
  }

  /// Width over height, following `resolveDimensions` in
  /// `lib/image-grid-carousel.js`: what the markup declared, else what it was
  /// uploaded at, else the same 4:3 that file falls back to.
  double get carouselAspectRatio {
    for (final size in [declared, intrinsic]) {
      if (size != null && size.width > 0 && size.height > 0) {
        return size.width / size.height;
      }
    }
    return 1024 / 768;
  }
}

/// A parsed `div.d-image-grid`.
class ImageGridData {
  const ImageGridData({required this.mode, required this.items});

  final ImageGridMode mode;
  final List<ImageGridItem> items;

  /// `Columns.minCount`. Under two items the web client marks the grid
  /// `data-disabled` and the stylesheet bails out of the layout entirely, which
  /// leaves the images stacked — so there is nothing to draw differently.
  static const int minCount = 2;

  /// Reads [grid], which must be the `div.d-image-grid` element itself.
  static ImageGridData from(dom.Element grid) {
    final mode = ImageGridMode.from(grid.attributes['data-mode']);
    final elements = mode == ImageGridMode.carousel
        ? _carouselItems(grid)
        : _prepareItems(grid);

    return ImageGridData(
      mode: mode,
      items: [for (final el in elements) _item(el)],
    );
  }

  /// `Columns#_prepareItems`: the grid's children, except that an item the
  /// markdown wrapped in a paragraph is taken out of it, and `br`/`p` never
  /// count as items of their own.
  static List<dom.Element> _prepareItems(dom.Element grid) {
    final targets = <dom.Element>[];

    for (final child in grid.children) {
      if (child.localName == 'p' && child.children.isNotEmpty) {
        for (final nested in child.children) {
          if (nested.localName != 'br' && nested.localName != 'p') {
            targets.add(nested);
          }
        }
      } else if (child.localName != 'br' && child.localName != 'p') {
        targets.add(child);
      }
    }

    return targets;
  }

  /// `buildCarouselItems`: every drawable image anywhere in the grid, taken up
  /// to its lightbox wrapper and deduplicated, which is a different question
  /// from [_prepareItems] — a carousel shows images, not children.
  static List<dom.Element> _carouselItems(dom.Element grid) {
    const skip = {'thumbnail', 'ytp-thumbnail-image', 'emoji'};
    final seen = <dom.Element>[];

    for (final img in grid.querySelectorAll('img')) {
      if (img.classes.any(skip.contains)) continue;

      final wrapper =
          _ancestor(img, (e) => e.classes.contains('lightbox-wrapper')) ??
          _ancestor(
            img,
            (e) => e.localName == 'a' && e.classes.contains('lightbox'),
          ) ??
          img;
      if (!seen.contains(wrapper)) seen.add(wrapper);
    }

    return seen;
  }

  static ImageGridItem _item(dom.Element element) {
    final anchor =
        element.localName == 'a' && element.classes.contains('lightbox')
        ? element
        : _descendant(element, (e) => e.classes.contains('lightbox'));
    final img = element.localName == 'img'
        ? element
        : _descendant(element, (e) => e.localName == 'img');

    final width = double.tryParse(img?.attributes['width'] ?? '');
    final height = double.tryParse(img?.attributes['height'] ?? '');

    final informations = _descendant(
      element,
      (e) => e.classes.contains('informations'),
    );

    return ImageGridItem(
      element: element,
      anchor: anchor,
      image: anchor == null ? null : LightboxImage.from(anchor),
      declared: (width == null || height == null) ? null : Size(width, height),
      intrinsic: _parseInformations(informations?.text),
    );
  }

  /// `parseInfoDimensions`: the leading `1920×1080` of an `.informations` line,
  /// which Discourse writes with either separator.
  static Size? _parseInformations(String? text) {
    if (text == null) return null;
    final dimensions = text.trim().split(' ').first;
    final parts = dimensions.split(RegExp('x|×'));
    if (parts.length != 2) return null;

    final width = double.tryParse(parts[0]);
    final height = double.tryParse(parts[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }
}

/// Hands `div.d-image-grid` to the layout its mode asks for, for
/// [HtmlWidget.customWidgetBuilder].
///
/// Returns null — leaving [HtmlWidget] to draw the div and its images the
/// ordinary way — for the two cases the web client also declines to lay out: a
/// grid holding fewer than two things, and a carousel holding no images.
Widget? imageGridWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.localName != 'div') return null;
  if (!element.classes.contains('d-image-grid')) return null;

  final data = ImageGridData.from(element);

  return switch (data.mode) {
    ImageGridMode.carousel when data.items.isNotEmpty => ImageGridCarousel(
      data: data,
      siteUrl: siteUrl,
    ),
    ImageGridMode.grid when data.items.length >= ImageGridData.minCount =>
      ImageGridMosaic(data: data, siteUrl: siteUrl),
    _ => null,
  };
}

/// The mosaic: images packed into columns, cropped so the columns end level.
///
/// `lib/columns.js` walks the items in the order they were written and drops
/// each into whichever column is shortest so far, measuring in units of column
/// width. The stylesheet then does the part that is easy to miss: the columns
/// are flex items in a stretch container, so **every column is as tall as the
/// tallest**, and inside a short column the leftover height is split *equally*
/// between its items, which `object-fit: cover` absorbs by cropping.
///
/// Reproducing that with [IntrinsicHeight] would be both expensive and wrong —
/// a post scrolls, so the height it would measure against is unbounded. It does
/// not need measuring: every aspect ratio is already in the markup, so given a
/// column width the whole layout is arithmetic.
class ImageGridMosaic extends StatelessWidget {
  const ImageGridMosaic({super.key, required this.data, this.siteUrl});

  final ImageGridData data;
  final String? siteUrl;

  /// `$grid-column-gap`, used between columns and under every item.
  static const double gap = 6;

  /// The stylesheet's `max-height`, which stops one very tall image from
  /// setting the height of the whole grid.
  static const double maxItemHeight = 1200;

  /// Below this the grid drops to two columns.
  ///
  /// The web client asks `site.mobileView`, a question about the device. This
  /// shell is adaptive — the same window is wide or narrow depending on what
  /// else is open — so the honest question here is how much room the post
  /// actually has.
  static const double narrowWidth = 700;

  /// `Columns#count`: two columns for two or four items regardless of room,
  /// because a 2x2 block reads better than a row of four.
  int columnCount(double width) {
    if (data.items.length == 2 || data.items.length == 4) return 2;
    return width < narrowWidth ? 2 : 3;
  }

  /// `Columns#_distributeEvenly`: each item joins the shortest column so far.
  /// Returns the item indices per column, so callers keep the written order.
  static List<List<int>> distribute(List<double> heightUnits, int count) {
    final columns = List.generate(count, (_) => <int>[]);
    final heights = List.filled(count, 0.0);

    for (var index = 0; index < heightUnits.length; index++) {
      var shortest = 0;
      for (var column = 1; column < count; column++) {
        if (heights[column] < heights[shortest]) shortest = column;
      }

      heights[shortest] += heightUnits[index];
      columns[shortest].add(index);
    }

    return columns;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = columnCount(constraints.maxWidth);
        final columnWidth = (constraints.maxWidth - gap * (count - 1)) / count;
        if (columnWidth <= 0) return const SizedBox.shrink();

        final columns = distribute([
          for (final item in data.items) item.mosaicHeightUnit,
        ], count);

        // What each item would be at its own aspect ratio, before the stretch.
        final natural = [
          for (final item in data.items)
            math.min(columnWidth * item.mosaicHeightUnit, maxItemHeight),
        ];

        // Every item carries a bottom margin, including the last in a column,
        // so the margins are part of what makes a column tall.
        double naturalColumnHeight(List<int> column) =>
            column.fold<double>(0, (sum, i) => sum + natural[i]) +
            gap * column.length;

        final gridHeight = columns
            .map(naturalColumnHeight)
            .fold<double>(0, math.max);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: gridHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, column) in columns.indexed) ...[
                  if (index > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: columnWidth,
                    child: _column(
                      column,
                      natural,
                      // `flex-grow: 1` on every item: the slack is shared out
                      // evenly, not in proportion to what is already there.
                      slack: column.isEmpty
                          ? 0
                          : (gridHeight - naturalColumnHeight(column)) /
                                column.length,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _column(
    List<int> column,
    List<double> natural, {
    required double slack,
  }) {
    return Column(
      children: [
        for (final index in column)
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: SizedBox(
              height: natural[index] + slack,
              width: double.infinity,
              child: ImageGridTile(item: data.items[index], siteUrl: siteUrl),
            ),
          ),
      ],
    );
  }
}

/// One item, filling whatever box it was given.
class ImageGridTile extends StatelessWidget {
  const ImageGridTile({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.siteUrl,
  });

  final ImageGridItem item;
  final String? siteUrl;

  /// A mosaic crops to square off its columns; a carousel shows the whole
  /// image. The stylesheet says `cover` for one and `contain` for the other.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (item.isLightbox) {
      return LightboxTile(
        anchor: item.anchor!,
        image: item.image!,
        fit: fit,
        siteUrl: siteUrl,
      );
    }

    final src = item.plainSrc;
    if (src != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          resolveSiteUrl(src, siteUrl),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            reportImageError(error, stackTrace, operation: 'imageGrid.image');
            return UnavailableImage(color: Theme.of(context).shell.placeholder);
          },
        ),
      );
    }

    // Whatever else was written into the grid — a onebox, a video, text.
    return CookedHtml(html: item.element.outerHtml, siteUrl: siteUrl);
  }
}

/// The carousel: one image at a time, on a track that snaps.
///
/// `components/image-carousel` is a horizontal scroll-snap strip with a fixed
/// track height, images shown whole rather than cropped, and a row of controls
/// underneath — arrows that wrap around, and either a dot per image or a
/// counter once there are too many dots to be useful.
class ImageGridCarousel extends StatefulWidget {
  const ImageGridCarousel({super.key, required this.data, this.siteUrl});

  final ImageGridData data;
  final String? siteUrl;

  /// The stylesheet's `height: 400px` on `.d-image-carousel__track`.
  static const double trackHeight = 400;

  /// `MAX_DOTS`. Past this the dots become a counter.
  static const int maxDots = 10;

  @override
  State<ImageGridCarousel> createState() => _ImageGridCarouselState();
}

class _ImageGridCarouselState extends State<ImageGridCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(ImageGridCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_items.isEmpty) {
      _index = 0;
      return;
    }
    final target = math.min(_index, _items.length - 1);
    if (target == _index && oldWidget.data.items.isNotEmpty) return;

    _index = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(target);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ImageGridItem> get _items => widget.data.items;

  bool get _isSingle => _items.length < 2;

  /// Both wrap, the way `prevIndex`/`nextIndex` do.
  int get _previous => _index == 0 ? _items.length - 1 : _index - 1;
  int get _next => _index == _items.length - 1 ? 0 : _index + 1;

  void _scrollTo(int index) {
    unawaited(
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    return switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => _handled(_previous),
      LogicalKeyboardKey.arrowRight => _handled(_next),
      _ => KeyEventResult.ignored,
    };
  }

  KeyEventResult _handled(int index) {
    _scrollTo(index);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Focusable rather than merely tappable, so the arrow keys are
          // reachable at all — the web client gives the track a `tabindex` for
          // the same reason.
          Focus(
            onKeyEvent: _onKey,
            child: SizedBox(
              height: ImageGridCarousel.trackHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => Center(
                  child: ImageGridTile(
                    item: _items[index],
                    fit: BoxFit.contain,
                    siteUrl: widget.siteUrl,
                  ),
                ),
              ),
            ),
          ),
          if (!_isSingle) ...[
            const SizedBox(height: 8),
            _Controls(
              index: _index,
              total: _items.length,
              onPrevious: () => _scrollTo(_previous),
              onNext: () => _scrollTo(_next),
              onSelect: _scrollTo,
            ),
          ],
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final int index;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Nav(icon: DIcons.chevronLeft, tooltip: 'Previous', onTap: onPrevious),
        const SizedBox(width: 8),
        if (total <= ImageGridCarousel.maxDots)
          _Dots(index: index, total: total, onSelect: onSelect)
        else
          _Counter(index: index, total: total),
        const SizedBox(width: 8),
        _Nav(icon: DIcons.chevronRight, tooltip: 'Next', onTap: onNext),
      ],
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({required this.icon, required this.tooltip, required this.onTap});

  final DIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 14,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      icon: DIcon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        semanticLabel: tooltip,
      ),
    );
  }
}

/// One dot per image, the current one stretched into a pill.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.index,
    required this.total,
    required this.onSelect,
  });

  final int index;
  final int total;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.shell.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var dot = 0; dot < total; dot++) ...[
            if (dot > 0) const SizedBox(width: 12),
            Semantics(
              label: 'Go to image ${dot + 1}',
              selected: dot == index,
              button: true,
              child: GestureDetector(
                onTap: () => onSelect(dot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: dot == index ? 22 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dot == index
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.shell.divider,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What replaces the dots once there are too many of them to aim at.
class _Counter extends StatelessWidget {
  const _Counter({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.shell.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${index + 1} / $total',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

dom.Element? _descendant(dom.Element root, bool Function(dom.Element) test) {
  for (final child in root.children) {
    if (test(child)) return child;
    final found = _descendant(child, test);
    if (found != null) return found;
  }
  return null;
}

dom.Element? _ancestor(dom.Element node, bool Function(dom.Element) test) {
  dom.Element? current = node;
  while (current != null) {
    if (test(current)) return current;
    current = current.parent;
  }
  return null;
}
