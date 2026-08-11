import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../data/emoji_cache.dart';
import '../foundation/diagnostic_errors.dart';
import 'image_decode.dart';

/// One emoji, drawn from the image the site serves for it.
///
/// Goes through [EmojiCache] rather than [Image.network] for the reason written
/// down there: a post can carry thirty of these and a screen six posts, and
/// unbounded parallel requests are what a site answers with 429.
///
/// [alt] is what Discourse writes in the `alt` attribute — `:slight_smile:` —
/// and is what stands in when the image cannot be fetched. It is a worse answer
/// than the artwork and a much better one than a gap.
class EmojiImage extends StatefulWidget {
  const EmojiImage({
    super.key,
    required this.url,
    required this.size,
    required this.alt,
    this.style,
  });

  final String url;
  final double size;
  final String alt;

  /// The prose the emoji is sitting in, for the fallback text only.
  final TextStyle? style;

  @override
  State<EmojiImage> createState() => _EmojiImageState();
}

class _EmojiImageState extends State<EmojiImage> {
  Uint8List? _bytes;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(EmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    final cache = EmojiCache.instance;

    if (cache.isCached(url)) {
      // Paint synchronously on rebuild. Emoji repeat across every post on a
      // site, so after the first screen this is the ordinary case rather than
      // the lucky one, and going async here would flicker the whole page.
      _bytes = cache.cached(url);
      _resolved = true;
      return;
    }

    _resolved = false;
    unawaited(
      cache.load(url).then((bytes) {
        if (!mounted || widget.url != url) return;
        setState(() {
          _bytes = bytes;
          _resolved = true;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    // Nothing yet: hold the space rather than drawing the shortcode, so a
    // paragraph does not reflow under the reader when the images land.
    if (!_resolved) return SizedBox(width: widget.size, height: widget.size);

    if (bytes == null) return Text(widget.alt, style: widget.style);

    return Image(
      image: memoryImageForLayout(
        context,
        bytes,
        logicalSize: Size.square(widget.size),
      ),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        reportImageError(error, stackTrace, operation: 'emoji.decode');
        return Text(widget.alt, style: widget.style);
      },
    );
  }
}

/// How much bigger than the prose an emoji is drawn.
///
/// Discourse's stylesheet fixes `img.emoji` at 20px against a 15px body. Here
/// the surrounding style varies — a post is `bodyMedium`, an onebox body and a
/// user card bio are `bodySmall` — so the ratio is kept rather than the pixels,
/// the way [InlineCode] keeps `0.875`. Public because the composer draws the
/// same artwork over a shortcode someone is typing, and the two must agree.
const double emojiScale = 1.35;

/// Hands `<img class="emoji">` to [EmojiImage], for
/// [HtmlWidget.customWidgetBuilder].
///
/// Without this, emoji do not render at all: Discourse cooks them with a
/// root-relative `src`, [HtmlWidget] has no base URL to resolve that against,
/// and its `TagImg` falls back to the `alt` attribute — so every emoji in every
/// post reads as the literal text `:slight_smile:`.
///
/// [siteUrl] is what the relative `src` is resolved against, and is null where
/// this is drawn outside the shell — a quote in a test. The `alt` fallback
/// stands there, exactly as it did before this existed.
Widget? emojiWidgetBuilder(
  dom.Element element,
  String? siteUrl,
  TextStyle? baseStyle,
) {
  if (element.localName != 'img') return null;
  // `emoji` alone on a standard one, `emoji emoji-custom` on an upload, and
  // `emoji only-emoji` on a post that is nothing but emoji.
  if (!element.classes.contains('emoji')) return null;

  final url = absoluteEmojiUrl(element.attributes['src'], siteUrl);
  if (url == null) return null;

  final onlyEmoji = element.classes.contains('only-emoji');
  final emoji = EmojiImage(
    url: url,
    size: onlyEmoji ? 32 : (baseStyle?.fontSize ?? 14) * emojiScale,
    alt: element.attributes['alt'] ?? element.attributes['title'] ?? '',
    style: baseStyle,
  );

  return InlineCustomWidget(
    // HtmlWidget unwraps a paragraph containing one inline widget into that
    // widget directly. The paragraph's tight block width would then stretch
    // the image across the message and paint its artwork in the centre. Align
    // absorbs that width while giving the emoji its intended square.
    child: onlyEmoji
        ? Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            heightFactor: 1,
            child: emoji,
          )
        : emoji,
  );
}

/// Resolves a cooked emoji `src` against the site that cooked it.
///
/// Three shapes reach here, depending on whether the site has a CDN and where
/// its custom emoji are uploaded: absolute, protocol-relative, and — the usual
/// one — root-relative. Null when there is nothing to resolve it against, which
/// is not an error; see [emojiWidgetBuilder].
String? absoluteEmojiUrl(String? src, String? siteUrl) {
  if (src == null || src.isEmpty) return null;
  if (src.startsWith('//')) return 'https:$src';
  if (src.startsWith('http://') || src.startsWith('https://')) return src;
  if (siteUrl == null || siteUrl.isEmpty) return null;
  return '$siteUrl${src.startsWith('/') ? '' : '/'}$src';
}
