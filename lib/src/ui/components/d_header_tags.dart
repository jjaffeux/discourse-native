import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/control_style.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_direction.dart';

/// A category step displayed before a header's tags.
class DHeaderStep {
  const DHeaderStep({
    required this.label,
    required this.child,
    this.marked = true,
    this.own = true,
  });

  /// Measured to decide whether the whole path fits.
  final String label;
  final Widget child;

  /// Whether [child] leads its label with the category's mark.
  final bool marked;

  /// The final selected category, which stays when the path will not fit.
  final bool own;
}

/// The reference's head arithmetic: each chip counted with the gap after
/// it. The path is kept whole only while it and a count of every tag fit,
/// else the step at [own] stands alone; then as many tags as fit beside the
/// count of the rest.
({bool wholePath, int tags}) fitHeaderTags({
  required double available,
  required List<double> path,
  required int own,
  required List<double> tags,
  required double Function(int hidden) count,
  double gap = DSpacing.sm,
}) {
  double run(Iterable<double> widths) =>
      widths.fold(0.0, (sum, width) => sum + width + gap);
  final wholePath =
      path.length < 2 ||
      run(path) + (tags.isEmpty ? 0 : count(tags.length) + gap) <= available;
  var used = run(wholePath ? path : [path[own]]);
  var shown = 0;
  while (shown < tags.length) {
    final rest = tags.length - shown - 1;
    final next = tags[shown] + gap;
    if (used + next + (rest > 0 ? count(rest) + gap : 0) > available) break;
    used += next;
    shown++;
  }
  return (wholePath: wholePath, tags: shown);
}

/// One tag label and its filter-sized Native hash-prefixed button.
class DHeaderTag {
  const DHeaderTag({required this.name, required this.child});

  final String name;
  final Widget child;
}

/// A compact category and tag row that expands hidden tags inline.
/// Callers own the tag controls and their navigation or editing actions.
class DHeaderTags extends StatefulWidget {
  const DHeaderTags({
    super.key,
    required this.identity,
    required this.tags,
    required this.expandSemanticLabel,
    this.path = const [],
    this.emptyAction,
    this.expandedAction,
    this.tools,
    this.moreKey,
  });

  final Object identity;
  final List<DHeaderTag> tags;
  final List<DHeaderStep> path;
  final String expandSemanticLabel;
  final Widget? emptyAction;
  final Widget? expandedAction;
  final Widget? tools;
  final Key? moreKey;

  @override
  State<DHeaderTags> createState() => _DHeaderTagsState();
}

class _DHeaderTagsState extends State<DHeaderTags> {
  Object get _storageId => widget.identity;

  bool get _allTags =>
      PageStorage.maybeOf(context)?.readState(context, identifier: _storageId)
          as bool? ??
      _expanded;
  bool _expanded = false;

  /// Whether the whole path fit on the line before the tags were opened.
  bool? _wholePath;

  void _showAllTags() {
    PageStorage.maybeOf(
      context,
    )?.writeState(context, true, identifier: _storageId);
    setState(() => _expanded = true);
  }

  @override
  void didUpdateWidget(DHeaderTags oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _expanded = false;
      _wholePath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    final style = _chipStyle(context);
    double labelWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: DDirection.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final inset = DControlStyle.horizontalInset(DControlSize.filter) * 2;
    final mark =
        DControlStyle.iconDimension(DControlSize.filter, context: context) +
        DSpacing.controlGap;
    double stepWidth(DHeaderStep step) =>
        (labelWidth(step.label) + inset + (step.marked ? mark : 0))
            .ceilToDouble();
    double tagWidth(DHeaderTag tag) =>
        (labelWidth('#') + DSpacing.controlGap + labelWidth(tag.name) + inset)
            .ceilToDouble();
    double countWidth(int hidden) =>
        (labelWidth('+$hidden') + inset).ceilToDouble();

    final muted = DTokens.of(context).mutedForeground;
    Widget countChip(int hidden) => DButton(
      key: widget.moreKey,
      variant: DButtonVariant.ghost,
      shape: DButtonShape.pill,
      size: DButtonSize.filter,
      foregroundColor: muted,
      tooltip: [
        for (final tag in tags.skip(tags.length - hidden)) tag.name,
      ].join(', '),
      semanticLabel: widget.expandSemanticLabel,
      onPressed: _showAllTags,
      label: Text('+$hidden', maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    final tools = widget.tools;
    final steps = widget.path;
    final own = math.max(0, steps.lastIndexWhere((step) => step.own));
    ({bool wholePath, int tags}) fit(double available) => fitHeaderTags(
      available: available,
      path: [for (final step in steps) stepWidth(step)],
      own: own,
      tags: [for (final tag in tags) tagWidth(tag)],
      count: countWidth,
    );
    if (_allTags && tags.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // The path is still the one that fit beside the tools.
          final wholePath = _wholePath ?? fit(constraints.maxWidth).wholePath;
          return _HeaderTagsRun(
            children: [
              for (final (index, step) in steps.indexed)
                if (wholePath || index == own) step.child,
              for (final tag in tags) tag.child,
              ?widget.expandedAction,
              tools ?? const SizedBox.shrink(),
            ],
          );
        },
      );
    }
    final identity = LayoutBuilder(
      builder: (context, constraints) {
        final fitted = fit(constraints.maxWidth);
        _wholePath = fitted.wholePath;
        return Row(
          spacing: DSpacing.sm,
          children: [
            for (final (index, step) in steps.indexed)
              if (fitted.wholePath || index == own) Flexible(child: step.child),
            for (final tag in tags.take(fitted.tags)) tag.child,
            // Only narrower than its label in a strip with no room for
            // a tag, where it must still not run past the end.
            if (fitted.tags < tags.length)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    0,
                    constraints.maxWidth - (steps.isEmpty ? 0 : DSpacing.sm),
                  ),
                ),
                child: countChip(tags.length - fitted.tags),
              ),
            if (tags.isEmpty && widget.emptyAction != null)
              Flexible(child: widget.emptyAction!),
          ],
        );
      },
    );
    return tools == null
        ? identity
        : _HeaderTagsLine(children: [identity, tools]);
  }
}

