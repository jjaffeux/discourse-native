import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// Side-by-side acceptance surface for control styles and interactions.
class ControlComparisonExample extends StatefulWidget {
  const ControlComparisonExample({super.key});

  @override
  State<ControlComparisonExample> createState() =>
      _ControlComparisonExampleState();
}

class _ControlComparisonExampleState extends State<ControlComparisonExample> {
  String _feed = 'Recent';
  String _category = 'Bugs';
  int _notification = 2;
  String _result = 'No action yet';

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final size in DControlSize.values) ...[
          Text('${size.name} — ${DControlStyle.height(size).toInt()}px'),
          const SizedBox(height: DSpacing.sm),
          Wrap(
            spacing: DSpacing.sm,
            runSpacing: DSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DButton(
                label: const Text('Button'),
                variant: DButtonVariant.outline,
                size: size,
                onPressed: () => setState(() => _result = 'Button activated'),
              ),
              DButton.iconOnly(
                icon: const Icon(Icons.add),
                tooltip: '${size.name} icon button',
                variant: DButtonVariant.outline,
                size: size,
                onPressed: () => setState(() => _result = 'Icon activated'),
              ),
              DToggle(
                size: size,
                variant: DToggleVariant.outline,
                child: const Text('Toggle'),
              ),
              DSelect<String>(
                width: 128,
                size: size,
                semanticLabel: '${size.name} feed',
                value: _feed,
                entries: [
                  for (final label in ['Recent', 'Top', 'Trending'])
                    DSelectItem(
                      value: label,
                      textValue: label,
                      child: Text(label),
                    ),
                ],
                onChanged: (value) => setState(() => _feed = value!),
              ),
              DDropdownMenu(
                content: DDropdownMenuContent(
                  children: [
                    for (final label in ['Bugs', 'Support', 'General'])
                      DDropdownMenuItem(
                        onPressed: () => setState(() => _category = label),
                        child: Text(label),
                      ),
                  ],
                ),
                child: DDropdownMenuTrigger.button(
                  label: Text(_category),
                  icon: const Icon(Icons.keyboard_arrow_down),
                  iconPosition: DButtonIconPosition.end,
                  semanticLabel: '${size.name} category',
                  size: size,
                ),
              ),
              DButton(
                label: const Text('Disabled'),
                variant: DButtonVariant.outline,
                size: size,
                onPressed: null,
              ),
            ],
          ),
          const SizedBox(height: DSpacing.lg),
        ],
        const Text('Contextual actions'),
        const SizedBox(height: DSpacing.sm),
        // Wrap keeps the group usable at large text and narrow preview widths.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DButton(
                label: const Text('Reply'),
                icon: const Icon(Icons.reply),
                size: DButtonSize.regular,
                onPressed: () => setState(() => _result = 'Reply activated'),
              ),
              const SizedBox(width: DSpacing.sm),
              DButtonGroup(
                children: [
                  DButton.iconOnly(
                    icon: const Icon(Icons.bookmark_outline),
                    tooltip: 'Bookmark',
                    variant: DButtonVariant.outline,
                    size: DButtonSize.regular,
                    onPressed: () =>
                        setState(() => _result = 'Bookmark activated'),
                  ),
                  DNotificationLevelMenu<int>(
                    value: _notification,
                    onChanged: (value) => setState(() => _notification = value),
                    semanticLabel: 'Notifications',
                    showLabel: true,
                    variant: DButtonVariant.outline,
                    size: DButtonSize.regular,
                    options: const [
                      DNotificationLevelOption(
                        value: 1,
                        label: 'Normal',
                        description: 'Notify on mentions',
                        icon: Icon(Icons.notifications_none),
                      ),
                      DNotificationLevelOption(
                        value: 2,
                        label: 'Watching',
                        description: 'Notify on every reply',
                        icon: Icon(Icons.notifications_active),
                        emphasized: true,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DSpacing.sm),
        Text(_result),
      ],
    ),
  );
}
