import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

/// The same section navigation for forum Interface and account Preferences.
class SettingsSectionTabs<T> extends StatelessWidget {
  const SettingsSectionTabs({
    super.key,
    required this.value,
    required this.sections,
    required this.onChanged,
  });
  final T value;
  final List<({T value, String label, Key? key})> sections;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => DTabs<T>.controlled(
    value: value,
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
    children: [
      DTabList<T>(
        variant: DTabListVariant.line,
        children: [
          for (final section in sections)
            DTabTrigger<T>(
              key: section.key,
              value: section.value,
              child: Text(section.label),
            ),
        ],
      ),
    ],
  );
}
