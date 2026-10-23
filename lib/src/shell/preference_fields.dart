import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// The one surface every Preferences section, core or plugin, lays its rows
/// on, so a plugin tab cannot drift from the core tabs' card and row rhythm.
class PreferenceCard extends StatelessWidget {
  const PreferenceCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DFieldGroup(spacing: 0, children: children);
  }
}

/// A setting row shares Field layout and the existing Select interaction owner.
class PreferenceSelect<T> extends StatelessWidget {
  const PreferenceSelect({
    super.key,
    required this.value,
    required this.label,
    this.description,
    required this.entries,
    required this.onChanged,
    required this.initialValue,
    required this.enabled,
    this.isExpanded = true,
    this.size = DControlSize.preference,
  });
  final T value;
  final Widget label;
  final Widget? description;
  final List<DSelectEntry<T>> entries;
  final ValueChanged<T?>? onChanged;
  final T initialValue;
  final bool enabled;
  final bool isExpanded;
  final DControlSize size;
  @override
  Widget build(BuildContext context) => DField(
    enabled: enabled,
    orientation: MediaQuery.textScalerOf(context).scale(14) > 21
        ? DFieldOrientation.vertical
        : DFieldOrientation.responsive,
    responsiveBreakpoint: 520,
    children: [
      DFieldContent(
        children: [
          DFieldLabel(child: label),
          if (description != null) DFieldDescription(child: description!),
        ],
      ),
      DFieldControl(
        label: label is Text ? ((label as Text).data ?? '') : '',
        expand: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: DSelect<T>.controlled(
            value: value,
            initialValue: initialValue,
            size: size,
            isExpanded: isExpanded,
            entries: entries,
            semanticLabel: label is Text ? (label as Text).data : null,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}
