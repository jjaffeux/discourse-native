import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import '../foundation/embed_document.dart';
import '../foundation/native_webview_scroll.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_card.dart';
import 'd_spinner.dart';

// Leave the Card's existing outline visible beneath the native platform view.
const _embedBorderInsets = EdgeInsets.only(left: 1, right: 1, bottom: 1);

/// A bounded iframe with Native loading and failure controls.
///
/// The caller validates the provider's URL and supplies its exact trusted
/// [origins], including redirect origins. [canNavigate] can recognize canonical
/// URLs for the same content; otherwise only the original path may navigate
/// inside the view. Other HTTP(S) destinations go to [onOpenLink].
/// The provider owns the embedded content and its appearance. Surrounding
/// chrome uses Native tokens. Touch readers retain vertical drag scrolling;
/// macOS views use a root overlay to keep native pointer interaction above
/// Flutter's card surfaces and forward wheel events to the surrounding reader.
/// Self-contained `data:text/html` documents support offline examples; they use
/// an opaque origin (`null`) and cannot navigate to other embedded documents.
class DEmbed extends StatefulWidget {
  const DEmbed({
    super.key,
    required this.uri,
    required this.origins,
    required this.title,
    required this.externalUri,
    required this.onOpenLink,
    this.openLabel = 'Open in browser',
    this.height = 500,
    this.resizeMessageType,
    this.canNavigate,
    this.onError,
  });

  final Uri uri;
  final Set<String> origins;
  final String title;
  final Uri externalUri;
  final ValueChanged<Uri> onOpenLink;
  final String openLabel;

  /// Initial viewport height, bounded to 120–2000 logical pixels.
  final double height;

  /// Optional provider message type with a numeric `data` height. Both object
  /// and JSON-string messages are accepted, from this iframe and [origins] only.
  final String? resizeMessageType;

  /// Narrows navigation within [origins], for providers that canonicalize paths.
  final bool Function(Uri uri)? canNavigate;
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<DEmbed> createState() => _DEmbedState();
}

class _DEmbedState extends State<DEmbed> {
  WebViewController? _controller;
  Timer? _timeout;
  int _generation = 0;
  bool _loading = true;
  bool _failed = false;
  late double _height;

