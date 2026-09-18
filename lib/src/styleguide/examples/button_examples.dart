import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icons.dart';
import '../styleguide_example.dart';
import 'button_reference_icons.dart';
import 'control_comparison_example.dart';
import 'linear_controls_example.dart';

final buttonExamples = ComponentExamples(
  topLevelExampleIndex: 10,
  description: 'Actions and links, with variants for emphasis and intent.',
  status: ComponentStatus.implemented,
  notes:
      'Linear-style actions use the theme corner radius, 0.5px borders, subtle shadows and solid primary fills. '
      'Actions and popup triggers share that radius; menus use 12px corners and 32px rows. '
      'Small controls are 24px with 12px labels; regular and large controls retain '
      '28px and 32px surfaces with 13px labels. Touch targets remain 48px. '
      'Hover, pressed and open fills update immediately; keyboard focus uses a 1px '
      'ring with a 2px gap. Actions stay in place on press. Disabled buttons use '
      '60% opacity; disabled selectors and switches use 50%. '
      'Transparent background actions reveal a subtle hover fill; inline text actions '
      'stay clear. Rich labels may wrap. All colors follow the current forum palette. '
      'Loading, navigation and asynchronous operations remain caller-owned. '
      'See docs/component-library/linear-controls.md for the measured reference and verification.',
  examples: [
    StyleguideExample(
      title: 'Pill toolbar action',
      description:
          'Round actions share the normal button focus, hover and target size.',
      code:
          "DButton.iconOnly(shape: DButtonShape.pill, size: DButtonSize.large, variant: DButtonVariant.secondary, icon: DIcon(DIcons.filter), tooltip: 'Filter topics', onPressed: openFilters)",
      builder: (_) => DButton.iconOnly(
        shape: DButtonShape.pill,
        size: DButtonSize.large,
        variant: DButtonVariant.secondary,
        icon: const DIcon(DIcons.filter),
        tooltip: 'Filter topics',
        onPressed: () {},
      ),
    ),
    StyleguideExample(
      title: 'Variants',
      description: 'Activate a button, or use Tab and Enter to compare focus.',
      states: const [
        'Default',
        'Outline',
        'Secondary',
        'Ghost',
        'Destructive',
        'Link',
      ],
      code:
          "DButton(label: const Text('Outline'), variant: DButtonVariant.outline, onPressed: save)",
      builder: (_) => const _ButtonVariants(),
    ),
    StyleguideExample(
      title: 'Size',
      description: 'Three sizes and their corresponding square icon buttons.',
      states: const ['Small 24px', 'Default 28px', 'Large 32px', 'Icon'],
      code:
          "DButton.iconOnly(icon: const Icon(Icons.north_east), tooltip: 'Submit', size: DButtonSize.small, variant: DButtonVariant.outline, onPressed: submit)",
      builder: (_) => const _ButtonSizes(),
    ),
    StyleguideExample(
      title: 'With icon and rounded',
      description:
          'Icons follow the reading direction. Pill shape scales its radius with the control size.',
      states: const ['Leading icon', 'Trailing icon', 'Rounded', 'RTL'],
      code:
          "DButton(label: const Text('Fork'), icon: const Icon(Icons.fork_right), iconPosition: DButtonIconPosition.end, variant: DButtonVariant.outline, onPressed: fork)",
      builder: (_) => const _ButtonComposition(),
    ),
    StyleguideExample(
      title: 'Spinner and disabled',
      description:
          'Generate starts a local operation. Repeated activation is blocked while busy.',
      states: const ['Spinner', 'Loading label', 'Disabled', 'Async ownership'],
      code:
          "DButton(label: const Text('Generate'), loading: busy, loadingLabel: const Text('Generating'), variant: DButtonVariant.outline, onPressed: generate)",
      builder: (_) => const _ButtonLoading(),
    ),
    StyleguideExample(
      title: 'Button Group',
      description:
          'The documented nested groups with a Dropdown Menu trigger. Go Back '
          'appears from 640px; Label As… keeps a local radio selection.',
      states: const [
        'Nested groups',
        'Icon trigger',
        'Dropdown Menu',
        'Submenu radio',
        'Destructive item',
      ],
      code: '''DButtonGroup(children: [
  DButtonGroup(children: [
    DButton(variant: DButtonVariant.outline, label: Text('Archive'), onPressed: archive),
    DButton(variant: DButtonVariant.outline, label: Text('Report'), onPressed: report),
  ]),
  DButtonGroup(children: [
    DButton(variant: DButtonVariant.outline, label: Text('Snooze'), onPressed: snooze),
    DDropdownMenu(
      content: DDropdownMenuContent(align: DPopoverAlign.end, children: items),
      child: DDropdownMenuTrigger(builder: (_, state) => DButton.iconOnly(
        variant: DButtonVariant.outline, hasPopup: true, expanded: state.open,
        focusNode: state.focusNode, tooltip: 'More Options',
        icon: Icon(Icons.more_horiz), onPressed: state.toggle)),
    ),
  ]),
])''',
      builder: (_) => const _ButtonGroupComposition(),
    ),
    StyleguideExample(
      title: 'As link and shortcuts',
      description:
          'Login opens a local sample route with link semantics. Hover Reply for its shortcut hint.',
      states: const ['As link', 'Tooltip', 'Shortcut'],
      code:
          "DButton(label: const Text('Login'), isLink: true, size: DButtonSize.small, variant: DButtonVariant.secondary, onPressed: openLogin)",
      builder: (_) => const _ButtonLinks(),
    ),
    StyleguideExample(
      title: 'Rich labels and trigger states',
      description:
          'Test narrow widths and 200% text. Toggle a popup trigger’s expanded state.',
      states: const [
        'Rich content',
        'Large text',
        'Invalid',
        'Expanded',
        'RTL',
      ],
      code:
          "DButton(label: const Text('Wrap long labels', softWrap: true, maxLines: 3), variant: DButtonVariant.outline, onPressed: save)",
      builder: (_) => const _ButtonEdges(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'The documented Arabic composition mirrors icons and spacing.',
      states: const ['Arabic', 'RTL', 'Disabled spinner'],
      code:
          "Directionality(textDirection: TextDirection.rtl, child: DButton(label: const Text('إرسال'), iconPosition: DButtonIconPosition.end, icon: const Icon(Icons.arrow_back), variant: DButtonVariant.outline, onPressed: submit))",
      builder: (_) => const _ButtonRtl(),
    ),
    StyleguideExample(
      title: 'Control consistency',
      description:
          'Compare buttons, selects, menu triggers and joined actions together. '
          'Open each menu and check hover, focus and disabled states.',
      states: const [
        'Default',
        'Small',
        'Disabled',
        'Dropdown',
        'Select',
        'Joined',
      ],
      code: "DDropdownMenuTrigger.button(label: const Text('Open'))",
      builder: (_) => const ControlComparisonExample(),
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The basic demo pairs an outline text button with its square icon action.',
      states: const ['Outline', 'Icon', 'Keyboard', 'Touch'],
      code: '''Wrap(
  spacing: DSpacing.sm,
  children: [
    DButton(
      label: const Text('Button'),
      variant: DButtonVariant.outline,
      onPressed: activate,
    ),
    DButton.iconOnly(
      icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUp),
      tooltip: 'Submit',
      variant: DButtonVariant.outline,
      onPressed: submit,
    ),

  ],
)''',
      builder: (_) => const _ButtonDemo(),
    ),
    StyleguideExample(
      title: 'Custom colors',
      description:
          'Category-tinted split controls with independent picker and browse '
          'actions. Change a category to update its colors, or use Tab to inspect focus.',
      states: const [
        'Custom fill',
        'Custom border',
        'Hover',
        'Focus',
        'Expanded',
        'Disabled',
        'Button Group',
      ],
      code: r'''final fill = categoryColor.withValues(alpha: .10);
final border = categoryColor.withValues(alpha: .25);
final hover = Color.alphaBlend(categoryColor.withValues(alpha: .08), fill);

DButtonGroup(children: [
  DButton(
    label: Text(categoryName),
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
    backgroundColor: fill,
    borderColor: border,
    interactiveBackgroundColor: hover,
    hasPopup: true,
    expanded: pickerOpen,
    onPressed: togglePicker,
  ),
  DButton.iconOnly(
    icon: Icon(Icons.open_in_new),
    tooltip: 'Browse $categoryName',
    isLink: true,
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
    backgroundColor: fill,
    borderColor: border,
    interactiveBackgroundColor: hover,
    onPressed: browseCategory,
  ),
])''',
      builder: (_) => const _ButtonCustomColors(),
    ),
    StyleguideExample(
      title: 'Transparent background',
      description:
          'Light themes give enabled icons and labels more weight than metadata. '
          'Subdued actions return to the normal foreground on hover, '
          'focus or expansion. Hover and expansion add a subtle neutral fill. '
          'Use Tab to compare the keyboard focus ring.',
      states: const [
        'Text',
        'Inline',
        'Icon',
        'Hover',
        'Focus',
        'Expanded',
        'Disabled',
      ],
      code: '''DButton.iconOnly(
  icon: const DIcon(DIcons.link),
  tooltip: 'Copy link',
  variant: DButtonVariant.transparentBackground,
  onPressed: copyLink,
)
DButton(
  label: const Text('Replies'),
  size: DButtonSize.small,
  variant: DButtonVariant.inline,
  onPressed: sortReplies,
)''',
      builder: (_) => const _ButtonTransparentBackground(),
    ),
    StyleguideExample(
      title: 'Linear settings controls',
      description:
          'The integration, account and preference compositions. Compare hover, '
          'press, Tab focus, disabled selectors, rich content and open menus.',
      states: const [
        'Primary',
        'Small',
        'Disabled',
        'Rich content',
        'Icon',
        'Transparent',
        'Switch',
        'Item',
      ],
      code:
          "DButton(label: Text('Enable'), size: DButtonSize.large, onPressed: enable)",
      builder: (_) => const LinearControlsExample(),
    ),
  ],
);

class _ButtonTransparentBackground extends StatefulWidget {
  const _ButtonTransparentBackground();

  @override
  State<_ButtonTransparentBackground> createState() =>
      _ButtonTransparentBackgroundState();
}

class _ButtonTransparentBackgroundState
    extends State<_ButtonTransparentBackground> {
  String _result = 'No action yet';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: DSpacing.xs,
        runSpacing: DSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DButton(
            label: const Text('Reply'),
            icon: const DIcon(DIcons.reply),
            variant: DButtonVariant.transparentBackground,
            onPressed: () => setState(() => _result = 'Reply activated'),
          ),
          DButton.iconOnly(
            icon: const DIcon(DIcons.link),
            tooltip: 'Copy link',
            variant: DButtonVariant.transparentBackground,
            onPressed: () => setState(() => _result = 'Link copied'),
          ),
          DDropdownMenu(
            content: DDropdownMenuContent(
              children: [
                DDropdownMenuItem(
                  child: const Text('Insert image'),
                  onPressed: () => setState(() => _result = 'Image inserted'),
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (_, trigger) => DButton.iconOnly(
                icon: const DIcon(DIcons.circlePlus),
                tooltip: 'Insert',
                variant: DButtonVariant.transparentBackground,
                hasPopup: true,
                expanded: trigger.open,
                focusNode: trigger.focusNode,
                onPressed: trigger.toggle,
              ),
            ),
          ),
          const DButton.iconOnly(
            icon: DIcon(DIcons.trashCan),
            tooltip: 'Discard draft',
            variant: DButtonVariant.transparentBackground,
            onPressed: null,
          ),
        ],
      ),
      const SizedBox(height: DSpacing.lg),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Topic content'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DButton(
                label: const Text('Replies'),
                size: DButtonSize.small,
                variant: DButtonVariant.inline,
                onPressed: () => setState(() => _result = 'Replies sorted'),
              ),
              const SizedBox(width: DSpacing.xs),
              const Text('226'),
            ],
          ),
        ],
      ),
      Text(_result),
    ],
  );
}

