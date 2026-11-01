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
    this.onRemove,
  });

  final DMathExpression expression;
  final DMathConfiguration configuration;
  final List<DMathExpression> expressions;
  final int expressionIndex;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => DCard(
    size: DCardSize.small,
    children: [
      DCardHeader(
        title: DCardTitle(
          child: Row(
            spacing: DSpacing.sm,
            children: [
              const DIcon(DIcons.squareRootVariable),
              Flexible(child: Text(context.l10n.mathExpression)),
            ],
          ),
        ),
        action: DCardAction(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DButton.iconOnly(
                icon: const DIcon(DIcons.pencil),
                tooltip: context.l10n.editMath,
                onPressed: onEdit,
              ),
              DDropdownMenu(
                content: DDropdownMenuContent(
                  children: [
                    DDropdownMenuItem(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: expression.source),
                      ),
                      child: Text(context.l10n.copySource),
                    ),
                    const DDropdownMenuSeparator(),
                    DDropdownMenuItem(
                      variant: DDropdownMenuItemVariant.destructive,
                      onPressed: onRemove,
                      child: Text(context.l10n.delete),
                    ),
                  ],
                ),
                child: DDropdownMenuTrigger(
                  builder: (context, state) => DButton.iconOnly(
                    variant: DButtonVariant.ghost,
                    icon: const DIcon(DIcons.ellipsis),
                    tooltip: context.l10n.moreOptions,
                    expanded: state.open,
                    hasPopup: true,
                    onPressed: state.toggle,
                  ),
                ),
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
