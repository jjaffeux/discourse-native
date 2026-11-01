import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:webview_all/webview_all.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'd_button.dart';
import 'd_context_menu.dart';
import 'd_dialog.dart';
import 'd_scroll_area.dart';

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

class _DMathState extends State<DMath> {
  _MathView? _view;
  String? _requestIdentity;
  final _menu = DContextMenuTriggerController();
  int _generation = 0;
  double _width = 80, _height = 28, _baseline = 22;
  bool _rendered = false;
  Map<String, String> _formats = const {};
  DMathJax? _configurationOverride;
  DMathConfiguration get _configuration =>
      _configurationOverride ?? widget.configuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    final style = DefaultTextStyle.of(context).style;
    final color = style.color ?? Theme.of(context).colorScheme.onSurface;
    final request = <String, Object?>{
      'v': 1,
      ...widget.expression.toMessage(),
      'config': _configuration.toMessage(),
      'context': widget.context.map((e) => e.toMessage()).toList(),
      'contextIndex': widget.contextIndex,
      'color':
          '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'fontSize':
          widget.fontSize ??
          MediaQuery.textScalerOf(context).scale(style.fontSize ?? 16),
    };
    final identity = jsonEncode(request);
    if (_requestIdentity == identity) return;
    _requestIdentity = identity;
    _view?.retire();
    _view = null;
    _rendered = false;
    _formats = const {};
    final generation = ++_generation;
    if (widget.expression.source.length > 16384 ||
        identity.length > 131072 ||
        widget.context.length > 128) {
      return;
    }
    final view = _view = _MathView(
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
        if (widget.configuration case DMathJax(menu: true)) {
          final x = data['x'], y = data['y'];
          if (x is num && y is num && x.isFinite && y.isFinite) {
            _menu.openAt(Offset(x.toDouble(), y.toDouble()));
          }
        }
      case 'activate':
        if (widget.configuration case DMathJax(zoom: true)) {
          unawaited(_expand());
        }
    }
  }

  Future<void> _expand() async {
    await showDDialog<void>(
      context: context,
      builder: (context, controller) => DDialogContent(
        maxWidth: 900,
        children: [
          DDialogTitle(child: Text(context.l10n.mathExpression)),
          DMath(
            expression: widget.expression,
            configuration: switch (widget.configuration) {
              DMathJax(:final output, :final accessibility) => DMathJax(
                output: output,
                accessibility: accessibility,
              ),
              final DMathKatex value => value,
            },
            context: widget.context,
            contextIndex: widget.contextIndex,
            onLink: widget.onLink,
            fontSize:
                (widget.fontSize ??
                    DefaultTextStyle.of(context).style.fontSize ??
                    16) *
                1.75,
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
    _ => context.l10n.mathBraille,
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

  @override
  Widget build(BuildContext context) {
    Widget content = Stack(
      children: [
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
    if (widget.configuration case DMathJax(menu: true)) {
      content = DContextMenu(
        content: DContextMenuContent(
          children: [
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
        ),
        child: DContextMenuTrigger(controller: _menu, child: content),
      );
    }
    if (widget.onEdit != null) {
      final edit = DButton.iconOnly(
        icon: const DIcon(DIcons.pencil),
        tooltip: context.l10n.editMath,
        onPressed: widget.onEdit,
      );
      content = widget.expression.display
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.topRight, child: edit),
                content,
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: content),
                edit,
              ],
            );
    }
    return _MathBaseline(
      baseline:
          _baseline +
          (widget.onEdit != null && widget.expression.display ? 32 : 0),
      child: content,
    );
  }

  @override
  void dispose() {
    ++_generation;
    _view?.retire();
    super.dispose();
  }
}

/// Teardown waits for setup so a late channel/load cannot resurrect a retired view.
final class _MathView {
  _MathView({
    required this.request,
    required this.current,
    required this.onMessage,
    required this.onChanged,
  });
  final Map<String, Object?> request;
  final bool Function() current;
  final void Function(Map<String, dynamic>) onMessage;
  final VoidCallback onChanged;
  WebViewController? controller;
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
    if (_active.length < 8) {
      _admit();
    } else if (_waiting.length < 64) {
      _waiting.add(this);
    } else {
      scheduleMicrotask(
        () => onMessage({'type': 'error', 'generation': request['generation']}),
      );
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
      await view.setBackgroundColor(Colors.transparent);
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
        NavigationDelegate(
          onNavigationRequest: (request) =>
              active &&
                  request.url.startsWith('file:') &&
                  request.url.endsWith('/index.html')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      if (!active) return;
      await view.loadFlutterAsset(_document);
    } on Object {
      if (active) {
        onMessage({'type': 'error', 'generation': request['generation']});
      }
    }
  }

  void finish() => _timeout?.cancel();
  void retire() {
    if (_retired) return;
    _retired = true;
    _waiting.remove(this);
    _timeout?.cancel();
    unawaited(
      _release().whenComplete(() {
        if (_admitted) _active.remove(this);
        while (_active.length < 8 && _waiting.isNotEmpty) {
          _waiting.removeAt(0)._admit();
        }
      }),
    );
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
