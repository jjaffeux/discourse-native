import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../data/site_image_repository.dart';
import '../plugin_api/plugin_registry.dart';
import '../theme/d_button.dart';
import 'image_decode.dart';
import 'shell_scope.dart';
import 'site_url.dart';

class SiteImage extends StatefulWidget {
  const SiteImage({
    super.key,
    required this.url,
    required this.siteUrl,
    this.repository,
    this.fit,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.onNaturalSize,
    this.loadingBuilder,
    this.errorBuilder,
    this.gifPlaybackControls = false,
    this.knownAnimated = false,
  });

  final String url;
  final String? siteUrl;
  final SiteImageRepository? repository;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final ValueChanged<Size>? onNaturalSize;
  final WidgetBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final bool gifPlaybackControls;
  final bool knownAnimated;

  @override
  State<SiteImage> createState() => _SiteImageState();
}

class _SiteImageState extends State<SiteImage> {
  SiteImageRepository? _repository;
  SiteImageBytes? _bytes;
  Object? _error;
  StackTrace? _errorStack;
  bool _resolved = false;
  bool _configured = false;
  int _generation = 0;
  ImageStream? _stream;
  ImageStreamListener? _streamListener;
  Size? _reportedNaturalSize;

  String get _url => resolveSiteUrl(widget.url, widget.siteUrl);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository =
        widget.repository ?? ShellScope.maybeIdentityOf(context)?.siteImages;
    if (identical(repository, _repository) && _configured) return;
    _repository = repository;
    _resolve();
  }

  @override
  void didUpdateWidget(SiteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.repository, widget.repository) ||
        (oldWidget.onNaturalSize == null) != (widget.onNaturalSize == null)) {
      _repository =
          widget.repository ?? ShellScope.maybeIdentityOf(context)?.siteImages;
      _resolve();
    }
  }

  void _resolve() {
    _configured = true;
    final generation = ++_generation;
    _stopListening();
    _reportedNaturalSize = null;
    _bytes = null;
    _error = null;
    _errorStack = null;

    final repository = _repository;
    final siteUrl = widget.siteUrl;
    final url = _url;
    if (url.isEmpty) {
      _resolved = true;
      _error = SiteImageUnavailableException(url);
      return;
    }

    if (repository == null || siteUrl == null) {
      _resolved = true;
      if (widget.onNaturalSize != null && !_isSvgUrl(url)) {
        _listen(NetworkImage(url));
      }
      return;
    }

    if (repository.isCached(siteUrl: siteUrl, url: url)) {
      _bytes = repository.cached(siteUrl: siteUrl, url: url);
      _resolved = true;
      if (_bytes == null) _error = SiteImageUnavailableException(url);
      _listenToBytes();
      return;
    }

    _resolved = false;
    unawaited(
      repository
          .load(siteUrl: siteUrl, url: url)
          .then(
            (bytes) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _bytes = bytes;
                _resolved = true;
                if (bytes == null) {
                  _error = SiteImageUnavailableException(url);
                }
              });
              _listenToBytes();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _resolved = true;
                _error = error;
                _errorStack = stackTrace;
              });
            },
          ),
    );
  }

  void _listenToBytes() {
    final bytes = _bytes;
    if (bytes == null || bytes.isSvg || widget.onNaturalSize == null) return;
    _listen(MemoryImage(bytes.bytes));
  }

  void _listen(ImageProvider<Object> provider) {
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      if (_reportedNaturalSize == size) return;
      _reportedNaturalSize = size;
      widget.onNaturalSize?.call(size);
    });
    _stream = stream;
    _streamListener = listener;
    stream.addListener(listener);
  }

  void _stopListening() {
    final listener = _streamListener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _streamListener = null;
  }

  @override
  void dispose() {
    _generation++;
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!_resolved) {
      child = widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    } else if (_error case final error?) {
      child =
          widget.errorBuilder?.call(
            context,
            error,
            _errorStack ?? StackTrace.current,
          ) ??
          const SizedBox.shrink();
    } else if (_repository == null || widget.siteUrl == null) {
      child = _networkImage();
    } else if (_bytes case final bytes?) {
      child = bytes.isSvg ? _svg(bytes) : _raster(bytes);
    } else {
      child = const SizedBox.shrink();
    }

    if (widget.excludeFromSemantics) {
      child = ExcludeSemantics(child: child);
    } else if (widget.semanticLabel case final label?) {
      child = Semantics(
        image: true,
        label: label,
        child: ExcludeSemantics(child: child),
      );
    }

    if (!widget.gifPlaybackControls || !_isAnimated) return child;

    final appSettings = ShellScope.maybeIdentityOf(context)?.appSettings;
    if (appSettings == null) {
      return _GifPlaybackControl(disabledByDefault: false, child: child);
    }
    return ListenableBuilder(
      listenable: appSettings,
      child: child,
      builder: (context, child) => _GifPlaybackControl(
        disabledByDefault: appSettings.disableGifAnimations,
        child: child!,
      ),
    );
  }

  bool get _isAnimated =>
      widget.knownAnimated ||
      _bytes?.isAnimated == true ||
      Uri.tryParse(_url)?.path.toLowerCase().endsWith('.gif') == true;

  Widget _networkImage() {
    if (_isSvgUrl(_url)) {
      return SvgPicture.network(
        _url,
        fit: widget.fit ?? BoxFit.contain,
        width: widget.width,
        height: widget.height,
        excludeFromSemantics: true,
        placeholderBuilder: (context) =>
            widget.loadingBuilder?.call(context) ?? const SizedBox.shrink(),
        errorBuilder: (context, error, stackTrace) =>
            widget.errorBuilder?.call(context, error, stackTrace) ??
            const SizedBox.shrink(),
      );
    }
    return Image.network(
      _url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, _) =>
          frame == null ? widget.loadingBuilder?.call(context) ?? child : child,
      errorBuilder: widget.errorBuilder,
    );
  }

  Widget _svg(SiteImageBytes image) => SvgPicture.memory(
    image.bytes,
    fit: widget.fit ?? BoxFit.contain,
    width: widget.width,
    height: widget.height,
    excludeFromSemantics: true,
    placeholderBuilder: (context) =>
        widget.loadingBuilder?.call(context) ?? const SizedBox.shrink(),
    errorBuilder: (context, error, stackTrace) =>
        widget.errorBuilder?.call(context, error, stackTrace) ??
        const SizedBox.shrink(),
  );

  Widget _raster(SiteImageBytes image) {
    ImageProvider<Object> provider = MemoryImage(image.bytes);
    if (widget.cacheWidth != null || widget.cacheHeight != null) {
      provider = ResizeImage(
        provider,
        width: widget.cacheWidth,
        height: widget.cacheHeight,
        policy: ResizeImagePolicy.fit,
      );
    }
    return Image(
      image: provider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      errorBuilder: widget.errorBuilder,
    );
  }

  static bool _isSvgUrl(String url) =>
      Uri.tryParse(url)?.path.toLowerCase().endsWith('.svg') == true;
}

