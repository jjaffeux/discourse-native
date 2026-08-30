import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:photo_view/photo_view.dart';

import '../foundation/diagnostic_errors.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'cooked_dom.dart';
import 'image_decode.dart';
import 'image_download.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'site_image.dart';

const double _maximumPhotoViewDimension = 10000;
const double _maximumPhotoViewAspectRatio = 10000;

/// Normalizes untrusted image dimensions for transform math without changing
/// their aspect ratio.
///
/// Post layout deliberately clamps extreme ratios, but the full-screen viewer
/// must retain them so wide panoramas and tall screenshots pan and zoom against
/// their real geometry. Values too extreme for useful finite transform math are
/// rejected instead of being reshaped.
Size? _safePhotoViewImageSize(double? width, double? height) {
  if (width == null ||
      height == null ||
      !width.isFinite ||
      !height.isFinite ||
      width < 1 ||
      height < 1) {
    return null;
  }

  final ratio = width / height;
  if (!ratio.isFinite ||
      ratio < 1 / _maximumPhotoViewAspectRatio ||
      ratio > _maximumPhotoViewAspectRatio) {
    return null;
  }

  final normalization = math.min(
    1.0,
    _maximumPhotoViewDimension / math.max(width, height),
  );
  return Size(width * normalization, height * normalization);
}

Size? _parsePhotoViewImageSize(String? width, String? height) =>
    _safePhotoViewImageSize(
      double.tryParse(width ?? ''),
      double.tryParse(height ?? ''),
    );

Size? _parsePhotoViewInformationSize(String? text) {
  if (text == null) return null;
  final dimensions = text.trim().split(' ').first;
  final parts = dimensions.split(RegExp('x|×'));
  if (parts.length != 2) return null;
  return _parsePhotoViewImageSize(parts[0], parts[1]);
}

/// Renders Discourse's post images, and the gallery behind them.
///
/// `CookedPostProcessor#add_lightbox!` wraps every uploaded image wide and tall
/// enough to be worth enlarging (100x100, `MIN_LIGHTBOX_WIDTH/HEIGHT`) in this:
///
/// ```html
/// <div class="lightbox-wrapper">
///   <a class="lightbox" href="FULL" data-download-href="DOWNLOAD" title="TITLE">
///     <img src="THUMBNAIL" width="690" height="388">
///     <div class="meta">
///       <svg class="d-icon-far-image"></svg>
///       <span class="filename">TITLE</span>
///       <span class="informations">1920×1080 234 KB</span>
///       <svg class="d-icon-discourse-expand"></svg>
///     </div>
///   </a>
/// </div>
/// ```
///
/// The `href` is the full-size image and the `src` is a resized thumbnail, so
/// left to [HtmlWidget] a post shows the small one with no way to reach the
/// large one. Everything the viewer needs is in that markup — Discourse writes
/// the intrinsic size and the file size into `.informations` precisely so the
/// client does not have to fetch the image to find out.
///
/// Images Discourse decides *not* to lightbox — anything under 100x100,
/// animated GIFs, images inside a onebox, and hotlinked images it never took a
/// copy of — have no wrapper, never reach here, and stay plain `<img>` tags.
class LightboxImage {
  const LightboxImage({
    required this.fullSrc,
    required this.thumbnailSrc,
    required this.title,
    required this.description,
    required this.details,
    required this.downloadHref,
    required this.width,
    required this.height,
    required this.heroTag,
    this.fullWidth,
    this.fullHeight,
  });

  /// The full-size image the gallery shows.
  final String fullSrc;

  /// The resized image the post shows. Null only for markup that omitted it,
  /// in which case the post shows [fullSrc] too.
  final String? thumbnailSrc;

  /// Caption line: the anchor's `title`, which Discourse fills from the image's
  /// title, its alt text, or failing both the uploaded filename.
  final String? title;

  /// Human-readable image content, kept separate from [title] because an
  /// upload's visible caption is often only its filename. Prefer the author's
  /// alt text for assistive technology when the markup carries both.
  final String? description;

  /// The `.informations` line — `"1920×1080 234 KB"`, the *intrinsic* size and
  /// the weight, not the size the post draws it at. Shown under [title].
  final String? details;

