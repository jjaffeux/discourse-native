import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:webview_all/webview_all.dart';

import 'd_button.dart';
import 'd_card.dart';
import 'd_context_menu.dart';
import 'd_dialog.dart';
import 'd_scroll_area.dart';
import 'd_slider.dart';

bool _licenseRegistered = false;
const _document = 'packages/discourse_native/src/ui/assets/math/index.html';

enum DMathInput { tex, ascii }

enum DMathJaxOutput { html, svg }

sealed class DMathConfiguration {
  const DMathConfiguration();
  Map<String, Object?> toMessage();
}

final class DMathJax extends DMathConfiguration {
  const DMathJax({
    this.output = DMathJaxOutput.html,
    this.menu = true,
    this.zoom = false,
    this.accessibility = false,
  });
  final DMathJaxOutput output;
  final bool menu, zoom, accessibility;
  @override
  Map<String, Object?> toMessage() => {
    'engine': 'mathjax',
    'output': output.name,
    'accessibility': accessibility,
    'menu': menu,
    'zoom': zoom,
  };
  @override
  bool operator ==(Object other) =>
      other is DMathJax &&
      output == other.output &&
      menu == other.menu &&
      zoom == other.zoom &&
      accessibility == other.accessibility;
  @override
  int get hashCode => Object.hash(output, menu, zoom, accessibility);
}

final class DMathKatex extends DMathConfiguration {
  const DMathKatex();
  @override
  Map<String, Object?> toMessage() => {'engine': 'katex'};
  @override
  bool operator ==(Object other) => other is DMathKatex;
  @override
  int get hashCode => 0x4b61546558;
}

@immutable
final class DMathExpression {
  const DMathExpression(
    this.source, {
    this.input = DMathInput.tex,
    this.display = false,
  });
  final String source;
  final DMathInput input;
  final bool display;
  Map<String, Object?> toMessage() => {
    'source': source,
    'input': input.name,
    'display': display,
  };
}

/// Offline engine output remains a live, isolated document for math semantics.
/// Source remains readable when the platform or expression cannot render.
class DMath extends StatefulWidget {
  const DMath({
    super.key,
    required this.expression,
    required this.configuration,
    this.context = const [],
    this.contextIndex,
    this.onLink,
    this.fontSize,
    this.onEdit,
  });
  final DMathExpression expression;
  final DMathConfiguration configuration;
  final List<DMathExpression> context;
  final int? contextIndex;
  final ValueChanged<String>? onLink;
  final double? fontSize;
  final VoidCallback? onEdit;
  @override
  State<DMath> createState() => _DMathState();
}

