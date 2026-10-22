import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_all/webview_all.dart';

import '../../foundation/foreground_lifecycle.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/mermaid_document.dart';
import '../foundation/tokens.dart';
import 'd_alert.dart';
import 'd_button.dart';
import 'd_dialog.dart';
import 'd_scroll_area.dart';
import 'd_skeleton.dart';

const _assets = 'packages/discourse_native/src/ui/assets/mermaid';

final class _RenderKey {
  const _RenderKey(this.source, this.dark, this.bundle);

  final String source;
  final bool dark;
  final AssetBundle bundle;

  @override
  bool operator ==(Object other) =>
      other is _RenderKey &&
      source == other.source &&
      dark == other.dark &&
      identical(bundle, other.bundle);

  @override
  int get hashCode => Object.hash(source, dark, identityHashCode(bundle));
}

final _images = <_RenderKey, _MermaidImage>{};
final _renders = _MermaidRenders();
var _cachedBytes = 0;
bool _licenseRegistered = false;

enum _RenderPhase { queued, active, retired }

final class _MermaidRenders {
  final _jobs = <_RenderKey, _MermaidRender>{};
  final _queued = <_MermaidRender>[];
  final _active = <_MermaidRender>{};
  Timer? _drainTimeout;
  bool _stalled = false;

  _MermaidLease? acquire(
    _RenderKey key,
    OverlayState overlay,
    VoidCallback onChanged,
  ) {
    if (_stalled) return null;
    var job = _jobs[key];
    if (job == null) {
      if (_queued.length + _active.length >= 32) return null;
      job = _MermaidRender(this, key);
      _jobs[key] = job;
      _queued.add(job);
    }
    final lease = _MermaidLease(job, overlay, onChanged);
    job._consumers.add(lease);
    _drain();
    job._checkHost();
    return lease;
  }

  void _drain() {
    while (_active.length < 2 && _queued.isNotEmpty) {
      final ready = _queued.indexWhere(
        (job) => job._predecessor?._viewRemoved.isCompleted ?? true,
      );
      if (ready == -1) return;
      final job = _queued.removeAt(ready);
      _active.add(job);
      job._start();
    }
  }

  void _retire(_MermaidRender job) {
    _jobs.remove(job.key);
    if (!_queued.remove(job)) {
      unawaited(
        job._release().whenComplete(() {
          _active.remove(job);
          _watchDrain();
          _drain();
        }),
      );
    }
    _watchDrain();
  }

  void _watchDrain() {
    final blocked =
        _active.length == 2 &&
        _active.every((job) => job._phase == _RenderPhase.retired);
    if (!blocked) {
      _stalled = false;
      _drainTimeout?.cancel();
      _drainTimeout = null;
    } else if (_drainTimeout == null && !_stalled) {
      _drainTimeout = Timer(const Duration(seconds: 20), () {
        _drainTimeout = null;
        _stalled = true;
        for (final job in _queued.toList()) {
          job._fail(appL10n.couldNotStartTheDiagramRenderer);
        }
      });
    }
  }

  void _rehost(_MermaidRender previous) {
    final consumers = previous._consumers.toList();
    previous._consumers.clear();
    previous._retire();
    if (_stalled ||
        _queued.length + _active.length >= 32 ||
        !consumers.any((lease) => lease.overlay.mounted)) {
      previous.error = appL10n.couldNotStartTheDiagramRenderer;
      previous._consumers.addAll(consumers);
      return;
    }
    final replacement = _MermaidRender(this, previous.key, previous);
    _jobs[previous.key] = replacement;
    _queued.add(replacement);
    for (final lease in consumers) {
      lease.job = replacement;
      replacement._consumers.add(lease);
    }
    _drain();
  }
}

final class _MermaidLease {
  _MermaidLease(this.job, this.overlay, this.onChanged);

  _MermaidRender job;
  final OverlayState overlay;
  final VoidCallback onChanged;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    job._consumers.remove(this);
    if (job._consumers.isEmpty) {
      job._retire();
    } else {
      job._checkHost();
    }
  }
}

final class _MermaidRender {
  _MermaidRender(this._owner, this.key, [this._predecessor]);

  final _MermaidRenders _owner;
  final _RenderKey key;
  OverlayState? _overlay;
  _MermaidRender? _predecessor;
  final _consumers = <_MermaidLease>{};
  final _setupDone = Completer<void>();
  final _viewRemoved = Completer<void>();
  final _viewKey = GlobalKey();
  _RenderPhase _phase = _RenderPhase.queued;
  WebViewController? _controller;
  OverlayEntry? _entry;
  bool _inserted = false;
  bool _setupFinished = false;
  Timer? _timeout;
  _MermaidImage? image;
  String? error;

