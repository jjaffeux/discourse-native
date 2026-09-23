import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icons.dart';
import '../../theme/d_native_icons.dart';

/// The application reference's control families at their natural artwork size.
class MockupControlSizesExample extends StatefulWidget {
  const MockupControlSizesExample({super.key});

  @override
  State<MockupControlSizesExample> createState() =>
      _MockupControlSizesExampleState();
}

class _MockupControlSizesExampleState extends State<MockupControlSizesExample> {
  String _filter = 'Latest';
  String _preference = 'Always';
  bool _notifications = true;
  String _result = 'No action yet';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    spacing: DSpacing.lg,
    children: [
      const Text('Filters · 30.75px'),
      Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DDropdownMenu(
            content: DDropdownMenuContent(
              children: [
                for (final filter in ['Latest', 'Unread', 'New'])
                  DDropdownMenuItem(
                    onPressed: () => setState(() => _filter = filter),
                    child: Text(filter),
                  ),
              ],
            ),
            child: DDropdownMenuTrigger.button(
              size: DControlSize.filter,
              label: Text(
                _filter,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              icon: const DIcon(DNativeIcons.filterChevron, size: 10),
              iconPosition: DButtonIconPosition.end,
            ),
          ),
          DSelect<String>(
            size: DControlSize.filter,
            width: 140,
            value: 'All groups',
            entries: const [
              DSelectOption(
                value: 'All groups',
                label: 'All groups',
                child: Text('All groups'),
              ),
            ],
            onChanged: (_) {},
          ),
          DButton.iconOnly(
            size: DControlSize.chip,
            icon: const DIcon(DIcons.bookmark),
            variant: DButtonVariant.outline,
            tooltip: 'Bookmark',
            onPressed: () => setState(() => _result = 'Bookmarked'),
          ),
        ],
      ),
      const Text('Search field · 35.5px'),
      DInput(size: DControlSize.field, hintText: 'Filter users'),
      const Text('Preference · 40.25px'),
      DSelect<String>(
        size: DControlSize.preference,
        isExpanded: true,
        value: _preference,
        semanticLabel: 'Like notifications',
        entries: [
          for (final value in ['Always', 'First time and daily', 'Never'])
            DSelectOption(value: value, label: value, child: Text(value)),
        ],
        onChanged: (value) => setState(() => _preference = value!),
      ),
      DSwitchTile(
        size: DSwitchSize.preference,
        value: _notifications,
        onChanged: (value) => setState(() => _notifications = value),
        title: const Text('Notify me about replies'),
        subtitle: const Text('38 × 22px artwork; an 18px thumb.'),
      ),
      const Text('Toolbar · 34px / segments · 28px'),
      Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DButton.iconOnly(
            size: DControlSize.toolbar,
            variant: DButtonVariant.transparentBackground,
            icon: const DIcon(DIcons.bold),
            tooltip: 'Bold',
            onPressed: () => setState(() => _result = 'Bold activated'),
          ),
          const DToggleGroup<String>(
            size: DControlSize.segment,
            inset: true,
            initialValues: ['list'],
            items: [
              DToggleGroupItem.iconOnly(
                value: 'list',
                semanticLabel: 'List',
                icon: DIcon(DIcons.list),
              ),
              DToggleGroupItem.iconOnly(
                value: 'split',
                semanticLabel: 'Split',
                icon: Icon(Icons.view_sidebar_outlined),
              ),
            ],
          ),
          DButton(
            size: DControlSize.action,
            label: const Text('Reply'),
            onPressed: () => setState(() => _result = 'Reply activated'),
          ),
        ],
      ),
      Text(_result),
    ],
  );
}
