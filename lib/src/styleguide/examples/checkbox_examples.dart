import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final checkboxExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Choose one or more options with a checkbox.',
  notes:
      'DCheckbox owns one focus and semantic target, including its optional '
      'title and subtitle. Use value/onChanged for controlled state, or '
      'DCheckbox.defaultValue for local default state. Null is mixed with '
      'tristate enabled. DCheckboxFormField integrates validation, save and reset. '
      'Independent actions belong outside title/subtitle. Reference control is '
      '16px with 14px Lucide artwork; invisible native targets are larger. '
      'Use the shared preview controls for live light/dark/custom palettes, '
      '360px width, 200% text, RTL and reduced motion.',
  examples: [
    StyleguideExample(
      title: 'Basic and description',
      description:
          'Click the label or press Space while focused. Each checkbox keeps its own local state.',
      states: const ['Default', 'Checked', 'Description', 'Disabled'],
      code:
          '''DCheckbox.defaultValue(title: DLabel(child: Text('Accept terms and conditions')))
DCheckbox.defaultValue(
  defaultValue: true,
  title: Text('Accept terms and conditions'),
  subtitle: Text('By clicking this checkbox, you agree to the terms.'),
)
DCheckbox.defaultValue(enabled: false, title: Text('Enable notifications'))''',
      builder: (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DCheckbox.defaultValue(
            title: DLabel(child: Text('Accept terms and conditions')),
          ),
          SizedBox(height: 20),
          DCheckbox.defaultValue(
            defaultValue: true,
            title: Text('Accept terms and conditions'),
            subtitle: Text(
              'By clicking this checkbox, you agree to the terms.',
            ),
          ),
          SizedBox(height: 20),
          DCheckbox.defaultValue(
            enabled: false,
            title: Text('Enable notifications'),
          ),
          SizedBox(height: 20),
          _NotificationCard(),
        ],
      ),
    ),
    StyleguideExample(
      title: 'All states',
      description:
          'The first three controls start unchecked, checked and mixed. Mixed activates to checked. Invalid controls retain their value and remain interactive.',
      states: const [
        'Unchecked',
        'Checked',
        'Indeterminate',
        'Disabled',
        'Read only',
        'Invalid',
        'Focus',
      ],
      code: '''DCheckbox.defaultValue(tristate: true, defaultValue: null,
  semanticLabel: 'Mixed selection')
DCheckbox.defaultValue(invalid: true, title: Text('Accept terms'))''',
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in <bool?>[false, true, null])
            DCheckbox.defaultValue(
              defaultValue: value,
              tristate: true,
              title: Text(
                value == null
                    ? 'Mixed selection'
                    : value
                    ? 'Checked'
                    : 'Unchecked',
              ),
            ),
          for (final value in <bool?>[false, true, null])
            DCheckbox.defaultValue(
              defaultValue: value,
              tristate: true,
              enabled: false,
              title: Text('Disabled ${value ?? 'mixed'}'),
            ),
          const DCheckbox.defaultValue(
            defaultValue: true,
            readOnly: true,
            title: Text('Read only selection'),
          ),
          const DCheckbox.defaultValue(
            invalid: true,
            title: Text('Accept terms and conditions'),
          ),
          const DCheckbox.defaultValue(
            defaultValue: true,
            invalid: true,
            title: Text('Checked invalid'),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Group',
      description: 'Choose which local devices appear on the desktop.',
      states: const ['Group', 'Independent choices'],
      code: '''Column(children: [
  DLabel(child: Text('Show these items on the desktop:')),
  DCheckbox.defaultValue(defaultValue: true, title: Text('Hard disks')),
  DCheckbox.defaultValue(title: Text('Connected servers')),
])''',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DLabel(
            style: TextStyle(height: 20 / 14),
            child: Text('Show these items on the desktop:'),
          ),
          const SizedBox(height: 2),
          Text(
            'Select the items you want to show on the desktop.',
            style: TextStyle(
              fontSize: DiscourseTypography.sm,
              height: 1.5,
              color: DTokens.of(context).mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          for (final (index, name) in [
            'Hard disks',
            'External disks',
            'CDs, DVDs, and iPods',
            'Connected servers',
          ].indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            DCheckbox.defaultValue(
              defaultValue: index < 2,
              title: DLabel(
                style: const TextStyle(
                  height: 1.375,
                  fontWeight: FontWeight.w400,
                ),
                child: Text(name),
              ),
            ),
          ],
        ],
      ),
    ),
    StyleguideExample(
      title: 'Table selection',
      description:
          'Select individual local people or toggle all. Partial selection has a mixed header.',
      states: const ['Controlled', 'Table', 'Select all', 'Indeterminate'],
      code: '''DCheckbox(
  value: selected.isEmpty ? false : selected.length == people.length ? true : null,
  tristate: true,
  semanticLabel: 'Select all people',
  onChanged: (_) => setState(() {
    selected = selected.length == people.length ? {} : people.toSet();
  }),
)''',
      builder: (_) => const _SelectionTable(),
    ),
    StyleguideExample(
      title: 'Validation and recovery',
      description:
          'Save without accepting to show an error. Accept and save again, then reset the native Form.',
      states: const ['Form', 'Invalid', 'Recovery', 'Save', 'Reset'],
      code: '''DCheckboxFormField(
  title: Text('Accept terms and conditions'),
  validator: (value) => value == true ? null : 'Please accept the terms.',
  autovalidateMode: AutovalidateMode.onUserInteraction,
  onSaved: (value) => accepted = value == true,
)
// formKey.currentState!.validate();
// formKey.currentState!.save();
// formKey.currentState!.reset();''',
      builder: (_) => const _CheckboxForm(),
    ),
    StyleguideExample(
      title: 'Long labels and RTL',
      description:
          'Labels and descriptions wrap naturally at 360px and 200% text. Change the preview palette without losing selection.',
      states: const ['RTL', '200%', 'Narrow', 'Live theme'],
      code: '''Directionality(textDirection: TextDirection.rtl,
  child: DCheckbox.defaultValue(
    title: Text('قبول الشروط والأحكام'),
    subtitle: Text('بالنقر على هذا المربع، فإنك توافق على الشروط.'),
  ),
)''',
      builder: (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DCheckbox.defaultValue(
            title: Text(
              'Receive occasional product updates, community announcements, and important information about the spaces I follow.',
            ),
            subtitle: Text(
              'You can change these preferences at any time. This choice is stored only in this example.',
            ),
          ),
          SizedBox(height: 24),
          Directionality(
            textDirection: TextDirection.rtl,
            child: DCheckbox.defaultValue(
              title: Text('قبول الشروط والأحكام'),
              subtitle: Text('بالنقر على هذا المربع، فإنك توافق على الشروط.'),
            ),
          ),
          SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.rtl,
            child: DCheckbox.defaultValue(
              defaultValue: true,
              title: Text('תנאים והגבלות'),
            ),
          ),
        ],
      ),
    ),
  ],
);

