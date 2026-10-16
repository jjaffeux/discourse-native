part of 'd_calendar_events.dart';

/// Calendar days and their ordered schedule row identities.
@immutable
class DCalendarScheduleDayData {
  const DCalendarScheduleDayData({
    required this.date,
    required this.label,
    required this.rows,
    this.today = false,
  });
  final DateTime date;
  final String label;
  final List<Object> rows;
  final bool today;
}

enum DCalendarScheduleTodayPosition { before, visible, after }

/// Pins schedule dates and places Today against the live viewport geometry.
///
/// The calendar engine retains ownership of its list and navigation. Row paint,
/// heading handoff, clipping, hit testing and semantics share one frame reading.
class DCalendarScheduleViewport extends StatefulWidget {
  const DCalendarScheduleViewport({
    super.key,
    required this.days,
    required this.missingTodayPosition,
    required this.todayLabel,
    required this.onToday,
    required this.child,
    this.bottomInset = 0,
  });
  final List<DCalendarScheduleDayData> days;
  final DCalendarScheduleTodayPosition missingTodayPosition;
  final String todayLabel;
  final VoidCallback onToday;
  final double bottomInset;
  final Widget child;
  @override
  State<DCalendarScheduleViewport> createState() =>
      _CalendarScheduleViewportState();
}

