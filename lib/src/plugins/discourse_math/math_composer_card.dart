import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
    children: [
      DCardHeader(
        title: const DIcon(DIcons.squareRootVariable),
        action: DCardAction(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DButton.iconOnly(
                icon: const DIcon(DIcons.pencil),
                tooltip: context.l10n.editMath,
                onPressed: onEdit,
              ),
              DButton.iconOnly(
                variant: DButtonVariant.ghost,
                icon: const DIcon(DIcons.copy),
                tooltip: context.l10n.copySource,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: expression.source)),
              ),
            ],
          ),
        ),
      ),
      DCardContent(
        child: DCard(
          variant: DCardVariant.well,
          spacing: 0,
          border: false,
          child: Padding(
            padding: const EdgeInsets.all(DSpacing.lg),
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
      ),
    ],
  );
}
