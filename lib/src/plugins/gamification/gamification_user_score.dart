import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'gamification_controller.dart';
import 'gamification_labels.dart';
import 'gamification_models.dart';
import 'gamification_navigation.dart';

class GamificationUserScoreMetadata extends StatelessWidget {
  const GamificationUserScoreMetadata({
    super.key,
    required this.controller,
    required this.site,
    required this.score,
    required this.navigation,
    this.close,
  });
  final GamificationController controller;
  final String site;
  final GamificationUserScore score;
  final GamificationNavigation navigation;
  final VoidCallback? close;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => controller.enabled(site) && score.totalScore != 0
        ? DButton(
            variant: DButtonVariant.inline,
            onPressed: () {
              close?.call();
              navigation.openForSite(
                site,
                const GamificationRoute(period: GamificationPeriod.allTime),
              );
            },
            label: Text(
              '${gameNumber(context, score.totalScore)} ${context.l10n.gamificationCheers}',
            ),
          )
        : const SizedBox.shrink(),
  );
}