class _CalendarScheduleViewportState extends State<DCalendarScheduleViewport> {
  final _frame = _ScheduleFrame();
  late final _beforeFocus = _ScheduleTodayFocusNode(
    _frame,
    DCalendarScheduleTodayPosition.before,
  );
  late final _afterFocus = _ScheduleTodayFocusNode(
    _frame,
    DCalendarScheduleTodayPosition.after,
  );
  @override
  void dispose() {
    _beforeFocus.dispose();
    _afterFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _frame
      ..days = widget.days
      ..missingToday = widget.missingTodayPosition
      ..bottomInset = widget.bottomInset
      ..stacked = MediaQuery.textScalerOf(context).scale(14) > 21
      ..direction = Directionality.of(context);
    _frame.invalidate();
    Widget call(DCalendarScheduleTodayPosition position) => _ScheduleLayer(
      frame: _frame,
      today: position,
      child: Center(
        child: DButton(
          key: ValueKey('schedule-today-${position.name}'),
          focusNode: position == DCalendarScheduleTodayPosition.before
              ? _beforeFocus
              : _afterFocus,
          density: DButtonDensity.floatingCall,
          variant: DButtonVariant.ghost,
          icon: RotatedBox(
            quarterTurns: position == DCalendarScheduleTodayPosition.before
                ? 2
                : 0,
            child: const DIcon(DIcons.chevronDown, size: 10),
          ),
          label: Text(widget.todayLabel),
          onPressed: widget.onToday,
        ),
      ),
    );
    return _ScheduleScope(
      frame: _frame,
      child: ClipRect(
        child: _SchedulePaintViewport(
          frame: _frame,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ScheduleContent(frame: _frame, child: widget.child),
              for (final day in widget.days)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _ScheduleLayer(
                    key: ValueKey(day.date),
                    frame: _frame,
                    day: day.date,
                    child: DCalendarScheduleDay(
                      label: day.label,
                      today: day.today,
                      pinned: true,
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: call(DCalendarScheduleTodayPosition.before),
              ),
              Positioned(
                bottom: 12 + widget.bottomInset,
                left: 0,
                right: 0,
                child: call(DCalendarScheduleTodayPosition.after),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Registers one engine-owned row with its enclosing schedule viewport.
class DCalendarScheduleRow extends StatelessWidget {
  const DCalendarScheduleRow({
    super.key,
    required this.date,
    required this.rowId,
    required this.child,
  });
  final DateTime date;
  final Object rowId;
  final Widget child;
  @override
  Widget build(BuildContext context) => _ScheduleRowScope(
    date: date,
    child: _ScheduleRowMeasure(
      frame: _ScheduleScope.of(context),
      position: Scrollable.maybeOf(context, axis: Axis.vertical)?.position,
      date: date,
      rowId: rowId,
      child: child,
    ),
  );
}

class _ScheduleScope extends InheritedWidget {
  const _ScheduleScope({required this.frame, required super.child});
  final _ScheduleFrame frame;
  static _ScheduleFrame? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScheduleScope>()?.frame;
  @override
  bool updateShouldNotify(_ScheduleScope oldWidget) => frame != oldWidget.frame;
}

class _ScheduleRowScope extends InheritedWidget {
  const _ScheduleRowScope({required this.date, required super.child});
  final DateTime date;
  @override
  bool updateShouldNotify(_ScheduleRowScope oldWidget) =>
      date != oldWidget.date;
}

class _ScheduleTodayFocusNode extends FocusNode {
  _ScheduleTodayFocusNode(this.frame, this.position) {
    frame.focusNodes.add(this);
  }
  final _ScheduleFrame frame;
  final DCalendarScheduleTodayPosition position;
  @override
  bool get canRequestFocus =>
      frame.reading.today == position && super.canRequestFocus;
  @override
  bool get skipTraversal => !canRequestFocus || super.skipTraversal;
  @override
  void dispose() {
    frame.focusNodes.remove(this);
    super.dispose();
  }
}

class _ScheduleReading {
  const _ScheduleReading({
    this.day,
    this.push = 0,
    this.opacity = 1,
    this.clip = Rect.zero,
    this.today = DCalendarScheduleTodayPosition.visible,
  });
  final DateTime? day;
  final double push;
  final double opacity;
  final Rect clip;
  final DCalendarScheduleTodayPosition today;
}

class _ScheduleFrame {
  List<DCalendarScheduleDayData> days = const [];
  DCalendarScheduleTodayPosition missingToday =
      DCalendarScheduleTodayPosition.visible;
  double bottomInset = 0;
  bool stacked = false;
  TextDirection direction = TextDirection.ltr;
  RenderBox? viewport;
  final rows = <_RenderScheduleRow>{};
  final positions = <ScrollPosition, int>{};
  void invalidate() {
    viewport?.markNeedsPaint();
    // The engine caches individual rows. A hidden source heading must repaint
    // when a reverse scroll brings its original row back into view.
    for (final source in sourceHeadings) {
      source.markNeedsPaint();
    }
  }

  void addRow(_RenderScheduleRow row) {
    rows.add(row);
    final position = row.position;
    if (position == null) return;
    if (!positions.containsKey(position)) position.addListener(invalidate);
    positions[position] = (positions[position] ?? 0) + 1;
  }

  void removeRow(_RenderScheduleRow row) {
    rows.remove(row);
    final position = row.position;
    if (position == null) return;
    final remaining = (positions[position] ?? 1) - 1;
    if (remaining == 0) {
      positions.remove(position);
      position.removeListener(invalidate);
    } else {
      positions[position] = remaining;
    }
  }

  final layers = <_RenderScheduleLayer>{};
  final sourceHeadings = <_RenderScheduleSourceHeading>{};
  final focusNodes = <_ScheduleTodayFocusNode>{};
  var reading = const _ScheduleReading();

  void read() {
    final viewport = this.viewport;
    if (viewport == null || !viewport.hasSize) return;
    final order = <(DateTime, Object), int>{};
    final first = <DateTime, Object>{};
    for (final day in days) {
      if (day.rows.isNotEmpty) first[day.date] = day.rows.first;
      for (final row in day.rows) {
        order[(day.date, row)] = order.length;
      }
    }
    final live =
        <
          ({DateTime date, Object row, Rect bounds, int order, double opacity})
        >[];
    for (final row in rows) {
      final index = order[(row.date, row.rowId)];
      if (index == null || !row.attached || !row.hasSize) continue;
      var opacity = 1.0;
      RenderObject? ancestor = row;
      while (ancestor != null && ancestor != viewport) {
        final data = ancestor.parentData;
        if (data is SliverMultiBoxAdaptorParentData &&
            (data.keptAlive || data.layoutOffset == null)) {
          opacity = 0;
          break;
        }
        if (ancestor is RenderOpacity) opacity *= ancestor.opacity;
        if (ancestor is RenderAnimatedOpacity) {
          opacity *= ancestor.opacity.value;
        }
        ancestor = ancestor.parent;
      }
      if (ancestor != viewport || opacity < .5) continue;
      final bounds =
          row.localToGlobal(Offset.zero, ancestor: viewport) & row.size;
      if (bounds.bottom <= 0 ||
          bounds.top >= viewport.size.height - bottomInset) {
        continue;
      }
      live.add((
        date: row.date,
        row: row.rowId,
        bounds: bounds,
        order: index,
        opacity: opacity,
      ));
    }
    live.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order != 0 ? order : b.opacity.compareTo(a.opacity);
    });
    DateTime? active;
    var push = 0.0;
    var alpha = 1.0;
    var clip = Rect.zero;
    var today = missingToday;
    if (live.isNotEmpty) {
      final top = live.first;
      if (top.row != first[top.date] || top.bounds.top < -.5) active = top.date;
      if (active != null) {
        final heading = layers
            .where((layer) => layer.day == active && layer.hasSize)
            .firstOrNull;
        if (heading != null) {
          final incoming = live
              .where(
                (row) =>
                    row.date.isAfter(active!) && row.row == first[row.date],
              )
              .firstOrNull;
          if (incoming != null) {
            push = math.min(0, incoming.bounds.top - heading.size.height);
          }
          alpha = (1 + push / heading.size.height).clamp(0, 1);
          RenderParagraph? label;
          void findLabel(RenderObject object) {
            if (label != null) return;
            if (object is RenderParagraph) {
              label = object;
              return;
            }
            object.visitChildren(findLabel);
          }

          findLabel(heading);
          if (label != null && label!.hasSize) {
            final ink =
                label!.localToGlobal(Offset.zero, ancestor: heading) &
                label!.size;
            final bottom = math.max(0.0, ink.bottom + push);
            final column =
                20.0 + math.min(70.0, (viewport.size.width - 20) * .3);
            clip = stacked || viewport.size.width - 20 < 220
                ? Rect.fromLTRB(0, 0, viewport.size.width, bottom)
                : direction == TextDirection.ltr
                ? Rect.fromLTRB(
                    0,
                    0,
                    math.min(
                      viewport.size.width,
                      math.max(column, ink.right + 10),
                    ),
                    bottom,
                  )
                : Rect.fromLTRB(
                    math.max(
                      0,
                      math.min(viewport.size.width - column, ink.left - 10),
                    ),
                    0,
                    viewport.size.width,
                    bottom,
                  );
          }
        }
      }
      final todayDay = days.where((day) => day.today).firstOrNull;
      if (todayDay != null) {
        today = live.any((row) => row.date == todayDay.date)
            ? DCalendarScheduleTodayPosition.visible
            : todayDay.date.isBefore(top.date)
            ? DCalendarScheduleTodayPosition.before
            : DCalendarScheduleTodayPosition.after;
      }
    }
    final previous = reading;
    reading = _ScheduleReading(
      day: active,
      push: push,
      opacity: alpha,
      clip: clip,
      today: today,
    );
    if (previous.today != today) {
      for (final node in focusNodes) {
        if (!node.canRequestFocus && node.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (node.context != null &&
                !node.canRequestFocus &&
                node.hasFocus) {
              node.unfocus();
            }
          });
        }
      }
    }
    if (previous.day != active ||
        previous.today != today ||
        previous.push != push) {
      for (final layer in layers) {
        layer.markNeedsSemanticsUpdate();
      }
      for (final source in sourceHeadings) {
        source.markNeedsSemanticsUpdate();
      }
    }
  }
}

class _SchedulePaintViewport extends SingleChildRenderObjectWidget {
  const _SchedulePaintViewport({required this.frame, required super.child});
  final _ScheduleFrame frame;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScheduleViewport(frame);
}

class _RenderScheduleViewport extends RenderProxyBox {
  _RenderScheduleViewport(this.frame) {
    frame.viewport = this;
  }
  final _ScheduleFrame frame;
  @override
  void paint(PaintingContext context, Offset offset) {
    frame.read();
    super.paint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    frame.read();
    return super.hitTestChildren(result, position: position);
  }
}

class _ScheduleRowMeasure extends SingleChildRenderObjectWidget {
  const _ScheduleRowMeasure({
    required this.frame,
    required this.position,
    required this.date,
    required this.rowId,
    required super.child,
  });
  final _ScheduleFrame? frame;
  final ScrollPosition? position;
  final DateTime date;
  final Object rowId;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScheduleRow(frame, position, date, rowId);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScheduleRow object,
  ) {
    object.update(frame, position, date, rowId);
  }
}

class _RenderScheduleRow extends RenderProxyBox {
  _RenderScheduleRow(this.frame, this.position, this.date, this.rowId);
  _ScheduleFrame? frame;
  ScrollPosition? position;
  DateTime date;
  Object rowId;
  void update(
    _ScheduleFrame? nextFrame,
    ScrollPosition? nextPosition,
    DateTime nextDate,
    Object nextRowId,
  ) {
    if (attached) frame?.removeRow(this);
    frame = nextFrame;
    position = nextPosition;
    date = nextDate;
    rowId = nextRowId;
    if (attached) frame?.addRow(this);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final frame = this.frame;
    final viewport = frame?.viewport;
    if (frame != null && viewport != null) {
      frame.read();
      if (frame.reading.clip.contains(
        localToGlobal(position, ancestor: viewport),
      )) {
        return false;
      }
    }
    return super.hitTestChildren(result, position: position);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    frame?.addRow(this);
  }

  @override
  void detach() {
    frame?.removeRow(this);
    super.detach();
  }
}

class _ScheduleLayer extends SingleChildRenderObjectWidget {
  const _ScheduleLayer({
    super.key,
    required this.frame,
    this.day,
    this.today,
    required super.child,
  });
  final _ScheduleFrame frame;
  final DateTime? day;
  final DCalendarScheduleTodayPosition? today;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScheduleLayer(frame, day, today);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScheduleLayer object,
  ) {
    object
      ..day = day
      ..today = today
      ..markNeedsPaint()
      ..markNeedsSemanticsUpdate();
  }
}

class _RenderScheduleLayer extends RenderProxyBox {
  _RenderScheduleLayer(this.frame, this.day, this.today);
  final _ScheduleFrame frame;
  DateTime? day;
  DCalendarScheduleTodayPosition? today;
  bool get visible =>
      day != null ? frame.reading.day == day : frame.reading.today == today;
  Offset get shift => Offset(0, day != null ? frame.reading.push : 0);
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    frame.layers.add(this);
  }

