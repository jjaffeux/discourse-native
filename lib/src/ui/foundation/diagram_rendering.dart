import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_all/webview_all.dart';

import '../../foundation/foreground_lifecycle.dart';

/// Describes an offline diagram renderer and its trusted bundled scripts.
class DiagramRenderer {
  const DiagramRenderer({
    required this.channel,
    required this.assets,
    required this.document,
  });

  final String channel;
  final List<String> assets;

  /// Build a local document that reports a PNG or error on [channel].
  final String Function(
    List<String> assets,
    String source,
    String? variant,
    bool dark,
  )
  document;
}

final class _RenderKey {
  const _RenderKey(
    this.renderer,
    this.source,
    this.variant,
    this.dark,
    this.bundle,
  );

  final DiagramRenderer renderer;
  final String? variant;

  final String source;
  final bool dark;
  final AssetBundle bundle;

  @override
  bool operator ==(Object other) =>
      other is _RenderKey &&
      identical(renderer, other.renderer) &&
      source == other.source &&
      variant == other.variant &&
      dark == other.dark &&
      identical(bundle, other.bundle);

  @override
  int get hashCode =>
      Object.hash(renderer, source, variant, dark, identityHashCode(bundle));
}

final _images = <_RenderKey, DiagramImage>{};
final _renders = _DiagramRenders();
var _cachedBytes = 0;

enum _RenderPhase { queued, active, retired }

final class _DiagramRenders {
  final _jobs = <_RenderKey, _DiagramRender>{};
  final _queued = <_DiagramRender>[];
  final _active = <_DiagramRender>{};
  Timer? _drainTimeout;
  bool _stalled = false;

  _DiagramLease? acquire(
    _RenderKey key,
    OverlayState overlay,
    VoidCallback onChanged,
  ) {
    if (_stalled) return null;
    var job = _jobs[key];
    if (job == null) {
      if (_queued.length + _active.length >= 32) return null;
      job = _DiagramRender(this, key);
      _jobs[key] = job;
      _queued.add(job);
    }
    final lease = _DiagramLease(job, overlay, onChanged);
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

  void _retire(_DiagramRender job) {
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

  void _rehost(_DiagramRender previous) {
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
    final replacement = _DiagramRender(this, previous.key, previous);
    _jobs[previous.key] = replacement;
    _queued.add(replacement);
    for (final lease in consumers) {
      lease.job = replacement;
      replacement._consumers.add(lease);
    }
    _drain();
  }
}

final class _DiagramLease {
  _DiagramLease(this.job, this.overlay, this.onChanged);

  _DiagramRender job;
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

final class _DiagramRender {
  _DiagramRender(this._owner, this.key, [this._predecessor]);

  final _DiagramRenders _owner;
  final _RenderKey key;
  OverlayState? _overlay;
  _DiagramRender? _predecessor;
  final _consumers = <_DiagramLease>{};
  final _setupDone = Completer<void>();
  final _viewRemoved = Completer<void>();
  final _viewKey = GlobalKey();
  _RenderPhase _phase = _RenderPhase.queued;
  WebViewController? _controller;
  OverlayEntry? _entry;
  bool _inserted = false;
  bool _setupFinished = false;
  Timer? _timeout;
  DiagramImage? image;
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
        key.renderer.channel,
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
                    : appL10n.couldNotReadTheRenderedDiagram,
              );
              return;
            }
            final rendered = DiagramImage._fromMessage(data);
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
      final assets = await Future.wait(
        key.renderer.assets.map((path) => key.bundle.loadString(path)),
      );
      if (!_current) return;
      await controller.loadHtmlString(
        key.renderer.document(assets, key.source, key.variant, key.dark),
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
      await controller.removeJavaScriptChannel(key.renderer.channel);
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

/// Shares renderer admission, caching and lifecycle across diagram views.
abstract class DiagramRenderState<T extends StatefulWidget> extends State<T>
    with WidgetsBindingObserver {
  DiagramRenderer get diagramRenderer;
  String get diagramSource;
  String? get diagramVariant => null;

  _RenderKey? _key;
  _DiagramLease? _lease;
  DiagramImage? _image;
  String? _error;

  DiagramImage? get diagramImage => _image;
  String? get diagramError => _error;

  void didChangeDiagram() {}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(_update);
  }

  void _update() {
    final key = _RenderKey(
      diagramRenderer,
      diagramSource,
      diagramVariant,
      Theme.of(context).brightness == Brightness.dark,
      DefaultAssetBundle.of(context),
    );
    if (key != _key) {
      _release();
      _key = key;
      _image = null;
      _error = null;
      didChangeDiagram();
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
}

final class DiagramImage {
  const DiagramImage._(this.bytes, this.width, this.height);
  factory DiagramImage._fromMessage(Map<String, dynamic> data) {
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
    return DiagramImage._(bytes, width.toDouble(), height.toDouble());
  }
  final Uint8List bytes;
  final double width;
  final double height;
  double get aspectRatio => width / height;
  Widget build(String label) => Image.memory(
    bytes,
    fit: BoxFit.contain,
    semanticLabel: label,
    errorBuilder: (_, _, _) => Text(appL10n.couldNotDisplayTheDiagram),
  );
}
