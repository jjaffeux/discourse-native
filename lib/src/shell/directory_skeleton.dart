import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'skeleton_fill.dart';

enum DirectorySkeletonKind {
  bookmarks,
  badges,
  categories,
  groups,
  tags,
  users,
}

/// Page placeholders composed from the Native skeletons, sized to the viewport.
class DirectorySkeleton extends StatelessWidget {
  const DirectorySkeleton({super.key, required this.kind});

  final DirectorySkeletonKind kind;

  double get _rowHeight => switch (kind) {
    DirectorySkeletonKind.bookmarks => 80,
    DirectorySkeletonKind.badges => 96,
    DirectorySkeletonKind.categories => 80,
    DirectorySkeletonKind.groups => _GroupRowSkeleton.minHeight,
    DirectorySkeletonKind.tags => 80,
    DirectorySkeletonKind.users => 48,
  };

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: context.l10n.loadingDirectoryskeleton(
      (kind.name).toString(),
    ),
    color: skeletonFill(context),
    expand: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (kind == DirectorySkeletonKind.categories) {
          final columns = DPlaceCardGrid.columnsFor(
            context,
            constraints.maxWidth,
          );
          final rows = constraints.hasBoundedHeight
              ? (constraints.maxHeight / 100).ceil() + 1
              : 6;
          return CustomScrollView(
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              DPlaceCardGrid(
                itemCount: rows * columns,
                itemBuilder: (context, index) => const DPlaceCardSkeleton(),
              ),
            ],
          );
        }
        final rows = constraints.hasBoundedHeight
            ? math.max(1, (constraints.maxHeight / _rowHeight).ceil())
            : 6;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < rows; index++)
                  if (kind == DirectorySkeletonKind.groups) ...[
                    if (index > 0) const DSeparator(),
                    _GroupRowSkeleton(index: index),
                  ] else
                    SizedBox(
                      height: _rowHeight,
                      child: _row(index, constraints.maxWidth),
                    ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _row(int index, double width) {
    final users = kind == DirectorySkeletonKind.users;
    final tags = kind == DirectorySkeletonKind.tags;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DSpacing.lg,
        vertical: users ? DSpacing.sm : DSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (kind == DirectorySkeletonKind.categories)
                DSkeleton(
                  width: 40,
                  height: 40,
                  borderRadius: BorderRadius.circular(DRadius.popover),
                )
              else
                DSkeleton.circle(diameter: users || tags ? 24 : 40),
              SizedBox(width: users ? DSpacing.sm : DSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: index.isEven ? .65 : .85,
                      child: const DSkeleton(height: 14),
                    ),
                    if (!users) ...[
                      const SizedBox(height: DSpacing.sm),
                      FractionallySizedBox(
                        widthFactor: index.isEven ? .85 : .55,
                        child: const DSkeleton(height: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (users || tags)
                for (
                  var column = 0;
                  column < (tags || width < 600 ? 1 : 4);
                  column++
                )
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(start: DSpacing.lg),
                      child: FractionallySizedBox(
                        widthFactor: .6,
                        alignment: AlignmentDirectional.centerEnd,
                        child: DSkeleton(height: 14),
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The groups directory row's own geometry, so replacing the placeholder with
/// loaded groups does not move the rows: the same item padding and spacing,
/// and bars centred in slots as tall as the text lines they stand in for.
class _GroupRowSkeleton extends StatelessWidget {
  const _GroupRowSkeleton({required this.index});

  /// The shortest real row: an identity line and a member line, without a bio.
  /// Sizes how many rows fill the viewport, so it must never overestimate.
  static const double minHeight = 100;

  final int index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium;
    return DItem(
      shape: DItemShape.fullWidth,
      children: [
        DItemContent(
          spacing: DSpacing.md,
          alignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DSkeleton.circle(diameter: DAvatarSize.lg.dimension),
                const SizedBox(width: DSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TextLineSkeleton(
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        widthFactor: index.isEven ? .55 : .7,
                        height: 14,
                      ),
                      _TextLineSkeleton(
                        style: body,
                        widthFactor: index.isEven ? .35 : .45,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TextLineSkeleton(
                  style: body,
                  widthFactor: index.isEven ? .85 : 1,
                ),
                if (index.isOdd)
                  _TextLineSkeleton(style: body, widthFactor: .5),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: DAvatarSize.sm.dimension),
              child: Row(
                children: [
                  DSkeleton(
                    width: DAvatarSize.sm.dimension * 3,
                    height: DAvatarSize.sm.dimension,
                    borderRadius: BorderRadius.circular(
                      DAvatarSize.sm.dimension / 2,
                    ),
                  ),
                  const SizedBox(width: DSpacing.sm),
                  const Expanded(child: _TextLineSkeleton(widthFactor: .3)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A bar in a slot exactly one line of [style] tall, at the host text scale.
class _TextLineSkeleton extends StatelessWidget {
  const _TextLineSkeleton({
    this.style,
    required this.widthFactor,
    this.height = 12,
  });

  final TextStyle? style;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: AlignmentDirectional.centerStart,
    children: [
      Text(' ', style: style),
      FractionallySizedBox(
        widthFactor: widthFactor,
        child: DSkeleton(height: height),
      ),
    ],
  );
}

/// Reserves the space below a route's controls without an intrinsic-size probe.
class SliverDirectorySkeleton extends StatelessWidget {
  const SliverDirectorySkeleton({super.key, required this.kind});

  final DirectorySkeletonKind kind;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverToBoxAdapter(
      child: SizedBox(
        height: math.max(
          0,
          constraints.viewportMainAxisExtent -
              constraints.precedingScrollExtent,
        ),
        child: DirectorySkeleton(kind: kind),
      ),
    ),
  );
}
