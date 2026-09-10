import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// The base-nova avatar sizes, in logical pixels.
enum DAvatarSize {
  sm(24),
  standard(32),
  lg(40);

  const DAvatarSize(this.dimension);
  final double dimension;
}

/// A non-interactive identity picture. Compose inside a button or user-card
/// target to give it an action; that owner retains focus and hit testing.
class DAvatar extends StatelessWidget {
  const DAvatar({
    super.key,
    this.size = DAvatarSize.standard,
    this.dimension,
    this.image,
    this.fallback = const DAvatarFallback(child: SizedBox.shrink()),
    this.child,
    this.badge,
    this.ring = false,
    this.ringSemanticLabel,
    this.semanticLabel,
    this.decorative = false,
    this.borderRadius,
  }) : assert(dimension == null || dimension > 0),
       assert(image == null || child == null),
       _intrinsic = false;

  /// Presents already-sized content, including application image adapters.
  /// The child owns its dimensions; loading and ready must use the same bounds.
  const DAvatar.frame({
    super.key,
    required this.child,
    this.badge,
    this.ring = false,
    this.ringSemanticLabel,
    this.semanticLabel,
    this.decorative = false,
    this.borderRadius,
  }) : size = DAvatarSize.standard,
       dimension = null,
       image = null,
       fallback = const SizedBox.shrink(),
       _intrinsic = true;

  final DAvatarSize size;
  final double? dimension;
  final DAvatarImage? image;
  final Widget fallback;
  final Widget? child;
  final Widget? badge;

  /// Applies Discourse's online treatment without changing the avatar's outer
  /// dimensions: a one-pixel success ring, a one-pixel background gap, then
  /// the image. The host supplies both colors through [DTokens].
  final bool ring;

  /// Accessible meaning of [ring], such as "Online". It is combined with
  /// [semanticLabel], so the state is not communicated by color alone.
  final String? ringSemanticLabel;
  final String? semanticLabel;
  final bool decorative;

  /// Site/forum artwork may require rounded squares instead of user circles.
  final BorderRadius? borderRadius;
  final bool _intrinsic;

  @override
  Widget build(BuildContext context) {
    final effectiveSize = _AvatarGroupScope.of(context)?.overrideSize ?? size;
    final radius = borderRadius ?? BorderRadius.circular(9999);
    final tokens = DTokens.of(context);
    Widget picture = ClipRRect(
      borderRadius: radius,
      child: child ?? image ?? fallback,
    );
    if (ring) {
      picture = DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.background,
          borderRadius: radius,
          border: Border.all(color: tokens.success),
        ),
        child: _AvatarRingInset(child: picture),
      );
    } else {
      picture = CustomPaint(
        foregroundPainter: _AvatarBorder(
          tokens.border,
          radius,
          Theme.of(context).brightness == Brightness.dark
              ? BlendMode.lighten
              : BlendMode.darken,
        ),
        child: picture,
      );
    }
    final semanticsLabel = [
      ?semanticLabel,
      if (ring) ?ringSemanticLabel,
    ].join(', ');
    if (decorative || semanticsLabel.isNotEmpty) {
      picture = Semantics(
        label: decorative ? null : semanticsLabel,
        image: !decorative,
        excludeSemantics: true,
        child: picture,
      );
    }
    return _AvatarScope(
      size: effectiveSize,
      fallback: fallback,
      child: SelectionContainer.disabled(
        child: SizedBox(
          width: _intrinsic
              ? null
              : dimension ?? _scaledExtent(context, effectiveSize),
          height: _intrinsic
              ? null
              : dimension ?? _scaledExtent(context, effectiveSize),
          child: Stack(
            fit: _intrinsic ? StackFit.loose : StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              picture,
              if (badge != null)
                PositionedDirectional(end: 0, bottom: 0, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the child's former outer extent while laying its visible content out
/// four pixels smaller. This reproduces core's border-box `padding: 2px` for
/// both enum-sized avatars and intrinsically sized application frames.
class _AvatarRingInset extends SingleChildRenderObjectWidget {
  const _AvatarRingInset({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAvatarRingInset();
}

class _RenderAvatarRingInset extends RenderShiftedBox {
  _RenderAvatarRingInset([super.child]);

  static const _inset = 2.0;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final naturalSize = child.getDryLayout(constraints.loosen());
    size = constraints.constrain(naturalSize);
    child.layout(
      BoxConstraints.tight(
        Size(
          math.max(0, size.width - _inset * 2),
          math.max(0, size.height - _inset * 2),
        ),
      ),
    );
    (child.parentData! as BoxParentData).offset = const Offset(_inset, _inset);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    return constraints.constrain(
      child?.getDryLayout(constraints.loosen()) ?? constraints.smallest,
    );
  }
}

class _AvatarScope extends InheritedWidget {
  const _AvatarScope({
    required this.size,
    required this.fallback,
    required super.child,
  });
  final DAvatarSize size;
  final Widget fallback;
  static _AvatarScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AvatarScope>();
  @override
  bool updateShouldNotify(_AvatarScope oldWidget) =>
      size != oldWidget.size || fallback != oldWidget.fallback;
}

/// Loading state of a provider-backed avatar image.
enum DAvatarImageStatus { loading, ready, error }

/// Decodes a caller-supplied provider. The library owns no networking, cache,
/// credentials, or application error reporting. Changing providers detaches
/// the old stream immediately, including when its first frame arrives late.
class DAvatarImage extends StatefulWidget {
  const DAvatarImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.onStatusChanged,
  });
  final ImageProvider image;
  final BoxFit fit;
  final ValueChanged<DAvatarImageStatus>? onStatusChanged;
  @override
  State<DAvatarImage> createState() => _DAvatarImageState();
}

class _DAvatarImageState extends State<DAvatarImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  DAvatarImageStatus _status = DAvatarImageStatus.loading;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(DAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _detach();
    final generation = ++_generation;
    _info?.dispose();
    _info = null;
    _status = DAvatarImageStatus.loading;
    _notify(generation);
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronous) {
        if (!mounted || generation != _generation) {
          info.dispose();
          return;
        }
        final changed = _status != DAvatarImageStatus.ready;
        void update() {
          _info?.dispose();
          _info = info;
          _status = DAvatarImageStatus.ready;
        }

        if (synchronous) {
          update();
        } else {
          setState(update);
        }
        if (changed) _notify(generation);
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _info?.dispose();
          _info = null;
          _status = DAvatarImageStatus.error;
        });
        _notify(generation);
      },
    );
    stream.addListener(_listener!);
  }

  void _notify(int generation) {
    final status = _status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        widget.onStatusChanged?.call(status);
      }
    });
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
  }

  @override
  void dispose() {
    _detach();
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _info == null
      ? _AvatarScope.of(context)?.fallback ?? const SizedBox.shrink()
      : RawImage(image: _info!.image, scale: _info!.scale, fit: widget.fit);
}

