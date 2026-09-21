import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_all/webview_all.dart';

import '../foundation/focus_highlight.dart';
import '../foundation/mermaid_document.dart';
import '../foundation/tokens.dart';
import 'd_alert.dart';
import 'd_button.dart';
import 'd_dialog.dart';
import 'd_scroll_area.dart';
import 'd_spinner.dart';

const _assets = 'packages/discourse_native/src/ui/assets/mermaid';
typedef _RenderKey = ({String source, bool dark, AssetBundle bundle});
final _images = <_RenderKey, _MermaidImage>{};
var _cachedBytes = 0;
bool _licenseRegistered = false;

/// Offline Mermaid artwork with source access and an expanded zoom/pan view.
///
/// A short-lived local WebView renders the bundled Mermaid runtime to a bounded
/// image. The reader and expanded view use Flutter images, so diagrams do not
/// intercept post scrolling or retain native browser surfaces. Author links and
/// scripts are disabled. Syntax/platform errors leave the source accessible.
/// [height] constrains only the inline artwork; null fits it up to 420 pixels.
/// Mermaid owns diagram typography; use Expand to inspect small labels.
class DMermaid extends StatefulWidget {
  const DMermaid({
    super.key,
    required this.source,
    this.height,
    this.semanticLabel = 'Mermaid diagram',
    this.showControls = true,
  }) : assert(height == null || (height > 0 && height < double.infinity)),
       _expanded = false;

  const DMermaid._fullscreen({required this.source, required this.height})
    : semanticLabel = 'Mermaid diagram',
      showControls = true,
      _expanded = true;

  /// Hide reader actions when embedded beside an editable source pane.
  final bool showControls;
  final String source;
  final double? height;
  final String semanticLabel;
  final bool _expanded;

  @override
  State<DMermaid> createState() => _DMermaidState();
}

class _DMermaidState extends State<DMermaid> {
  _RenderKey? _key;
  WebViewController? _controller;
  _MermaidImage? _image;
  String? _error;
  Timer? _timeout;
  int _generation = 0;
  String _copyLabel = 'Copy source';