class _GifPlaybackControl extends StatefulWidget {
  const _GifPlaybackControl({
    required this.disabledByDefault,
    required this.child,
  });

  final bool disabledByDefault;
  final Widget child;

  @override
  State<_GifPlaybackControl> createState() => _GifPlaybackControlState();
}

class _GifPlaybackControlState extends State<_GifPlaybackControl> {
  late bool _playing = !widget.disabledByDefault;

  @override
  void didUpdateWidget(_GifPlaybackControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disabledByDefault != widget.disabledByDefault) {
      _playing = !widget.disabledByDefault;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inheritedMediaQuery = MediaQuery.maybeOf(context);
    final image = inheritedMediaQuery == null
        ? widget.child
        : MediaQuery(
            data: inheritedMediaQuery.copyWith(disableAnimations: !_playing),
            child: widget.child,
          );
    final action = _playing ? 'Pause GIF' : 'Play GIF';

    return Stack(
      fit: StackFit.passthrough,
      children: [
        image,
        PositionedDirectional(
          end: 4,
          bottom: 4,
          child: DButton.iconOnly(
            key: const ValueKey('gif-playback-toggle'),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 18),
            tooltip: action,
            semanticLabel: action,
            size: DButtonSize.small,
            onPressed: () => setState(() => _playing = !_playing),
          ),
        ),
      ],
    );
  }
}

