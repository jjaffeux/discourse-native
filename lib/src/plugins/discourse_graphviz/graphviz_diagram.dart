import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart'
    show CodeBlock, CodeBlockData;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'graphviz_document.dart';

const _assets =
    'packages/discourse_native/src/plugins/discourse_graphviz/assets';

const _renderer = DiagramRenderer(
  channel: 'NativeGraphviz',
  assets: ['$_assets/viz-3.31.0.js', '$_assets/render.js'],
  document: graphvizDocument,
);

bool _licenseRegistered = false;

class GraphvizDiagram extends StatefulWidget {
  const GraphvizDiagram({
    super.key,
    required this.source,
    required this.engine,
    this.height,
  });

  final String source;
  final String engine;
  final double? height;

  @override
  State<GraphvizDiagram> createState() => _GraphvizDiagramState();
}

class _GraphvizDiagramState extends DiagramRenderState<GraphvizDiagram> {
  @override
  DiagramRenderer get diagramRenderer => _renderer;

  @override
  String get diagramSource => widget.source;

  @override
  String get diagramVariant => widget.engine;

  @override
  void initState() {
    super.initState();
    if (_licenseRegistered) return;
    _licenseRegistered = true;
    LicenseRegistry.addLicense(() async* {
      for (final (name, file) in const [
        ('Viz.js', 'LICENSE-viz'),
        ('Graphviz', 'LICENSE-graphviz'),
        ('Expat', 'LICENSE-expat'),
        ('Emscripten', 'LICENSE-emscripten'),
      ]) {
        yield LicenseEntryWithLineBreaks([
          name,
        ], await rootBundle.loadString('$_assets/$file'));
      }
    });
  }

  void _viewSource() {
    final data = CodeBlockData.fromSource(widget.source, language: 'dot');
    unawaited(
      showDDialog<void>(
        context: context,
        builder: (context, _) => DDialogContent(
          maxWidth: 720,
          children: [
            DDialogHeader(
              children: [DDialogTitle(child: Text(context.l10n.viewSource))],
            ),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .55,
              child: DScrollArea(
                child: SelectionArea(
                  child: CodeBlock(data: data, showFullscreen: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _expand(DiagramImage image) {
    unawaited(
      showDDialog<void>(
        context: context,
        builder: (context, _) {
          final scale = math.min(
            1.0,
            4096 / math.max(image.width, image.height),
          );
          final label = context.l10n.graphvizDiagram;
          return DDialogContent(
            maxWidth: 1200,
            children: [
              DDialogHeader(children: [DDialogTitle(child: Text(label))]),
              SizedBox(
                height: math.min(
                  image.height * scale,
                  MediaQuery.sizeOf(context).height * .65,
                ),
                child: DScrollArea(
                  axes: DScrollAxes.both,
                  child: SizedBox(
                    width: image.width * scale,
                    height: image.height * scale,
                    child: image.build(label),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = diagramImage;
    final label = context.l10n.graphvizDiagram;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.xs,
      children: [
        if (diagramError case final error?)
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
                  (image == null
                      ? 160.0
                      : (width / image.aspectRatio).clamp(80.0, 420.0));
              return SizedBox(
                height: height,
                child: image == null
                    ? DSkeletonRegion(
                        semanticsLabel: context.l10n.renderingDiagram,
                        child: const DSkeleton(),
                      )
                    : DImagePreview(
                        semanticLabel: label,
                        filename: label,
                        onPressed: () => _expand(image),
                        child: SizedBox.expand(child: image.build(label)),
                      ),
              );
            },
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DButton(
            label: Text(context.l10n.viewSource),
            variant: DButtonVariant.ghost,
            onPressed: _viewSource,
          ),
        ),
      ],
    );
  }
}
