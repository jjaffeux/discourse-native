import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'composer_images.dart';

class ComposerImagePreview extends StatelessWidget {
  const ComposerImagePreview({
    super.key,
    required this.image,
    required this.url,
    required this.onNaturalSize,
  });

  final ComposerImageBlock image;
  final String? url;
  final void Function(Size size) onNaturalSize;

  static Size displaySize(ComposerImageBlock image) {
    final sourceWidth = image.width?.toDouble() ?? 360;
    final sourceHeight = image.height?.toDouble() ?? sourceWidth / (16 / 9);
    final scale = (image.scale ?? 100) / 100;
    final bound = [
      460 / sourceWidth,
      190 / sourceHeight,
      1.0,
    ].reduce((a, b) => a < b ? a : b);
    return Size(sourceWidth * bound * scale, sourceHeight * bound * scale);
  }

  @override
  Widget build(BuildContext context) {
    final size = displaySize(image);
    final source = url;

    return Semantics(
      image: source != null,
      label: image.alt.isEmpty ? 'Image' : image.alt,
      child: Container(
        width: size.width,
        height: size.height,
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _MeasuredNetworkImage(
                url: source,
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
    required this.onNaturalSize,
    required this.fallback,
  });

  final String url;
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
    if (oldWidget.url != widget.url) _listen();
  }

  void _listen() {
    if (_url == widget.url) return;
    final next = NetworkImage(
      widget.url,
    ).resolve(createLocalImageConfiguration(context));
    final oldListener = _listener;
    if (oldListener != null) _stream?.removeListener(oldListener);
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

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image.network(
    widget.url,
    fit: BoxFit.contain,
    frameBuilder: (context, child, frame, _) => frame == null
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : child,
    errorBuilder: (_, _, _) => widget.fallback,
  );
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
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
  );
}
