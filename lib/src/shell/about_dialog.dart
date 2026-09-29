import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

import '../theme/d_icons.dart';
import 'external_link.dart';

Future<void> showNativeAboutDialog(BuildContext context) => showDDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (context, controller) => const NativeAboutDialog(),
);

class NativeAboutDialog extends StatefulWidget {
  const NativeAboutDialog({super.key});

  @override
  State<NativeAboutDialog> createState() => _NativeAboutDialogState();
}

class _NativeAboutDialogState extends State<NativeAboutDialog>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2460),
  );
  _BrandArtwork? _artwork;
  bool _reducedMotion = false;
  String? _openingLink;
  String? _linkError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadArtwork());
  }

  Future<void> _loadArtwork() async {
    final artwork = await _BrandArtwork.load();
    if (!mounted) return;
    setState(() => _artwork = artwork);
    _replay();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) _animation.value = 1;
  }

  void _replay() {
    if (_reducedMotion) {
      _animation.value = 1;
    } else {
      _animation.forward(from: 0);
    }
  }

  Future<void> _openLink(String url) async {
    if (_openingLink != null) return;
    setState(() {
      _openingLink = url;
      _linkError = null;
    });
    final opened = await openExternalLink(url);
    if (!mounted) return;
    setState(() {
      _openingLink = null;
      if (!opened) _linkError = context.l10n.aboutLinkOpenFailed;
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Widget _link(String label, String url) => DButton(
    variant: DButtonVariant.secondary,
    size: DButtonSize.large,
    alignment: AlignmentDirectional.centerStart,
    isLink: true,
    semanticLabel: context.l10n.aboutExternalLinkLabel(label),
    loading: _openingLink == url,
    onPressed: _openingLink == null ? () => unawaited(_openLink(url)) : null,
    label: Row(
      children: [
        Expanded(child: Text(label, softWrap: true, maxLines: 3)),
        const SizedBox(width: DSpacing.controlGap),
        const DIcon(DIcons.upRightFromSquare, size: 14),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => DDialogContent(
    key: const ValueKey('native-about-dialog'),
    maxWidth: 380,
    semanticLabel: context.l10n.about,
    children: [
      Center(
        child: DButton(
          key: const ValueKey('about-replay-mark'),
          variant: DButtonVariant.transparentBackground,
          tooltip: context.l10n.aboutReplayMark,
          semanticLabel: context.l10n.aboutReplayMark,
          onPressed: _artwork == null ? null : _replay,
          label: ExcludeSemantics(
            child: SizedBox.square(
              dimension: 96,
              child: _artwork == null
                  ? null
                  : CustomPaint(
                      key: const ValueKey('about-mark-artwork'),
                      painter: _BrandPainter(
                        artwork: _artwork!,
                        animation: _animation,
                        foreground: DTokens.of(context).foreground,
                      ),
                    ),
            ),
          ),
        ),
      ),
      DDialogHeader(
        children: [
          DDialogTitle(
            child: Text(context.l10n.about, textAlign: TextAlign.center),
          ),
          DDialogDescription(
            child: Text(context.l10n.discourse, textAlign: TextAlign.center),
          ),
        ],
      ),
      DButtonGroup(
        orientation: DButtonGroupOrientation.vertical,
        children: [
          _link(context.l10n.aboutDiscourseMeta, 'https://meta.discourse.org'),
          _link(
            context.l10n.aboutDocumentation,
            'https://meta.discourse.org/c/documentation/10',
          ),
        ],
      ),
      if (_linkError case final error?)
        Semantics(
          liveRegion: true,
          child: Text(
            error,
            style: TextStyle(color: DTokens.of(context).destructive),
          ),
        ),
    ],
  );
}

// Read the same source vector used by the app icons. Only the artwork is
// painted here; the Native button owns its hit area, focus and replay action.
class _BrandArtwork {
  _BrandArtwork(this.size, this.pieces);

  final Size size;
  final List<_BrandPiece> pieces;
  static _BrandArtwork? _cached;

  static Future<_BrandArtwork> load() async => _cached ??= await _load();

  static Future<_BrandArtwork> _load() async {
    final svg = await rootBundle.loadString('assets/logo_mark.svg');
    final vector = vg.parseWithoutOptimizers(svg);
    final pieces = <_BrandPiece>[];
    for (final draw in vector.commands) {
      if (draw.type != vg.DrawCommandType.path || draw.paintId == null) {
        continue;
      }
      final fill = vector.paints[draw.paintId!].fill;
      if (fill == null) continue;
      final source = vector.paths[draw.objectId!];
      final path = Path()
        ..fillType = PathFillType.values[source.fillType.index];
      for (final command in source.commands) {
        switch (command) {
          case vg.MoveToCommand(:final x, :final y):
            path.moveTo(x, y);
          case vg.LineToCommand(:final x, :final y):
            path.lineTo(x, y);
          case vg.CubicToCommand(
            :final x1,
            :final y1,
            :final x2,
            :final y2,
            :final x3,
            :final y3,
          ):
            path.cubicTo(x1, y1, x2, y2, x3, y3);
          case vg.CloseCommand():
            path.close();
        }
      }
      pieces.add(
        _BrandPiece(
          path,
          Color.fromARGB(
            fill.color.a,
            fill.color.r,
            fill.color.g,
            fill.color.b,
          ),
        ),
      );
    }
    return _BrandArtwork(Size(vector.width, vector.height), pieces);
  }
}

class _BrandPiece {
  _BrandPiece(this.path, this.color) : metrics = path.computeMetrics().toList();

  final Path path;
  final Color color;
  final List<PathMetric> metrics;
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({
    required this.artwork,
    required this.animation,
    required this.foreground,
  }) : super(repaint: animation);

  final _BrandArtwork artwork;
  final Animation<double> animation;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    // Leave room around the source vector for the animated contour stroke.
    final scale = (size.shortestSide - 4) / artwork.size.longestSide;
    canvas
      ..save()
      ..translate(2, 2)
      ..scale(scale);
    for (final (index, piece) in artwork.pieces.indexed) {
      final delay = index == 0 ? 0 : 720 + (index - 1) * 110;
      final progress = Curves.fastOutSlowIn.transform(
        ((animation.value * 2460 - delay) / 1300).clamp(0.0, 1.0),
      );
      final fill = ((progress - .55) / .45).clamp(0.0, 1.0);
      final color = piece.color == const Color(0xFFFFFFFF)
          ? foreground
          : piece.color;
      if (fill > 0) {
        canvas.drawPath(
          piece.path,
          Paint()..color = color.withValues(alpha: fill),
        );
      }
      if (progress > 0 && fill < 1) {
        final stroke = Paint()
          ..color = color.withValues(alpha: 1 - fill)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final metric in piece.metrics) {
          canvas.drawPath(
            metric.extractPath(
              0,
              metric.length * (progress / .55).clamp(0.0, 1.0),
            ),
            stroke,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      artwork != oldDelegate.artwork ||
      animation != oldDelegate.animation ||
      foreground != oldDelegate.foreground;
}