class _ButtonCustomColors extends StatefulWidget {
  const _ButtonCustomColors();

  @override
  State<_ButtonCustomColors> createState() => _ButtonCustomColorsState();
}

class _ButtonCustomColorsState extends State<_ButtonCustomColors> {
  static const _colors = {
    'sales': Color(0xffed1681),
    'deals': Color(0xff0088cc),
    'support': Color(0xff629b32),
  };
  final _categories = ['sales', 'deals'];
  String _result = 'Choose or browse a category';

  Widget _picker(int index) {
    final name = _categories[index];
    final color = _colors[name]!;
    final fill = color.withValues(alpha: .10);
    final border = color.withValues(alpha: .25);
    final hover = Color.alphaBlend(color.withValues(alpha: .08), fill);
    return DButtonGroup(
      semanticLabel: 'Category ${index + 1}',
      children: [
        DCombobox<String>.controlled(
          value: name,
          options: [
            for (final category in _colors.keys)
              DComboboxOption(value: category, label: category),
          ],
          onChanged: (value, _) {
            if (value == null) return;
            setState(() {
              _categories[index] = value;
              _result = 'Category ${index + 1}: $value';
            });
          },
          anchor: DComboboxTrigger<String>(
            builder: (_, trigger) => DButton(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name),
                  const SizedBox(width: DSpacing.xs),
                  const Icon(Icons.keyboard_arrow_down, size: 12),
                ],
              ),
              icon: Icon(Icons.square_rounded, size: 12, color: color),
              semanticLabel: 'Edit $name',
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              backgroundColor: fill,
              borderColor: border,
              interactiveBackgroundColor: hover,
              hasPopup: true,
              expanded: trigger.open,
              focusNode: trigger.focusNode,
              onPressed: trigger.toggle,
            ),
          ),
          content: const DComboboxContent(
            width: 240,
            maxHeight: 240,
            children: [
              Padding(
                padding: EdgeInsets.all(DSpacing.xs),
                child: DComboboxInput<String>(
                  placeholder: 'Search categories…',
                  semanticLabel: 'Search categories',
                  registerAsAnchor: false,
                  showTrigger: false,
                ),
              ),
              DComboboxEmpty<String>(child: Text('No matching categories.')),
              DComboboxList<String>(),
            ],
          ),
        ),
        DButton.iconOnly(
          icon: const Icon(Icons.open_in_new),
          tooltip: 'Browse $name',
          isLink: true,
          variant: DButtonVariant.outline,
          size: DButtonSize.small,
          backgroundColor: fill,
          borderColor: border,
          interactiveBackgroundColor: hover,
          onPressed: () => setState(() => _result = 'Browse $name'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          for (var index = 0; index < _categories.length; index++)
            _picker(index),
          DButton(
            label: const Text('Disabled'),
            variant: DButtonVariant.outline,
            size: DButtonSize.small,
            backgroundColor: _colors['sales']!.withValues(alpha: .10),
            borderColor: _colors['sales']!.withValues(alpha: .25),
            onPressed: null,
          ),
        ],
      ),
      const SizedBox(height: DSpacing.lg),
      Text(_result),
    ],
  );
}

