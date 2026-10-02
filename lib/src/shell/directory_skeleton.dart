import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'skeleton_fill.dart';

enum DirectorySkeletonKind { bookmarks, badges, categories, groups, users }

/// Page placeholders composed from the Native skeletons, sized to the viewport.
class DirectorySkeleton extends StatelessWidget {
  const DirectorySkeleton({super.key, required this.kind});

  final DirectorySkeletonKind kind;

  double get _rowHeight => switch (kind) {
    DirectorySkeletonKind.bookmarks => 80,
    DirectorySkeletonKind.badges => 96,
    DirectorySkeletonKind.categories => 80,
    DirectorySkeletonKind.groups => 144,
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
    final groups = kind == DirectorySkeletonKind.groups;
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
                DSkeleton.circle(diameter: users ? 24 : 40),
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
              if (users)
                for (var column = 0; column < (width < 600 ? 1 : 4); column++)
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
          if (groups) ...[
            const SizedBox(height: DSpacing.md),
            const DSkeleton(height: 12),
            const SizedBox(height: DSpacing.sm),
            const FractionallySizedBox(
              widthFactor: .6,
              child: DSkeleton(height: 12),
            ),
          ],
        ],
      ),
    );
  }
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
