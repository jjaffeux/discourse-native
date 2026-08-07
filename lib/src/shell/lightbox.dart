import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'open_link.dart';
import 'platform.dart';

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
    final (w, h) = (width, height);
    if (w == null || h == null || h <= 0) return null;
    return w / h;
  }

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

    final img = _descendant(anchor, (e) => e.localName == 'img');
    final informations = _descendant(
      anchor,
      (e) => e.classes.contains('informations'),
    );

    return LightboxImage(
      fullSrc: fullSrc,
      thumbnailSrc: img?.attributes['src'].orNull,
      title:
          anchor.attributes['title'].orNull ??
          img?.attributes['alt'].orNull ??
          img?.attributes['title'].orNull,
      details: informations?.text.trim().orNull,
      downloadHref: anchor.attributes['data-download-href'].orNull,
      width: double.tryParse(img?.attributes['width'] ?? ''),
      height: double.tryParse(img?.attributes['height'] ?? ''),
      heroTag: _heroTag(anchor),
    );
  }

  /// Every image in the same post as [anchor], in the order they are written.
  ///
  /// The web client scopes a gallery the same way — `decorateCookedElement`
  /// runs once per cooked post — and each [CookedHtml] parses one post into one
  /// document, so the document [anchor] belongs to *is* the post.
  ///
  /// Two knowing divergences from `lib/lightbox.js`:
  ///
  /// * It sorts `.d-image-grid` carousels by `data-lightbox-position`. That
  ///   attribute is written by `lib/columns.js` after the fact and is never in
  ///   `cooked`, so there is nothing here to sort by.
  /// * It excludes `.spoiler`/`.spoiled`, except its selector does not: the
  ///   `div.lightbox-wrapper` in between is itself an ancestor that is neither,
  ///   which satisfies the descendant combinator. Spoilered images are in the
  ///   gallery on the web, so they are in it here.
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

  static dom.Element? _descendant(
    dom.Element root,
    bool Function(dom.Element) test,
  ) {
    for (final child in root.children) {
      if (test(child)) return child;
      final found = _descendant(child, test);
      if (found != null) return found;
    }
    return null;
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
Widget? lightboxWidgetBuilder(dom.Element element) {
  final anchor = switch (element) {
    _ when element.classes.contains('lightbox-wrapper') =>
      LightboxImage._descendant(element, (e) => e.classes.contains('lightbox')),
    _ when element.localName == 'a' && element.classes.contains('lightbox') =>
      element,
    _ => null,
  };
  if (anchor == null) return null;

  final image = LightboxImage.from(anchor);
  if (image == null) return null;

  return LightboxThumbnail(anchor: anchor, image: image);
}

/// A post image: the thumbnail Discourse resized, at the size it asked for.
class LightboxThumbnail extends StatelessWidget {
  const LightboxThumbnail({
    super.key,
    required this.anchor,
    required this.image,
  });

  /// Kept rather than the parsed gallery so the sibling scan happens on tap
  /// instead of once per image per build.
  final dom.Element anchor;

  final LightboxImage image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = image.aspectRatio;

    Widget thumbnail = Image.network(
      image.thumbnailSrc ?? image.fullSrc,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _Unavailable(color: theme.shell.placeholder),
    );

    // Reserve the slot from the size the markup declared, so the post does not
    // reflow as images land.
    if (ratio != null) {
      thumbnail = AspectRatio(aspectRatio: ratio, child: thumbnail);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          // Discourse's `max-width: 100%; height: auto` — never wider than the
          // column, and never blown up past the size it was resized to.
          constraints: BoxConstraints(maxWidth: image.width ?? double.infinity),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => _open(context),
                child: Hero(tag: image.heroTag, child: thumbnail),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final gallery = LightboxImage.galleryFor(anchor);
    final index = gallery.indexWhere((i) => i.heroTag == image.heroTag);

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
            ),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
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
  });

  final List<LightboxImage> images;
  final int initialIndex;

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
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
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
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      ),
      builder: (context, index) {
        final image = widget.images[index];
        return PhotoViewGalleryPageOptions(
          imageProvider: NetworkImage(image.fullSrc),
          heroAttributes: PhotoViewHeroAttributes(tag: image.heroTag),
          semanticLabel: image.title,
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (context, details, value) =>
              setState(() => _chromeVisible = !_chromeVisible),
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: _Unavailable(color: Colors.white54)),
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
    required this.onStep,
    required this.onClose,
  });

  final bool visible;
  final int index;
  final int total;
  final LightboxImage image;
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
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            const Spacer(),
            if (downloadHref != null)
              _Button(
                icon: DIcons.download,
                tooltip: 'Download',
                onTap: () => openLink(context, downloadHref),
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
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            if (title != null && details != null) const SizedBox(height: 2),
            if (details != null)
              Text(
                details,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
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
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
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
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Center(child: DIcon(DIcons.triangleExclamation, size: 20, color: color));
}

extension on String? {
  /// Absent and empty mean the same thing in this markup.
  String? get orNull => (this == null || this!.isEmpty) ? null : this;
}