class _ButtonDemo extends StatelessWidget {
  const _ButtonDemo();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: DSpacing.sm,
    runSpacing: DSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DButton(
        label: const Text('Button'),
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
      DButton.iconOnly(
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUp),
        tooltip: 'Submit',
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
    ],
  );
}

class _ButtonVariants extends StatefulWidget {
  const _ButtonVariants();
  @override
  State<_ButtonVariants> createState() => _ButtonVariantsState();
}

class _ButtonVariantsState extends State<_ButtonVariants> {
  String result = 'No action yet';
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final variant in [
            DButtonVariant.primary,
            DButtonVariant.outline,
            DButtonVariant.secondary,
            DButtonVariant.ghost,
            DButtonVariant.destructive,
            DButtonVariant.link,
          ])
            DButton(
              label: Text(
                variant == DButtonVariant.primary ? 'Button' : variant.name,
              ),
              variant: variant,
              onPressed: () =>
                  setState(() => result = '${variant.name} activated'),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text(result),
    ],
  );
}

class _ButtonSizes extends StatelessWidget {
  const _ButtonSizes();
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final size in DButtonSize.values)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DButton(
                label: Text(switch (size) {
                  DButtonSize.small => 'Small',
                  DButtonSize.regular => 'Default',
                  DButtonSize.large => 'Large',
                }),
                size: size,
                variant: DButtonVariant.outline,
                onPressed: () => _buttonFeedback(context),
              ),
            ),
            const SizedBox(width: 8),
            DButton.iconOnly(
              icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUpRight),
              tooltip: 'Submit ${size.name}',
              size: size,
              variant: DButtonVariant.outline,
              onPressed: () => _buttonFeedback(context),
            ),
          ],
        ),
    ];
    return MediaQuery.sizeOf(context).width < 640
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 32,
            children: children,
          )
        : Wrap(
            spacing: 32,
            runSpacing: 32,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: children,
          );
  }
}