  bool get _current => _phase == _RenderPhase.active;

  void _start() {
    _predecessor = null;
    _phase = _RenderPhase.active;
    for (final lease in _consumers) {
      if (lease.overlay.mounted) {
        _overlay = lease.overlay;
        break;
      }
    }
    if (_overlay == null) {
      _fail(appL10n.couldNotStartTheDiagramRenderer);
      return;
    }
    _timeout = Timer(const Duration(seconds: 20), () {
      _fail(appL10n.diagramRenderingTimedOut);
    });
    unawaited(_render());
  }

  void _checkHost() {
    scheduleMicrotask(() {
      if (_current && _overlay?.mounted == false) _owner._rehost(this);
    });
  }

  void _notify() {
    scheduleMicrotask(() {
      for (final lease in _consumers.toList()) {
        if (!lease._released) lease.onChanged();
      }
    });
  }

  void _mount(WebViewController controller) {
    final entry = _entry = OverlayEntry(
      maintainState: true,
      builder: (_) => Positioned(
        top: 0,
        left: 0,
        width: 1,
        height: 1,
        child: ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: WebViewWidget(key: _viewKey, controller: controller),
            ),
          ),
        ),
      ),
    );
    entry.addListener(() {
      if (!entry.mounted) _checkHost();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_current) return;
      final overlay = _overlay!;
      if (!overlay.mounted) {
        _owner._rehost(this);
        return;
      }
      overlay.insert(entry);
      _inserted = true;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _render() async {
    try {
      final controller = _controller = WebViewController();
      _mount(controller);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!_current) return;
      await controller.setBackgroundColor(Colors.transparent);
      if (!_current) return;
      await controller.addJavaScriptChannel(
        'NativeMermaid',
        onMessageReceived: (message) {
          if (!_current) return;
          try {
            if (message.message.length > 24000000) {
              throw FormatException(appL10n.diagramImageIsTooLarge);
            }
            final data = jsonDecode(message.message);
            if (data is! Map<String, dynamic>) throw const FormatException();
            if (data['type'] == 'error') {
              final message = data['message'];
              _fail(
                message is String
                    ? message.substring(0, message.length.clamp(0, 500))
                    : appL10n.invalidMermaidSyntax,
              );
              return;
            }
            final rendered = _MermaidImage.fromMessage(data);
            _cachedBytes -= _images.remove(key)?.bytes.length ?? 0;
            _images[key] = rendered;
            _cachedBytes += rendered.bytes.length;
            while (_images.length > 12 || _cachedBytes > 16000000) {
              _cachedBytes -= _images.remove(_images.keys.first)!.bytes.length;
            }
            image = rendered;
            _retire();
          } on Object {
            if (_current) _fail(appL10n.couldNotReadTheRenderedDiagram);
          }
        },
      );
      if (!_current) return;
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              _current && request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (_current && error.isForMainFrame == true) {
              _fail(appL10n.couldNotLoadTheDiagramRenderer);
            }
          },
        ),
      );
      if (!_current) return;
      final assets = await Future.wait([
        key.bundle.loadString('$_assets/mermaid-11.17.2.min.js'),
        key.bundle.loadString('$_assets/render.js'),
      ]);
      if (!_current) return;
      await controller.loadHtmlString(
        mermaidDocument(
          runtime: assets[0],
          renderer: assets[1],
          source: key.source,
          dark: key.dark,
        ),
      );
    } on Object {
      if (_current) _fail(appL10n.couldNotStartTheDiagramRenderer);
    } finally {
      _setupFinished = true;
      _setupDone.complete();
    }
  }

  void _fail(String message) {
    if (_phase == _RenderPhase.retired) return;
    error = message;
    _retire();
  }

  void _retire() {
    if (_phase == _RenderPhase.retired) return;
    _phase = _RenderPhase.retired;
    _timeout?.cancel();
    _timeout = null;
    _owner._retire(this);
    _notify();
  }

  Future<void> _unmount() async {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    final removed = Completer<void>();

    void remove() {
      if (_inserted) {
        void unmounted() {
          if (!entry.mounted && !removed.isCompleted) removed.complete();
        }

        entry.addListener(unmounted);
        entry.remove();
        unmounted();
      } else {
        removed.complete();
      }
      entry.dispose();
    }

    await Future<void>.value();
    if (!_inserted || _overlay?.mounted != true) {
      remove();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
      WidgetsBinding.instance.scheduleFrame();
    }
    await removed.future;
  }

  Future<void> _release() async {
    final unmounted = _unmount().then((_) {
      _viewRemoved.complete();
      _owner._drain();
    });
    final controller = _controller;
    if (controller != null) {
      final setupFinished = _setupFinished;
      await _clear(controller);
      if (!setupFinished) {
        await _setupDone.future;
        await _clear(controller);
      }
    }
    await unmounted;
    _controller = null;
  }

  Future<void> _clear(WebViewController controller) async {
    // The platform has no controller.dispose API. Clear callbacks and unload
    // again after pending setup settles so it cannot restore retired content.
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
}

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

    this.showControls = true,
  }) : assert(height == null || (height > 0 && height < double.infinity)),
       _expanded = false;

  const DMermaid._fullscreen({required this.source, required this.height})
    : showControls = true,
      _expanded = true;

  /// Hide reader actions when embedded beside an editable source pane.
  final bool showControls;
  final String source;
  final double? height;

  String get semanticLabel => appL10n.mermaidDiagram;
  final bool _expanded;

  @override
  State<DMermaid> createState() => _DMermaidState();
}

