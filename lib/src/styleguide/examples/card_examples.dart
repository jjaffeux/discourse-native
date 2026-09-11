import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final cardExamples = ComponentExamples(
  description:
      'A container for related content, with a header and optional footer.',
  status: ComponentStatus.implemented,
  notes:
      'The seven passive Card parts use base-nova metrics. Install by importing '
      'package:discourse_native/discourse_ui.dart. Spacing is shared by all parts; '
      'footer is an explicit root slot. Child widgets own interactions and state. '
      'The frozen compositions use the accepted Button, Input, Label, Field, Badge '
      'and Toggle Group owners. No example makes requests. At narrow/large text '
      'the header action moves below its text to keep both readable.',
  examples: [
    StyleguideExample(
      title: 'Login',
      description:
          'Frozen login composition, max width 384. Enter an email and '
          'password, submit locally, or use Sign Up / Forgot password / Google.',
      code: _loginCode,
      builder: (_) => const _Login(),
    ),
    StyleguideExample(
      title: 'Composition',
      description:
          'All seven parts. A footer supplies its own border and muted background.',
      code: """DCard(children: [
  DCardHeader(
    title: DCardTitle(child: Text('Card Title')),
    description: DCardDescription(child: Text('Card Description')),
    action: DCardAction(child: Text('Card Action')),
  ),
  DCardContent(child: Text('Card Content')),
], footer: DCardFooter(child: Text('Card Footer')))""",
      builder: (_) => const _Frame(
        child: DCard(
          footer: DCardFooter(child: Text('Card Footer')),
          children: [
            DCardHeader(
              title: DCardTitle(child: Text('Card Title')),
              description: DCardDescription(child: Text('Card Description')),
              action: DCardAction(child: Text('Card Action')),
            ),
            DCardContent(child: Text('Card Content')),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Small',
      description:
          'Frozen scheduled reports composition, max width 320; 12px spacing and 14px title.',
      code: """DCard(size: DCardSize.small, children: [
  DCardHeader(title: DCardTitle(child: Text('Scheduled reports')),
    description: DCardDescription(child: Text('Weekly snapshots. No more manual exports.'))),
  DCardContent(child: reportFeatures),
], footer: DCardFooter(child: reportActions))""",
      builder: (_) => const _Reports(),
    ),
    StyleguideExample(
      title: 'Shared spacing',
      description:
          'Change 16/20/24/32px while retaining your input and local status.',
      code: _spacingCode,
      builder: (_) => const _Login(configurableSpacing: true),
    ),
    StyleguideExample(
      title: 'Edge-to-edge terms',
      description:
          'Scrollable terms (192px maximum), edge-to-edge content and no gap above the footer.',
      code: """DCard(children: [
  DCardHeader(title: DCardTitle(child: Text('Terms of Service')),
    description: DCardDescription(child: Text('Review the terms before accepting the agreement.'))),
  DCardContent(edgeToEdge: true, joinNext: true, child: termsScrollView),
], footer: DCardFooter(child: Wrap(spacing: 8, children: [
  DButton(onPressed: decline, variant: DButtonVariant.outline,
    label: Text('Decline')),
  DButton(onPressed: accept, variant: DButtonVariant.primary,
    label: Text('Accept')),
])))""",
      builder: (_) => const _Terms(),
    ),
    StyleguideExample(
      title: 'Image',
      description:
          'Frozen event composition using the bundled cover, clipped at the top edge; no network fallback.',
      code: """DCard(
  leading: DAspectRatio(ratio: 16 / 9, child: Image.asset(
    'packages/discourse_native/src/styleguide/assets/discourse.png',
    fit: BoxFit.cover, semanticLabel: 'Event cover')),
  children: [DCardHeader(
    title: DCardTitle(child: Text('Design systems meetup')),
    description: DCardDescription(child: Text('A practical talk on component APIs, accessibility, and shipping faster.')),
    action: DCardAction(child: DBadge(
      variant: DBadgeVariant.secondary, child: Text('Featured'))),
  )],
  footer: DCardFooter(child: DButton(onPressed: viewEvent,
    variant: DButtonVariant.primary, label: Text('View Event'))),
)""",
      builder: (_) => const _ImageCard(),
    ),
    StyleguideExample(
      title: 'RTL login',
      description:
          'Frozen Arabic login. Header action follows logical end; inputs retain native editing.',
      code:
          'DDirection(textDirection: TextDirection.rtl, child: loginCard)\n// Use the Login composition with translated labels.',
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: _Login(arabic: true),
      ),
    ),
    StyleguideExample(
      title: 'Application states and absent parts',
      description:
          'Select loaded, disabled, selected, busy, error or empty. '
          'Card stays passive; child controls and explicit status text carry state. '
          'Bordered header and footer-free composition are also shown.',
      code: """DCard(children: [
  DCardHeader(border: true, title: DCardTitle(child: Text('Community digest'))),
  DCardContent(child: Text(status)),
  DCardContent(child: DButton(onPressed: enabled ? activate : null,
    label: Text('Open digest'))),
])""",
      builder: (_) => const _States(),
    ),
  ],
);

const _loginCode = """DCard(spacing: spacing, children: [
  DCardHeader(
    title: DCardTitle(child: Text('Login to your account')),
    description: DCardDescription(child: Text('Enter your email below to login to your account')),
    action: DCardAction(child: DButton(onPressed: signUp,
      variant: DButtonVariant.link, label: Text('Sign Up'))),
  ),
  DCardContent(child: Form(key: formKey, child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DField(children: [
      DFieldLabel(focusNode: emailFocus, excludeSemantics: true,
        style: TextStyle(height: 1),
        child: Text('Email')),
      DFieldControl(label: 'Email', required: true, child: DInput(
        focusNode: emailFocus, keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => passwordFocus.requestFocus(),
        hintText: 'm@example.com', isRequired: true, validator: validateEmail)),
    ]),
    SizedBox(height: 24),
    DField(children: [
      Wrap(alignment: WrapAlignment.spaceBetween, children: [
        DFieldLabel(focusNode: passwordFocus, excludeSemantics: true,
          style: TextStyle(height: 1),
          child: Text('Password')),
        // Inline text bounds, no padding; DButton retains native activation.
        recoveryLink,
      ]),
      DFieldControl(label: 'Password', required: true, child: DInput(
        focusNode: passwordFocus, obscureText: true, isRequired: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => submit(),
        validator: validatePassword)),
    ]),
  ]))),
], footer: DCardFooter(child: Column(
  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
  DButton(onPressed: submit, variant: DButtonVariant.primary, label: Text('Login')),
  SizedBox(height: 8),
  DButton(onPressed: google, variant: DButtonVariant.outline,
    label: Text('Login with Google')),
])))""";

const _spacingCode = """DToggleGroup<double>(
  values: [spacing],
  onChanged: (values) => setState(() => spacing = values.single),
  allowEmptySelection: false,
  variant: DToggleVariant.outline,
  size: DToggleSize.small,
  items: [16, 20, 24, 32].map((value) => DToggleGroupItem(
    value: value.toDouble(), child: Text('\${value}px'))).toList(),
)

$_loginCode""";

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.width = 384});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