  /// `data-download-href`, absent for images that are not uploads.
  final String? downloadHref;

  /// The size the post draws the thumbnail at, as Discourse resized it.
  final double? width;
  final double? height;

  /// The full image's intrinsic size, when the cooked markup declares it.
  ///
  /// Kept separate from [width] and [height]: those size the post thumbnail,
  /// while this size gives the gallery the correct scale and pan boundaries.
  /// Chat uploads only carry one size, so [fullSize] falls back to the thumbnail
  /// fields for callers which construct a [LightboxImage] directly.
  final double? fullWidth;
  final double? fullHeight;

  /// Identity shared by the post's thumbnail and the gallery's page, so the
  /// image flies between them. Comes from [_heroTags] rather than the URL: the
  /// same image can appear twice in one post, and two [Hero]s alive at once
  /// under one tag is an error.
  final Object heroTag;

  double? get aspectRatio {
    final size = safeImageLayoutSize(width, height);
    return size == null ? null : size.width / size.height;
  }

  double? get layoutWidth => safeImageLayoutSize(width, height)?.width;

  Size? get fullSize =>
      _safePhotoViewImageSize(fullWidth, fullHeight) ??
      _safePhotoViewImageSize(width, height);

  /// Reads [anchor], which must be the `a.lightbox` element itself. Null when
  /// there is no image to point at, which is not markup Discourse writes but is
  /// cheaper to tolerate than to trust.
  static LightboxImage? from(dom.Element anchor) {
    // `data-large-src` first, matching core's generic `lib/lightbox.js`
    // consumer. Chat is one current producer, but the attribute belongs to
    // every upstream `a.lightbox`, not to the feature which happened to write
    // a particular element.
    final fullSrc =
        anchor.attributes['data-large-src'].orNull ??
        anchor.attributes['href'].orNull;
    if (fullSrc == null) return null;

    final img = descendantWhere(anchor, (e) => e.localName == 'img');
    final informations = descendantWhere(
      anchor,
      (e) => e.classes.contains('informations'),
    );

    final alt = img?.attributes['alt'].orNull;
    final imageTitle = img?.attributes['title'].orNull;
    final anchorTitle = anchor.attributes['title'].orNull;

    final thumbnailSize = parseSafeImageLayoutSize(
      img?.attributes['width'],
      img?.attributes['height'],
    );
    final thumbnailTransformSize = _parsePhotoViewImageSize(
      img?.attributes['width'],
      img?.attributes['height'],
    );
    // Match core's PhotoSwipe item-data filter: explicit target dimensions are
    // authoritative, then the `.informations` line supplies the original size.
    // If neither exists, retain the thumbnail's unclamped aspect ratio for
    // chat and older cooked markup which only declares one pair of dimensions.
    final fullSize =
        _parsePhotoViewImageSize(
          anchor.attributes['data-target-width'],
          anchor.attributes['data-target-height'],
        ) ??
        _parsePhotoViewInformationSize(informations?.text) ??
        thumbnailTransformSize;
    // Preserve the old defensive thumbnail fallback for malformed/sizeless
    // markup, without losing the distinction when both sizes are present.
    final layoutSize =
        thumbnailSize ?? safeImageLayoutSize(fullSize?.width, fullSize?.height);
    return LightboxImage(
      fullSrc: fullSrc,
      thumbnailSrc: img?.attributes['src'].orNull,
      title: anchorTitle ?? alt ?? imageTitle,
      description: alt ?? imageTitle ?? anchorTitle,
      details: informations?.text.trim().orNull,
      downloadHref: anchor.attributes['data-download-href'].orNull,
      width: layoutSize?.width,
      height: layoutSize?.height,
      heroTag: _heroTag(anchor),
      fullWidth: fullSize?.width,
      fullHeight: fullSize?.height,
    );
  }

