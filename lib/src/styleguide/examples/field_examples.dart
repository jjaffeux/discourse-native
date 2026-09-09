import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';
import 'field_example_sources.dart';

final fieldExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description:
      'Labels, controls, help and validation composed into accessible fields.',
  notes:
      'Field is composition, not a second Form owner. DFieldControl supplies '
      'the native accessible name, help and errors; DFieldLabel reuses the control '
      'focus node or callback without a second tab stop. FieldGroup reflows at 448px. '
      'Input, Checkbox, Radio and Button use their completed merged owners. '
      'Multiline editors, Switch, RangeSlider and native selection remain explicit '
      'temporary dependencies; no unmerged worktree is imported. '
      'The responsive custom-error example intentionally retains a native '
      'FormField/TextField: DInput owns its own error slot and does not expose an '
      'error builder. This keeps DFieldError custom validation demonstrated with '
      'exactly one FormField owner. All values stay local; reference/native review is blocked.',
  examples: [
    _example(
      'Payment method',
      'payment',
      'The frozen payment/billing form. Submit validates required local fields; '
          'Cancel resets. No payment information leaves the preview.',
      const ['Form', 'FieldSet', 'Legend', 'Separator', 'Save', 'Reset'],
      (_) => const FieldPaymentExample(),
    ),
    _example(
      'Input, textarea and select',
      'editors',
      'Username and password show both help positions; feedback and department '
          'demonstrate multiline and selection composition.',
      const ['Input', 'Textarea', 'Select', 'Description'],
      (_) => const FieldEditorsExample(),
    ),
    _example(
      'Price range',
      'slider',
      'A title and live description accompany a range slider. Both thumbs retain '
          'their native adjustable semantics.',
      const ['Slider', 'Title', 'Controlled'],
      (_) => const FieldSliderExample(),
    ),
    _example(
      'Address information',
      'address',
      'A legend and description group street, city and postal code. The address '
          'columns stack at narrow widths and large text.',
      const ['Fieldset', 'Responsive'],
      (_) => const FieldAddressExample(),
    ),
    _example(
      'Desktop items and sync',
      'checkbox',
      'Label clicks toggle the same checkbox as Space. A content column keeps '
          'the sync description aligned.',
      const ['Checkbox', 'Label legend', 'Content'],
      (_) => const FieldCheckboxExample(),
    ),
    _example(
      'Subscription and choice cards',
      'choice',
      'Arrow keys select within each radio group. Click the card text or its '
          'control; selection is owned locally. The disabled card cannot activate.',
      const ['Radio', 'Choice Card', 'Selected', 'Disabled', 'Focus'],
      (_) => const FieldChoiceExample(),
    ),
    _example(
      'Notifications and switch',
      'notifications',
      'Two sections, a text separator, independent help action and a switch '
          'demonstrate grouped preferences. The first checkbox is disabled.',
      const ['Field Group', 'Switch', 'Disabled', 'Rich help'],
      (_) => const FieldNotificationsExample(),
    ),
    _example(
      'Responsive validation',
      'responsive',
      'At 448px the field changes from stacked to horizontal. Edit, submit, '
          'resize and reset: the native Form owns value and validation throughout.',
      const ['Responsive', 'Validation', 'Errors', 'Form', 'Keyboard'],
      (_) => const FieldResponsiveExample(),
    ),
    _example(
      'RTL payment form',
      'rtl',
      'The same payment composition uses Arabic labels and RTL direction. '
          'Try 200% text and a narrow preview.',
      const ['RTL', 'Arabic', 'Large text'],
      (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: FieldPaymentExample(arabic: true),
      ),
    ),
  ],
);

StyleguideExample _example(
  String title,
  String source,
  String description,
  List<String> states,
  WidgetBuilder builder,
) => StyleguideExample(
  title: title,
  description: description,
  states: states,
  code: fieldExampleSources[source]!,
  builder: builder,
);