class _ButtonComposition extends StatelessWidget {
  const _ButtonComposition();
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      DButton.iconOnly(
        icon: const ButtonReferenceIcon(
          ButtonReferenceIcon.circleFadingArrowUp,
        ),
        tooltip: 'Upload',
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
      DButton(
        label: const Text('New Branch'),
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.gitBranch),
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
      DButton(
        label: const Text('Fork'),
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.gitFork),
        iconPosition: DButtonIconPosition.end,
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
      DButton(
        label: const Text('Get Started'),
        borderRadius: BorderRadius.circular(999),
        onPressed: () => _buttonFeedback(context),
      ),
      DButton.iconOnly(
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUp),
        tooltip: 'Submit',
        borderRadius: BorderRadius.circular(999),
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
    ],
  );
}

class _ButtonLoading extends StatefulWidget {
  const _ButtonLoading();
  @override
  State<_ButtonLoading> createState() => _ButtonLoadingState();
}

class _ButtonLoadingState extends State<_ButtonLoading> {
  bool busy = false;
  int completed = 0;
  Future<void> generate() async {
    if (busy) return;
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      busy = false;
      completed++;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: const Text('Generate'),
            loading: busy,
            loadingLabel: const Text('Generating'),
            variant: DButtonVariant.outline,
            onPressed: generate,
          ),
          const DButton(
            label: Text('Downloading'),
            icon: DSpinner(semanticLabel: null),
            iconPosition: DButtonIconPosition.end,
            variant: DButtonVariant.secondary,
            onPressed: null,
          ),
          const DButton(label: Text('Unavailable'), onPressed: null),
        ],
      ),
      const SizedBox(height: 16),
      Text('$completed operations completed'),
    ],
  );
}