// The chips' own text style, which DButton builds on labelLarge.
TextStyle? _chipStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: DControlStyle.fontSize(DControlSize.filter, context: context),
      height:
          DControlStyle.lineHeight(DControlSize.filter, context: context) /
          DControlStyle.fontSize(DControlSize.filter, context: context),
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );

/// The identity and the tools on one line, the tools at its end and the
/// identity in what they leave. Tools that would leave it too little room to
/// say anything, as at the largest text sizes, go below it instead.
class _HeaderTagsLine extends MultiChildRenderObjectWidget {
  const _HeaderTagsLine({required super.children})
    : assert(children.length == 2);

  @override
  _RenderHeaderTagsLine createRenderObject(BuildContext context) =>
      _RenderHeaderTagsLine(
        Directionality.of(context),
        DControlStyle.scaledHeight(
          DControlSize.filter,
          MediaQuery.textScalerOf(context),
          context: context,
        ),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderTagsLine renderObject,
  ) => renderObject
    ..textDirection = Directionality.of(context)
    ..controlHeight = DControlStyle.scaledHeight(
      DControlSize.filter,
      MediaQuery.textScalerOf(context),
      context: context,
    );
}

class _RenderHeaderTagsLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderTagsRunData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderTagsRunData> {
  _RenderHeaderTagsLine(this._textDirection, this._controlHeight);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  double _controlHeight;
  set controlHeight(double value) {
    if (value == _controlHeight) return;
    _controlHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderTagsRunData) {
      child.parentData = _HeaderTagsRunData();
    }
  }

  @override
  void performLayout() {
    const gap = DSpacing.sm;
    final width = constraints.maxWidth;
    final identity = firstChild!;
    final tools = lastChild!;
    tools.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final room = width - tools.size.width - gap;
    final shared = room >= _controlHeight * 3;
    identity.layout(
      BoxConstraints.tightFor(width: shared ? room : width),
      parentUsesSize: true,
    );
    double x(RenderBox box, double start) => _textDirection == TextDirection.ltr
        ? start
        : width - start - box.size.width;
    final toolsData = tools.parentData! as _HeaderTagsRunData;
    final identityData = identity.parentData! as _HeaderTagsRunData;
    if (shared) {
      final height = math.max(identity.size.height, tools.size.height);
      identityData.offset = Offset(
        x(identity, 0),
        (height - identity.size.height) / 2,
      );
      toolsData.offset = Offset(
        x(tools, width - tools.size.width),
        (height - tools.size.height) / 2,
      );
      size = constraints.constrain(Size(width, height));
      return;
    }
    identityData.offset = Offset(x(identity, 0), 0);
    final top = identity.size.height > 0 ? identity.size.height + gap : 0.0;
    toolsData.offset = Offset(x(tools, width - tools.size.width), top);
    size = constraints.constrain(Size(width, top + tools.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Lays its children out as a wrapping run with their gaps, the last child
/// held to the end of whichever line it lands on.
class _HeaderTagsRun extends MultiChildRenderObjectWidget {
  const _HeaderTagsRun({required super.children});

  @override
  _RenderHeaderTagsRun createRenderObject(BuildContext context) =>
      _RenderHeaderTagsRun(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderTagsRun renderObject,
  ) => renderObject.textDirection = Directionality.of(context);
}

class _HeaderTagsRunData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeaderTagsRun extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderTagsRunData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderTagsRunData> {
  _RenderHeaderTagsRun(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  static const _gap = DSpacing.sm;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderTagsRunData) {
      child.parentData = _HeaderTagsRunData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final lines = <List<RenderBox>>[[]];
    final lineWidths = <double>[0];
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      final line = lines.last;
      final needed =
          lineWidths.last + (line.isEmpty ? 0 : _gap) + child.size.width;
      if (line.isNotEmpty && needed > width) {
        lines.add([child]);
        lineWidths.add(child.size.width);
      } else {
        line.add(child);
        lineWidths.last = needed;
      }
      child = childAfter(child);
    }
    var y = 0.0;
    for (final line in lines) {
      final height = line.fold(0.0, (h, box) => math.max(h, box.size.height));
      var x = 0.0;
      for (final box in line) {
        final start = box == lastChild ? width - box.size.width : x;
        (box.parentData! as _HeaderTagsRunData).offset = Offset(
          _textDirection == TextDirection.ltr
              ? start
              : width - start - box.size.width,
          y + (height - box.size.height) / 2,
        );
        x += box.size.width + _gap;
      }
      y += height + _gap;
    }
    size = constraints.constrain(Size(width, math.max(0, y - _gap)));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
