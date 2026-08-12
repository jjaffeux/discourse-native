import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'composer_images.dart';
import 'image_decode.dart';

class ComposerImagePreview extends StatelessWidget {
  const ComposerImagePreview({
    super.key,
    required this.image,
    required this.url,
    required this.onNaturalSize,
    this.highlighted = false,
  });

  final ComposerImageBlock image;
  final String? url;
  final void Function(Size size) onNaturalSize;
  final bool highlighted;

  static Size displaySize(ComposerImageBlock image) {
    final sourceSize =
        safeImageLayoutSize(
          image.width?.toDouble(),
          image.height?.toDouble(),
        ) ??
        const Size(360, 360 / (16 / 9));
    final sourceWidth = sourceSize.width;
    final sourceHeight = sourceSize.height;
    final suppliedScale = image.scale;
    final scale =
        suppliedScale != null && suppliedScale >= 1 && suppliedScale <= 100
        ? suppliedScale / 100
        : 1.0;
    final bound = [
      460 / sourceWidth,
      190 / sourceHeight,
      1.0,
    ].reduce((a, b) => a < b ? a : b);
    return Size(
      (sourceWidth * bound * scale).clamp(0.0, 460.0),
      (sourceHeight * bound * scale).clamp(0.0, 190.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = displaySize(image);
    final source = url;

    return Semantics(
      // A pending upload has no resolved URL yet, but it is still an image
      // preview rather than ordinary text.
      image: true,
      label: image.alt.isEmpty ? 'Image' : image.alt,
      selected: highlighted,
      child: Container(
        width: size.width,
        height: size.height,
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: highlighted
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: highlighted ? 2 : 1,
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: source == null
            ? _ImageFallback(label: image.alt)
            : _isSvg(source)
            ? SvgPicture.network(
                source,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _ImageFallback(label: image.alt),
                placeholderBuilder: (_) => const Center(
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              )
            : _MeasuredNetworkImage(
                url: source,
                logicalSize: size,
                measureNaturalSize: !image.hasDimensions,
                onNaturalSize: onNaturalSize,
                fallback: _ImageFallback(label: image.alt),
              ),
      ),
    );
  }

  static bool _isSvg(String url) =>
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') == true;
}

class _MeasuredNetworkImage extends StatefulWidget {
  const _MeasuredNetworkImage({
    required this.url,
    required this.logicalSize,
    required this.measureNaturalSize,
    required this.onNaturalSize,
    required this.fallback,
  });

  final String url;
  final Size logicalSize;
  final bool measureNaturalSize;
  final void Function(Size size) onNaturalSize;
  final Widget fallback;

  @override
  State<_MeasuredNetworkImage> createState() => _MeasuredNetworkImageState();
}

class _MeasuredNetworkImageState extends State<_MeasuredNetworkImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(_MeasuredNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.measureNaturalSize != widget.measureNaturalSize) {
      _listen();
    }
  }

  void _listen() {
    if (!widget.measureNaturalSize) {
      _stopListening();
      return;
    }
    if (_url == widget.url && _listener != null) return;
    _stopListening();
    final next = NetworkImage(
      widget.url,
    ).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      widget.onNaturalSize(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
      );
    });
    _stream = next;
    _url = widget.url;
    _listener = listener;
    next.addListener(listener);
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
    _url = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: composerPreviewImageProvider(
      context,
      url: widget.url,
      logicalSize: widget.logicalSize,
      measureNaturalSize: widget.measureNaturalSize,
    ),
    fit: BoxFit.contain,
    frameBuilder: (context, child, frame, _) => frame == null
        ? const Center(
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          )
        : child,
    errorBuilder: (_, _, _) => widget.fallback,
  );
}

/// Creates the preview provider without resolving it, so decode policy can be
/// verified without making a media request.
@visibleForTesting
ImageProvider<Object> composerPreviewImageProvider(
  BuildContext context, {
  required String url,
  required Size logicalSize,
  required bool measureNaturalSize,
}) {
  final provider = NetworkImage(url);
  if (measureNaturalSize ||
      !logicalSize.width.isFinite ||
      !logicalSize.height.isFinite ||
      logicalSize.width <= 0 ||
      logicalSize.height <= 0) {
    return provider;
  }
  return ResizeImage(
    provider,
    width: imagePhysicalPixels(context, logicalSize.width),
    height: imagePhysicalPixels(context, logicalSize.height),
    policy: ResizeImagePolicy.fit,
  );
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label.isEmpty ? 'Image' : label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