  static double _boundedHeight(double value) =>
      value.isFinite && value > 0 ? value.clamp(120.0, 2000.0) : 500;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(DEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        !setEquals(oldWidget.origins, widget.origins) ||
        oldWidget.resizeMessageType != widget.resizeMessageType) {
      _initialize();
    }
  }

  void _initialize() {
    _retire();
    _height = _boundedHeight(widget.height);
    _loading = true;
    _failed = false;
    if (!_isEmbedUri(widget.uri)) {
      _failed = true;
      _loading = false;
      return;
    }
    final generation = _generation;
    _timeout = Timer(const Duration(seconds: 20), () {
      if (_current(generation)) {
        _fail(TimeoutException('Embed loading timed out'), StackTrace.current);
      }
    });
    unawaited(_configure(generation));
  }

  bool _current(int generation) => mounted && generation == _generation;

  bool get _localDocument => widget.uri.scheme == 'data';

  bool _isEmbedUri(Uri uri) {
    if (_localDocument) {
      try {
        return uri == widget.uri && uri.data?.mimeType == 'text/html';
      } on FormatException {
        return false;
      }
    }
    return uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        widget.origins.contains(uri.origin) &&
        (widget.canNavigate?.call(uri) ?? uri.path == widget.uri.path);
  }

  Future<void> _configure(int generation) async {
    WebViewController? controller;
    try {
      controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!_current(generation)) return;
      await controller.setBackgroundColor(Colors.transparent);
      if (!_current(generation)) return;
      await controller.addJavaScriptChannel(
        'NativeEmbed',
        onMessageReceived: (message) {
          if (!_current(generation)) return;
          if (message.message == 'loaded') {
            _timeout?.cancel();
            setState(() => _loading = false);
            return;
          }
          if (message.message.length > 256) return;
          try {
            final data = jsonDecode(message.message);
            if (data is! Map<String, dynamic>) return;
            final height = data['height'];
            if (height is! num || !height.isFinite || height <= 0) return;
            setState(() => _height = _boundedHeight(height.toDouble()));
          } on FormatException {
            // Ignore messages which do not belong to the resize protocol.
          }
        },
      );
      if (!_current(generation)) return;
      final documentBase = _localDocument ? null : '${widget.uri.origin}/';
      var loadingDocument = true;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!_current(generation)) {
              // Retirement unloads the old document after callbacks are detached.
              return request.url == 'about:blank'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            if (request.isMainFrame &&
                loadingDocument &&
                (request.url == 'about:blank' || request.url == documentBase)) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (!request.isMainFrame && _isEmbedUri(uri)) {
              return NavigationDecision.navigate;
            }
            if (_isExternalUri(uri)) widget.onOpenLink(uri);
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) => loadingDocument = false,
          onWebResourceError: (error) {
            if (!_current(generation)) return;
            final uri = Uri.tryParse(error.url ?? '');
            if (error.isForMainFrame == true ||
                (uri != null && _isEmbedUri(uri))) {
              _fail(StateError(error.description), StackTrace.current);
            }
          },
          onHttpError: (error) {
            if (!_current(generation)) return;
            final uri = error.request?.uri ?? error.response?.uri;
            // WebKit currently omits the URL on document HTTP failures.
            if (uri == null || _isEmbedUri(uri)) {
              _fail(StateError('Embed request failed'), StackTrace.current);
            }
          },
        ),
      );
      if (!_current(generation)) return;
      await controller.loadHtmlString(
        embedDocument(
          uri: widget.uri,
          title: widget.title,
          origins: widget.origins,
          resizeMessageType: widget.resizeMessageType,
        ),
        baseUrl: documentBase,
      );
    } on Object catch (error, stackTrace) {
      if (_current(generation)) _fail(error, stackTrace);
    } finally {
      // A platform operation may finish after disposal or URL replacement.
      if (!_current(generation) && controller != null) {
        unawaited(_release(controller));
      }
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    _retire();
    setState(() {
      _failed = true;
      _loading = false;
    });
    widget.onError?.call(error, stackTrace);
  }

  void _retire() {
    _generation++;
    _timeout?.cancel();
    _timeout = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_release(controller));
  }

  Future<void> _release(WebViewController controller) async {
    // The platform API has no dispose; detach callbacks and unload the iframe.
    try {
      await controller.removeJavaScriptChannel('NativeEmbed');
    } on Object {
      // Partially initialized platforms may not have a channel.
    }
    try {
      await controller.loadHtmlString('<!doctype html><html></html>');
    } on Object {
      // Its native view may already have been removed.
    }
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DCard(
    size: DCardSize.small,
    trailing: _failed
        ? null
        : SizedBox(
            height: _height + _embedBorderInsets.vertical,
            child: _controller == null
                ? const SizedBox.shrink()
                : _EmbedViewport(
                    child: Semantics(
                      label: widget.title,
                      child: WebViewWidget(
                        controller: _controller!,
                        gestureRecognizers: const {
                          Factory<TapGestureRecognizer>(
                            TapGestureRecognizer.new,
                          ),
                        },
                      ),
                    ),
                  ),
          ),
    children: [
      DCardHeader(
        title: DCardTitle(child: Text(widget.title)),
        action: _loading
            ? DCardAction(
                child: DSpinner(semanticLabel: 'Loading ${widget.title}'),
              )
            : null,
      ),
      if (_failed)
        DCardContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Could not load this embed.'),
              const SizedBox(height: DSpacing.sm),
              Wrap(
                spacing: DSpacing.controlGap,
                runSpacing: DSpacing.xs,
                children: [
                  if (_isEmbedUri(widget.uri))
                    DButton(
                      label: const Text('Retry'),
                      variant: DButtonVariant.outline,
                      onPressed: () => setState(_initialize),
                    ),
                  DButton(
                    label: Text(widget.openLabel),
                    variant: DButtonVariant.link,
                    isLink: true,
                    onPressed: _isExternalUri(widget.externalUri)
                        ? () => widget.onOpenLink(widget.externalUri)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );
}

class _EmbedViewport extends StatefulWidget {
  const _EmbedViewport({required this.child});
  final Widget child;

  @override
  State<_EmbedViewport> createState() => _EmbedViewportState();
}

class _EmbedViewportState extends State<_EmbedViewport> {
  final _link = LayerLink();
  final _anchor = GlobalKey();
  final _surface = GlobalKey();
  final _overlay = OverlayPortalController();
  Size _size = Size.zero;
  Rect? _viewport;
  Object? _syncToken;

  void _syncGeometry({required bool sizeChanged}) {
    final token = Object();
    _syncToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_syncToken, token)) return;
      final overlayBox =
          Overlay.of(context, rootOverlay: true).context.findRenderObject()
              as RenderBox?;
      final viewportBox =
          Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
      Rect? viewport;
      if (overlayBox != null &&
          overlayBox.hasSize &&
          viewportBox != null &&
          viewportBox.hasSize) {
        viewport =
            viewportBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
            viewportBox.size;
      }
      final changed = _viewport != viewport || sizeChanged;
      _viewport = viewport;
      if (!_overlay.isShowing) {
        NativeWebViewScrollBridge.register(this, _scroll);
        _overlay.show();
      } else if (changed) {
        setState(() {});
      }
    });
  }

  bool _scroll(Offset globalPosition, double delta) {
    if (!mounted) return false;
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    var bounds = box.localToGlobal(Offset.zero) & box.size;
    final viewport =
        Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (viewport != null && viewport.attached && viewport.hasSize) {
      final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (!bounds.overlaps(visible)) return false;
      bounds = bounds.intersect(visible);
    }
    if (!bounds.contains(globalPosition)) return false;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      hit,
      globalPosition,
      View.of(context).viewId,
    );
    final surface = _surface.currentContext?.findRenderObject();
    if (!hit.path.any((entry) => identical(entry.target, surface))) {
      return false;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != null && position.hasContentDimensions) {
      position.pointerScroll(delta);
    }
    return true;
  }

  @override
  void dispose() {
    NativeWebViewScrollBridge.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: _embedBorderInsets,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(
            (DTokens.of(context).radius * 1.4 - _embedBorderInsets.bottom)
                .clamp(0.0, double.infinity),
          ),
        ),
        child: widget.child,
      ),
    );
    if (defaultTargetPlatform != TargetPlatform.macOS) return content;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final changed = size != _size;
        _size = size;
        _syncGeometry(sizeChanged: changed);
        return OverlayPortal(
          controller: _overlay,
          overlayLocation: OverlayChildLocation.rootOverlay,
          overlayChildBuilder: (context) => Positioned.fill(
            child: ClipRect(
              clipper: _EmbedViewportClipper(_viewport),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CompositedTransformFollower(
                      link: _link,
                      showWhenUnlinked: false,
                      child: SizedBox.fromSize(
                        key: _surface,
                        size: _size,
                        child: content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: CompositedTransformTarget(
            key: _anchor,
            link: _link,
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _EmbedViewportClipper extends CustomClipper<Rect> {
  const _EmbedViewportClipper(this.viewport);
  final Rect? viewport;

  @override
  Rect getClip(Size size) {
    final bounds = Offset.zero & size;
    final visible = viewport;
    if (visible == null) return bounds;
    return visible.overlaps(bounds) ? visible.intersect(bounds) : Rect.zero;
  }

  @override
  bool shouldReclip(_EmbedViewportClipper oldClipper) =>
      viewport != oldClipper.viewport;
}

bool _isExternalUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.hasAuthority &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;
