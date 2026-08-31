import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../foundation/diagnostic_errors.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_dom.dart';
import 'cooked_html.dart';
import 'image_decode.dart';
import 'lightbox.dart';
import 'site_image.dart';

enum ImageGridMode {
  grid,
  carousel;

  static ImageGridMode from(String? value) =>
      value == 'carousel' ? ImageGridMode.carousel : ImageGridMode.grid;
}

class ImageGridItem {
  const ImageGridItem({
    required this.element,
    required this.anchor,
    required this.image,
    required this.description,
    required this.declared,
    required this.intrinsic,
  });

  final dom.Element element;

  final dom.Element? anchor;

  final LightboxImage? image;

  final String? description;

  final Size? declared;

  final Size? intrinsic;

  bool get isLightbox => anchor != null && image != null;

  String? get plainSrc {
    if (isLightbox) return null;
    final img = element.localName == 'img'
        ? element
        : descendantWhere(element, (e) => e.localName == 'img');
    final src = img?.attributes['src'];
    return (src == null || src.isEmpty) ? null : src;
  }

  double get mosaicHeightUnit {
    final size = declared;
    if (size == null || size.width <= 0) return 1;
    return size.height / size.width;
  }

  double get carouselAspectRatio {
    for (final size in [declared, intrinsic]) {
      if (size != null && size.width > 0 && size.height > 0) {
        return size.width / size.height;
      }
    }
    return 1024 / 768;
  }
}

class ImageGridData {
  const ImageGridData({required this.mode, required this.items});

  final ImageGridMode mode;
  final List<ImageGridItem> items;

  static const int minCount = 2;

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

  static List<dom.Element> _prepareItems(dom.Element grid) {
    final targets = <dom.Element>[];

    for (final child in childElements(grid)) {
      if (child.localName == 'p') {
        for (final nested in childElements(child)) {
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
        : descendantWhere(element, (e) => e.classes.contains('lightbox'));
    final img = element.localName == 'img'
        ? element
        : descendantWhere(element, (e) => e.localName == 'img');

    final declared = parseSafeImageLayoutSize(
      img?.attributes['width'],
      img?.attributes['height'],
    );

    final informations = descendantWhere(
      element,
      (e) => e.classes.contains('informations'),
    );

    return ImageGridItem(
      element: element,
      anchor: anchor,
      image: anchor == null ? null : LightboxImage.from(anchor),
      description:
          _nonEmpty(img?.attributes['alt']) ??
          _nonEmpty(img?.attributes['title']),
      declared: declared,
      intrinsic: _parseInformations(informations?.text),
    );
  }

  static Size? _parseInformations(String? text) {
    return parseSafeImageInformationSize(text);
  }
}

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

class ImageGridMosaic extends StatelessWidget {
  const ImageGridMosaic({super.key, required this.data, this.siteUrl});

  final ImageGridData data;
  final String? siteUrl;

  static const double gap = 6;

  static const double maxItemHeight = 1200;

  static const double narrowWidth = 700;

  int columnCount(double width) {
    if (data.items.length == 2 || data.items.length == 4) return 2;
    return width < narrowWidth ? 2 : 3;
  }

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

class ImageGridTile extends StatelessWidget {
  const ImageGridTile({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
    this.siteUrl,
  });

  final ImageGridItem item;
  final String? siteUrl;

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
      return LayoutBuilder(
        builder: (context, constraints) {
          final cacheWidth =
              constraints.hasBoundedWidth &&
                  constraints.maxWidth.isFinite &&
                  constraints.maxWidth > 0
              ? imagePhysicalPixels(context, constraints.maxWidth)
              : null;
          final description = item.description;

          return Semantics(
            image: description != null,
            label: description,
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SiteImage(
                  url: src,
                  siteUrl: siteUrl,
                  fit: fit,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: cacheWidth,
                  errorBuilder: (context, error, stackTrace) {
                    reportImageError(
                      error,
                      stackTrace,
                      operation: 'imageGrid.image',
                    );
                    return UnavailableImage(
                      color: Theme.of(context).shell.placeholder,
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    }

    return CookedHtml(html: item.element.outerHtml, siteUrl: siteUrl);
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

class ImageGridCarousel extends StatefulWidget {
  const ImageGridCarousel({super.key, required this.data, this.siteUrl});

  final ImageGridData data;
  final String? siteUrl;

  static const double trackHeight = 400;

  static const int maxDots = 10;

  static const double controlTargetSize = 44;

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
        _Nav(
          key: const ValueKey('image-carousel-previous'),
          icon: DIcons.chevronLeft,
          label: 'Previous image',
          onTap: onPrevious,
        ),
        const SizedBox(width: 8),
        if (total <= ImageGridCarousel.maxDots)
          Flexible(
            child: SizedBox(
              width: total * ImageGridCarousel.controlTargetSize,
              child: _Dots(index: index, total: total, onSelect: onSelect),
            ),
          )
        else
          _Counter(index: index, total: total),
        const SizedBox(width: 8),
        _Nav(
          key: const ValueKey('image-carousel-next'),
          icon: DIcons.chevronRight,
          label: 'Next image',
          onTap: onNext,
        ),
      ],
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final DIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onTap,
          tooltip: label,
          iconSize: 14,
          constraints: const BoxConstraints.tightFor(
            width: ImageGridCarousel.controlTargetSize,
            height: ImageGridCarousel.controlTargetSize,
          ),
          padding: EdgeInsets.zero,
          icon: DIcon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

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

    return Material(
      color: theme.shell.panel,
      borderRadius: BorderRadius.circular(
        ImageGridCarousel.controlTargetSize / 2,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var dot = 0; dot < total; dot++)
              _DotButton(
                index: dot,
                total: total,
                selected: dot == index,
                color: dot == index
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.shell.divider,
                onTap: () => onSelect(dot),
              ),
          ],
        ),
      ),
    );
  }
}

class _DotButton extends StatefulWidget {
  const _DotButton({
    required this.index,
    required this.total,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final int index;
  final int total;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_DotButton> createState() => _DotButtonState();
}

class _DotButtonState extends State<_DotButton> {
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(_DotButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected && widget.selected) _reveal();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = context.findRenderObject();
      final scrollable = Scrollable.maybeOf(context);
      if (target == null ||
          scrollable == null ||
          axisDirectionToAxis(scrollable.axisDirection) != Axis.horizontal) {
        return;
      }
      // `Scrollable.ensureVisible` walks every enclosing scrollable. These dots
      // live inside the vertically scrolling topic, so that API can recenter
      // the whole post while merely changing carousel slides. Reveal through
      // the nearest (horizontal) position only.
      unawaited(scrollable.position.ensureVisible(target, alignment: 0.5));
    });
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.index + 1;
    final label = 'Go to image $number of ${widget.total}';

    return Semantics(
      key: ValueKey('image-carousel-dot-$number'),
      container: true,
      button: true,
      selected: widget.selected,
      label: label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: InkWell(
            key: ValueKey('image-carousel-dot-$number-button'),
            focusNode: _focusNode,
            onFocusChange: (focused) {
              if (focused) _reveal();
            },
            onTap: widget.onTap,
            child: SizedBox.square(
              dimension: ImageGridCarousel.controlTargetSize,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: widget.selected ? 22 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

dom.Element? _ancestor(dom.Element node, bool Function(dom.Element) test) {
  dom.Element? current = node;
  while (current != null) {
    if (test(current)) return current;
    current = current.parent;
  }
  return null;
}