Widget _button(
  String text,
  VoidCallback? callback, {
  DButtonVariant variant = DButtonVariant.primary,
  DButtonSize size = DButtonSize.regular,
}) => DButton(
  onPressed: callback,
  size: size,
  variant: variant,
  label: Builder(
    builder: (context) => DefaultTextStyle(
      style: DefaultTextStyle.of(context).style,
      child: Text(text),
    ),
  ),
);

class _Login extends StatefulWidget {
  const _Login({this.configurableSpacing = false, this.arabic = false});
  final bool configurableSpacing;
  final bool arabic;
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  double _spacing = 16;
  String _status = '';
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _notice(String value) => setState(() => _status = value);

  void _submit() =>
      _notice(_form.currentState!.validate() ? 'Signed in locally' : '');

  @override
  Widget build(BuildContext context) {
    final ar = widget.arabic;
    return _Frame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.configurableSpacing) ...[
            Align(
              alignment: Alignment.center,
              child: DToggleGroup<double>(
                values: [_spacing],
                onChanged: (values) {
                  if (values.isNotEmpty) {
                    setState(() => _spacing = values.single);
                  }
                },
                allowEmptySelection: false,
                variant: DToggleVariant.outline,
                size: DToggleSize.small,
                semanticLabel: 'Card spacing',
                items: [
                  for (final value in [16.0, 20.0, 24.0, 32.0])
                    DToggleGroupItem(
                      value: value,
                      semanticLabel: '${value.toInt()} pixel spacing',
                      child: Text('${value.toInt()}px'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          DCard(
            spacing: _spacing,
            footer: DCardFooter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _button(ar ? 'تسجيل الدخول' : 'Login', _submit),
                  const SizedBox(height: 8),
                  _button(
                    ar ? 'تسجيل الدخول باستخدام Google' : 'Login with Google',
                    () => _notice('Google login selected'),
                    variant: DButtonVariant.outline,
                  ),
                ],
              ),
            ),
            children: [
              DCardHeader(
                title: DCardTitle(
                  child: Text(
                    ar ? 'تسجيل الدخول إلى حسابك' : 'Login to your account',
                  ),
                ),
                description: DCardDescription(
                  child: Text(
                    ar
                        ? 'أدخل بريدك الإلكتروني أدناه لتسجيل الدخول إلى حسابك'
                        : 'Enter your email below to login to your account',
                  ),
                ),
                action: DCardAction(
                  child: _button(
                    ar ? 'إنشاء حساب' : 'Sign Up',
                    () => _notice('Sign up selected'),
                    variant: DButtonVariant.link,
                  ),
                ),
              ),
              DCardContent(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DField(
                        children: [
                          DFieldLabel(
                            focusNode: _emailFocus,
                            excludeSemantics: true,
                            style: const TextStyle(height: 1),
                            child: Text(ar ? 'البريد الإلكتروني' : 'Email'),
                          ),
                          DFieldControl(
                            label: ar ? 'البريد الإلكتروني' : 'Email',
                            required: true,
                            child: DInput(
                              controller: _email,
                              focusNode: _emailFocus,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _passwordFocus.requestFocus(),
                              hintText: 'm@example.com',
                              isRequired: true,
                              validator: (value) =>
                                  value != null && value.contains('@')
                                  ? null
                                  : 'Enter an email address',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      DField(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DFieldLabel(
                                focusNode: _passwordFocus,
                                excludeSemantics: true,
                                style: const TextStyle(height: 1),
                                child: Text(ar ? 'كلمة المرور' : 'Password'),
                              ),
                              _RecoveryLink(
                                label: ar
                                    ? 'نسيت كلمة المرور؟'
                                    : 'Forgot your password?',
                                onPressed: () =>
                                    _notice('Password recovery selected'),
                              ),
                            ],
                          ),
                          DFieldControl(
                            label: ar ? 'كلمة المرور' : 'Password',
                            required: true,
                            child: DInput(
                              controller: _password,
                              focusNode: _passwordFocus,
                              obscureText: true,
                              isRequired: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              validator: (value) =>
                                  value != null && value.isNotEmpty
                                  ? null
                                  : 'Enter a password',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(liveRegion: true, child: Text(_status)),
            ),
        ],
      ),
    );
  }
}

// The reference uses an inline anchor here, not a padded Button. Only its
// layout/text are adapted; the accepted DButton owns focus and activation.
class _RecoveryLink extends StatelessWidget {
  const _RecoveryLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DButton(
    onPressed: onPressed,
    isLink: true,
    variant: DButtonVariant.link,
    label: Text(label),
  );
}

class _Reports extends StatefulWidget {
  const _Reports();
  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  String _status = '';
  @override
  Widget build(BuildContext context) => _Frame(
    width: 320,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DCard(
          size: DCardSize.small,
          footer: DCardFooter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _button(
                  'Set up scheduled reports',
                  () => setState(() => _status = 'Weekly reports enabled'),
                  size: DButtonSize.small,
                ),
                const SizedBox(height: 8),
                _button(
                  "See what's new",
                  () => setState(
                    () =>
                        _status = 'Charts and delivery schedules are available',
                  ),
                  size: DButtonSize.small,
                  variant: DButtonVariant.outline,
                ),
              ],
            ),
          ),
          children: [
            const DCardHeader(
              title: DCardTitle(child: Text('Scheduled reports')),
              description: DCardDescription(
                child: Text('Weekly snapshots. No more manual exports.'),
              ),
            ),
            DCardContent(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (final text in [
                      'Choose a schedule (daily, or weekly).',
                      'Send to channels or specific teammates.',
                      'Include charts, tables, and key metrics.',
                    ])
                      Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              text == 'Include charts, tables, and key metrics.'
                              ? 0
                              : 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              // Lucide/Feather chevron-right. License retained
                              // in reference/empty/LICENSE.lucide.
                              child: SvgPicture.string(
                                '<svg xmlns="http://www.w3.org/2000/svg" '
                                'viewBox="0 0 24 24" fill="none" '
                                'stroke="currentColor" stroke-width="2" '
                                'stroke-linecap="round" stroke-linejoin="round">'
                                '<path d="m9 18 6-6-6-6"/></svg>',
                                width: 16,
                                height: 16,
                                excludeFromSemantics: true,
                                colorFilter: ColorFilter.mode(
                                  DTokens.of(context).mutedForeground,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(text)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_status.isNotEmpty) Text(_status),
      ],
    ),
  );
}

class _Terms extends StatefulWidget {
  const _Terms();
  @override
  State<_Terms> createState() => _TermsState();
}

class _TermsState extends State<_Terms> {
  String _status = '';
  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DCard(
          footer: DCardFooter(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(
                  'Decline',
                  () => setState(() => _status = 'Declined'),
                  variant: DButtonVariant.outline,
                ),
                _button('Accept', () => setState(() => _status = 'Accepted')),
              ],
            ),
          ),
          children: [
            const DCardHeader(
              title: DCardTitle(child: Text('Terms of Service')),
              description: DCardDescription(
                child: Text('Review the terms before accepting the agreement.'),
              ),
            ),
            DCardContent(
              edgeToEdge: true,
              joinNext: true,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 192),
                decoration: BoxDecoration(
                  color: DTokens.of(context).muted.withValues(alpha: .5),
                  border: Border(
                    top: BorderSide(color: DTokens.of(context).border),
                  ),
                ),
                child: const SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'These terms govern your use of the workspace, including access to shared documents, project files, and collaboration tools.',
                        style: TextStyle(height: 1.625),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'You are responsible for the content you upload and for ensuring that your team has the appropriate permissions to view or edit it.',
                        style: TextStyle(height: 1.625),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'We may update features or limits as the service evolves. When those changes materially affect your workflow, we will notify your workspace administrators.',
                        style: TextStyle(height: 1.625),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "By continuing, you agree to keep your account credentials secure and to follow your organization's acceptable use policies.",
                        style: TextStyle(height: 1.625),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_status.isNotEmpty) Text(_status),
      ],
    ),
  );
}

class _ImageCard extends StatefulWidget {
  const _ImageCard();
  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard> {
  bool _opened = false;
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness == Brightness.dark
        ? .4 * .65
        : .6 * .65;
    return _Frame(
      child: DCard(
        leading: DAspectRatio(
          ratio: 16 / 9,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix([
              .2126 * brightness,
              .7152 * brightness,
              .0722 * brightness,
              0,
              0,
              .2126 * brightness,
              .7152 * brightness,
              .0722 * brightness,
              0,
              0,
              .2126 * brightness,
              .7152 * brightness,
              .0722 * brightness,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: Image.asset(
              'packages/discourse_native/src/styleguide/assets/discourse.png',
              fit: BoxFit.cover,
              semanticLabel: 'Event cover',
            ),
          ),
        ),
        footer: DCardFooter(
          child: _button(
            'View Event',
            () => setState(() => _opened = !_opened),
          ),
        ),
        children: [
          const DCardHeader(
            title: DCardTitle(child: Text('Design systems meetup')),
            description: DCardDescription(
              child: Text(
                'A practical talk on component APIs, accessibility, and shipping faster.',
              ),
            ),
            action: DCardAction(
              child: DBadge(
                variant: DBadgeVariant.secondary,
                child: Text('Featured'),
              ),
            ),
          ),
          if (_opened)
            const DCardContent(
              child: Text('Local event details: Friday at 18:00.'),
            ),
        ],
      ),
    );
  }
}

class _States extends StatefulWidget {
  const _States();
  @override
  State<_States> createState() => _StatesState();
}

class _StatesState extends State<_States> {
  String _state = 'Loaded';
  int _count = 0;
  @override
  Widget build(BuildContext context) => _Frame(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final state in [
              'Loaded',
              'Disabled',
              'Selected',
              'Busy',
              'Error',
              'Empty',
            ])
              _button(
                state,
                () => setState(() => _state = state),
                variant: DButtonVariant.outline,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          selected: _state == 'Selected',
          child: DCard(
            children: [
              const DCardHeader(
                border: true,
                title: DCardTitle(child: Text('Community digest')),
              ),
              DCardContent(
                child: Text(switch (_state) {
                  'Empty' => 'No updates yet.',
                  'Error' => 'Could not load the digest. Retry below.',
                  'Busy' => 'Loading digest…',
                  'Selected' => 'Selected digest ✓',
                  'Disabled' => 'Digest unavailable for this account.',
                  _ => 'Three community updates. Opened $_count times.',
                }),
              ),
              if (_state == 'Busy')
                const DCardContent(
                  child: DSkeletonRegion(
                    semanticsLabel: 'Loading digest',
                    child: DSkeleton(height: 20),
                  ),
                ),
              if (_state != 'Empty')
                DCardContent(
                  child: _button(
                    _state == 'Error' ? 'Retry' : 'Open digest',
                    _state == 'Disabled' || _state == 'Busy'
                        ? null
                        : () => setState(() {
                            _state = 'Loaded';
                            _count++;
                          }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const DCard(
          children: [
            DCardContent(child: Text('Content only. No header or footer.')),
          ],
        ),
        const SizedBox(height: 16),
        const DCard(),
      ],
    ),
  );
}
