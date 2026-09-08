import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/avatar_loader.dart';
import '../data/media_pipeline.dart';
import '../foundation/diagnostic_errors.dart';
import 'image_decode.dart';

class AvatarImage extends StatefulWidget {
  const AvatarImage({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double size;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends State<AvatarImage> {
  AvatarBytes? _bytes;
  AvatarLoader? _sourceLoader;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      _sourceLoader = null;
      _bytes = null;
      _resolved = true;
      return;
    }

    final pipeline = MediaPipeline.instance;
    final loader = pipeline.avatars;
    _sourceLoader = loader;
    if (loader.isCached(url)) {
      // Paint synchronously on rebuild, so scrolling back does not flicker.
      _bytes = loader.cached(url);
      _resolved = true;
      return;
    }

    _resolved = false;
    unawaited(
      loader.load(url).then((bytes) {
        if (!mounted || widget.url != url) return;
        if (!identical(MediaPipeline.instance, pipeline)) {
          setState(_resolve);
          return;
        }
        setState(() {
          _bytes = bytes;
          _resolved = true;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: widget.size, child: _buildImage(context));

  Widget _buildImage(BuildContext context) {
    final bytes = _bytes;
    final url = widget.url;
    if (!_resolved || bytes == null || url == null) return widget.fallback;
    final loader = _sourceLoader;

    if (bytes.isSvg) {
      return SvgPicture.memory(
        bytes.bytes,
        width: widget.size,
        height: widget.size,
        fit: widget.fit,
        placeholderBuilder: (context) => widget.fallback,
        errorBuilder: (context, error, stackTrace) =>
            _decodeFallback(loader, url, bytes, error, stackTrace),
      );
    }

    return Image(
      image: memoryImageForLayout(
        context,
        bytes.bytes,
        logicalSize: Size.square(widget.size),
      ),
      width: widget.size,
      height: widget.size,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) =>
          _decodeFallback(loader, url, bytes, error, stackTrace),
    );
  }

  Widget _decodeFallback(
    AvatarLoader? loader,
    String url,
    AvatarBytes image,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (loader?.rejectAfterDecodeFailure(url, image) != false) {
      reportImageError(error, stackTrace, operation: 'avatar.decode');
    }
    if (widget.url == url && identical(_bytes, image)) _bytes = null;
    return widget.fallback;
  }
}
