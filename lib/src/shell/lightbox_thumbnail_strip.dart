part of 'lightbox.dart';

/// The gallery's filmstrip, below the image. It keeps its height while the
/// controls are hidden so the image area never resizes under a zoomed image.
class _ThumbnailStrip extends StatefulWidget {
  const _ThumbnailStrip({
    required this.images,
    required this.index,
    required this.visible,
    required this.siteUrl,
    required this.onSelect,
  });

  final List<LightboxImage> images;
  final int index;
  final bool visible;
  final String? siteUrl;
  final ValueChanged<int> onSelect;

  @override
  State<_ThumbnailStrip> createState() => _ThumbnailStripState();
}

class _ThumbnailStripState extends State<_ThumbnailStrip> {
  static const double _gap = 6;
  static const double _sideInset = 16;
  static const double _topInset = 14;
  static const double _bottomInset = 18;
  static const double _bareHeight = 24;
  static const double _pitch = DImageThumbnail.size + _gap;

  ScrollController? _scroll;
  double? _viewportWidth;

  @override
  void didUpdateWidget(_ThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _revealAfterFrame(animated: true);
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  double get _contentWidth => widget.images.length * _pitch - _gap;

  /// Centres a strip that fits, as `justify-content: center` does in the
  /// mockup, while a strip that overflows scrolls lazily from the side inset.
  double _inset(double viewport) =>
      math.max(_sideInset, (viewport - _contentWidth) / 2);

  /// Thumbnails are all one size, so the offset comes from the index: the one
  /// to reveal may be far outside the lazily built range.
  double _offsetOf(int index, double viewport) {
    final inset = _inset(viewport);
    final center = inset + index * _pitch + DImageThumbnail.size / 2;
    return (center - viewport / 2).clamp(
      0.0,
      math.max(0.0, inset * 2 + _contentWidth - viewport),
    );
  }

  void _rememberViewport(double viewport) {
    if (_viewportWidth == viewport) return;
    final resized = _viewportWidth != null;
    _viewportWidth = viewport;
    if (resized) _revealAfterFrame(animated: false);
  }

  void _revealAfterFrame({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = _scroll;
      final viewport = _viewportWidth;
      if (!mounted ||
          scroll == null ||
          viewport == null ||
          !scroll.hasClients) {
        return;
      }
      final target = _offsetOf(widget.index, viewport);
      if (!animated || MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(target);
        return;
      }
      unawaited(
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (widget.images.length < 2) {
      return SizedBox(height: math.max(_bareHeight, safeBottom));
    }
    final bottom = math.max(_bottomInset, safeBottom);
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: SafeArea(
          top: false,
          bottom: false,
          child: SizedBox(
            height: _topInset + DImageThumbnail.size + bottom,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = constraints.maxWidth;
                _rememberViewport(viewport);
                final inset = _inset(viewport);
                return ListView.builder(
                  controller: _scroll ??= ScrollController(
                    initialScrollOffset: _offsetOf(widget.index, viewport),
                  ),
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsetsDirectional.fromSTEB(
                    inset,
                    _topInset,
                    // Each item's extent carries the gap after it.
                    inset - _gap,
                    bottom,
                  ),
                  itemExtent: _pitch,
                  itemCount: widget.images.length,
                  itemBuilder: _item,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int index) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: DImageThumbnail(
      semanticLabel: context.l10n.goToImageOf(
        (index + 1).toString(),
        (widget.images.length).toString(),
      ),
      selected: index == widget.index,
      outlineColor: Colors.white,
      onPressed: () => widget.onSelect(index),
      child: _ThumbnailArtwork(
        image: widget.images[index],
        siteUrl: widget.siteUrl,
      ),
    ),
  );
}

/// What a thumbnail draws, decoded for its own size. A remote image with no
/// smaller copy shows a glyph: the strip never fetches a full-size original.
class _ThumbnailArtwork extends StatelessWidget {
  const _ThumbnailArtwork({required this.image, required this.siteUrl});

  static const _size = Size.square(DImageThumbnail.size);

  final LightboxImage image;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final url = switch (image.source) {
      RemoteLightboxImage() => image.thumbnailSrc,
      LightboxVideo(:final data) => data.posterUrl,
      LocalLightboxImage() => null,
    };
    Widget unavailable(BuildContext _, Object _, StackTrace? _) =>
        const UnavailableImage(color: Colors.white54);
    final source = image.source;
    return ColoredBox(
      color: Colors.white.withValues(alpha: .12),
      // A GIF stands still here: a row of them would all play at once.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: switch ((source, url)) {
          (LocalLightboxImage(:final file), _) => Image(
            image: imageForCover(context, FileImage(file), logicalSize: _size),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: unavailable,
          ),
          (_, final String url) => SiteImage(
            viewportAware: true,
            url: url,
            siteUrl: siteUrl,
            fit: BoxFit.cover,
            width: _size.width,
            height: _size.height,
            coverDecodeSize: _size,
            excludeFromSemantics: true,
            errorBuilder: unavailable,
          ),
          (LightboxVideo(), _) => const Center(
            child: DIcon(DIcons.play, size: 16, color: Colors.white),
          ),
          _ => const Center(
            child: DIcon(DNativeIcons.image, size: 16, color: Colors.white54),
          ),
        },
      ),
    );
  }
}