/// Muted initials or an icon, displayed while an image is unavailable.
/// A delay avoids flashing initials during fast loads. It restarts each time
/// the fallback is mounted; changing the delay updates the pending timer.
class DAvatarFallback extends StatefulWidget {
  const DAvatarFallback({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.backgroundColor,
    this.foregroundColor,
  });
  final Widget child;
  final Duration delay;
  final Color? backgroundColor;
  final Color? foregroundColor;
  @override
  State<DAvatarFallback> createState() => _DAvatarFallbackState();
}

class _DAvatarFallbackState extends State<DAvatarFallback> {
  Timer? _timer;
  bool _visible = false;
  void _start() {
    _timer?.cancel();
    _visible = widget.delay <= Duration.zero;
    if (!_visible) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(DAvatarFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay != widget.delay) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.expand();
    final tokens = DTokens.of(context);
    final small = _AvatarScope.of(context)?.size == DAvatarSize.sm;
    return ColoredBox(
      color: widget.backgroundColor ?? tokens.muted,
      child: Center(
        child: DefaultTextStyle(
          style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
              .copyWith(
                color: widget.foregroundColor ?? tokens.mutedForeground,
                fontSize: small
                    ? DiscourseTypography.xs
                    : DiscourseTypography.sm,
                height: small ? 16 / 12 : 20 / 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          child: IconTheme.merge(
            data: IconThemeData(
              size: small ? 12 : 16,
              color: widget.foregroundColor ?? tokens.mutedForeground,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A dot, icon or count at the avatar's bottom trailing edge. Small reference
/// badges hide their icon; custom dimensions preserve application status/flair.
class DAvatarBadge extends StatelessWidget {
  const DAvatarBadge({
    super.key,
    this.child,
    this.icon,
    this.semanticLabel,
    this.backgroundColor,
    this.foregroundColor,
    this.dimension,
    this.ringWidth = 2,
  }) : assert(child == null || icon == null);
  final Widget? child;

  /// Decorative icon artwork, including SVGs and custom painters. Sized to 8px
  /// and hidden at sm unless a custom badge dimension is supplied. Use [child]
  /// for count text; naming belongs to [semanticLabel].
  final Widget? icon;
  final String? semanticLabel;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? dimension;
  final double ringWidth;
  @override
  Widget build(BuildContext context) {
    final size = _AvatarScope.of(context)?.size ?? DAvatarSize.standard;
    final tokens = DTokens.of(context);
    final extent =
        dimension ??
        switch (size) {
          DAvatarSize.sm => 8.0,
          DAvatarSize.standard => 10.0,
          DAvatarSize.lg => 12.0,
        };
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null || child == null,
      child: Container(
        width: extent,
        height: extent,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? tokens.primary,
          boxShadow: [
            BoxShadow(color: tokens.background, spreadRadius: ringWidth),
          ],
        ),
        alignment: Alignment.center,
        child: size == DAvatarSize.sm && dimension == null && icon != null
            ? null
            : DefaultTextStyle(
                style: TextStyle(
                  fontFamily: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.fontFamily,
                  fontSize: 8,
                  height: 1,
                  color: foregroundColor ?? tokens.primaryForeground,
                ),
                child: IconTheme(
                  data: IconThemeData(
                    size: 8,
                    color: foregroundColor ?? tokens.primaryForeground,
                  ),
                  child: icon != null
                      ? SizedBox.square(
                          dimension: 8,
                          child: ExcludeSemantics(child: icon!),
                        )
                      : child ?? const SizedBox.shrink(),
                ),
              ),
      ),
    );
  }
}

/// Overlaps avatars by 8px with a 2px background ring. Under narrow constraints
/// rows wrap rather than compressing identities. Ordering mirrors in RTL.
/// Without [size], direct avatars keep their own size/dimension and the count
/// follows the reference's small-then-large precedence. An explicit [size]
/// overrides descendant avatar size, including badge and fallback metrics;
/// explicit avatar dimensions remain authoritative. Wrapped action children
/// reserve the group/count extent and retain their own interaction ownership.
class DAvatarGroup extends StatelessWidget {
  const DAvatarGroup({
    super.key,
    required this.children,
    this.size,
    this.overlap = 8,
  }) : assert(overlap >= 0);
  final List<Widget> children;
  final DAvatarSize? size;
  final double overlap;
  @override
  Widget build(BuildContext context) {
    final avatars = children.whereType<DAvatar>();
    final countSize =
        size ??
        (avatars.any((a) => a.size == DAvatarSize.sm)
            ? DAvatarSize.sm
            : avatars.any((a) => a.size == DAvatarSize.lg)
            ? DAvatarSize.lg
            : DAvatarSize.standard);
    final extents = [
      for (final child in children)
        child is DAvatar
            ? child.dimension ?? _scaledExtent(context, size ?? child.size)
            : _scaledExtent(context, countSize),
    ];
    return _AvatarGroupScope(
      overrideSize: size,
      countSize: countSize,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (children.isEmpty) return const SizedBox.shrink();
          final positions = <Offset>[];
          double x = 0, y = 0, rowHeight = 0, width = 0;
          for (final extent in extents) {
            if (x > 0 && x + extent > constraints.maxWidth) {
              x = 0;
              y += rowHeight + 4;
              rowHeight = 0;
            }
            positions.add(Offset(x, y));
            width = math.max(width, x + extent);
            rowHeight = math.max(rowHeight, extent);
            x += math.max(1, extent - overlap);
          }
          return SizedBox(
            width: width,
            height: y + rowHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < children.length; i++)
                  PositionedDirectional(
                    start: positions[i].dx,
                    top: positions[i].dy,
                    width: extents[i],
                    height: extents[i],
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: DTokens.of(context).background,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: children[i],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AvatarGroupScope extends InheritedWidget {
  const _AvatarGroupScope({
    required this.overrideSize,
    required this.countSize,
    required super.child,
  });
  final DAvatarSize? overrideSize;
  final DAvatarSize countSize;
  static _AvatarGroupScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AvatarGroupScope>();
  @override
  bool updateShouldNotify(_AvatarGroupScope oldWidget) =>
      overrideSize != oldWidget.overrideSize ||
      countSize != oldWidget.countSize;
}

/// Additional identities or a decorative group icon. Give icon-only counts a
/// semantic label; use a separate action owner if the count opens a list.
class DAvatarGroupCount extends StatelessWidget {
  const DAvatarGroupCount({super.key, required this.child, this.semanticLabel});
  final Widget child;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final size =
        _AvatarGroupScope.of(context)?.countSize ?? DAvatarSize.standard;
    final tokens = DTokens.of(context);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SelectionContainer.disabled(
        child: Container(
          width: _scaledExtent(context, size),
          height: _scaledExtent(context, size),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tokens.muted,
            boxShadow: [BoxShadow(color: tokens.background, spreadRadius: 2)],
          ),
          child: DefaultTextStyle(
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                  fontSize: DiscourseTypography.sm,
                  height: 20 / 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                  color: tokens.mutedForeground,
                ),
            child: IconTheme(
              data: IconThemeData(
                color: tokens.mutedForeground,
                size: switch (size) {
                  DAvatarSize.sm => 12,
                  DAvatarSize.standard => 16,
                  DAvatarSize.lg => 20,
                },
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarBorder extends CustomPainter {
  const _AvatarBorder(this.color, this.radius, this.blendMode);
  final Color color;
  final BorderRadius radius;
  final BlendMode blendMode;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    radius.toRRect(Offset.zero & size).deflate(.5),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..blendMode = blendMode,
  );
  @override
  bool shouldRepaint(_AvatarBorder oldDelegate) =>
      color != oldDelegate.color ||
      radius != oldDelegate.radius ||
      blendMode != oldDelegate.blendMode;
}

double _scaledExtent(BuildContext context, DAvatarSize size) =>
    size.dimension *
    math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);
