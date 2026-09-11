import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dropdown_menu.dart';

/// One notification level, with its explanation and bell artwork.
@immutable
class DNotificationLevelOption<T> {
  const DNotificationLevelOption({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
    this.emphasized = false,
  });

  final T value;
  final String label;
  final String description;

  /// Inherits the trigger or menu row's icon size and color.
  final Widget icon;

  /// Highlights an icon-only trigger for an active subscription.
  final bool emphasized;
}

/// A notification-level button and its descriptive, single-selection dropdown.
///
/// [value] must match exactly one option. The caller owns selection and saving.
/// A null [onChanged] disables the trigger and choices. [showLabel] adds the
/// selected level's name.
///
/// Dropdown Menu owns keyboard navigation, scrolling, collision handling,
/// dismissal, and focus restoration. Change this widget's key when its target
/// or account changes so an open menu cannot outlive its owner.
class DNotificationLevelMenu<T> extends StatelessWidget {
  const DNotificationLevelMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.semanticLabel,
    this.showLabel = false,
    this.size = DButtonSize.small,
    this.variant,
    this.backgroundColor,
    this.borderColor,
    this.interactiveBackgroundColor,
    this.buttonKey,
  }) : assert(options.length > 0);

  final T value;
  final List<DNotificationLevelOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String semanticLabel;
  final bool showLabel;
  final DButtonSize size;

  /// Overrides the trigger style for compositions such as an outlined group.
  /// When null, labeled triggers are outlined and emphasized icon triggers use
  /// the primary accent.
  final DButtonVariant? variant;

  /// Overrides the trigger fill without changing the dropdown surface.
  final Color? backgroundColor;

  /// Overrides the trigger outline while preserving its keyboard focus ring.
  final Color? borderColor;

  /// Overrides the trigger's hover and focus fill.
  final Color? interactiveBackgroundColor;

  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final selected = options.singleWhere((option) => option.value == value);
    final label = '$semanticLabel: ${selected.label}';
    return DDropdownMenu(
      content: DDropdownMenuContent(
        semanticLabel: semanticLabel,
        width: 336,
        children: [
          DDropdownMenuRadioGroup<T>(
            value: value,
            onChanged: onChanged,
            children: [
              for (final option in options)
                DDropdownMenuRadioItem<T>(
                  value: option.value,
                  closeOnSelect: true,
                  semanticLabel: '${option.label}. ${option.description}',
                  leading: option.icon,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label),
                      Text(
                        option.description,
                        style: TextStyle(
                          color: DTokens.of(context).mutedForeground,
                          fontSize: DiscourseTypography.xs,
                          height: DiscourseTypography.lineHeightCaption,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, state) => showLabel
            ? DButton(
                key: buttonKey,
                label: Text(selected.label),
                icon: selected.icon,
                tooltip: label,
                semanticLabel: label,
                onPressed: onChanged == null ? null : state.toggle,
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                variant: variant ?? DButtonVariant.outline,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                interactiveBackgroundColor: interactiveBackgroundColor,
                size: size,
              )
            : DButton.iconOnly(
                insetSurface: variant == null && !selected.emphasized,
                key: buttonKey,
                icon: selected.icon,
                tooltip: label,
                semanticLabel: label,
                onPressed: onChanged == null ? null : state.toggle,
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                variant:
                    variant ??
                    (selected.emphasized
                        ? DButtonVariant.primary
                        : DButtonVariant.ghost),
                backgroundColor: backgroundColor,
                borderColor: borderColor,
                interactiveBackgroundColor: interactiveBackgroundColor,
                size: size,
              ),
      ),
    );
  }
}
