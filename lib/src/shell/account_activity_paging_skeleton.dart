import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import 'skeleton_fill.dart';

class AccountActivityPagingSkeleton extends StatelessWidget {
  const AccountActivityPagingSkeleton({
    super.key,
    required this.semanticsLabel,
  });

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: semanticsLabel,
    color: skeletonFill(context),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const DSeparator(space: 1),
          DItem(
            shape: DItemShape.fullWidth,
            children: [
              const DItemMedia(child: DSkeleton.circle(diameter: 40)),
              DItemContent(
                spacing: DSpacing.sm,
                children: [
                  FractionallySizedBox(
                    widthFactor: row.isEven ? .65 : .8,
                    child: const DSkeleton(height: 14),
                  ),
                  const FractionallySizedBox(
                    widthFactor: .45,
                    child: DSkeleton(height: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