  @override
  void detach() {
    frame.layers.remove(this);
    super.detach();
  }

  @override
  Rect get paintBounds => visible ? super.paintBounds.shift(shift) : Rect.zero;
  @override
  void paint(PaintingContext context, Offset offset) {
    if (!visible) return;
    final opacity = day != null ? frame.reading.opacity : 1.0;
    if (opacity < 1) {
      context.canvas.saveLayer(
        paintBounds.shift(offset),
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
    }
    super.paint(context, offset + shift);
    if (opacity < 1) context.canvas.restore();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      day == null &&
      visible &&
      super.hitTestChildren(result, position: position);
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (visible) super.visitChildrenForSemantics(visitor);
  }
}

class _ScheduleContent extends SingleChildRenderObjectWidget {
  const _ScheduleContent({required this.frame, required super.child});
  final _ScheduleFrame frame;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScheduleContent(frame);
}

class _RenderScheduleContent extends RenderProxyBox {
  _RenderScheduleContent(this.frame);
  final _ScheduleFrame frame;
  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    final clip = frame.reading.clip;
    return clip.width >= size.width
        ? Rect.fromLTRB(0, clip.bottom, size.width, size.height)
        : Offset.zero & size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    frame.read();
    final clip = frame.reading.clip;
    if (clip.isEmpty) {
      super.paint(context, offset);
      return;
    }
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(clip);
    context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      path,
      super.paint,
    );
  }
}

class _ScheduleSourceHeading extends SingleChildRenderObjectWidget {
  const _ScheduleSourceHeading({
    required this.frame,
    required this.date,
    required super.child,
  });
  final _ScheduleFrame? frame;
  final DateTime? date;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScheduleSourceHeading(frame, date);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderScheduleSourceHeading object,
  ) {
    object.date = date;
  }
}

class _RenderScheduleSourceHeading extends RenderProxyBox {
  _RenderScheduleSourceHeading(this.frame, this.date);
  final _ScheduleFrame? frame;
  DateTime? date;
  bool get visible =>
      frame == null || date == null || frame!.reading.day != date;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    frame?.sourceHeadings.add(this);
  }

  @override
  void detach() {
    frame?.sourceHeadings.remove(this);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    frame?.read();
    if (visible) super.paint(context, offset);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (visible) super.visitChildrenForSemantics(visitor);
  }
}