class _DMermaidState extends State<DMermaid> with WidgetsBindingObserver {
  _RenderKey? _key;
  _MermaidLease? _lease;
  _MermaidImage? _image;
  String? _error;
  String _copyLabel = appL10n.copySource;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(_update);
  }

  void _update() {
    final key = _RenderKey(
      widget.source,
      Theme.of(context).brightness == Brightness.dark,
      DefaultAssetBundle.of(context),
    );
    if (key != _key) {
      _release();
      _key = key;
      _image = null;
      _error = null;
      _copyLabel = appL10n.copySource;
    }
    if (!TickerMode.valuesOf(context).enabled ||
        !isForegroundLifecycle(WidgetsBinding.instance.lifecycleState)) {
      _release();
      return;
    }
    if (_image != null || _error != null || _lease != null) return;
    _image = _images.remove(key);
    if (_image != null) {
      _images[key] = _image!;
      return;
    }
    if (key.source.trim().isEmpty || key.source.length > 50000) {
      _error = key.source.trim().isEmpty
          ? appL10n.theDiagramIsEmpty
          : appL10n.theDiagramExceedsThe50000CharacterLimit;
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      _lease = _renders.acquire(key, overlay, _renderChanged);
    }
    if (_lease == null) _error = appL10n.couldNotStartTheDiagramRenderer;
  }

  void _renderChanged() {
    if (!mounted) return;
    final job = _lease?.job;
    if (job == null || (job.image == null && job.error == null)) return;
    setState(() {
      _image = job.image;
      _error = job.error;
      _release();
    });
  }

  void _release() {
    final lease = _lease;
    if (lease != null) {
      _image ??= lease.job.image;
      _error ??= lease.job.error;
      lease.release();
    }
    _lease = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  Future<void> _copy() async {
    final source = widget.source;
    try {
      await Clipboard.setData(ClipboardData(text: source));
      if (mounted && widget.source == source) {
        setState(() => _copyLabel = appL10n.copied);
      }
    } on Object {
      if (mounted) setState(() => _copyLabel = appL10n.copyFailed);
    }
  }

  Future<void> _showSource() => showDDialog<void>(
    context: context,
    builder: (context, _) => DDialogContent(
      maxWidth: 720,
      children: [
        DDialogHeader(
          children: [DDialogTitle(child: Text(appL10n.mermaidSource))],
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
        DDialogHeader(
          children: [DDialogTitle(child: Text(appL10n.mermaidDiagram))],
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
          title: DAlertTitle(child: Text(context.l10n.couldnTRenderDiagram)),
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
                null => DSkeletonRegion(
                  semanticsLabel: context.l10n.renderingDiagram,
                  child: const DSkeleton(),
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
              label: Text(context.l10n.viewSource),
              variant: DButtonVariant.ghost,
              onPressed: () => unawaited(_showSource()),
            ),
            if (!widget._expanded)
              DButton(
                label: Text(context.l10n.expandDiagram),
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
    errorBuilder: (_, _, _) => Text(appL10n.couldNotDisplayTheDiagram),
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
            label: Text(context.l10n.zoomOut),
            variant: DButtonVariant.outline,
            onPressed: () => _zoom(1 / 1.5),
          ),
          DButton(
            label: Text(context.l10n.zoomIn),
            variant: DButtonVariant.outline,
            onPressed: () => _zoom(1.5),
          ),
          DButton(
            label: Text(context.l10n.fit),
            variant: DButtonVariant.outline,
            onPressed: () => _transform.value = Matrix4.identity(),
          ),
        ],
      ),
    ],
  );
}