  /// Every image in the same post as [anchor], in the order they are written.
  ///
  /// The web client scopes a gallery the same way — `decorateCookedElement`
  /// runs once per cooked post — and each [CookedHtml] parses one post into one
  /// document, so the document [anchor] belongs to *is* the post.
  ///
  /// Reading the document is also what keeps an [ImageGridMosaic] honest.
  /// `lib/columns.js` moves the grid's images into column elements, so the DOM
  /// ends up in column order and `sortLightboxItems` has to put it back using
  /// the `data-lightbox-position` it stamped on the way. Nothing here moves a
  /// node, so the order never leaves the one the post was written in.
  ///
  /// One knowing divergence from `lib/lightbox.js`: it excludes
  /// `.spoiler`/`.spoiled`, except its selector does not. The
  /// `div.lightbox-wrapper` in between is itself an ancestor that is neither,
  /// which satisfies the descendant combinator, so spoilered images are in the
  /// gallery on the web and are in it here.
  static List<LightboxImage> galleryFor(dom.Element anchor) {
    dom.Node root = anchor;
    while (root.parentNode != null) {
      root = root.parentNode!;
    }

    final anchors = switch (root) {
      dom.Document() => root.querySelectorAll('a.lightbox'),
      dom.DocumentFragment() => root.querySelectorAll('a.lightbox'),
      dom.Element() => root.querySelectorAll('a.lightbox'),
      _ => <dom.Element>[anchor],
    };

    final images = [for (final el in anchors) ?LightboxImage.from(el)];
    // Only if the anchor itself failed to parse, which `from` already ruled out
    // for the tapped one.
    return images.isEmpty ? [LightboxImage.from(anchor)!] : images;
  }
}

/// Hero tags, keyed by the anchor they belong to so they survive a rebuild and
/// collide with nothing. An [Expando] rather than a map because the entry
/// should go when the parsed document does.
final Expando<Object> _heroTags = Expando<Object>('lightbox hero');

Object _heroTag(dom.Element anchor) => _heroTags[anchor] ??= Object();

/// Hands `div.lightbox-wrapper` to [LightboxThumbnail], for
/// [HtmlWidget.customWidgetBuilder].
///
/// Matches the anchor as well as the wrapper. A claimed wrapper never has its
/// children visited, so the anchor arm only fires for markup that has no
/// wrapper at all.
Widget? lightboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final anchor = switch (element) {
    _ when element.classes.contains('lightbox-wrapper') => descendantWhere(
      element,
      (e) => e.classes.contains('lightbox'),
    ),
    _ when element.localName == 'a' && element.classes.contains('lightbox') =>
      element,
    _ => null,
  };
  if (anchor == null) return null;

  final image = LightboxImage.from(anchor);
  if (image == null) return null;

  return LightboxThumbnail(anchor: anchor, image: image, siteUrl: siteUrl);
}

/// A post image: the thumbnail Discourse resized, at the size it asked for.
class LightboxThumbnail extends StatelessWidget {
  const LightboxThumbnail({
    super.key,
    required this.anchor,
    required this.image,
    this.siteUrl,
  });

  /// Kept rather than the parsed gallery so the sibling scan happens on tap
  /// instead of once per image per build.
  final dom.Element anchor;

  final LightboxImage image;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final ratio = image.aspectRatio;

    Widget tile = LightboxTile(
      anchor: anchor,
      image: image,
      // A standalone post image should never crop authored content. This is
      // especially important when defensive ratio bounds shorten the reserved
      // slot for an unusually tall screenshot.
      fit: BoxFit.contain,
      fillsBox: ratio != null,
      siteUrl: siteUrl,
    );

    // Reserve the slot from the size the markup declared, so the post does not
    // reflow as images land.
    if (ratio != null) {
      tile = AspectRatio(aspectRatio: ratio, child: tile);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          // Discourse's `max-width: 100%; height: auto` — never wider than the
          // column, and never blown up past the size it was resized to.
          constraints: BoxConstraints(
            maxWidth: image.layoutWidth ?? double.infinity,
          ),
          child: tile,
        ),
      ),
    );
  }
}

/// The image itself: tappable, rounded, and sized by whoever placed it.
///
/// Split out of [LightboxThumbnail] because a post image and a grid tile want
/// the same picture in boxes chosen very differently — a standalone image keeps
/// its own aspect ratio, a mosaic tile is handed a box and crops to it.
class LightboxTile extends StatelessWidget {
  const LightboxTile({
    super.key,
    required this.anchor,
    required this.image,
    this.fit = BoxFit.cover,
    this.fillsBox = true,
    this.siteUrl,
  });

