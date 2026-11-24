import 'package:flutter/material.dart';

import '../../foundation/icons/d_icons.dart';
import '../../theme/d_icon.dart';
import '../../theme/tokens.dart';
import 'd_button.dart';
import 'd_card.dart';
import 'd_mobile_dock_geometry.dart';

/// The phone composer's actions occupy the navigation dock's bottom row.
class DComposerActionBar extends StatelessWidget {
  const DComposerActionBar({
    super.key,
    required this.closeLabel,
    required this.onClose,
    required this.history,
    required this.submitLabel,
    required this.onSubmit,
    this.closeHasChoices = false,
    this.submitting = false,
    this.closeKey,
    this.submitKey,
  });

  final String closeLabel;
  final VoidCallback onClose;
  final Widget history;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final bool closeHasChoices;
  final bool submitting;
  final Key? closeKey;
  final Key? submitKey;

  @override
  Widget build(BuildContext context) {
    final geometry = DMobileDockGeometry.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final tokens = DTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DMobileDockGeometry.inset,
      ),
      child: DCard(
        spacing: 0,
        border: false,
        borderRadius: keyboard
            ? BorderRadius.circular(geometry.topRadius)
            : geometry.borderRadius,
        backgroundColor: keyboard ? Colors.transparent : tokens.background,
        child: Padding(
          padding: const EdgeInsets.all(DMobileDockGeometry.inset),
          child: Row(
            spacing: DSpacing.sm,
            children: [
              DButton.iconOnly(
                key: closeKey,
                density: DButtonDensity.mobileDockAction,
                variant: DButtonVariant.secondary,
                shape: DButtonShape.pill,
                icon: const DIcon(DIcons.xmark),
                tooltip: closeLabel,
                semanticLabel: closeLabel,
                hasPopup: closeHasChoices,
                onPressed: onClose,
              ),
              history,
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DButton(
                    key: submitKey,
                    density: DButtonDensity.mobileDockAction,
                    shape: DButtonShape.pill,
                    backgroundColor: onSubmit == null ? null : tokens.primary,
                    foregroundColor: onSubmit == null
                        ? null
                        : tokens.colors.onPrimary,
                    semanticLabel: submitLabel,
                    tooltip: submitLabel,
                    loading: submitting,
                    onPressed: submitting ? null : onSubmit,
                    label: Text(
                      submitLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