  @override
  void initState() {
    super.initState();
    if (!_licenseRegistered) {
      _licenseRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'mermaid',
        ], await rootBundle.loadString('$_assets/LICENSE'));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(DMermaid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final key = (
      source: widget.source,
      dark: Theme.of(context).brightness == Brightness.dark,
      bundle: DefaultAssetBundle.of(context),
    );
    if (key == _key) return;
    _key = key;
    _retire();
    _image = _images.remove(key);
    if (_image != null) _images[key] = _image!;
    _error = null;
    _copyLabel = 'Copy source';
    if (_image != null) return;
    if (key.source.trim().isEmpty || key.source.length > 50000) {
      _error = key.source.trim().isEmpty
          ? 'The diagram is empty.'
          : 'The diagram exceeds the 50,000 character limit.';
      return;
    }
    final generation = _generation;
    _timeout = Timer(const Duration(seconds: 20), () {
      if (_current(generation)) _fail('Diagram rendering timed out.');
    });
    unawaited(_render(key, generation));
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _render(_RenderKey key, int generation) async {
    try {
      final controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!_current(generation)) return;
      await controller.setBackgroundColor(Colors.transparent);
      if (!_current(generation)) return;
      await controller.addJavaScriptChannel(
        'NativeMermaid',
        onMessageReceived: (message) {
          if (!_current(generation)) return;
          try {
            if (message.message.length > 24000000) {
              throw const FormatException('Diagram image is too large.');
            }
            final data = jsonDecode(message.message);
            if (data is! Map<String, dynamic>) throw const FormatException();
            if (data['type'] == 'error') {
              final error = data['message'];
              _fail(
                error is String
                    ? error.substring(0, error.length.clamp(0, 500))
                    : 'Invalid Mermaid syntax.',
              );
              return;
            }
            final image = _MermaidImage.fromMessage(data);
            _cachedBytes -= _images.remove(key)?.bytes.length ?? 0;
            _images[key] = image;
            _cachedBytes += image.bytes.length;
            while (_images.length > 12 || _cachedBytes > 16000000) {
              _cachedBytes -= _images.remove(_images.keys.first)!.bytes.length;
            }
            _retire();
            setState(() => _image = image);
          } on Object {
            if (_current(generation)) {
              _fail('Could not read the rendered diagram.');
            }
          }
        },
      );
      if (!_current(generation)) return;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              _current(generation) && request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (_current(generation) && error.isForMainFrame == true) {
              _fail('Could not load the diagram renderer.');
            }
          },
        ),
      );
      if (!_current(generation)) return;
      final assets = await Future.wait([
        key.bundle.loadString('$_assets/mermaid-11.15.0.min.js'),
        key.bundle.loadString('$_assets/render.js'),
      ]);
      if (!_current(generation)) return;
      await controller.loadHtmlString(
        mermaidDocument(
          runtime: assets[0],
          renderer: assets[1],
          source: key.source,
          dark: key.dark,
        ),
      );
    } on Object {
      if (_current(generation)) _fail('Could not start the diagram renderer.');
    }
  }

  void _fail(String message) {
    _retire();
    setState(() => _error = message);
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
    // The platform has no controller.dispose API. Remove the Dart callback and
    // unload the document before dropping its view/controller references.
    try {
      await controller.removeJavaScriptChannel('NativeMermaid');
    } on Object {
      /* A partially configured platform may have no channel. */
    }
    try {
      await controller.loadHtmlString('<!doctype html><html></html>');
    } on Object {
      /* The native view may already have been destroyed. */
    }
  }

  @override
  void dispose() {
    _retire();
    super.dispose();
  }

  Future<void> _copy() async {
    final source = widget.source;
    try {
      await Clipboard.setData(ClipboardData(text: source));
      if (mounted && widget.source == source) {
        setState(() => _copyLabel = 'Copied');
      }
    } on Object {
      if (mounted) setState(() => _copyLabel = 'Copy failed');
    }
  }

  Future<void> _showSource() => showDDialog<void>(
    context: context,
    builder: (context, _) => DDialogContent(
      maxWidth: 720,
      children: [
        const DDialogHeader(
          children: [DDialogTitle(child: Text('Mermaid source'))],
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .5,
          child: DScrollArea(
            child: SelectableText(
              widget.source,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _expand() => showDDialog<void>(
    context: context,
    builder: (context, _) => DDialogContent(
      maxWidth: 1200,
      children: [
        const DDialogHeader(
          children: [DDialogTitle(child: Text('Mermaid diagram'))],
        ),
        DMermaid._fullscreen(
          source: widget.source,
          height: MediaQuery.sizeOf(context).height * .55,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error case final String error)
        DAlert(
          variant: DAlertVariant.destructive,
          title: const DAlertTitle(child: Text("Couldn't render diagram")),
          description: DAlertDescription(child: Text(error)),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 600.0;
            final height =
                widget.height ??
                (_image == null
                    ? 160.0
                    : (width / _image!.aspectRatio).clamp(80.0, 420.0));
            return SizedBox(
              height: height,
              child: switch (_image) {
                final _MermaidImage image =>
                  (widget._expanded
                      ? _MermaidZoom(image: image, label: widget.semanticLabel)
                      : image.build(widget.semanticLabel)),
                null => Stack(
                  children: [
                    if (_controller case final WebViewController controller)
                      Positioned(
                        top: 0,
                        left: 0,
                        width: 1,
                        height: 1,
                        child: ExcludeSemantics(
                          child: ExcludeFocus(
                            child: IgnorePointer(
                              child: WebViewWidget(controller: controller),
                            ),
                          ),
                        ),
                      ),
                    const Center(
                      child: DSpinner(semanticLabel: 'Rendering diagram'),
                    ),
                  ],
                ),
              },
            );
          },
        ),
      if (widget.showControls) ...[
        const SizedBox(height: DSpacing.sm),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              label: Text(_copyLabel),
              variant: DButtonVariant.ghost,
              onPressed: () => unawaited(_copy()),
            ),
            DButton(
              label: const Text('View source'),
              variant: DButtonVariant.ghost,
              onPressed: () => unawaited(_showSource()),
            ),
            if (!widget._expanded)
              DButton(
                label: const Text('Expand diagram'),
                variant: DButtonVariant.ghost,
                onPressed: _image == null ? null : () => unawaited(_expand()),
              ),
          ],
        ),
      ],
    ],
  );
}

final class _MermaidImage {
  const _MermaidImage(this.bytes, this.aspectRatio);
  factory _MermaidImage.fromMessage(Map<String, dynamic> data) {
    final width = data['width'];
    final height = data['height'];
    final png = data['png'];
    if (data['type'] != 'rendered' ||
        width is! num ||
        height is! num ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        png is! String) {
      throw const FormatException();
    }
    final bytes = base64Decode(png);
    if (bytes.length < 24 ||
        bytes.buffer.asByteData().getUint64(0) != 0x89504e470d0a1a0a) {
      throw const FormatException();
    }
    final dimensions = bytes.buffer.asByteData();
    final pixelsWide = dimensions.getUint32(16);
    final pixelsHigh = dimensions.getUint32(20);
    if (pixelsWide == 0 ||
        pixelsHigh == 0 ||
        pixelsWide > 4096 ||
        pixelsHigh > 4096 ||
        pixelsWide * pixelsHigh > 4000000 ||
        !(width / height).isFinite) {
      throw const FormatException();
    }
    return _MermaidImage(bytes, width / height);
  }
  final Uint8List bytes;
  final double aspectRatio;
  Widget build(String label) => Image.memory(
    bytes,
    fit: BoxFit.contain,
    semanticLabel: label,
    errorBuilder: (_, _, _) => const Text('Could not display the diagram.'),
  );
}

class _MermaidZoom extends StatefulWidget {
  const _MermaidZoom({required this.image, required this.label});
  final _MermaidImage image;
  final String label;
  @override
  State<_MermaidZoom> createState() => _MermaidZoomState();
}

class _MermaidZoomState extends State<_MermaidZoom> {
  final _transform = TransformationController();
  final _viewport = GlobalKey();
  bool _focused = false;
  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 8.0);
    if (next == 1) {
      _transform.value = Matrix4.identity();
      return;
    }
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    final center = box?.size.center(Offset.zero) ?? Offset.zero;
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(next / current, next / current, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final offset = switch (event.logicalKey) {
              LogicalKeyboardKey.arrowLeft => const Offset(40, 0),
              LogicalKeyboardKey.arrowRight => const Offset(-40, 0),
              LogicalKeyboardKey.arrowUp => const Offset(0, 40),
              LogicalKeyboardKey.arrowDown => const Offset(0, -40),
              _ => null,
            };
            if (offset == null) return KeyEventResult.ignored;
            _transform.value = _transform.value.clone()
              ..translateByDouble(offset.dx, offset.dy, 0, 1);
            return KeyEventResult.handled;
          },
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                width: 2,
                color: _focused && DFocusHighlight.visibleOf(context)
                    ? DTokens.of(context).focusRing
                    : Colors.transparent,
              ),
            ),
            child: InteractiveViewer(
              key: _viewport,
              transformationController: _transform,
              minScale: 1,
              maxScale: 8,
              child: SizedBox.expand(child: widget.image.build(widget.label)),
            ),
          ),
        ),
      ),
      const SizedBox(height: DSpacing.sm),
      Wrap(
        spacing: DSpacing.sm,
        children: [
          DButton(
            label: const Text('Zoom out'),
            variant: DButtonVariant.outline,
            onPressed: () => _zoom(1 / 1.5),
          ),
          DButton(
            label: const Text('Zoom in'),
            variant: DButtonVariant.outline,
            onPressed: () => _zoom(1.5),
          ),
          DButton(
            label: const Text('Fit'),
            variant: DButtonVariant.outline,
            onPressed: () => _transform.value = Matrix4.identity(),
          ),
        ],
      ),
    ],
  );
}