class _SelectionTable extends StatefulWidget {
  const _SelectionTable();
  @override
  State<_SelectionTable> createState() => _SelectionTableState();
}

class _SelectionTableState extends State<_SelectionTable> {
  static const people = [
    'Sarah Chen',
    'Marcus Rodriguez',
    'Priya Patel',
    'David Kim',
  ];
  Set<String> selected = {'Sarah Chen'};
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 560,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontSize: DiscourseTypography.sm,
              height: 20 / 14,
            ),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(32),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(3),
                3: FlexColumnWidth(),
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: DTokens.of(context).border),
              ),
              children: [
                TableRow(
                  children: [
                    DCheckbox(
                      value: selected.isEmpty
                          ? false
                          : selected.length == people.length
                          ? true
                          : null,
                      tristate: true,
                      semanticLabel: 'Select all people',
                      onChanged: (_) => setState(
                        () => selected = selected.length == people.length
                            ? {}
                            : people.toSet(),
                      ),
                    ),
                    const SizedBox(
                      height: 40,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('Name'),
                      ),
                    ),
                    const Text('Email'),
                    const Text('Role'),
                  ],
                ),
                for (final (index, person) in people.indexed)
                  TableRow(
                    decoration: BoxDecoration(
                      color: selected.contains(person)
                          ? DTokens.of(context).muted.withValues(
                              alpha: DTokens.of(context).muted.a * .5,
                            )
                          : null,
                    ),
                    children: [
                      DCheckbox(
                        value: selected.contains(person),
                        semanticLabel: 'Select $person',
                        onChanged: (value) => setState(() {
                          value == true
                              ? selected.add(person)
                              : selected.remove(person);
                        }),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.5),
                        child: Text(
                          person,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${person.toLowerCase().replaceAll(' ', '.')}@example.com',
                      ),
                      Text(const ['Admin', 'User', 'User', 'Editor'][index]),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      Text('${selected.length} selected'),
    ],
  );
}

class _CheckboxForm extends StatefulWidget {
  const _CheckboxForm();
  @override
  State<_CheckboxForm> createState() => _CheckboxFormState();
}

class _CheckboxFormState extends State<_CheckboxForm> {
  final form = GlobalKey<FormState>();
  String result = '';
  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DCheckboxFormField(
          title: const Text('Accept terms and conditions'),
          validator: (value) =>
              value == true ? null : 'Please accept the terms.',
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onSaved: (value) => result = 'Saved: $value',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            DButton(
              label: const Text('Save'),
              onPressed: () {
                if (form.currentState!.validate()) {
                  form.currentState!.save();
                  setState(() {});
                }
              },
            ),
            DButton(
              label: const Text('Reset'),
              onPressed: () {
                form.currentState!.reset();
                setState(() => result = '');
              },
            ),
          ],
        ),
        if (result.isNotEmpty) Text(result),
      ],
    ),
  );
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard();
  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool checked = false;
  bool hovered = false;
  bool focusVisible = false;
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radius),
          border: Border.all(
            color: focusVisible
                ? tokens.focusRing
                : checked
                ? tokens.primary.withValues(
                    alpha: tokens.primary.a * (dark ? .2 : .3),
                  )
                : tokens.border,
          ),
          color: hovered
              ? tokens.muted.withValues(alpha: tokens.muted.a * .5)
              : checked
              ? tokens.primary.withValues(
                  alpha: tokens.primary.a * (dark ? .1 : .05),
                )
              : null,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radius),
          border: Border.all(
            color: focusVisible
                ? tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5)
                : Colors.transparent,
            width: 3,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: DCheckbox(
          value: checked,
          showFocusRing: false,
          onShowFocusHighlight: (value) => setState(() => focusVisible = value),
          onChanged: (value) => setState(() => checked = value == true),
          contentPadding: const EdgeInsets.all(10),
          title: const DLabel(
            style: TextStyle(height: 20 / 14),
            child: Text('Enable notifications'),
          ),
          subtitle: const Text(
            'You can enable or disable notifications at any time.',
          ),
        ),
      ),
    );
  }
}
