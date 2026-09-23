import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/forum_background.dart';

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

class _ForumTextureState extends State<ForumTexture>
    with SingleTickerProviderStateMixin {
  static final _program = ui.FragmentProgram.fromAsset(
    'packages/discourse_native/src/shell/shaders/forum_texture.frag',
  );
  ui.FragmentShader? _shader;
  ui.Image? _permutation;
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(hours: 1),
  );

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  bool _loading = false;

  void _loadIfNeeded() {
    if (_loading || widget.background.effect == ForumBackgroundEffect.normal) {
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
        widget.background.effect == ForumBackgroundEffect.lava &&
        widget.background.noiseIntensity > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!animate) {
      _motion.stop();
    }
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
      child:
          _shader == null ||
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
  final AnimationController motion;
  final ForumBackground background;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, (motion.lastElapsedDuration?.inMicroseconds ?? 0) / 1000000)
      ..setFloat(3, background.noiseIntensity)
      ..setFloat(4, background.effect == ForumBackgroundEffect.lava ? 1 : 0)
      ..setFloat(5, accent.r)
      ..setFloat(6, accent.g)
      ..setFloat(7, accent.b);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.overlay,
    );
  }

  @override
  bool shouldRepaint(_TexturePainter oldDelegate) =>
      shader != oldDelegate.shader ||
      background != oldDelegate.background ||
      accent != oldDelegate.accent;
}