/// The documented Button Group section: nested groups whose last control is
/// a Dropdown Menu trigger with groups, a radio submenu and a destructive item.
class _ButtonGroupComposition extends StatefulWidget {
  const _ButtonGroupComposition();
  @override
  State<_ButtonGroupComposition> createState() =>
      _ButtonGroupCompositionState();
}

class _ButtonGroupCompositionState extends State<_ButtonGroupComposition> {
  String label = 'personal';
  String result = 'No action yet';

  void _activate(String action) => setState(() => result = '$action activated');

  DDropdownMenuItem _item(
    String title,
    String svg, {
    DDropdownMenuItemVariant variant = DDropdownMenuItemVariant.standard,
  }) => DDropdownMenuItem(
    leading: ButtonReferenceIcon(svg),
    variant: variant,
    onPressed: () => _activate(title),
    child: Text(title),
  );

  DButton _action(String title) => DButton(
    variant: DButtonVariant.outline,
    label: Text(title),
    onPressed: () => _activate(title),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DButtonGroup(
          children: [
            // The reference hides Go Back below its 640px `sm` breakpoint.
            if (MediaQuery.sizeOf(context).width >= 640)
              DButtonGroup(
                children: [
                  DButton.iconOnly(
                    variant: DButtonVariant.outline,
                    icon: const ButtonReferenceIcon(
                      ButtonReferenceIcon.arrowLeft,
                    ),
                    tooltip: 'Go Back',
                    onPressed: () => _activate('Go Back'),
                  ),
                ],
              ),
            DButtonGroup(children: [_action('Archive'), _action('Report')]),
            DButtonGroup(
              children: [
                _action('Snooze'),
                DDropdownMenu(
                  content: DDropdownMenuContent(
                    semanticLabel: 'More options',
                    align: DPopoverAlign.end,
                    children: [
                      DDropdownMenuGroup(
                        children: [
                          _item('Mark as Read', ButtonReferenceIcon.mailCheck),
                          _item('Archive', ButtonReferenceIcon.archive),
                        ],
                      ),
                      const DDropdownMenuSeparator(),
                      DDropdownMenuGroup(
                        children: [
                          _item('Snooze', ButtonReferenceIcon.clock),
                          _item(
                            'Add to Calendar',
                            ButtonReferenceIcon.calendarPlus,
                          ),
                          _item('Add to List', ButtonReferenceIcon.listFilter),
                          DDropdownMenuSub(
                            leading: const ButtonReferenceIcon(
                              ButtonReferenceIcon.tag,
                            ),
                            trigger: const Text('Label As...'),
                            children: [
                              DDropdownMenuRadioGroup<String>(
                                value: label,
                                onChanged: (value) =>
                                    setState(() => label = value),
                                children: const [
                                  DDropdownMenuRadioItem(
                                    value: 'personal',
                                    child: Text('Personal'),
                                  ),
                                  DDropdownMenuRadioItem(
                                    value: 'work',
                                    child: Text('Work'),
                                  ),
                                  DDropdownMenuRadioItem(
                                    value: 'other',
                                    child: Text('Other'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const DDropdownMenuSeparator(),
                      DDropdownMenuGroup(
                        children: [
                          _item(
                            'Trash',
                            ButtonReferenceIcon.trash2,
                            variant: DDropdownMenuItemVariant.destructive,
                          ),
                        ],
                      ),
                    ],
                  ),
                  child: DDropdownMenuTrigger(
                    builder: (context, state) => DButton.iconOnly(
                      variant: DButtonVariant.outline,
                      hasPopup: true,
                      expanded: state.open,
                      focusNode: state.focusNode,
                      tooltip: 'More Options',
                      icon: const ButtonReferenceIcon(
                        ButtonReferenceIcon.ellipsis,
                      ),
                      onPressed: state.toggle,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('$result · Label: $label'),
    ],
  );
}

class _ButtonLinks extends StatelessWidget {
  const _ButtonLinks();
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      DButton(
        label: const Text('Login'),
        isLink: true,
        size: DButtonSize.small,
        variant: DButtonVariant.secondary,
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: Center(
                child: DButton(
                  label: const Text('Back to examples'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ),
      ),
      DButton(
        label: const Text('Reply'),
        tooltip: 'Reply to this topic',
        shortcut: const DShortcut(
          SingleActivator(LogicalKeyboardKey.keyR, shift: true),
        ),
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
    ],
  );
}

class _ButtonEdges extends StatefulWidget {
  const _ButtonEdges();
  @override
  State<_ButtonEdges> createState() => _ButtonEdgesState();
}

class _ButtonEdgesState extends State<_ButtonEdges> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      SizedBox(
        width: 220,
        child: DButton(
          label: const Text.rich(
            TextSpan(
              text: 'Save ',
              children: [
                TextSpan(
                  text: 'all community preferences',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            softWrap: true,
            maxLines: 4,
          ),
          variant: DButtonVariant.outline,
          onPressed: () => _buttonFeedback(context),
        ),
      ),
      DButton(
        label: Text(expanded ? 'Close options' : 'Choose options'),
        expanded: expanded,
        hasPopup: true,
        variant: DButtonVariant.outline,
        onPressed: () => setState(() => expanded = !expanded),
      ),
      DButton(
        label: const Text('Required choice'),
        invalid: true,
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
      DButton(
        label: const Text('إرسال'),
        icon: const Icon(Icons.arrow_forward, textDirection: TextDirection.rtl),
        iconPosition: DButtonIconPosition.end,
        variant: DButtonVariant.outline,
        onPressed: () => _buttonFeedback(context),
      ),
    ],
  );
}

class _ButtonRtl extends StatelessWidget {
  const _ButtonRtl();

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        DButton(
          label: const Text('زر'),
          variant: DButtonVariant.outline,
          onPressed: () => _feedback(context),
        ),
        DButton(
          label: const Text('حذف'),
          variant: DButtonVariant.destructive,
          onPressed: () => _feedback(context),
        ),
        DButton(
          label: const Text('إرسال'),
          variant: DButtonVariant.outline,
          iconPosition: DButtonIconPosition.end,
          icon: Transform.flip(
            flipX: true,
            child: const ButtonReferenceIcon(ButtonReferenceIcon.arrowRight),
          ),
          onPressed: () => _feedback(context),
        ),
        DButton.iconOnly(
          icon: const ButtonReferenceIcon(ButtonReferenceIcon.plus),
          tooltip: 'إضافة',
          variant: DButtonVariant.outline,
          onPressed: () => _feedback(context),
        ),
        const DButton(
          label: Text('جاري التحميل'),
          icon: DSpinner(semanticLabel: null),
          variant: DButtonVariant.secondary,
          onPressed: null,
        ),
      ],
    ),
  );

  void _feedback(BuildContext context) => DToast.show(context, 'تم التفعيل');
}

void _buttonFeedback(BuildContext context) => DToast.show(
  context,
  'Button activated',
  duration: const Duration(seconds: 1),
);
