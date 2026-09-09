import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final popoverExamples = ComponentExamples(
  description: 'Displays rich content in a portal, triggered by a button.',
  status: ComponentStatus.implemented,
  notes:
      'Installation: import package:discourse_native/discourse_ui.dart. '
      'Composition: DPopover > DPopoverTrigger + DPopoverContent; content may '
      'contain DPopoverHeader, DPopoverTitle, DPopoverDescription and '
      'DPopoverClose. The default 288px surface uses 10px padding/gaps, a '
      '4px side offset and host-relative lg radius. Positioning follows the '
      'trigger unless DPopoverAnchor marks another descendant. Input and Field '
      'are separate in-progress catalogue owners, so the form example uses '
      'native TextFormField plus DLabel without defining substitute owners. '
      'Menus, Select, Combobox, Hover Card, dialogs and Tooltip retain their '
      'specialized interaction owners.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'Open the compact reference surface. Tab enters the close action; '
          'Escape, outside press and Close restore focus to the trigger.',
      states: const ['Open', 'Close', 'Keyboard', 'Focus restoration'],
      code: '''DPopover(
  content: const DPopoverContent(
    semanticLabel: 'Dimensions',
    align: DPopoverAlign.start,
    child: DPopoverHeader(children: [
      DPopoverTitle(child: Text('Dimensions')),
      DPopoverDescription(child: Text('Set the dimensions for the layer.')),
    ]),
  ),
  child: DPopoverTrigger(builder: (context, trigger) => DButton(
    label: const Text('Open Popover'),
    variant: DButtonVariant.outline,
    hasPopup: true,
    expanded: trigger.open,
    focusNode: trigger.focusNode,
    onPressed: trigger.toggle,
  )),
)''',
      builder: (_) => const _BasicPopover(),
    ),
    StyleguideExample(
      title: 'Align',
      description:
          'Start, center and end align against the same bottom side. Logical '
          'start/end mirror automatically when the preview direction changes.',
      states: const ['Start', 'Center', 'End', 'RTL'],
      code:
          '''DPopoverContent(width: 160, align: DPopoverAlign.start, child: Text('Aligned to start'))''',
      builder: (_) => const Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _AlignmentPopover(label: 'Start', align: DPopoverAlign.start),
          _AlignmentPopover(label: 'Center', align: DPopoverAlign.center),
          _AlignmentPopover(label: 'End', align: DPopoverAlign.end),
        ],
      ),
    ),
    StyleguideExample(
      title: 'With Form',
      description:
          'Two actual editable fields keep field-sized semantics and independent '
          'buttons. Submit validates and saves locally; Reset uses Flutter Form.',
      states: const ['Form', 'Validation', 'Save', 'Reset', 'Large text'],
      code: '''DPopover(
  content: DPopoverContent(width: 256, align: DPopoverAlign.start,
    child: Form(child: Column(children: [
      DPopoverHeader(children: [DPopoverTitle(child: Text('Dimensions'))]),
      TextFormField(decoration: InputDecoration(labelText: 'Width')),
    ])),
  child: DPopoverTrigger(builder: buildButton),
)''',
      builder: (_) => const _FormPopover(),
    ),
    StyleguideExample(
      title: 'Controlled and close',
      description:
          'The parent owns open state and records every requested reason. The '
          'composed close action does not rely on inherited business state.',
      states: const ['Controlled', 'Reason', 'Close composition'],
      code: '''DPopover(
  open: open,
  onOpenChange: (value, reason) => setState(() { open = value; }),
  content: DPopoverContent(child: DPopoverClose(
    builder: (context, close) => DButton(label: const Text('Close'), onPressed: close),
  )),
  child: DPopoverTrigger(builder: buildButton),
)''',
      builder: (_) => const _ControlledPopover(),
    ),
    StyleguideExample(
      title: 'Sides and RTL',
      description:
          'Physical top/bottom/left/right remain physical. Inline start/end '
          'resolve from Arabic direction and offsets follow the alignment axis.',
      states: const [
        'All sides',
        'Inline start',
        'Inline end',
        'Arabic',
        'RTL',
      ],
      code:
          '''Directionality(textDirection: TextDirection.rtl, child: DPopoverContent(side: DPopoverSide.inlineStart, child: Text('بداية السطر')))''',
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SidePopover(label: 'أعلى', side: DPopoverSide.top),
            _SidePopover(label: 'أسفل', side: DPopoverSide.bottom),
            _SidePopover(label: 'يسار', side: DPopoverSide.left),
            _SidePopover(label: 'يمين', side: DPopoverSide.right),
            _SidePopover(label: 'بداية السطر', side: DPopoverSide.inlineStart),
            _SidePopover(label: 'نهاية السطر', side: DPopoverSide.inlineEnd),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Anchor, collision and movement',
      description:
          'Move the marked anchor while the surface is open. The overlay tracks '
          'layout changes and flips/shifts inside the preview boundary.',
      states: const [
        'Custom anchor',
        'Movement',
        'Collision flip',
        'Narrow',
        'Reduced motion',
      ],
      code: '''DPopover(
  content: const DPopoverContent(side: DPopoverSide.right, child: Text('Tracks the anchor')),
  child: Stack(children: [
    DPopoverAnchor(child: target),
    DPopoverTrigger(builder: buildButton),
  ]),
)''',
      builder: (_) => const _MovingAnchorPopover(),
    ),
  ],
);

class _BasicPopover extends StatelessWidget {
  const _BasicPopover();

