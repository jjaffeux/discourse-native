import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../foundation/diagnostic_errors.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'cooked_dom.dart';
import 'image_decode.dart';
import 'open_link.dart';
import 'platform.dart';
import 'site_image.dart';

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

  /// Reads [anchor], which must be the `a.lightbox` element itself. Null when
  /// there is no image to point at, which is not markup Discourse writes but is
  /// cheaper to tolerate than to trust.
  static LightboxImage? from(dom.Element anchor) {
    // `data-large-src` first, matching `lib/lightbox.js`. Only chat writes it
    // today, but the precedence is the contract.
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

    final layoutSize = parseSafeImageLayoutSize(
      img?.attributes['width'],
      img?.attributes['height'],
    );
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
/// upload, and a tap on the image to get all of it out of the way.
class LightboxGallery extends StatefulWidget {
  const LightboxGallery({
    super.key,
    required this.images,
    required this.initialIndex,
    this.siteUrl,
  });

  final List<LightboxImage> images;
  final int initialIndex;
  final String? siteUrl;

  @override
  State<LightboxGallery> createState() => _LightboxGalleryState();
}

class _LightboxGalleryState extends State<LightboxGallery> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  LightboxImage get _current => widget.images[_index];

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
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _pages(),
              _Chrome(
                visible: _chromeVisible,
                index: _index,
                total: widget.images.length,
                image: _current,
                siteUrl: widget.siteUrl,
                onStep: _step,
                onClose: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pages() {
    return PhotoViewGallery.builder(
      itemCount: widget.images.length,
      pageController: _controller,
      onPageChanged: (index) => setState(() => _index = index),
      // The route's barrier is the background.
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      loadingBuilder: (context, event) => const Center(
        child: SizedBox.square(
          dimension: 24,
          child: AdaptiveActivityIndicator(
            color: Colors.white,
            cupertinoRadius: 12,
            materialStrokeWidth: 2,
          ),
        ),
      ),
      builder: (context, index) {
        final image = widget.images[index];
        return PhotoViewGalleryPageOptions.customChild(
          child: SiteImage(
            url: image.fullSrc,
            siteUrl: widget.siteUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            excludeFromSemantics: true,
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
          heroAttributes: PhotoViewHeroAttributes(tag: image.heroTag),
          semanticLabel: image.title,
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (context, details, value) =>
              setState(() => _chromeVisible = !_chromeVisible),
        );
      },
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
    required this.siteUrl,
    required this.onStep,
    required this.onClose,
  });

  final bool visible;
  final int index;
  final int total;
  final LightboxImage image;
  final String? siteUrl;
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${index + 1} / $total',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ),
            const Spacer(),
            if (downloadHref != null)
              _Button(
                icon: DIcons.download,
                tooltip: 'Download',
                onTap: () => openLink(context, downloadHref, siteUrl: siteUrl),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xBB000000),
        foregroundColor: Colors.white,
      ),
      icon: DIcon(icon, size: 18, color: Colors.white, semanticLabel: tooltip),
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
