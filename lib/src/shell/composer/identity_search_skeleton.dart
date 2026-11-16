import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../skeleton_fill.dart';

const composerIdentityAvatarSize = 22.0;

class ComposerIdentitySearchSkeleton extends StatelessWidget {
  const ComposerIdentitySearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: context.l10n.searching,
    color: skeletonFill(context, on: SkeletonSurface.floating),
    child: ListView.builder(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: DInsets.menu,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.all(DSpacing.sm),
        child: Row(
          spacing: DSpacing.sm,
          children: [
            const DSkeleton.circle(diameter: composerIdentityAvatarSize),
            Flexible(
              child: DSkeleton(width: index.isEven ? 150 : 112, height: 14),
            ),
          ],
        ),
      ),
    ),
  );
}