  @override
  Widget build(BuildContext context) => const DPopover(
    content: DPopoverContent(
      semanticLabel: 'Dimensions',
      align: DPopoverAlign.start,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          DPopoverHeader(
            children: [
              DPopoverTitle(child: Text('Dimensions')),
              DPopoverDescription(
                child: Text('Set the dimensions for the layer.'),
              ),
            ],
          ),
          DPopoverClose(builder: _closeButton),
        ],
      ),
    ),
    child: DPopoverTrigger(builder: _triggerButton),
  );
}

Widget _triggerButton(BuildContext context, DPopoverTriggerState trigger) =>
    DButton(
      label: const Text('Open Popover'),
      variant: DButtonVariant.outline,
      hasPopup: true,
      expanded: trigger.open,
      focusNode: trigger.focusNode,
      onPressed: trigger.toggle,
    );

Widget _closeButton(BuildContext context, VoidCallback close) => DButton(
  label: const Text('Close'),
  variant: DButtonVariant.outline,
  size: DButtonSize.small,
  onPressed: close,
);

class _AlignmentPopover extends StatelessWidget {
  const _AlignmentPopover({required this.label, required this.align});

  final String label;
  final DPopoverAlign align;

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 160,
      align: align,
      child: Text('Aligned to ${label.toLowerCase()}'),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: Text(label),
        variant: DButtonVariant.outline,
        size: DButtonSize.small,
        hasPopup: true,
        expanded: trigger.open,
        focusNode: trigger.focusNode,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _SidePopover extends StatelessWidget {
  const _SidePopover({required this.label, required this.side});

  final String label;
  final DPopoverSide side;

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 176,
      side: side,
      child: const DPopoverHeader(
        children: [
          DPopoverTitle(child: Text('الأبعاد')),
          DPopoverDescription(child: Text('تعيين الأبعاد للطبقة.')),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton(
        label: Text(label),
        variant: DButtonVariant.outline,
        hasPopup: true,
        expanded: trigger.open,
        focusNode: trigger.focusNode,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _FormPopover extends StatefulWidget {
  const _FormPopover();

  @override
  State<_FormPopover> createState() => _FormPopoverState();
}

class _FormPopoverState extends State<_FormPopover> {
  final _form = GlobalKey<FormState>();
  String _saved = 'Not saved';

  @override
  Widget build(BuildContext context) => DPopover(
    content: DPopoverContent(
      width: 256,
      align: DPopoverAlign.start,
      semanticLabel: 'Dimensions form',
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const DPopoverHeader(
              children: [
                DPopoverTitle(child: Text('Dimensions')),
                DPopoverDescription(
                  child: Text('Set the dimensions for the layer.'),
                ),
              ],
            ),
            TextFormField(
              initialValue: '100%',
              decoration: const InputDecoration(labelText: 'Width'),
              validator: (value) =>
                  value?.trim().isEmpty == true ? 'Enter a width' : null,
              onSaved: (value) => _saved = 'Saved width: $value',
            ),
            TextFormField(
              initialValue: '25px',
              decoration: const InputDecoration(labelText: 'Height'),
            ),
            Text(_saved),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DButton(
                  label: const Text('Save'),
                  size: DButtonSize.small,
                  onPressed: () {
                    if (_form.currentState!.validate()) {
                      _form.currentState!.save();
                      setState(() {});
                    }
                  },
                ),
                DButton(
                  label: const Text('Reset'),
                  variant: DButtonVariant.outline,
                  size: DButtonSize.small,
                  onPressed: () {
                    _form.currentState!.reset();
                    setState(() => _saved = 'Not saved');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    child: const DPopoverTrigger(builder: _triggerButton),
  );
}

class _ControlledPopover extends StatefulWidget {
  const _ControlledPopover();

  @override
  State<_ControlledPopover> createState() => _ControlledPopoverState();
}

class _ControlledPopoverState extends State<_ControlledPopover> {
  bool _open = false;
  String _reason = 'none';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      DPopover(
        open: _open,
        onOpenChange: (open, reason) => setState(() {
          _open = open;
          _reason = reason.name;
        }),
        content: const DPopoverContent(
          semanticLabel: 'Controlled popover',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Text('Parent-controlled content'),
              DPopoverClose(builder: _closeButton),
            ],
          ),
        ),
        child: const DPopoverTrigger(builder: _triggerButton),
      ),
      Text('Open: $_open · Reason: $_reason'),
    ],
  );
}

class _MovingAnchorPopover extends StatefulWidget {
  const _MovingAnchorPopover();

  @override
  State<_MovingAnchorPopover> createState() => _MovingAnchorPopoverState();
}

class _MovingAnchorPopoverState extends State<_MovingAnchorPopover> {
  bool _end = false;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: DPopover(
      content: DPopoverContent(
        width: 190,
        side: DPopoverSide.right,
        align: DPopoverAlign.start,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const Text('Tracks the marked anchor and flips near an edge.'),
            DButton(
              label: const Text('Move anchor'),
              variant: DButtonVariant.outline,
              onPressed: () => setState(() => _end = !_end),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            alignment: _end ? Alignment.topRight : Alignment.topLeft,
            child: const DPopoverAnchor(
              child: SizedBox.square(
                dimension: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.transparent),
                  child: Icon(Icons.adjust, size: 18),
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomLeft,
            child: DPopoverTrigger(builder: _triggerButton),
          ),
        ],
      ),
    ),
  );
}