final class SiteImageUnavailableException implements Exception {
  const SiteImageUnavailableException(this.url);

  final String url;

  @override
  String toString() => 'Site image is unavailable: $url';
}

final class SiteImageWidgetFactory extends WidgetFactory {
  SiteImageWidgetFactory({
    required this.siteUrl,
    this.registry = PluginRegistry.empty,
    this.onMiddleClickUrl,
  });

  final String? siteUrl;
  final PluginRegistry registry;
  final ValueChanged<String>? onMiddleClickUrl;
  final Set<dom.Element> _excludeLinkSemantics = Set.identity();

  @override
  void parse(BuildTree tree) {
    super.parse(tree);

    final prefix = registry.cookedInlinePrefix(tree.element);
    if (prefix == null) return;
    if (prefix.excludeLinkSemantics) {
      _excludeLinkSemantics.add(tree.element);
    }

    tree.register(
      BuildOp(
        alwaysRenderBlock: false,
        debugLabel: 'plugin-cooked-inline-prefix',
        onRenderInline: (tree) {
          tree.prepend(
            WidgetBit.inline(tree, prefix.child, alignment: prefix.alignment),
          );
        },
      ),
    );
  }

  @override
  GestureRecognizer? buildGestureRecognizer(
    BuildTree tree, {
    GestureTapCallback? onTap,
  }) {
    final recognizer = super.buildGestureRecognizer(tree, onTap: onTap);
    final href = tree.element.attributes['href'];
    if (recognizer is TapGestureRecognizer &&
        href != null &&
        onMiddleClickUrl != null) {
      recognizer.onTertiaryTapUp = (_) =>
          onMiddleClickUrl!(urlFull(href) ?? href);
    }
    return recognizer;
  }

  @override
  Widget? buildGestureDetector(
    BuildTree tree,
    Widget child,
    GestureRecognizer recognizer,
  ) {
    var detector = super.buildGestureDetector(tree, child, recognizer);
    if (detector != null &&
        recognizer is TapGestureRecognizer &&
        recognizer.onTertiaryTapUp != null) {
      detector = GestureDetector(
        excludeFromSemantics: true,
        onTertiaryTapUp: recognizer.onTertiaryTapUp,
        child: detector,
      );
    }
    if (detector == null || !_excludeLinkSemantics.contains(tree.element)) {
      return detector;
    }
    return ExcludeSemantics(child: detector);
  }

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final uri = Uri.tryParse(src.url);
    if (uri == null ||
        uri.scheme == 'asset' ||
        uri.scheme == 'data' ||
        uri.scheme == 'file') {
      return super.buildImageWidget(tree, src);
    }

    final metadata = src.image;
    final semanticLabel = metadata?.alt ?? metadata?.title;
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            constraints.hasBoundedWidth &&
                constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0
            ? constraints.maxWidth
            : src.width;
        final cacheWidth =
            logicalWidth != null && logicalWidth.isFinite && logicalWidth > 0
            ? imagePhysicalPixels(context, logicalWidth.clamp(1, 10000))
            : null;
        return SiteImage(
          url: src.url,
          siteUrl: siteUrl,
          fit: BoxFit.fill,
          cacheWidth: cacheWidth,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
          gifPlaybackControls: true,
          loadingBuilder: (context) =>
              onLoadingBuilder(context, tree, null, src) ??
              const SizedBox.shrink(),
          errorBuilder: (context, error, stackTrace) =>
              onErrorBuilder(context, tree, error, src) ??
              const SizedBox.shrink(),
        );
      },
    );
  }
}