  final dom.Element anchor;
  final LightboxImage image;
  final BoxFit fit;
  final String? siteUrl;

  /// Whether something above bounds the height. False for markup that declared
  /// no size and so got no [AspectRatio]: asking to fill an unbounded box there
  /// is an infinite height, and the image sizes itself from its own pixels
  /// instead.
  final bool fillsBox;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : image.layoutWidth;
        final cacheWidth =
            logicalWidth != null && logicalWidth.isFinite && logicalWidth > 0
            ? imagePhysicalPixels(context, logicalWidth)
            : null;
        final label = switch (image.description) {
          final description? when description.isNotEmpty =>
            'Open image: $description',
          _ => 'Open image',
        };
        void activate() => open(context);

        return Semantics(
          button: true,
          label: label,
          onTap: activate,
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: activate,
                  child: Hero(
                    tag: image.heroTag,
                    child: SiteImage(
                      url: image.thumbnailSrc ?? image.fullSrc,
                      siteUrl: siteUrl,
                      fit: fit,
                      width: double.infinity,
                      height: fillsBox ? double.infinity : null,
                      cacheWidth: cacheWidth,
                      errorBuilder: (context, error, stackTrace) {
                        reportImageError(
                          error,
                          stackTrace,
                          operation: 'lightbox.thumbnail',
                        );
                        return UnavailableImage(color: theme.shell.placeholder);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens the post's gallery on this image.
  void open(BuildContext context) {
    final gallery = LightboxImage.galleryFor(anchor);
    final index = gallery.indexWhere((i) => i.heroTag == image.heroTag);

    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          // The barrier, not a background, so the [Hero] flies over the post
          // while the room darkens around it — which is what the web client's
          // zoom transition looks like.
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.92),
          barrierDismissible: true,
          barrierLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              LightboxGallery(
                images: gallery,
                initialIndex: index < 0 ? 0 : index,
                siteUrl: siteUrl,
              ),
          transitionsBuilder: (context, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
  }
}

/// The full-screen viewer: one post's images, swipeable, zoomable.
///
/// The chrome follows `lib/lightbox.js`: a counter, the title and the
/// `.informations` line as a caption, a download button when the image is an
/// upload, and a tap on the image to get all of it out of the way. Moving a
/// pointer brings the chrome back; touch users reveal it with another tap.
class LightboxGallery extends StatefulWidget {
  const LightboxGallery({
    super.key,
    required this.images,
    required this.initialIndex,
    this.siteUrl,
    this.imageDownloader,
  });

  final List<LightboxImage> images;
  final int initialIndex;
  final String? siteUrl;
  final LightboxImageDownloader? imageDownloader;

  @override
  State<LightboxGallery> createState() => _LightboxGalleryState();
}

class _LightboxGalleryState extends State<LightboxGallery> {
  static const double _zoomStep = 1.25;

  final GlobalKey _viewportKey = GlobalKey();
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late final List<PhotoViewController> _photoControllers;
  late final List<PhotoViewScaleStateController> _scaleControllers;
  late final List<Size?> _fullImageSizes;
  late int _index = widget.initialIndex;
  Size? _viewportSize;
  bool _chromeVisible = true;
  bool _downloading = false;
  late final LightboxImageDownloader _imageDownloader =
      widget.imageDownloader ?? NativeLightboxImageDownloader();

  @override
  void initState() {
    super.initState();
    _photoControllers = List.generate(
      widget.images.length,
      (_) => PhotoViewController(),
    );
    _scaleControllers = List.generate(
      widget.images.length,
      (_) => PhotoViewScaleStateController(),
    );
    _fullImageSizes = [for (final image in widget.images) image.fullSize];
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final controller in _photoControllers) {
      controller.dispose();
    }
    for (final controller in _scaleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  LightboxImage get _current => widget.images[_index];

  Future<void> _download() async {
    if (_downloading) return;
    final image = _current;
    final url = image.downloadHref;
    if (url == null) return;

    setState(() => _downloading = true);
    final renderObject = context.findRenderObject();
    final shareOrigin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    try {
      final outcome = await _imageDownloader.download(
        url: url,
        title: image.title,
        siteUrl: widget.siteUrl,
        repository: ShellScope.maybeIdentityOf(context)?.siteImages,
        sharePositionOrigin: shareOrigin,
      );
      if (!mounted || outcome != ImageDownloadOutcome.saved) return;
      final filename = imageDownloadFilename(title: image.title, url: url);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Saved $filename.')));
    } catch (error, stackTrace) {
      reportImageError(error, stackTrace, operation: 'lightbox.download');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text("Couldn't download image.")),
          );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _step(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.images.length) return;
    unawaited(
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  void _pageChanged(int index) {
    _resetZoom(_index);
    setState(() => _index = index);
  }

  void _rememberFullImageSize(int index, Size naturalSize) {
    if (index < 0 || index >= _fullImageSizes.length) return;
    final safeSize = _safePhotoViewImageSize(
      naturalSize.width,
      naturalSize.height,
    );
    if (safeSize == null || safeSize == _fullImageSizes[index]) return;

    // A cached ImageStream may report its dimensions synchronously while the
    // descendant SiteImage is building. Reconcile after that frame so this
    // ancestor never calls setState during a descendant build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          index >= _fullImageSizes.length ||
          safeSize == _fullImageSizes[index]) {
        return;
      }
      setState(() => _fullImageSizes[index] = safeSize);
      // New transform bounds invalidate both the old raw scale and pan offset.
      _resetZoom(index);
    });
  }

  void _rememberViewportSize(Size viewport) {
    final previous = _viewportSize;
    if (previous == viewport) return;
    _viewportSize = viewport;
    if (previous == null) return;

    // PhotoView retains its controller value across layout changes. Reset once
    // the new bounds have been built so rotation/window resizing cannot leave
    // an image outside its new min/max scale or pan range.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewportSize != viewport) return;
      for (var index = 0; index < widget.images.length; index++) {
        _resetZoom(index);
      }
    });
  }

  ({double minimum, double maximum}) _scaleBounds(int index, Size viewport) {
    final imageSize = _fullImageSizes[index] ?? viewport;
    final contained = math.min(
      viewport.width / imageSize.width,
      viewport.height / imageSize.height,
    );
    final covered = math.max(
      viewport.width / imageSize.width,
      viewport.height / imageSize.height,
    );
    return (minimum: contained, maximum: math.max(contained, covered * 3));
  }

  void _zoomCurrent(double factor, {Offset? focalPoint}) {
    final viewport = _viewportSize;
    if (viewport == null) return;
    _zoom(_index, factor, viewport: viewport, focalPoint: focalPoint);
  }

  void _zoom(
    int index,
    double factor, {
    required Size viewport,
    Offset? focalPoint,
  }) {
    final controller = _photoControllers[index];
    final bounds = _scaleBounds(index, viewport);
    final currentScale = controller.scale ?? bounds.minimum;
    if (!currentScale.isFinite || currentScale <= 0) return;

    var targetScale = (currentScale * factor).clamp(
      bounds.minimum,
      bounds.maximum,
    );
    final tolerance = bounds.maximum * 1e-9;
    if (targetScale <= bounds.minimum + tolerance) {
      targetScale = bounds.minimum;
    } else if (targetScale >= bounds.maximum - tolerance) {
      targetScale = bounds.maximum;
    }
    final scaleChange = targetScale / currentScale;
    final focalFromCenter =
        (focalPoint ?? viewport.center(Offset.zero)) -
        viewport.center(Offset.zero);
    final targetPosition = targetScale == bounds.minimum
        ? Offset.zero
        : focalFromCenter -
              (focalFromCenter - controller.position) * scaleChange;

    controller.updateMultiple(scale: targetScale, position: targetPosition);
    _scaleControllers[index].setInvisibly(
      targetScale == bounds.minimum
          ? PhotoViewScaleState.initial
          : PhotoViewScaleState.zoomedIn,
    );
  }

  void _resetZoom([int? index]) {
    final target = index ?? _index;
    final viewport = _viewportSize;
    if (viewport == null) {
      _photoControllers[target].reset();
    } else {
      _photoControllers[target].updateMultiple(
        position: Offset.zero,
        scale: _scaleBounds(target, viewport).minimum,
      );
    }
    _scaleControllers[target].setInvisibly(PhotoViewScaleState.initial);
  }

  bool get _hasKeyboardModifier {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed;
  }

  void _pointerSignal(PointerSignalEvent signal, Size viewport) {
    if (signal is! PointerScrollEvent ||
        signal.scrollDelta.dy == 0 ||
        signal.scrollDelta.dy.abs() <= signal.scrollDelta.dx.abs() ||
        _hasKeyboardModifier) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      signal,
      (event) => _handlePointerScroll(event, viewport),
    );
  }

