import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../../theme/d_icons.dart';

/// Local settings compositions for inspecting the shared Linear control styles.
class LinearControlsExample extends StatefulWidget {
  const LinearControlsExample({super.key});

  @override
  State<LinearControlsExample> createState() => _LinearControlsExampleState();
}

class _LinearControlsExampleState extends State<LinearControlsExample> {
  String _home = 'Inbox';
  String _theme = 'Light';
  bool _enabled = false;
  bool _emoticons = true;
  String _result = 'No action yet';

  Widget _themeLabel(String name) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const DBadge(variant: DBadgeVariant.secondary, child: Text('Aa')),
      const SizedBox(width: DSpacing.sm),
      Flexible(child: Text(name)),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DButton(
            label: Text(_enabled ? 'Enabled' : 'Enable'),
            size: DButtonSize.large,
            onPressed: () => setState(() => _enabled = !_enabled),
          ),
          DButton(
            label: const Text('Connect organization'),
            variant: DButtonVariant.outline,
            size: DButtonSize.small,
            onPressed: () => setState(() => _result = 'Organization connected'),
          ),
          DButton.iconOnly(
            icon: const DIcon(DIcons.pencil),
            tooltip: 'Change email',
            variant: DButtonVariant.outline,
            size: DButtonSize.small,
            onPressed: () => setState(() => _result = 'Email action activated'),
          ),
          DButton(
            icon: const DIcon(DIcons.chevronLeft),
            label: const Text('Back to app'),
            variant: DButtonVariant.transparentBackground,
            onPressed: () => setState(() => _result = 'Back action activated'),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.lg),
      DItemGroup(
        children: [
          DItem(
            variant: DItemVariant.muted,
            children: [
              const DItemContent(
                children: [
                  DItemTitle(child: Text('Default home view')),
                  DItemDescription(
                    child: Text('Select which view to display on launch'),
                  ),
                ],
              ),
              DItemActions(
                children: [
                  DSelect<String>(
                    semanticLabel: 'Default home view',
                    value: _home,
                    width: 160,
                    entries: [
                      for (final name in ['Inbox', 'My issues', 'Projects'])
                        DSelectItem(
                          value: name,
                          textValue: name,
                          child: Text(name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _home = value!),
                  ),
                ],
              ),
            ],
          ),
          DItem(
            variant: DItemVariant.muted,
            children: [
              const DItemContent(
                children: [
                  DItemTitle(child: Text('Interface theme')),
                  DItemDescription(
                    child: Text('Select your interface color scheme'),
                  ),
                ],
              ),
              DItemActions(
                children: [
                  DSelect<String>(
                    semanticLabel: 'Interface theme',
                    value: _theme,
                    width: 160,
                    valueBuilder: (_, value, _) => _themeLabel(value!),
                    entries: [
                      for (final name in ['Light', 'Dark', 'System'])
                        DSelectItem(
                          value: name,
                          textValue: name,
                          child: _themeLabel(name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _theme = value!),
                  ),
                ],
              ),
            ],
          ),
          DItem(
            variant: DItemVariant.muted,
            children: [
              const DItemContent(
                children: [DItemTitle(child: Text('Branch format'))],
              ),
              DItemActions(
                children: [
                  DSelect<String>(
                    semanticLabel: 'Branch format',
                    enabled: false,
                    width: 208,
                    value: 'username/identifier-title',
                    entries: const [
                      DSelectItem(
                        value: 'username/identifier-title',
                        textValue: 'username/identifier-title',
                        child: Text('username/identifier-title'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          DItem(
            variant: DItemVariant.muted,
            children: [
              const DItemMedia(child: DIcon(DIcons.link)),
              const DItemContent(
                children: [
                  DItemTitle(child: Text('GitHub')),
                  DItemDescription(
                    child: Text(
                      'Sync attribution of your commits and comments',
                    ),
                  ),
                ],
              ),
              DItemActions(
                children: [
                  DButton(
                    label: const Text('Connect'),
                    variant: DButtonVariant.ghost,
                    onPressed: () =>
                        setState(() => _result = 'Account connected'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: DSpacing.lg),
      DSwitchTile(
        title: const Text('Convert text emoticons into emojis'),
        value: _emoticons,
        onChanged: (value) => setState(() => _emoticons = value),
      ),
      const DSwitchTile(
        title: Text('Unavailable preference'),
        value: false,
        onChanged: null,
      ),
      const SizedBox(height: DSpacing.sm),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          const DToggle(variant: DToggleVariant.outline, child: Text('Toggle')),
          DDropdownMenu(
            content: DDropdownMenuContent(
              children: [
                DDropdownMenuItem(
                  onPressed: () => setState(() => _result = 'Copied link'),
                  child: const Text('Copy link'),
                ),
                const DDropdownMenuItem(
                  onPressed: null,
                  child: Text('Unavailable action'),
                ),
              ],
            ),
            child: DDropdownMenuTrigger.button(
              label: const Text('More actions'),
            ),
          ),
        ],
      ),
      const SizedBox(height: DSpacing.sm),
      Text(_result),
    ],
  );
}