class _DMathState extends State<DMath> with WidgetsBindingObserver {
  ScrollPosition? _scrollPosition;
  bool _visible = false;
  bool _visibilityScheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _scheduleVisibility() {
    if (_visibilityScheduled) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (!mounted) return;
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) return;
      var viewport = Offset.zero & MediaQuery.sizeOf(context);
      RenderObject child = render;
      bool paints = TickerMode.valuesOf(context).enabled;
      while (child.parent != null) {
        final parent = child.parent!;
        if (!parent.paintsChild(child)) paints = false;
        if (parent is RenderAbstractViewport && parent is RenderBox) {
          viewport = viewport.intersect(
            MatrixUtils.transformRect(
              parent.getTransformTo(null),
              parent.paintBounds,
            ),
          );
        }
        child = parent;
      }
      final bounds = MatrixUtils.transformRect(
        render.getTransformTo(null),
        render.paintBounds,
      );
      final visible = paints && viewport.overlaps(bounds);
      if (visible == _visible) return;
      setState(() {
        _visible = visible;
        _requestIdentity = null;
        if (visible) {
          _update();
        } else {
          ++_generation;
          _view?.retire();
          _view = null;
          _rendered = false;
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        (state == AppLifecycleState.resumed && _view != null)) {
      return;
    }
    setState(() {
      if (state == AppLifecycleState.resumed) {
        _requestIdentity = null;
        _update();
      } else {
        ++_generation;
        _view?.retire();
        _view = null;
        _rendered = false;
      }
    });
  }

  _MathView? _view;
  String? _requestIdentity;
  final _menu = DContextMenuTriggerController();
  int _generation = 0;
  double _width = 80, _height = 28, _baseline = 22;
  bool _rendered = false;
  Map<String, String> _formats = const {};
  List<_MathMenuEntry> _engineMenu = const [];
  DMathJax? _configurationOverride;
  DMathConfiguration get _configuration =>
      _configurationOverride ?? widget.configuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_licenseRegistered) {
      _licenseRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(
          ['MathJax', 'MathJax NewCM', 'KaTeX'],
          await rootBundle.loadString(
            'packages/discourse_native/src/ui/assets/math/NOTICE.txt',
          ),
        );
      });
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_scheduleVisibility);
      _scrollPosition = position;
      position?.addListener(_scheduleVisibility);
    }
    _scheduleVisibility();
    _update();
  }

  @override
  void didUpdateWidget(DMath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration != widget.configuration) {
      _configurationOverride = null;
    }
    _update();
  }

  void _update() {
    _scheduleVisibility();
    if (!_visible || !TickerMode.valuesOf(context).enabled) return;
    final bounded = _mathContext(
      widget.expression,
      widget.context,
      widget.contextIndex,
    );
    final style = DefaultTextStyle.of(context).style;
    final color = style.color ?? Theme.of(context).colorScheme.onSurface;
    var background = Colors.transparent;
    context.visitAncestorElements((element) {
      if (element.widget case Material(color: final color?)) {
        background = Color.alphaBlend(background, color);
      }
      return background.a < 1;
    });
    background = Color.alphaBlend(background, DCard.surfaceColorOf(context));
    final request = <String, Object?>{
      'v': 1,
      ...widget.expression.toMessage(),
      'config': _configuration.toMessage(),
      'editable': widget.onEdit != null,
      'context': bounded.expressions.map((e) => e.toMessage()).toList(),
      'contextIndex': bounded.index,
      'color':
          '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'background':
          '#${background.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'fontSize':
          widget.fontSize ??
          MediaQuery.textScalerOf(context).scale(
            style.fontSize ?? Theme.of(context).textTheme.bodyLarge!.fontSize!,
          ),
    };
    final identity = jsonEncode(request);
    if (_requestIdentity == identity) return;
    _requestIdentity = identity;
    _view?.retire();
    _view = null;
    _rendered = false;
    _formats = const {};
    _engineMenu = const [];
    final generation = ++_generation;
    if (widget.expression.source.trim().isEmpty ||
        widget.expression.source.length > 16384 ||
        identity.length > 131072) {
      return;
    }
    final view = _view = _MathView(
      background: background,
      request: {...request, 'generation': generation},
      current: () => mounted && generation == _generation,
      onMessage: _message,
      onChanged: () {
        if (mounted && generation == _generation) setState(() {});
      },
    );
    view.start();
  }

  void _message(Map<String, dynamic> data) {
    if (data['generation'] != _generation) return;
    switch (data['type']) {
      case 'result':
        final width = data['width'],
            height = data['height'],
            baseline = data['baseline'];
        if (width is! num ||
            height is! num ||
            !width.isFinite ||
            !height.isFinite ||
            width <= 0 ||
            height <= 0 ||
            width > 16384 ||
            height > 4096 ||
            baseline is! num ||
            !baseline.isFinite ||
            baseline < 0 ||
            baseline > height) {
          return;
        }
        _view?.finish();
        final formats = data['formats'];
        _engineMenu = _MathMenuEntry.parse(data['menu']);
        _formats = formats is Map<String, dynamic>
            ? {
                for (final entry in formats.entries)
                  if ([
                        'mathml',
                        'svg',
                        'speech',
                        'braille',
                      ].contains(entry.key) &&
                      entry.value is String &&
                      (entry.value as String).length <= 65536)
                    entry.key: entry.value as String,
              }
            : const {};
        setState(() {
          _width = width.toDouble();
          _height = height.toDouble();
          _baseline = baseline.toDouble();
          _rendered = true;
        });
      case 'error':
        _view?.retire();
        setState(() {
          _view = null;
          _rendered = false;
        });
      case 'link':
        if (data['url'] case final String url when url.length <= 2048) {
          widget.onLink?.call(url);
        }
      case 'menu':
        if (widget.configuration case DMathJax(menu: true) || DMathKatex()) {
          final x = data['x'], y = data['y'];
          if (x is num && y is num && x.isFinite && y.isFinite) {
            _menu.openAt(Offset(x.toDouble(), y.toDouble()));
          }
        }
      case 'menuText':
        if (data['text'] case final String value when value.length <= 65536) {
          if (data['copy'] == true) {
            unawaited(Clipboard.setData(ClipboardData(text: value)));
          } else {
            unawaited(
              _showFormat(
                data['label'] is String ? data['label'] as String : 'mathml',
                value,
              ),
            );
          }
        }
      case 'zoom':
        final scale = data['scale'];
        if (scale is num && scale.isFinite && scale >= 1 && scale <= 5) {
          unawaited(_expand(scale: scale.toDouble()));
        }
      case 'scale':
        final scale = data['scale'];
        if (scale is num && scale.isFinite && scale >= .5 && scale <= 4) {
          unawaited(_showScale(scale.toDouble()));
        }
      case 'activate':
        widget.onEdit?.call();
    }
  }

  Future<void> _expand({double scale = 1.75}) async {
    final fontSize =
        widget.fontSize ??
        MediaQuery.textScalerOf(context).scale(
          DefaultTextStyle.of(context).style.fontSize ??
              Theme.of(context).textTheme.bodyLarge!.fontSize!,
        );
    await showDDialog<void>(
      context: context,
      builder: (context, controller) => DDialogContent(
        maxWidth: 900,
        children: [
          DDialogTitle(child: Text(context.l10n.mathExpression)),
          DMath(
            expression: widget.expression,
            configuration: switch (_configuration) {
              DMathJax(:final output, :final accessibility) => DMathJax(
                output: output,
                accessibility: accessibility,
              ),
              final DMathKatex value => value,
            },
            context: widget.context,
            contextIndex: widget.contextIndex,
            onLink: widget.onLink,
            fontSize: fontSize * scale,
          ),
          DButton(
            label: Text(context.l10n.close),
            onPressed: () => controller.close(),
          ),
        ],
      ),
    );
  }

  void _setConfiguration(DMathJax? value) {
    setState(() {
      _configurationOverride = value;
      _requestIdentity = null;
      _update();
    });
  }

  String _formatLabel(BuildContext context, String format) => switch (format) {
    'mathml' => context.l10n.mathMathml,
    'svg' => context.l10n.mathSvg,
    'speech' => context.l10n.mathSpeech,
    'braille' => context.l10n.mathBraille,
    _ => format,
  };
  Future<void> _showFormat(String format, String value) async {
    await showDDialog<void>(
      context: context,
      builder: (context, controller) => DDialogContent(
        maxWidth: 700,
        children: [
          DDialogTitle(child: Text(_formatLabel(context, format))),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: DScrollArea(child: SelectionArea(child: Text(value))),
          ),
          DButton(
            label: Text(context.l10n.copySource),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
    );
  }

  Future<void> _menuAction(_MathMenuEntry entry, [double? value]) async {
    await _runMenuScript(
      'window.mathMenuAction(${jsonEncode({'v': 1, 'generation': _generation, 'id': entry.id, 'value': ?value})});',
    );
  }

  Future<void> _runMenuScript(String script) async {
    final view = _view;
    if (!mounted || view == null) return;
    try {
      await view.controller?.runJavaScript(script);
    } on PlatformException {
      // The native surface may retire while a menu action is in flight.
    }
  }

  Widget _menuEntry(_MathMenuEntry entry) => switch (entry.type) {
    'rule' => const DContextMenuSeparator(),
    'label' => DContextMenuLabel(child: Text(entry.label)),
    'submenu' => DContextMenuSub(
      trigger: Text(entry.label),
      enabled: !entry.disabled,
      children: entry.children.map(_menuEntry).toList(),
    ),
    'checkbox' || 'radio' || 'radioCompare' => DContextMenuCheckboxItem(
      checked: entry.checked,
      enabled: !entry.disabled,
      onChanged: (_) => _menuAction(entry),
      child: Text(entry.label),
    ),
    'slider' => DSlider(
      value: entry.value,
      min: 0,
      max: 100,
      onChanged: entry.disabled ? null : (value) => _menuAction(entry, value),
      semanticLabel: entry.label.isEmpty
          ? context.l10n.mathOpacity
          : entry.label,
    ),
    _ => DContextMenuItem(
      onPressed: entry.disabled ? null : () => _menuAction(entry),
      child: Text(entry.label),
    ),
  };
  Future<void> _showScale(double initialScale) async {
    var scale = initialScale * 100;
    await showDDialog<void>(
      context: context,
      builder: (context, dialog) => StatefulBuilder(
        builder: (context, setState) => DDialogContent(
          children: [
            DDialogTitle(child: Text(context.l10n.mathScale)),
            DSlider(
              value: scale,
              min: 50,
              max: 400,
              onChanged: (value) {
                setState(() => scale = value);
                unawaited(
                  _runMenuScript(
                    'window.mathMenuScale(${jsonEncode({'generation': _generation, 'value': value / 100})});',
                  ),
                );
              },
            ),
            DButton(
              label: Text(context.l10n.close),
              onPressed: () => dialog.close(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Stack(
      children: [
        SizedBox(width: _width, height: _height),
        if (!_rendered) Text(widget.expression.source),
        if (_view?.controller case final controller?)
          SizedBox(
            width: _width,
            height: _height,
            child: Opacity(
              opacity: _rendered ? 1 : 0,
              child: WebViewWidget(
                key: ObjectKey(_view),
                controller: controller,
              ),
            ),
          ),
      ],
    );
    content = DScrollArea(axes: DScrollAxes.horizontal, child: content);
    if (!widget.expression.display) {
      final inline = content;
      content = LayoutBuilder(
        builder: (_, constraints) => SizedBox(
          width: _width.clamp(0, constraints.maxWidth),
          child: inline,
        ),
      );
    }
    if (widget.configuration case DMathJax(menu: true) || DMathKatex()) {
      content = DContextMenu(
        content: DContextMenuContent(
          children: [
            if (_engineMenu.isNotEmpty)
              ..._engineMenu.map(_menuEntry)
            else ...[
              DContextMenuItem(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: widget.expression.source),
                ),
                child: Text(context.l10n.copySource),
              ),
              DContextMenuItem(
                onPressed: _expand,
                child: Text(context.l10n.expand),
              ),
              for (final format in _formats.entries)
                DContextMenuItem(
                  onPressed: () => _showFormat(format.key, format.value),
                  child: Text(_formatLabel(context, format.key)),
                ),
              if (_configuration case final DMathJax configuration) ...[
                const DContextMenuSeparator(),
                DContextMenuItem(
                  onPressed: () => _setConfiguration(
                    DMathJax(
                      output: configuration.output == DMathJaxOutput.html
                          ? DMathJaxOutput.svg
                          : DMathJaxOutput.html,
                      menu: configuration.menu,
                      zoom: configuration.zoom,
                      accessibility: configuration.accessibility,
                    ),
                  ),
                  child: Text(
                    configuration.output == DMathJaxOutput.html
                        ? context.l10n.mathUseSvg
                        : context.l10n.mathUseHtml,
                  ),
                ),
                DContextMenuCheckboxItem(
                  checked: configuration.accessibility,
                  onChanged: (value) => _setConfiguration(
                    DMathJax(
                      output: configuration.output,
                      menu: configuration.menu,
                      zoom: configuration.zoom,
                      accessibility: value,
                    ),
                  ),
                  child: Text(context.l10n.mathAccessibility),
                ),
                DContextMenuItem(
                  onPressed: () => _setConfiguration(null),
                  child: Text(context.l10n.mathReset),
                ),
              ],
            ],
          ],
        ),
        child: DContextMenuTrigger(controller: _menu, child: content),
      );
    }
    return _MathBaseline(baseline: _baseline, child: content);
  }

  @override
  void dispose() {
    ++_generation;
    _scrollPosition?.removeListener(_scheduleVisibility);
    WidgetsBinding.instance.removeObserver(this);
    _view?.retire();
    super.dispose();
  }
}

/// Teardown waits for setup so a late channel/load cannot resurrect a retired view.
final class _MathView {
  _MathView({
    required this.background,
    required this.request,
    required this.current,
    required this.onMessage,
    required this.onChanged,
  });
  final Color background;
  final Map<String, Object?> request;
  final bool Function() current;
  final void Function(Map<String, dynamic>) onMessage;
  final VoidCallback onChanged;
  WebViewController? controller;
  Uri? _initialDocument;
  Future<void>? _setup;
  Timer? _timeout;
  bool _retired = false;
  bool _admitted = false;
  static final _active = <_MathView>{};
  static final _waiting = <_MathView>[];
  bool get active => !_retired && current();

  void start() {
    _timeout = Timer(const Duration(seconds: 20), () {
      if (!active) return;
      onMessage({'type': 'error', 'generation': request['generation']});
    });
    if (_active.length < 16) {
      _admit();
    } else {
      _waiting.add(this);
    }
  }

  void _admit() {
    if (!active) return;
    _admitted = true;
    _active.add(this);
    _setup = _start();
  }

  Future<void> _start() async {
    try {
      final view = controller = WebViewController();
      onChanged();
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!active) return;
      await view.setBackgroundColor(background);
      if (!active) return;
      await view.addJavaScriptChannel(
        'NativeMath',
        onMessageReceived: (message) {
          if (!active || message.message.length > 270000) return;
          try {
            final data = jsonDecode(message.message);
            if (data is! Map<String, dynamic> || data['v'] != 1) return;
            if (data['type'] == 'ready') {
              unawaited(
                view
                    .runJavaScript('window.renderMath(${jsonEncode(request)});')
                    .catchError((Object _) {
                      if (active) {
                        onMessage({
                          'type': 'error',
                          'generation': request['generation'],
                        });
                      }
                    }),
              );
            } else {
              onMessage(data);
            }
          } on FormatException {
            return;
          }
        },
      );
      if (!active) return;
      await view.setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _navigationDecision),
      );
      if (!active) return;
      await view.loadFlutterAsset(_document);
    } on Object {
      if (active) {
        onMessage({'type': 'error', 'generation': request['generation']});
      }
    }
  }

  NavigationDecision _navigationDecision(NavigationRequest request) {
    if (!active ||
        !request.isMainFrame ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(request.url)) {
      return NavigationDecision.prevent;
    }
    final uri = Uri.tryParse(request.url);
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return NavigationDecision.prevent;
    }
    final localAsset =
        uri.scheme == 'file' ||
        (uri.scheme == 'https' &&
            RegExp(
              r'^flutter-assets-[0-9a-f]{32}\.webview\.invalid$',
            ).hasMatch(uri.host));
    if (!localAsset) return NavigationDecision.prevent;
    try {
      if (!Uri.decodeComponent(uri.path).endsWith('/$_document')) {
        return NavigationDecision.prevent;
      }
    } on FormatException {
      return NavigationDecision.prevent;
    }
    _initialDocument ??= uri;
    return uri == _initialDocument
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  void finish() {
    _timeout?.cancel();
    _releaseAdmission();
  }

  void _releaseAdmission() {
    if (!_admitted) return;
    _admitted = false;
    _active.remove(this);
    while (_active.length < 16 && _waiting.isNotEmpty) {
      _waiting.removeAt(0)._admit();
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _waiting.remove(this);
    _timeout?.cancel();
    unawaited(_release().whenComplete(_releaseAdmission));
  }

  Future<void> _release() async {
    await _setup;
    final view = controller;
    if (view == null) return;
    try {
      await view.removeJavaScriptChannel('NativeMath');
      await view.setJavaScriptMode(JavaScriptMode.disabled);
      await view.loadHtmlString('<!doctype html><html></html>');
    } on Object {
      /* The platform view may already have been removed. */
    }
  }
}

class _MathBaseline extends SingleChildRenderObjectWidget {
  const _MathBaseline({required this.baseline, required super.child});
  final double baseline;
  @override
  _RenderMathBaseline createRenderObject(BuildContext context) =>
      _RenderMathBaseline(baseline);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMathBaseline renderObject,
  ) => renderObject.baseline = baseline;
}

class _RenderMathBaseline extends RenderProxyBox {
  _RenderMathBaseline(this._baseline);
  double _baseline;
  set baseline(double value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _baseline.clamp(0, size.height);
}

({List<DMathExpression> expressions, int? index}) _mathContext(
  DMathExpression selected,
  List<DMathExpression> context,
  int? index,
) {
  final validIndex = index != null && index >= 0 && index < context.length;
  final selectedIndex = validIndex ? index : context.length;
  return (
    expressions: [
      for (var i = 0; i < context.length; i++)
        if (i == selectedIndex)
          selected
        else if (context[i].source.length > 16384)
          DMathExpression(
            '',
            input: context[i].input,
            display: context[i].display,
          )
        else
          context[i],
      if (!validIndex) selected,
    ],
    index: selectedIndex,
  );
}

final class _MathMenuEntry {
  const _MathMenuEntry(
    this.id,
    this.type,
    this.label,
    this.disabled,
    this.checked,
    this.value,
    this.children,
  );
  final String id, type, label;
  final bool disabled, checked;
  final double value;
  final List<_MathMenuEntry> children;
  static List<_MathMenuEntry> parse(Object? data, [int depth = 0]) {
    if (data is! List || depth > 8 || data.length > 200) return const [];
    return [
      for (final item in data)
        if (item is Map<String, dynamic> &&
            item['id'] is String &&
            item['type'] is String &&
            item['label'] is String &&
            (item['label'] as String).length <= 160)
          _MathMenuEntry(
            item['id'] as String,
            item['type'] as String,
            item['label'] as String,
            item['disabled'] == true,
            item['checked'] == true,
            item['value'] is num && (item['value'] as num).isFinite
                ? (item['value'] as num).toDouble().clamp(0, 100)
                : 0,
            parse(item['children'], depth + 1),
          ),
    ];
  }
}