  void _handlePointerScroll(PointerEvent event, Size viewport) {
    final scroll = event as PointerScrollEvent;
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    final focalPoint = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.globalToLocal(scroll.position)
        : viewport.center(Offset.zero);
    _zoom(
      _index,
      math.exp(-scroll.scrollDelta.dy / kDefaultMouseScrollToScaleFactor),
      viewport: viewport,
      focalPoint: focalPoint,
    );
    scroll.respond(allowPlatformDefault: false);
  }

  void _revealChrome() {
    if (_chromeVisible) return;
    setState(() => _chromeVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    // Esc and the arrow keys, which the web client binds too. Harmless where
    // there is no keyboard.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const CharacterActivator('+'): () => _zoomCurrent(_zoomStep),
        const CharacterActivator('='): () => _zoomCurrent(_zoomStep),
        const SingleActivator(LogicalKeyboardKey.equal): () =>
            _zoomCurrent(_zoomStep),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
            _zoomCurrent(_zoomStep),
        const SingleActivator(LogicalKeyboardKey.numpadEqual): () =>
            _zoomCurrent(_zoomStep),
        const CharacterActivator('-'): () => _zoomCurrent(1 / _zoomStep),
        const SingleActivator(LogicalKeyboardKey.minus): () =>
            _zoomCurrent(1 / _zoomStep),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
            _zoomCurrent(1 / _zoomStep),
        const CharacterActivator('0'): _resetZoom,
        const SingleActivator(LogicalKeyboardKey.digit0): _resetZoom,
        const SingleActivator(LogicalKeyboardKey.numpad0): _resetZoom,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              _rememberViewportSize(viewport);
              return MouseRegion(
                onEnter: (_) => _revealChrome(),
                onHover: (_) => _revealChrome(),
                child: Listener(
                  key: _viewportKey,
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (signal) => _pointerSignal(signal, viewport),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [_pages(viewport), _chrome(viewport)],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chrome(Size viewport) {
    final controller = _photoControllers[_index];
    return StreamBuilder<PhotoViewControllerValue>(
      key: ValueKey(_index),
      stream: controller.outputStateStream,
      initialData: controller.value,
      builder: (context, snapshot) {
        final value = snapshot.data ?? controller.value;
        final bounds = _scaleBounds(_index, viewport);
        final scale = value.scale ?? bounds.minimum;
        final tolerance = bounds.maximum * 1e-9;
        final canZoomOut = scale > bounds.minimum + tolerance;
        final canZoomIn = scale < bounds.maximum - tolerance;
        final canReset =
            (scale - bounds.minimum).abs() > tolerance ||
            value.position.distanceSquared > 1e-12;
        return _Chrome(
          visible: _chromeVisible,
          index: _index,
          total: widget.images.length,
          image: _current,
          downloading: _downloading,
          onDownload: _download,
          onZoomOut: canZoomOut ? () => _zoomCurrent(1 / _zoomStep) : null,
          onResetZoom: canReset ? _resetZoom : null,
          onZoomIn: canZoomIn ? () => _zoomCurrent(_zoomStep) : null,
          onStep: _step,
          onClose: () => Navigator.of(context).maybePop(),
        );
      },
    );
  }

  Widget _pages(Size viewport) {
    // Keep the pointer listener inside PageView's Scrollable. The deepest
    // pointer-signal listener wins, so vertical-dominant diagonal trackpad
    // events zoom while horizontal-dominant events remain available to page.
    return PhotoViewGestureDetectorScope(
      axis: Axis.horizontal,
      child: PageView.builder(
        controller: _controller,
        onPageChanged: _pageChanged,
        itemCount: widget.images.length,
        itemBuilder: (context, index) => Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (signal) => _pointerSignal(signal, viewport),
          child: ClipRect(
            child: PhotoView.customChild(
              key: ObjectKey(index),
              childSize: _fullImageSizes[index],
              controller: _photoControllers[index],
              scaleStateController: _scaleControllers[index],
              backgroundDecoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              heroAttributes: PhotoViewHeroAttributes(
                tag: widget.images[index].heroTag,
              ),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              gestureDetectorBehavior: HitTestBehavior.opaque,
              onTapUp: (context, details, value) =>
                  setState(() => _chromeVisible = !_chromeVisible),
              child: Semantics(
                image: true,
                label:
                    widget.images[index].description ??
                    widget.images[index].title,
                child: ExcludeSemantics(
                  child: SiteImage(
                    url: widget.images[index].fullSrc,
                    siteUrl: widget.siteUrl,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    excludeFromSemantics: true,
                    onNaturalSize: (size) =>
                        _rememberFullImageSize(index, size),
                    loadingBuilder: (context) => const Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: AdaptiveActivityIndicator(
                          color: Colors.white,
                          cupertinoRadius: 12,
                          materialStrokeWidth: 2,
                        ),
                      ),
                    ),
                    errorBuilder: (context, error, stackTrace) {
                      reportImageError(
                        error,
                        stackTrace,
                        operation: 'lightbox.fullImage',
                      );
                      return const Center(
                        child: UnavailableImage(color: Colors.white54),
                      );
                    },
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

/// Everything drawn over the image: counter, buttons, caption, arrows.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.index,
    required this.total,
    required this.image,
    required this.downloading,
    required this.onDownload,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.onZoomIn,
    required this.onStep,
    required this.onClose,
  });

  final bool visible;
  final int index;
  final int total;
  final LightboxImage image;
  final bool downloading;
  final VoidCallback onDownload;
  final VoidCallback? onZoomOut;
  final VoidCallback? onResetZoom;
  final VoidCallback? onZoomIn;
  final void Function(int delta) onStep;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Arrows are for a pointer; a finger swipes.
    final showArrows = total > 1 && !context.isTouch;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(alignment: Alignment.topCenter, child: _bar(context)),
            if (image.title != null || image.details != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: _caption(context),
              ),
            if (showArrows) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _Arrow(
                  icon: DIcons.chevronLeft,
                  enabled: index > 0,
                  onTap: () => onStep(-1),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _Arrow(
                  icon: DIcons.chevronRight,
                  enabled: index < total - 1,
                  onTap: () => onStep(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final downloadHref = image.downloadHref;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            if (total > 1)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${index + 1} / $total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
              )
            else
              const Spacer(),
            _Button(
              icon: DIcons.circleMinus,
              tooltip: 'Zoom out',
              onTap: onZoomOut,
            ),
            _Button(
              icon: DIcons.expand,
              tooltip: 'Reset zoom',
              onTap: onResetZoom,
            ),
            _Button(
              icon: DIcons.circlePlus,
              tooltip: 'Zoom in',
              onTap: onZoomIn,
            ),
            if (downloadHref != null)
              _Button(
                icon: DIcons.download,
                tooltip: downloading ? 'Downloading…' : 'Download',
                onTap: downloading ? null : onDownload,
              ),
            _Button(icon: DIcons.xmark, tooltip: 'Close', onTap: onClose),
          ],
        ),
      ),
    );
  }

  Widget _caption(BuildContext context) {
    final title = image.title;
    final details = image.details;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            if (title != null && details != null) const SizedBox(height: 2),
            if (details != null)
              Text(
                details,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.white60),
              ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final DIconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xBB000000),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
      ),
      icon: DIcon(icon, size: 18, semanticLabel: tooltip),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final DIconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Opacity(
        opacity: enabled ? 1 : 0.25,
        child: IconButton(
          onPressed: enabled ? onTap : null,
          icon: DIcon(icon, size: 20, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// What an image that will not load leaves behind, in the space it would have
/// taken.
class UnavailableImage extends StatelessWidget {
  const UnavailableImage({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Center(child: DIcon(DIcons.triangleExclamation, size: 20, color: color));
}

extension on String? {
  /// Absent and empty mean the same thing in this markup.
  String? get orNull => (this == null || this!.isEmpty) ? null : this;
}
