import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';
import 'button_reference_icons.dart';

final buttonExamples = ComponentExamples(
  description: 'Actions and links, with variants for emphasis and intent.',
  status: ComponentStatus.implemented,
  notes:
      'The base-nova surfaces use 24, 28, 32 and 36px sizes. Touch targets '
      'expand invisibly to 48px. The app supplies colors, font and radius. '
      'Loading and asynchronous ownership remain controlled by the caller. '
      'Navigation uses isLink and an application-owned callback. Pointer cursors '
      'retain the app convention. Rich labels may explicitly wrap. Button Group '
      'and Dropdown Menu remain separate catalogue owners; the joined example '
      'shows Button composition without claiming those components are complete. '
      'Reference and native visual verification are recorded in the library documentation.',
  examples: [
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
      description:
          'Four text sizes and their corresponding square icon buttons.',
      states: const ['Extra small', 'Small', 'Default', 'Large', 'Icon'],
      code:
          "DButton.iconOnly(icon: const Icon(Icons.north_east), tooltip: 'Submit', size: DButtonSize.extraSmall, variant: DButtonVariant.outline, onPressed: submit)",
      builder: (_) => const _ButtonSizes(),
    ),
    StyleguideExample(
      title: 'With icon and rounded',
      description:
          'Icons follow the reading direction. Rounded surfaces use an explicit radius.',
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
      title: 'Links, shortcuts and joined actions',
      description:
          'Login opens a local sample route. Hover Reply for its shortcut hint.',
      states: const ['As link', 'Tooltip', 'Shortcut', 'Joined composition'],
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
      title: 'Application variants',
      description:
          'Compatibility variants retain existing app-specific emphasis.',
      states: const ['Success', 'Danger', 'Flat', 'Transparent'],
      code:
          "DButton(label: const Text('Approve'), variant: DButtonVariant.success, onPressed: approve)",
      builder: (_) => const _ButtonVariants(compatibility: true),
    ),
  ],
);

class _ButtonVariants extends StatefulWidget {
  const _ButtonVariants({this.compatibility = false});
  final bool compatibility;
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
          for (final variant
              in widget.compatibility
                  ? [
                      DButtonVariant.standard,
                      DButtonVariant.danger,
                      DButtonVariant.success,
                      DButtonVariant.flat,
                      DButtonVariant.flatClose,
                      DButtonVariant.transparent,
                      DButtonVariant.transparentPrimary,
                      DButtonVariant.transparentDanger,
                      DButtonVariant.transparentSuccess,
                    ]
                  : [
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
                  DButtonSize.extraSmall => 'Extra Small',
                  DButtonSize.small => 'Small',
                  DButtonSize.regular => 'Default',
                  DButtonSize.large => 'Large',
                }),
                size: size,
                variant: DButtonVariant.outline,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Button activated'),
                    duration: Duration(seconds: 1),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            DButton.iconOnly(
              icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUpRight),
              tooltip: 'Submit ${size.name}',
              size: size,
              variant: DButtonVariant.outline,
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Button activated'),
                  duration: Duration(seconds: 1),
                ),
              ),
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
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
      ),
      DButton(
        label: const Text('New Branch'),
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.gitBranch),
        variant: DButtonVariant.outline,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
      ),
      DButton(
        label: const Text('Fork'),
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.gitFork),
        iconPosition: DButtonIconPosition.end,
        variant: DButtonVariant.outline,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
      ),
      DButton(
        label: const Text('Get Started'),
        borderRadius: BorderRadius.circular(999),
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
      ),
      DButton.iconOnly(
        icon: const ButtonReferenceIcon(ButtonReferenceIcon.arrowUp),
        tooltip: 'Submit',
        borderRadius: BorderRadius.circular(999),
        variant: DButtonVariant.outline,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
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
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
      ),
      Wrap(
        children: [
          DButton(
            label: const Text('Archive'),
            variant: DButtonVariant.outline,
            borderRadius: const BorderRadiusDirectional.horizontal(
              start: Radius.circular(4),
            ),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Button activated'),
                duration: Duration(seconds: 1),
              ),
            ),
          ),
          DButton(
            label: const Text('Report'),
            variant: DButtonVariant.outline,
            borderRadius: const BorderRadiusDirectional.horizontal(
              end: Radius.circular(4),
            ),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Button activated'),
                duration: Duration(seconds: 1),
              ),
            ),
          ),
        ],
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
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Button activated'),
              duration: Duration(seconds: 1),
            ),
          ),
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
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
      ),
      DButton(
        label: const Text('إرسال'),
        icon: const Icon(Icons.arrow_forward, textDirection: TextDirection.rtl),
        iconPosition: DButtonIconPosition.end,
        variant: DButtonVariant.outline,
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Button activated'),
            duration: Duration(seconds: 1),
          ),
        ),
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

  void _feedback(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم التفعيل'),
          duration: Duration(seconds: 1),
        ),
      );
}
