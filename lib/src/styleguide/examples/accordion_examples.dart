import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final accordionExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description:
      'A vertically stacked set of interactive headings that reveal content.',
  notes:
      'Source-prepared for independent review. DAccordion composes the accepted '
      'DCollapsible owner, adds single/multiple coordination, stable typed values, '
      'headings, base-nova visuals and controlled, local or borrowed-controller '
      'state. Headers remain bounded accessibility buttons; retained panel fields '
      'stay independently accessible. Desktop uses compact 40px artwork and touch '
      'platforms use 48px targets. Host palette, font, radius, scaling, RTL and '
      'reduced-motion settings remain live. Native/browser comparison is assigned '
      'to the independent reviewer.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description:
          'One FAQ is open at a time; the first starts open and all may close.',
      code: _basicCode,
      builder: (_) => const _Frame(
        child: _Example(items: _basicItems, initial: ['password']),
      ),
    ),
    StyleguideExample(
      title: 'Multiple',
      description:
          'Open several settings panels independently. Notifications starts open.',
      code: _multipleCode,
      builder: (_) => const _Frame(
        child: _Example(
          items: _multipleItems,
          initial: ['notifications'],
          multiple: true,
        ),
      ),
    ),
    StyleguideExample(
      title: 'Disabled',
      description:
          'The premium heading remains discoverable but cannot be activated.',
      code: _disabledCode,
      builder: (_) => const _Frame(
        child: _Example(items: _disabledItems, disabledValue: 'premium'),
      ),
    ),
    StyleguideExample(
      title: 'Borders',
      description:
          'Rounded outer border, 16px item inset and no doubled final divider.',
      code: _bordersCode,
      builder: (_) => const _Frame(
        child: _Example(
          items: _borderItems,
          initial: ['billing'],
          outlined: true,
        ),
      ),
    ),
    StyleguideExample(
      title: 'Card',
      description:
          'The accepted Card owner supplies the subscription heading and surface.',
      code: _cardCode,
      builder: (_) => const _Frame(width: 384, child: _CardExample()),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic FAQ with logical alignment and the chevron at inline end.',
      code: _rtlCode,
      builder: (_) => const _Frame(
        width: 448,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: _Example(items: _rtlItems, initial: ['password']),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Controlled and lifecycle',
      description:
          'External controls reorder/remove items, toggle disabled state and retain a local draft in an open panel.',
      code: _controlledCode,
      builder: (_) => const _Frame(child: _ControlledExample()),
    ),
  ],
);

class _Entry {
  const _Entry(this.value, this.question, this.answer);
  final String value;
  final String question;
  final String answer;
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.width = 512});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

class _Example extends StatelessWidget {
  const _Example({
    required this.items,
    this.initial = const [],
    this.multiple = false,
    this.disabledValue,
    this.outlined = false,
  });
  final List<_Entry> items;
  final List<String> initial;
  final bool multiple;
  final String? disabledValue;
  final bool outlined;

  @override
  Widget build(BuildContext context) => DAccordion<String>(
    defaultValues: initial,
    multiple: multiple,
    outlined: outlined,
    children: [
      for (final entry in items)
        _item(entry, disabled: entry.value == disabledValue),
    ],
  );
}

DAccordionItem<String> _item(
  _Entry entry, {
  bool disabled = false,
  Widget? content,
}) => DAccordionItem<String>(
  key: ValueKey('accordion-${entry.value}'),
  value: entry.value,
  disabled: disabled,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DAccordionHeader(child: DAccordionTrigger(child: Text(entry.question))),
      DAccordionContent(child: content ?? Text(entry.answer)),
    ],
  ),
);

class _CardExample extends StatelessWidget {
  const _CardExample();
  @override
  Widget build(BuildContext context) => DCard(
    children: [
      const DCardHeader(
        title: DCardTitle(child: Text('Subscription & Billing')),
        description: DCardDescription(
          child: Text(
            'Common questions about your account, plans, payments and cancellations.',
          ),
        ),
      ),
      DCardContent(
        child: DAccordion<String>(
          defaultValues: const ['plans'],
          children: [for (final entry in _cardItems) _item(entry)],
        ),
      ),
    ],
  );
}

class _ControlledExample extends StatefulWidget {
  const _ControlledExample();
  @override
  State<_ControlledExample> createState() => _ControlledExampleState();
}

class _ControlledExampleState extends State<_ControlledExample> {
  final _draft = TextEditingController(text: 'Local draft');
  Set<String> _values = {'profile'};
  bool _reversed = false;
  bool _disabled = false;
  bool _showSecurity = true;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var entries = [
      _controlledItems.first,
      if (_showSecurity) _controlledItems.last,
    ];
    if (_reversed) entries = entries.reversed.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              size: DButtonSize.small,
              variant: DButtonVariant.outline,
              onPressed: () => setState(() => _reversed = !_reversed),
              label: const Text('Reorder'),
            ),
            DButton(
              size: DButtonSize.small,
              variant: DButtonVariant.outline,
              onPressed: () => setState(() {
                _showSecurity = !_showSecurity;
                if (!_showSecurity) {
                  _values.remove('security');
                }
              }),
              label: Text(_showSecurity ? 'Remove security' : 'Add security'),
            ),
            DButton(
              size: DButtonSize.small,
              variant: DButtonVariant.outline,
              onPressed: () => setState(() => _disabled = !_disabled),
              label: Text(_disabled ? 'Enable accordion' : 'Disable accordion'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DAccordion<String>(
          multiple: true,
          disabled: _disabled,
          keepMounted: true,
          values: _values,
          onValuesChange: (value) => setState(() => _values = {...value}),
          children: [
            for (final entry in entries)
              _item(
                entry,
                content: entry.value == 'profile'
                    ? Semantics(
                        textField: true,
                        label: 'Profile draft',
                        child: DInput(controller: _draft),
                      )
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            _values.isEmpty ? 'No panels open' : 'Open: ${_values.join(', ')}',
          ),
        ),
      ],
    );
  }
}

