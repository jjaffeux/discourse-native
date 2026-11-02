import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

class MathComposerCard extends StatelessWidget {
  const MathComposerCard({
    super.key,
    required this.expression,
    required this.configuration,
    required this.expressions,
    required this.expressionIndex,
    this.onEdit,
  });

  final DMathExpression expression;
  final DMathConfiguration configuration;
  final List<DMathExpression> expressions;
  final int expressionIndex;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => DCard(
    size: DCardSize.small,
    spacing: DSpacing.sm,
    border: false,
    borderRadius: BorderRadius.circular(DRadius.nested),
    backgroundColor: Theme.of(context).code.blockBackground,
    children: [
      DCardContent(
        child: Align(
          alignment: Alignment.centerRight,
          child: DButton.iconOnly(
            variant: DButtonVariant.ghost,
            size: DButtonSize.small,
            icon: const DIcon(DIcons.pencil),
            tooltip: context.l10n.editMath,
            onPressed: onEdit,
          ),
        ),
      ),
      DCardContent(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
          child: Align(
            alignment: Alignment.center,
            child: DMath(
              expression: expression,
              configuration: configuration,
              context: expressions,
              contextIndex: expressionIndex,
              fontSize: MediaQuery.textScalerOf(
                context,
              ).scale(DiscourseTypography.xxl),
            ),
          ),
        ),
      ),
    ],
  );
}