// Local composition adapters. Multiline and unmerged controls remain native.
class _Editor extends StatefulWidget {
  const _Editor(
    this.label, {
    this.description,
    this.placeholder,
    this.required = false,
    this.lines = 1,
    this.obscure = false,
    this.helpBefore = false,
  });
  final String label;
  final String? description;
  final String? placeholder;
  final bool required;
  final int lines;
  final bool obscure;
  final bool helpBefore;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DField(
    children: [
      DFieldLabel(
        focusNode: _focus,
        excludeSemantics: true,
        child: Text(widget.label),
      ),
      if (widget.helpBefore && widget.description != null)
        DFieldDescription(child: Text(widget.description!)),
      DFieldControl(
        label: widget.label,
        description: widget.description,
        required: widget.required,
        child: widget.lines == 1
            ? DInput(
                focusNode: _focus,
                hintText: widget.placeholder,
                obscureText: widget.obscure,
                isRequired: widget.required,
                validator: widget.required
                    ? (value) => value == null || value.trim().isEmpty
                          ? 'Required'
                          : null
                    : null,
              )
            : TextFormField(
                focusNode: _focus,
                maxLines: widget.lines,
                obscureText: widget.obscure,
                decoration: InputDecoration(
                  hintText: widget.placeholder,
                  errorMaxLines: 4,
                  border: const OutlineInputBorder(),
                ),
                validator: widget.required
                    ? (value) => value == null || value.trim().isEmpty
                          ? 'Required'
                          : null
                    : null,
              ),
      ),
      if (!widget.helpBefore && widget.description != null)
        DFieldDescription(child: Text(widget.description!)),
    ],
  );
}

class _Choice extends StatefulWidget {
  const _Choice(
    this.label, {
    this.description,
    this.initial = false,
    this.enabled = true,
    this.switchControl = false,
  });
  final String label;
  final String? description;
  final bool initial;
  final bool enabled;
  final bool switchControl;
  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  late bool _value = widget.initial;
  void _change(bool value) => setState(() => _value = value);
  @override
  Widget build(BuildContext context) {
    if (!widget.switchControl) {
      return DField(
        enabled: widget.enabled,
        children: [
          DFieldControl(
            label: widget.label,
            description: widget.description,
            child: DCheckbox(
              value: _value,
              enabled: widget.enabled,
              onChanged: widget.enabled
                  ? (value) => _change(value ?? false)
                  : null,
              title: DFieldLabel(
                excludeSemantics: true,
                style: const TextStyle(fontWeight: FontWeight.w400),
                child: Text(widget.label),
              ),
              subtitle: widget.description == null
                  ? null
                  : ExcludeSemantics(
                      child: DFieldDescription(
                        child: Text(widget.description!),
                      ),
                    ),
            ),
          ),
        ],
      );
    }
    return DField(
      enabled: widget.enabled,
      children: [
        DSwitchTile(
          value: _value,
          enabled: widget.enabled,
          onChanged: widget.enabled ? _change : null,
          title: DFieldLabel(
            style: const TextStyle(fontWeight: FontWeight.w400),
            child: Text(widget.label),
          ),
          subtitle: widget.description == null
              ? null
              : DFieldDescription(child: Text(widget.description!)),
        ),
      ],
    );
  }
}

class _Selection extends StatefulWidget {
  const _Selection(this.label, this.items, {this.description});
  final String label;
  final List<String> items;
  final String? description;
  @override
  State<_Selection> createState() => _SelectionState();
}

class _SelectionState extends State<_Selection> {
  final _focus = FocusNode();
  String? _value;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DField(
    children: [
      DFieldLabel(
        focusNode: _focus,
        excludeSemantics: true,
        child: Text(widget.label),
      ),
      DFieldControl(
        label: widget.label,
        description: widget.description,
        child: DropdownButtonFormField<String>(
          focusNode: _focus,
          initialValue: _value,
          isExpanded: true,
          hint: const Text('Choose'),
          items: [
            for (final item in widget.items)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: (value) => setState(() => _value = value),
        ),
      ),
      if (widget.description != null)
        DFieldDescription(child: Text(widget.description!)),
    ],
  );
}

class _Columns extends StatelessWidget {
  const _Columns({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal =
          constraints.maxWidth >= 360 &&
          MediaQuery.textScalerOf(context).scale(14) <= 21;
      return Flex(
        direction: horizontal ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              SizedBox(width: horizontal ? 16 : 0, height: horizontal ? 0 : 16),
            Flexible(flex: horizontal ? 1 : 0, child: children[i]),
          ],
        ],
      );
    },
  );
}

class FieldPaymentExample extends StatefulWidget {
  const FieldPaymentExample({super.key, this.arabic = false});
  final bool arabic;
  @override
  State<FieldPaymentExample> createState() => _FieldPaymentExampleState();
}