const _basicItems = [
  _Entry(
    'password',
    'How do I reset my password?',
    "Click 'Forgot Password' on the login page, enter your email address, and we'll send a reset link that expires in 24 hours.",
  ),
  _Entry(
    'plan',
    'Can I change my subscription plan?',
    'Yes, upgrade or downgrade from account settings. Changes appear in your next billing cycle.',
  ),
  _Entry(
    'payment',
    'What payment methods do you accept?',
    'We accept major credit cards, PayPal and bank transfers through secure payment partners.',
  ),
];

const _multipleItems = [
  _Entry(
    'notifications',
    'Notification Settings',
    'Choose email alerts for updates or push notifications for mobile devices.',
  ),
  _Entry(
    'privacy',
    'Privacy & Security',
    'Manage two-factor authentication, connected devices, active sessions and data sharing.',
  ),
  _Entry(
    'billing',
    'Billing & Subscription',
    'View your plan, payment history and invoices, or update and cancel your subscription.',
  ),
];

const _disabledItems = [
  _Entry(
    'history',
    'Can I access my account history?',
    'Yes, open Account History to view transactions, plan changes and support tickets.',
  ),
  _Entry(
    'premium',
    'Premium feature information',
    'Upgrade your plan to access premium feature information.',
  ),
  _Entry(
    'email',
    'How do I update my email address?',
    'Update it in account settings, then confirm the verification email.',
  ),
];

const _borderItems = [
  _Entry(
    'billing',
    'How does billing work?',
    'Monthly and annual plans are charged at the start of each cycle and can be cancelled anytime.',
  ),
  _Entry(
    'security',
    'Is my data secure?',
    'Data is encrypted at rest and in transit with regular third-party security audits.',
  ),
  _Entry(
    'integration',
    'What integrations do you support?',
    'Connect popular tools or build custom integrations with the REST API and webhooks.',
  ),
];

const _cardItems = [
  _Entry(
    'plans',
    'What subscription plans do you offer?',
    'Starter, Professional and Enterprise tiers include increasing storage, API access and support.',
  ),
  _Entry(
    'billing',
    'How does billing work?',
    'Billing occurs automatically at the start of each cycle and an invoice is sent by email.',
  ),
  _Entry(
    'cancel',
    'How do I cancel my subscription?',
    'Cancel anytime in account settings. Access continues until the end of the billing period.',
  ),
];

const _rtlItems = [
  _Entry(
    'password',
    'كيف أعيد تعيين كلمة المرور؟',
    'اختر «نسيت كلمة المرور» وأدخل بريدك الإلكتروني لتلقي رابط إعادة التعيين.',
  ),
  _Entry(
    'plan',
    'هل يمكنني تغيير خطة الاشتراك؟',
    'نعم، يمكنك ترقية خطتك أو تخفيضها من إعدادات الحساب في أي وقت.',
  ),
  _Entry(
    'payment',
    'ما طرق الدفع المقبولة؟',
    'نقبل بطاقات الائتمان الرئيسية وPayPal والتحويلات المصرفية.',
  ),
];

const _controlledItems = [
  _Entry(
    'profile',
    'Profile draft',
    'Edit the locally retained profile draft.',
  ),
  _Entry(
    'security',
    'Security review',
    'Review recent sessions and two-factor authentication.',
  ),
];

const _basicCode =
    '''DAccordion<String>(defaultValues: {'password'}, children: [
  DAccordionItem<String>(value: 'password', child: Column(children: [
    DAccordionHeader(child: DAccordionTrigger(child: Text('How do I reset my password?'))),
    DAccordionContent(child: Text('Use Forgot Password on the login page.')),
  ])),
])''';

const _multipleCode = '''DAccordion<String>(multiple: true,
  defaultValues: {'notifications'}, children: items)''';

const _disabledCode =
    '''DAccordionItem<String>(value: 'premium', disabled: true,
  child: Column(children: [
    DAccordionHeader(child: DAccordionTrigger(child: Text('Premium feature information'))),
    DAccordionContent(child: Text('Upgrade to access this content.')),
  ]))''';

const _bordersCode = '''DAccordion<String>(outlined: true,
  defaultValues: {'billing'}, children: items)
// outlined maps the documented rounded border + 16px item inset composition.''';

const _cardCode = '''DCard(children: [
  DCardHeader(title: DCardTitle(child: Text('Subscription & Billing')),
    description: DCardDescription(child: Text('Common questions about your account.'))),
  DCardContent(child: DAccordion<String>(
    defaultValues: {'plans'}, children: items)),
])''';

const _rtlCode = '''Directionality(textDirection: TextDirection.rtl,
  child: DAccordion<String>(defaultValues: {'password'}, children: translatedItems))''';

const _controlledCode = '''Set<String> values = {'profile'};
DAccordion<String>(multiple: true, values: values,
  onValuesChange: (next) => setState(() => values = {...next}),
  keepMounted: true, disabled: disabled, children: dynamicItems)''';
