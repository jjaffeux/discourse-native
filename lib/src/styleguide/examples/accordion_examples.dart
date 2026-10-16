import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final accordionExamples = ComponentExamples(
  topLevelExampleIndex: 4,
  status: ComponentStatus.implemented,
  description:
      'A vertically stacked set of interactive headings that reveal content.',
  notes:
      'Accepted after independent source, browser and native review. DAccordion '
      'composes the accepted '
      'DCollapsible owner, adds one-panel coordination and stable typed values, '
      'headings, base-nova visuals and local or borrowed-controller '
      'state. Headers remain bounded accessibility buttons; retained panel fields '
      'stay independently accessible. Desktop uses compact 40px artwork and touch '
      'platforms use the same visible bounds. Host palette, font, radius, scaling, RTL and '
      'reduced-motion settings remain live.',
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
          'External controls reorder/remove items and retain a local draft in an open panel.',
      code: _controlledCode,
      builder: (_) => const _Frame(child: _ControlledExample()),
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical shipping, returns, and support questions with Shipping open initially.',
      states: const ['Single', 'Collapsible', 'Shipping'],
      code: '''DAccordion<String>(
  defaultValues: const ['shipping'],
  children: [
    for (final item in shippingQuestions)
      DAccordionItem<String>(
        value: item.value,
        child: Column(children: [
          DAccordionHeader(
            child: DAccordionTrigger(child: Text(item.question)),
          ),
          DAccordionContent(child: Text(item.answer)),
        ]),
      ),
  ],
)''',
      builder: (_) => const _Frame(
        child: _Example(items: _referenceItems, initial: ['shipping']),
      ),
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
  const _Example({required this.items, this.initial = const []});
  final List<_Entry> items;
  final List<String> initial;

  @override
  Widget build(BuildContext context) => DAccordion<String>(
    defaultValues: initial,

    children: [for (final entry in items) _item(entry)],
  );
}

DAccordionItem<String> _item(_Entry entry, {Widget? content}) =>
    DAccordionItem<String>(
      key: ValueKey('accordion-${entry.value}'),
      value: entry.value,

      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DAccordionHeader(
            child: DAccordionTrigger(child: Text(entry.question)),
          ),
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
  final _controller = DAccordionController<String>(initialValues: ['profile']);
  Set<String> get _values => _controller.values;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() => setState(() {});
  bool _reversed = false;
  bool _showSecurity = true;

  @override
  void dispose() {
    _draft.dispose();
    _controller.dispose();
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
                  _controller.open('profile');
                }
              }),
              label: Text(_showSecurity ? 'Remove security' : 'Add security'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DAccordion<String>(
          controller: _controller,
          keepMounted: true,

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

const _referenceItems = [
  _Entry(
    'shipping',
    'What are your shipping options?',
    'We offer standard (5-7 days), express (2-3 days), and overnight shipping. Free shipping on international orders.',
  ),
  _Entry(
    'returns',
    'What is your return policy?',
    'Returns accepted within 30 days. Items must be unused and in original packaging. Refunds processed within 5-7 business days.',
  ),
  _Entry(
    'support',
    'How can I contact customer support?',
    'Reach us via email, live chat, or phone. We respond within 24 hours during business days.',
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

const _cardCode = '''DCard(children: [
  DCardHeader(title: DCardTitle(child: Text('Subscription & Billing')),
    description: DCardDescription(child: Text('Common questions about your account.'))),
  DCardContent(child: DAccordion<String>(
    defaultValues: {'plans'}, children: items)),
])''';

const _rtlCode = '''Directionality(textDirection: TextDirection.rtl,
  child: DAccordion<String>(defaultValues: {'password'}, children: translatedItems))''';

const _controlledCode =
    "Set<String> values = {'profile'};\nDAccordion<String>( \n  \n  keepMounted: true,  children: dynamicItems)";