class _FieldPaymentExampleState extends State<FieldPaymentExample> {
  final _form = GlobalKey<FormState>();
  int _reset = 0;
  String? _saved;
  @override
  Widget build(BuildContext context) {
    final ar = widget.arabic;
    return Form(
      key: _form,
      child: DFieldGroup(
        children: [
          DFieldSet(
            children: [
              DFieldLegend(child: Text(ar ? 'طريقة الدفع' : 'Payment Method')),
              DFieldDescription(
                child: Text(
                  ar
                      ? 'جميع المعاملات آمنة ومشفرة'
                      : 'All transactions are secure and encrypted',
                ),
              ),
              DFieldGroup(
                children: [
                  _Editor(
                    ar ? 'الاسم على البطاقة' : 'Name on Card',
                    placeholder: 'Evil Rabbit',
                    required: true,
                  ),
                  _Editor(
                    ar ? 'رقم البطاقة' : 'Card Number',
                    placeholder: '1234 5678 9012 3456',
                    required: true,
                    description: ar
                        ? 'أدخل رقم البطاقة المكون من 16 رقمًا'
                        : 'Enter your 16-digit card number',
                  ),
                  _Columns(
                    children: [
                      _Selection(ar ? 'الشهر' : 'Month', const [
                        '01',
                        '02',
                        '03',
                        '04',
                        '05',
                        '06',
                        '07',
                        '08',
                        '09',
                        '10',
                        '11',
                        '12',
                      ]),
                      _Selection(ar ? 'السنة' : 'Year', const [
                        '2024',
                        '2025',
                        '2026',
                        '2027',
                        '2028',
                        '2029',
                      ]),
                      const _Editor('CVV', placeholder: '123', required: true),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const DFieldSeparator(),
          DFieldSet(
            children: [
              DFieldLegend(
                child: Text(ar ? 'عنوان الفوترة' : 'Billing Address'),
              ),
              DFieldDescription(
                child: Text(
                  ar
                      ? 'عنوان الفوترة المرتبط بطريقة الدفع الخاصة بك'
                      : 'The billing address associated with your payment method',
                ),
              ),
              KeyedSubtree(
                key: ValueKey(_reset),
                child: _Choice(
                  ar ? 'نفس عنوان الشحن' : 'Same as shipping address',
                  initial: true,
                ),
              ),
            ],
          ),
          _Editor(
            ar ? 'تعليقات' : 'Comments',
            lines: 3,
            placeholder: ar
                ? 'أضف أي تعليقات إضافية'
                : 'Add any additional comments',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DButton(
                label: Text(ar ? 'إرسال' : 'Submit'),
                variant: DButtonVariant.primary,
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    setState(
                      () => _saved = ar ? 'تم الحفظ محليًا' : 'Saved locally',
                    );
                  }
                },
              ),
              DButton(
                label: Text(ar ? 'إلغاء' : 'Cancel'),
                variant: DButtonVariant.outline,
                onPressed: () {
                  _form.currentState!.reset();
                  setState(() {
                    _reset++;
                    _saved = null;
                  });
                },
              ),
            ],
          ),
          if (_saved != null) Semantics(liveRegion: true, child: Text(_saved!)),
        ],
      ),
    );
  }
}

class FieldEditorsExample extends StatelessWidget {
  const FieldEditorsExample({super.key});
  @override
  Widget build(BuildContext context) => const DFieldSet(
    children: [
      DFieldGroup(
        children: [
          _Editor(
            'Username',
            placeholder: 'Max Leiter',
            description: 'Choose a unique username for your account.',
          ),
          _Editor(
            'Password',
            obscure: true,
            placeholder: '••••••••',
            helpBefore: true,
            description: 'Must be at least 8 characters long.',
          ),
          _Editor(
            'Feedback',
            lines: 4,
            placeholder: 'Your feedback helps us improve...',
            description: 'Share your thoughts about our service.',
          ),
          _Selection('Department', [
            'Engineering',
            'Design',
            'Marketing',
            'Sales',
            'Customer Support',
            'Human Resources',
            'Finance',
            'Operations',
          ], description: 'Select your department or area of work.'),
        ],
      ),
    ],
  );
}

class FieldSliderExample extends StatefulWidget {
  const FieldSliderExample({super.key});
  @override
  State<FieldSliderExample> createState() => _FieldSliderExampleState();
}

class _FieldSliderExampleState extends State<FieldSliderExample> {
  List<double> _range = const [200, 800];
  @override
  Widget build(BuildContext context) => DField(
    children: [
      const DFieldTitle(child: Text('Price Range')),
      DFieldDescription(
        child: Text(
          'Set your budget range (\$${_range.first.round()} - \$${_range.last.round()}).',
        ),
      ),
      DMultiSlider(
        values: _range,
        max: 1000,
        step: 10,
        semanticLabels: const ['Minimum price', 'Maximum price'],
        semanticFormatter: (value, _) => '\$${value.round()}',
        onChanged: (value) => setState(() => _range = value),
      ),
    ],
  );
}

class FieldAddressExample extends StatelessWidget {
  const FieldAddressExample({super.key});
  @override
  Widget build(BuildContext context) => const DFieldSet(
    children: [
      DFieldLegend(child: Text('Address Information')),
      DFieldDescription(
        child: Text('We need your address to deliver your order.'),
      ),
      DFieldGroup(
        children: [
          _Editor('Street Address', placeholder: '123 Main St'),
          _Columns(
            children: [
              _Editor('City', placeholder: 'New York'),
              _Editor('Postal Code', placeholder: '90502'),
            ],
          ),
        ],
      ),
    ],
  );
}

class FieldCheckboxExample extends StatelessWidget {
  const FieldCheckboxExample({super.key});
  @override
  Widget build(BuildContext context) => const DFieldGroup(
    children: [
      DFieldSet(
        children: [
          DFieldLegend(
            variant: DFieldLegendVariant.label,
            child: Text('Show these items on the desktop'),
          ),
          DFieldDescription(
            child: Text('Select the items you want to show on the desktop.'),
          ),
          DFieldGroup(
            variant: DFieldGroupVariant.choice,
            children: [
              _Choice('Hard disks'),
              _Choice('External disks'),
              _Choice('CDs, DVDs, and iPods'),
              _Choice('Connected servers'),
            ],
          ),
        ],
      ),
      DFieldSeparator(),
      _Choice(
        'Sync Desktop & Documents folders',
        initial: true,
        description:
            'Your Desktop & Documents folders are being synced with iCloud Drive. You can access them from other devices.',
      ),
    ],
  );
}

class FieldChoiceExample extends StatefulWidget {
  const FieldChoiceExample({super.key});
  @override
  State<FieldChoiceExample> createState() => _FieldChoiceExampleState();
}

class _FieldChoiceExampleState extends State<FieldChoiceExample> {
  String _plan = 'Monthly (\$9.99/month)';
  String _compute = 'Kubernetes';
  final _focusNodes = <String, FocusNode>{};
  FocusNode _focus(String value) =>
      _focusNodes.putIfAbsent(value, FocusNode.new);
  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DFieldGroup(
    children: [
      DFieldSet(
        spacing: 12,
        children: [
          const DFieldLegend(
            variant: DFieldLegendVariant.label,
            child: Text('Subscription Plan'),
          ),
          const DFieldDescription(
            child: Text('Yearly and lifetime plans offer significant savings.'),
          ),
          DRadioGroup<String>.controlled(
            groupValue: _plan,
            onChanged: (value) => setState(() => _plan = value!),
            child: DFieldGroup(
              variant: DFieldGroupVariant.choice,
              children: [
                for (final plan in [
                  'Monthly (\$9.99/month)',
                  'Yearly (\$99.99/year)',
                  'Lifetime (\$299.99)',
                ])
                  DField(
                    orientation: DFieldOrientation.horizontal,
                    children: [
                      DFieldControl(
                        label: plan,
                        expand: false,
                        alignIndicatorToContent: true,
                        child: DRadioGroupItem<String>(
                          value: plan,
                          focusNode: _focus(plan),
                          semanticLabel: '',
                        ),
                      ),
                      DFieldLabel(
                        excludeSemantics: true,
                        onPressed: () => setState(() => _plan = plan),
                        focusNode: _focus(plan),
                        style: const TextStyle(fontWeight: FontWeight.w400),
                        child: Text(plan),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      DFieldSet(
        spacing: 12,
        children: [
          const DFieldLegend(
            variant: DFieldLegendVariant.label,
            child: Text('Compute Environment'),
          ),
          const DFieldDescription(
            child: Text('Select the compute environment for your cluster.'),
          ),
          DRadioGroup<String>.controlled(
            groupValue: _compute,
            onChanged: (value) => setState(() => _compute = value!),
            child: DFieldGroup(
              variant: DFieldGroupVariant.choice,
              children: [
                for (final name in [
                  'Kubernetes',
                  'Virtual Machine',
                  'Unavailable environment',
                ])
                  DFieldLabel.choice(
                    selected: _compute == name,
                    enabled: name != 'Unavailable environment',
                    onPressed: () => setState(() => _compute = name),
                    focusNode: _focus(name),
                    child: DField(
                      orientation: DFieldOrientation.horizontal,
                      children: [
                        DFieldContent(
                          children: [
                            DFieldTitle(
                              excludeSemantics: true,
                              child: Text(name),
                            ),
                            DFieldDescription(
                              child: Text(
                                name == 'Kubernetes'
                                    ? 'Run GPU workloads on a K8s cluster.'
                                    : 'Access a cluster to run GPU workloads.',
                              ),
                            ),
                          ],
                        ),
                        DFieldControl(
                          label: name,
                          expand: false,
                          alignIndicatorToContent: true,
                          child: DRadioGroupItem<String>(
                            semanticLabel: '',
                            value: name,
                            focusNode: _focus(name),
                            enabled: name != 'Unavailable environment',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

class FieldNotificationsExample extends StatefulWidget {
  const FieldNotificationsExample({super.key});
  @override
  State<FieldNotificationsExample> createState() =>
      _FieldNotificationsExampleState();
}

class _FieldNotificationsExampleState extends State<FieldNotificationsExample> {
  bool _manage = false;
  @override
  Widget build(BuildContext context) => DFieldGroup(
    children: [
      const DFieldSet(
        children: [
          DFieldLegend(
            variant: DFieldLegendVariant.label,
            child: Text('Responses'),
          ),
          DFieldDescription(
            child: Text(
              'Get notified when ChatGPT responds to requests that take time, like research or image generation.',
            ),
          ),
          _Choice('Push notifications', initial: true, enabled: false),
        ],
      ),
      const DFieldSeparator(child: Text('Notification preferences')),
      DFieldSet(
        children: [
          const DFieldLegend(
            variant: DFieldLegendVariant.label,
            child: Text('Tasks'),
          ),
          const DFieldDescription(
            child: Text("Get notified when tasks you've created have updates."),
          ),
          DButton(
            label: Text(_manage ? 'Hide tasks' : 'Manage tasks'),
            onPressed: () => setState(() => _manage = !_manage),
          ),
          if (_manage) const Text('No local tasks.'),
          const DFieldGroup(
            variant: DFieldGroupVariant.choice,
            children: [
              _Choice('Push task notifications'),
              _Choice('Email notifications'),
            ],
          ),
        ],
      ),
      const _Choice('Multi-factor authentication', switchControl: true),
    ],
  );
}

class FieldResponsiveExample extends StatefulWidget {
  const FieldResponsiveExample({super.key});
  @override
  State<FieldResponsiveExample> createState() => _FieldResponsiveExampleState();
}

class _FieldResponsiveExampleState extends State<FieldResponsiveExample> {
  final _form = GlobalKey<FormState>();
  final _focus = FocusNode();
  final _text = TextEditingController();
  String? _saved;
  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: DFieldSet(
      children: [
        const DFieldLegend(child: Text('Profile')),
        const DFieldDescription(
          child: Text('Fill in your profile information.'),
        ),
        DFieldGroup(
          children: [
            FormField<String>(
              initialValue: '',
              onReset: _text.clear,
              onSaved: (value) => _saved = value,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Provide your full name.'
                  : null,
              builder: (state) {
                final errors = [state.errorText];
                return DField(
                  orientation: DFieldOrientation.responsive,
                  invalid: state.hasError,
                  children: [
                    DFieldContent(
                      children: [
                        DFieldLabel(
                          focusNode: _focus,
                          excludeSemantics: true,
                          child: const Text('Name'),
                        ),
                        const DFieldDescription(
                          child: Text(
                            'Provide your full name for identification',
                          ),
                        ),
                      ],
                    ),
                    DFieldContent(
                      children: [
                        DFieldControl(
                          label: 'Name',
                          required: true,
                          description:
                              'Provide your full name for identification',
                          errors: errors,
                          child: TextField(
                            focusNode: _focus,
                            controller: _text,
                            decoration: const InputDecoration(
                              hintText: 'Evil Rabbit',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: state.didChange,
                          ),
                        ),
                        if (state.hasError) DFieldError(errors: errors),
                      ],
                    ),
                  ],
                );
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DButton(
                  label: const Text('Submit profile'),
                  variant: DButtonVariant.primary,
                  onPressed: () {
                    if (_form.currentState!.validate()) {
                      setState(() => _form.currentState!.save());
                    }
                  },
                ),
                DButton(
                  label: const Text('Reset profile'),
                  variant: DButtonVariant.outline,
                  onPressed: () {
                    _form.currentState!.reset();
                    setState(() => _saved = null);
                  },
                ),
              ],
            ),
            if (_saved != null)
              Semantics(
                liveRegion: true,
                child: Text('Saved locally: $_saved'),
              ),
            const DFieldError(
              errors: [
                null,
                'Example of multiple errors.',
                'Example of multiple errors.',
                'Each unique message appears once.',
              ],
            ),
          ],
        ),
      ],
    ),
  );
}
