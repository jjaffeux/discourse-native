import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../foundation/diagram_rendering.dart';
import '../foundation/focus_highlight.dart';
import '../foundation/mermaid_document.dart';
import 'd_alert.dart';
import 'd_button.dart';
import 'd_dialog.dart';
import 'd_scroll_area.dart';
import 'd_skeleton.dart';

const _assets = 'packages/discourse_native/src/ui/assets/pele';

bool _licenseRegistered = false;

const _renderer = DiagramRenderer(
  channel: 'NativeMermaid',
  assets: ['$_assets/pele-1.10.0.global.js', '$_assets/render.js'],
  document: _document,
);

String _document(
  List<String> assets,
  String source,
  String? variant,
  bool dark,
) => mermaidDocument(
  runtime: assets[0],
  renderer: assets[1],
  source: source,
  dark: dark,
);

/// Offline Mermaid artwork with source access and an expanded zoom/pan view.
///
/// A short-lived local WebView renders the bundled Pele runtime to a bounded
/// image. The reader and expanded view use Flutter images, so diagrams do not
/// intercept post scrolling or retain native browser surfaces. Author links and
/// scripts are disabled. Syntax/platform errors leave the source accessible.
/// [height] constrains only the inline artwork; null fits it up to 420 pixels.
/// Pele owns diagram typography; use Expand to inspect small labels.
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

class _DMermaidState extends DiagramRenderState<DMermaid> {
  String _copyLabel = appL10n.copySource;

  @override
  DiagramRenderer get diagramRenderer => _renderer;

  @override
  String get diagramSource => widget.source;

  @override
  void didChangeDiagram() => _copyLabel = appL10n.copySource;

  @override
  void initState() {
    super.initState();
    if (!_licenseRegistered) {
      _licenseRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'pele',
        ], await rootBundle.loadString('$_assets/LICENSE'));
      });
    }
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
      if (diagramError case final String error)
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
                (diagramImage == null
                    ? 160.0
                    : (width / diagramImage!.aspectRatio).clamp(80.0, 420.0));
            return SizedBox(
              height: height,
              child: switch (diagramImage) {
                final DiagramImage image =>
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
                onPressed: diagramImage == null
                    ? null
                    : () => unawaited(_expand()),
              ),
          ],
        ),
      ],
    ],
  );
}

class _MermaidZoom extends StatefulWidget {
  const _MermaidZoom({required this.image, required this.label});
  final DiagramImage image;
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
