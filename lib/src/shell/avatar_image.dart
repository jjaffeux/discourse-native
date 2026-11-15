import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/avatar_loader.dart';
import '../data/cached_image_bytes.dart';
import '../data/media_pipeline.dart';
import 'image_decode.dart';
import 'own_avatar_overrides.dart';
import 'shell_scope.dart';

/// Names whose picture the avatars below it are, so one the signed-in
/// account has since replaced is drawn as the current one. An avatar outside
/// any owner is drawn from the URL it was given.
class AvatarOwner extends InheritedWidget {
  const AvatarOwner({
    super.key,
    required this.siteUrl,
    required this.username,
    required super.child,
  });

  final String siteUrl;
  final String username;

  @override
  bool updateShouldNotify(AvatarOwner oldWidget) =>
      siteUrl != oldWidget.siteUrl || username != oldWidget.username;
}

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
  CachedImageBytes? _bytes;
  AvatarLoader? _sourceLoader;
  bool _resolved = false;
  AvatarOwner? _owner;
  OwnAvatarOverrides? _overrides;
  String? _url;
  bool _started = false;

  String? get _current {
    final owner = _owner;
    final overrides = _overrides;
    return owner == null || overrides == null
        ? widget.url
        : overrides.urlFor(owner.siteUrl, owner.username, widget.url);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owner = context.dependOnInheritedWidgetOfExactType<AvatarOwner>();
    final overrides = _owner == null
        ? null
        : ShellScope.maybeIdentityOf(context)?.ownAvatars;
    if (!identical(overrides, _overrides)) {
      _overrides?.removeListener(_select);
      _overrides = overrides?..addListener(_select);
    }
    if (_started && _current == _url) return;
    _started = true;
    _resolve();
  }

  @override
  void didUpdateWidget(AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_current != _url) _resolve();
  }

  // Only an avatar whose own picture was replaced rebuilds.
  void _select() {
    if (_current != _url) setState(_resolve);
  }

  @override
  void dispose() {
    _overrides?.removeListener(_select);
    super.dispose();
  }

  void _resolve() {
    final url = _url = _current;
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
        if (!mounted || _url != url) return;
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
    final url = _url;
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
            _decodeFallback(loader, url, bytes),
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
          _decodeFallback(loader, url, bytes),
    );
  }

  Widget _decodeFallback(
    AvatarLoader? loader,
    String url,
    CachedImageBytes image,
  ) {
    loader?.rejectAfterDecodeFailure(url, image);
    if (_url == url && identical(_bytes, image)) _bytes = null;
    return widget.fallback;
  }
}
