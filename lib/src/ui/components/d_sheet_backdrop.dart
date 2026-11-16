part of 'd_sheet.dart';

const _sheetTouchEntrance = Duration(milliseconds: 320);
const _sheetModalTransition = Duration(milliseconds: 200);
const _sheetPageTransition = Duration(milliseconds: 280);

Duration _sheetModalEntranceDuration(BuildContext context) =>
    DControlStyle.isTouch(context)
    ? _sheetTouchEntrance
    : _sheetModalTransition;

final _routeBackdropPulls = Expando<ValueNotifier<double>>();

ValueNotifier<double> _routeBackdropPull(Animation<double> animation) =>
    _routeBackdropPulls[animation] ??= ValueNotifier(0);

Widget _routeSheetBackground(
  BuildContext context,
  Animation<double> animation,
  Widget child,
) {
  final pull = _routeBackdropPull(animation);
  final animate = !MediaQuery.disableAnimationsOf(context);
  return ListenableBuilder(
    listenable: Listenable.merge([animation, pull]),
    child: child,
    builder: (context, child) => _DSheetBackgroundMotion(
      depth: animate
          ? Curves.easeInOut.transform(animation.value) * (1 - pull.value)
          : 0,
      surroundingColor: DTokens.of(context).wellFill,
      child: child!,
    ),
  );
}

/// Applies the reading sheet's depth to a live surface behind a retained sheet.
/// Place both surfaces inside the same [DSheetDragScope]. The host owns focus,
/// semantics, and pointer exclusion while the sheet covers the surface.
class DSheetBackdrop extends StatefulWidget {
  const DSheetBackdrop({
    super.key,
    required this.covered,
    this.surfaceIdentity,
    required this.child,
  });

  final bool covered;

  /// A replacement surface is already uncovered when the host changes pages.
  final Object? surfaceIdentity;
  final Widget child;

  @override
  State<DSheetBackdrop> createState() => _DSheetBackdropState();
}

class _DSheetBackdropState extends State<DSheetBackdrop>
    with SingleTickerProviderStateMixin {
  late final _cover = AnimationController(
    vsync: this,
    duration: _sheetTouchEntrance,
    reverseDuration: _sheetPageTransition,
    value: widget.covered ? 1 : 0,
  );
  ValueListenable<double>? _pull;
  double _exitPull = 0;
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pull = context
        .dependOnInheritedWidgetOfExactType<_DSheetDragHost>()
        ?.owner
        ._backdropPull;
    _animate =
        _pull != null &&
        DControlStyle.isTouch(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_animate) _cover.value = widget.covered ? 1 : 0;
  }

  @override
  void didUpdateWidget(DSheetBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.covered) {
      if (oldWidget.covered) return;
      if (_animate && DHistoryTransition.shouldAnimatePageEntranceOf(context)) {
        unawaited(_cover.forward());
      } else {
        _cover.value = 1;
      }
    } else if (widget.surfaceIdentity != oldWidget.surfaceIdentity) {
      _cover.value = 0;
    } else if (oldWidget.covered) {
      _exitPull = _pull?.value ?? 0;
      if (_animate && _exitPull < 1) {
        unawaited(_cover.reverse());
      } else {
        _cover.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_cover, _pull]),
    child: widget.child,
    builder: (context, child) {
      final pull = widget.covered ? _pull?.value ?? 0 : _exitPull;
      return _DSheetBackgroundMotion(
        depth: _animate
            ? Curves.easeInOut.transform(_cover.value) * (1 - pull)
            : 0,
        child: child!,
      );
    },
  );
}

class _DSheetBackgroundMotion extends StatelessWidget {
  const _DSheetBackgroundMotion({
    required this.depth,
    this.rounded = false,
    this.surroundingColor,
    this.visibleHeight,
    required this.child,
  });

  final double depth;
  final bool rounded;
  final Color? surroundingColor;
  final double? visibleHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tint = depth == 0
        ? null
        : DTokens.of(context).colors.scrim.withValues(alpha: .24 * depth);
    final scale = 1 - .06 * depth;
    final height = visibleHeight;
    final scaled = Transform.scale(
      scale: scale,
      child: _DSheetBackgroundTint(
        tint: tint,
        child: ClipRect(
          clipBehavior: height == null ? Clip.none : Clip.hardEdge,
          clipper: height == null
              ? null
              : _DSheetBackgroundClipper(height, scale),
          child: ClipRRect(
            clipBehavior: rounded || depth > 0 ? Clip.antiAlias : Clip.none,
            borderRadius: DSheetViewport.pageBorderRadius(context),
            child: child,
          ),
        ),
      ),
    );
    final surround = surroundingColor;
    if (surround == null) return scaled;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint == null ? null : Color.alphaBlend(tint, surround),
      ),
      child: scaled,
    );
  }
}

class _DSheetBackgroundClipper extends CustomClipper<Rect> {
  const _DSheetBackgroundClipper(this.visibleHeight, this.scale);

  final double visibleHeight;
  final double scale;

  @override
  Rect getClip(Size size) {
    final scaledTop = size.height * (1 - scale) / 2;
    final bottom = (visibleHeight - scaledTop) / scale;
    // Keep the original antialiasing on the other three sides. Skip bottom
    // clipping when the backdrop is close enough to show through a side edge.
    if (bottom >= size.height || size.width * (1 - scale) / 2 < 1) {
      return Rect.fromLTRB(-1, -1, size.width + 1, size.height + 1);
    }
    return Rect.fromLTRB(-1, -1, size.width + 1, math.max(-1, bottom));
  }

  @override
  bool shouldReclip(_DSheetBackgroundClipper oldClipper) =>
      oldClipper.visibleHeight != visibleHeight || oldClipper.scale != scale;
}

class _DSheetBackgroundTint extends SingleChildRenderObjectWidget {
  const _DSheetBackgroundTint({required this.tint, required super.child});

  final Color? tint;

  @override
  _RenderSheetBackgroundTint createRenderObject(BuildContext context) =>
      _RenderSheetBackgroundTint(tint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetBackgroundTint renderObject,
  ) => renderObject.tint = tint;
}

class _RenderSheetBackgroundTint extends RenderProxyBox {
  _RenderSheetBackgroundTint(this._tint);

  Color? _tint;
  set tint(Color? value) {
    if (value == _tint) return;
    if ((value == null) != (_tint == null)) markNeedsCompositingBitsUpdate();
    _tint = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _tint != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final tint = _tint;
    if (tint == null) {
      layer = null;
      super.paint(context, offset);
    } else if (child != null) {
      layer = context.pushColorFilter(
        offset,
        ColorFilter.mode(tint, BlendMode.srcATop),
        super.paint,
        oldLayer: layer as ColorFilterLayer?,
      );
    }
  }
}
