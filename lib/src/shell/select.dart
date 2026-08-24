import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';

/// A form select with the shell's shared floating-menu treatment.
///
/// Flutter does not expose a theme for the route created by
/// [DropdownButtonFormField], so keeping these route properties in an
/// app-owned wrapper is the only way form selects can match other menus.
class DSelectField<T> extends StatelessWidget {
  const DSelectField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = false,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.extension<ShellColors>();
    final floating = shell?.floating ?? theme.colorScheme.surfaceContainer;
    final hover =
        shell?.hover ?? theme.colorScheme.onSurface.withValues(alpha: 0.08);
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: onChanged,
      decoration: decoration,
      isExpanded: isExpanded,
      elevation: 8,
      dropdownColor: floating,
      borderRadius: BorderRadius.circular(12),
      menuMaxHeight: 360,
      focusColor: hover,
      icon: const DIcon(DIcons.chevronDown, size: 16),
      iconEnabledColor: theme.colorScheme.onSurfaceVariant,
      iconDisabledColor: theme.colorScheme.onSurfaceVariant.withValues(
        alpha: 0.45,
      ),
    );
  }
}

/// A non-form select with the same popup surface as [DSelectField].
class DSelect<T> extends StatelessWidget {
  const DSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.extension<ShellColors>();
    final floating = shell?.floating ?? theme.colorScheme.surfaceContainer;
    final hover =
        shell?.hover ?? theme.colorScheme.onSurface.withValues(alpha: 0.08);
    return DropdownButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: isExpanded,
      elevation: 8,
      dropdownColor: floating,
      borderRadius: BorderRadius.circular(12),
      menuMaxHeight: 360,
      focusColor: hover,
      icon: const DIcon(DIcons.chevronDown, size: 16),
      iconEnabledColor: theme.colorScheme.onSurfaceVariant,
      iconDisabledColor: theme.colorScheme.onSurfaceVariant.withValues(
        alpha: 0.45,
      ),
    );
  }
}
