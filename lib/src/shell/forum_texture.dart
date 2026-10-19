import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import 'decorative_cadence.dart';

/// The reference's single texture layer, composited over the whole workspace.
/// Its animation repaints independently of the widgets underneath it.
class ForumTexture extends StatefulWidget {
  const ForumTexture({
    super.key,
    required this.background,
    required this.accent,
  });

  final ForumBackground background;
  final Color accent;

  @override
  State<ForumTexture> createState() => _ForumTextureState();
}

class _ForumTextureState extends State<ForumTexture> {
  static final _program = ui.FragmentProgram.fromAsset(
    'packages/discourse_native/src/shell/shaders/forum_texture.frag',
  );
  ui.FragmentShader? _shader;
  ui.Image? _permutation;
  final _motion = DecorativeCadence();

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  bool _loading = false;

  void _loadIfNeeded() {
    if (_loading ||
        (widget.background.effect == ForumBackgroundEffect.normal ||
            widget.background.effect == ForumBackgroundEffect.hatch)) {
      return;
    }
    _loading = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final program = await _program;
    if (!mounted) return;
    final values = List.generate(256, (index) => index)..shuffle(Random(73));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < values.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i.toDouble(), 0, 1, 1),
        Paint()..color = Color.fromARGB(255, values[i], 0, 0),
      );
    }
    final picture = recorder.endRecording();
    _permutation = picture.toImageSync(256, 1);
    picture.dispose();
    setState(
      () =>
          _shader = program.fragmentShader()..setImageSampler(0, _permutation!),
    );
    _updateMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(ForumTexture oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadIfNeeded();
    _updateMotion();
  }

  void _updateMotion() {
    final animate =
        _shader != null &&
        widget.background.effect == ForumBackgroundEffect.lava &&
        widget.background.noiseIntensity > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _motion.setActive(animate);
  }

  @override
  void dispose() {
    _motion.dispose();
    _shader?.dispose();
    _permutation?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: widget.background.effect == ForumBackgroundEffect.hatch
          ? CustomPaint(
              key: const ValueKey('forum-hatch-texture'),
              painter: _HatchPainter(
                widget.accent,
                widget.background.noiseIntensity,
              ),
            )
          : _shader == null ||
                widget.background.effect == ForumBackgroundEffect.normal ||
                widget.background.noiseIntensity == 0
          ? const SizedBox.expand()
          : CustomPaint(
              key: const ValueKey('forum-reference-texture'),
              painter: _TexturePainter(
                _shader!,
                _motion,
                widget.background,
                widget.accent,
              ),
            ),
    ),
  );
}

class _TexturePainter extends CustomPainter {
  _TexturePainter(this.shader, this.motion, this.background, this.accent)
    : super(repaint: motion);
  final ui.FragmentShader shader;
  final DecorativeCadence motion;
  final ForumBackground background;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, motion.sampleElapsed().inMicroseconds / 1000000)
      ..setFloat(3, background.noiseIntensity)
      ..setFloat(4, background.effect == ForumBackgroundEffect.lava ? 1 : 0)
      ..setFloat(5, accent.r)
      ..setFloat(6, accent.g)
      ..setFloat(7, accent.b);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_TexturePainter oldDelegate) =>
      shader != oldDelegate.shader ||
      background != oldDelegate.background ||
      accent != oldDelegate.accent;
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.ink, this.intensity);
  final Color ink;
  final double intensity;
  @override
  void paint(Canvas canvas, Size size) {
    if (intensity == 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = ink.withValues(alpha: intensity * .22)
      ..strokeWidth = .5;
    for (double x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.ink != ink || old.intensity != intensity;
}
