import 'package:discourse_native/src/theme/discourse_typography.dart';

import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final directionExamples = ComponentExamples(
  description:
      'Set the reading direction for a component or part of your interface.',
  status: ComponentStatus.implemented,
  notes:
      'Import discourse_ui.dart; no additional dependency is needed. '
      'DDirection wraps Flutter Directionality, so one provider drives native '
      'layout, text, semantics and DDirection.of(context), the useDirection '
      'equivalent. The reference wraps the whole app: pass '
      'MaterialApp.builder a DDirection above the Navigator, or scope a '
      'subtree. A null textDirection inherits the host locale instead of the '
      'reference LTR default; of requires an ancestor and maybeOf returns '
      'null without one. Direction changes preserve state and focus. Themes, '
      'text scale and motion remain owned by the host. Use directional '
      'padding/alignment; text is not translated and physical geometry or '
      'arbitrary icons are not mirrored. An OverlayPortal consumer such as '
      'DSelect or DDropdownMenu keeps its popup in the originating scope.',
  examples: [
    StyleguideExample(
      title: 'Card RTL',
      description:
          'The documented preview. Choose English, Arabic or Hebrew: the login '
          'card takes that language\'s direction while the selector stays LTR. '
          'Drafts, validation and focus survive the switch.',
      states: const [
        'Arabic default',
        'Hebrew',
        'English',
        'Fixed LTR selector',
        'Retained edits',
      ],
      code: _cardRtlCode,
      builder: (_) => const _CardRtl(),
    ),
    StyleguideExample(
      title: 'Live direction and editing',
      description:
          'Edit and save a name, then switch Inherit / LTR / RTL. Inherit follows '
          'the preview Right to left control. Tab between the actions and use '
          'Enter or Space to activate them. The draft, saved value and native '
          'focus survive direction and theme changes.',
      states: const ['Inherited', 'LTR', 'RTL', 'Keyboard', 'Live changes'],
      code:
          '''// App-wide, like <DirectionProvider direction="rtl"> around the app:
// MaterialApp(builder: (context, child) =>
//   DDirection(textDirection: TextDirection.rtl, child: child!))

// In a State: TextDirection? direction; null means inherit.
Column(
  children: [
    DToggleGroup<String>(
      values: [scope],
      allowEmptySelection: false,
      variant: DToggleVariant.outline,
      size: DToggleSize.small,
      items: const [
        DToggleGroupItem(value: 'inherit', child: Text('Inherit')),
        DToggleGroupItem(value: 'ltr', child: Text('LTR')),
        DToggleGroupItem(value: 'rtl', child: Text('RTL')),
      ],
      onChanged: (values) => setState(() => scope = values.single),
    ),
    // Keep the editor mounted when the selected direction changes.
    DDirection(
      textDirection: direction,
      child: Builder(builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current direction: \${DDirection.of(context).name.toUpperCase()}'),
          DInput(controller: name, labelText: 'Display name'),
        ],
      )),
    ),
  ],
)''',
      builder: (_) => const _LiveDirectionPreview(),
    ),
    StyleguideExample(
      title: 'Nested overrides and fixed content',
      description:
          'An RTL section contains an LTR URL island. Its inner inherited scope '
          'reads LTR; a sibling resumes RTL. Changing the preview direction does '
          'not override these explicit boundaries.',
      states: const ['Nested', 'Nearest lookup', 'Fixed LTR content'],
      code: '''DDirection(
  textDirection: TextDirection.rtl,
  child: Column(children: [
    const Text('مرحبًا بك'),
    DDirection(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        const SelectableText('https://example.com/topics/42'),
        DDirection(child: Builder(builder: (context) =>
          Text('Inherited: \${DDirection.of(context).name}'),
        )),
      ]),
    ),
    const Text('العودة إلى القسم'),
  ]),
)''',
      builder: (_) => const _NestedDirectionPreview(),
    ),
    StyleguideExample(
      title: 'Inherited direction in a dropdown menu',
      description:
          'The menu inherits preview direction and theme, including host '
          'updates while open. Arrow keys navigate; '
          'Enter selects; Escape or an outside click dismisses. DDropdownMenu owns '
          'positioning, scrolling, dismissal and focus restoration.',
      states: const ['Live overlay', 'Keyboard', 'Theme changes'],
      code: '''// Own menuFocus = FocusNode() in State and dispose it there.
DDirection(
  child: DDropdownMenu(
    content: DDropdownMenuContent(children: [
      Builder(builder: (context) => DDropdownMenuItem(
        onPressed: select,
        child: Text(
          'Menu direction: \${DDirection.of(context).name.toUpperCase()}',
        ),
      )),
    ]),
    child: DDropdownMenuTrigger(
      focusNode: menuFocus,
      builder: (context, menu) => DButton(
        focusNode: menu.focusNode,
        label: const Text('Open direction menu'),
        variant: DButtonVariant.outline,
        hasPopup: true,
        expanded: menu.open,
        onPressed: menu.toggle,
      ),
    ),
  ),
)''',
      builder: (_) => const _DirectionMenuPreview(),
    ),
  ],
);

const _cardRtlCode =
    '''// In a State: var language = 'ar'; translations map a language
// to its direction and strings, like the reference useTranslation.
final t = translations[language]!;
Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
  // The selector keeps dir="ltr" on its trigger and popup.
  Align(alignment: AlignmentDirectional.centerEnd, child: DDirection(
    textDirection: TextDirection.ltr,
    child: DSelect<String>(
      value: language,
      size: DSelectSize.small,
      width: 144,
      semanticLabel: 'Language',
      entries: const [
        DSelectOption(value: 'en', label: 'English', child: Text('English')),
        DSelectOption(value: 'ar', label: 'Arabic (العربية)',
          child: Text('Arabic (العربية)')),
        DSelectOption(value: 'he', label: 'Hebrew (עברית)',
          child: Text('Hebrew (עברית)')),
      ],
      onChanged: (value) => setState(() => language = value!),
    ),
  )),
  const SizedBox(height: 16),
  DDirection(textDirection: t.dir, child: DCard(children: [
    DCardHeader(
      title: DCardTitle(child: Text(t.title)),
      description: DCardDescription(child: Text(t.description)),
      action: DCardAction(child: DButton(onPressed: signUp,
        variant: DButtonVariant.link, label: Text(t.signUp))),
    ),
    DCardContent(child: Form(key: formKey, child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DField(children: [
        DFieldLabel(focusNode: emailFocus, excludeSemantics: true,
          style: TextStyle(height: 1), child: Text(t.email)),
        DFieldControl(label: t.email, required: true, child: DInput(
          focusNode: emailFocus, keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => passwordFocus.requestFocus(),
          hintText: t.emailPlaceholder, isRequired: true,
          validator: validateEmail)),
      ]),
      SizedBox(height: 24),
      DField(children: [
        Wrap(alignment: WrapAlignment.spaceBetween, children: [
          DFieldLabel(focusNode: passwordFocus, excludeSemantics: true,
            style: TextStyle(height: 1), child: Text(t.password)),
          // Inline text bounds, no padding; DButton retains native activation.
          forgotPasswordLink,
        ]),
        DFieldControl(label: t.password, required: true, child: DInput(
          focusNode: passwordFocus, obscureText: true, isRequired: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(), validator: validatePassword)),
      ]),
    ]))),
  ], footer: DCardFooter(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DButton(onPressed: submit, variant: DButtonVariant.primary,
      label: Text(t.login)),
    SizedBox(height: 8),
    DButton(onPressed: google, variant: DButtonVariant.outline,
      label: Text(t.loginWithGoogle)),
  ])))),
])''';

/// One language of the reference `Translations` record: its direction and
/// the login card strings.
class _Translation {
  const _Translation({
    required this.dir,
    required this.title,
    required this.description,
    required this.signUp,
    required this.email,
    required this.emailPlaceholder,
    required this.password,
    required this.forgotPassword,
    required this.login,
    required this.loginWithGoogle,
  });

  final TextDirection dir;
  final String title;
  final String description;
  final String signUp;
  final String email;
  final String emailPlaceholder;
  final String password;
  final String forgotPassword;
  final String login;
  final String loginWithGoogle;
}

const _translations = <String, _Translation>{
  'en': _Translation(
    dir: TextDirection.ltr,
    title: 'Login to your account',
    description: 'Enter your email below to login to your account',
    signUp: 'Sign Up',
    email: 'Email',
    emailPlaceholder: 'm@example.com',
    password: 'Password',
    forgotPassword: 'Forgot your password?',
    login: 'Login',
    loginWithGoogle: 'Login with Google',
  ),
  'ar': _Translation(
    dir: TextDirection.rtl,
    title: 'تسجيل الدخول إلى حسابك',
    description: 'أدخل بريدك الإلكتروني أدناه لتسجيل الدخول إلى حسابك',
    signUp: 'إنشاء حساب',
    email: 'البريد الإلكتروني',
    emailPlaceholder: 'm@example.com',
    password: 'كلمة المرور',
    forgotPassword: 'نسيت كلمة المرور؟',
    login: 'تسجيل الدخول',
    loginWithGoogle: 'تسجيل الدخول باستخدام Google',
  ),
  'he': _Translation(
    dir: TextDirection.rtl,
    title: 'התחבר לחשבון שלך',
    description: 'הזן את האימייל שלך למטה כדי להתחבר לחשבון שלך',
    signUp: 'הירשם',
    email: 'אימייל',
    emailPlaceholder: 'm@example.com',
    password: 'סיסמה',
    forgotPassword: 'שכחת את הסיסמה?',
    login: 'התחבר',
    loginWithGoogle: 'התחבר עם Google',
  ),
};

/// The reference language selector options, in its declaration order.
const _languageOptions = [
  ('en', 'English'),
  ('ar', 'Arabic (العربية)'),
  ('he', 'Hebrew (עברית)'),
];

class _CardRtl extends StatefulWidget {
  const _CardRtl();

  @override
  State<_CardRtl> createState() => _CardRtlState();
}

class _CardRtlState extends State<_CardRtl> {
  String _language = 'ar';
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final translation = _translations[_language]!;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              // The reference selector sets dir="ltr" on its trigger and
              // popup; DSelect's OverlayPortal keeps the popup in this scope.
              child: DDirection(
                textDirection: TextDirection.ltr,
                child: DSelect<String>(
                  value: _language,
                  size: DSelectSize.small,
                  width: 144,
                  semanticLabel: 'Language',
                  entries: [
                    for (final (value, label) in _languageOptions)
                      DSelectOption(
                        value: value,
                        label: label,
                        child: Text(label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _language = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: DSpacing.lg),
            DDirection(
              textDirection: translation.dir,
              child: _LoginCard(
                strings: translation,
                onNotice: (value) => setState(() => _status = value),
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DSpacing.sm),
                child: Semantics(liveRegion: true, child: Text(_status)),
              ),
          ],
        ),
      ),
    );
  }
}

/// The reference CardRtl composition. Strings change with the language while
/// the form, controllers and focus nodes stay mounted.
class _LoginCard extends StatefulWidget {
  const _LoginCard({required this.strings, required this.onNotice});

  final _Translation strings;
  final ValueChanged<String> onNotice;

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode(debugLabel: 'Login email');
  final _passwordFocus = FocusNode(debugLabel: 'Login password');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() => widget.onNotice(
    _form.currentState!.validate() ? 'Signed in locally' : '',
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.strings;
    return DCard(
      footer: DCardFooter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _wrappingButton(t.login, _submit),
            const SizedBox(height: DSpacing.sm),
            _wrappingButton(
              t.loginWithGoogle,
              () => widget.onNotice('Google login selected'),
              variant: DButtonVariant.outline,
            ),
          ],
        ),
      ),
      children: [
        DCardHeader(
          title: DCardTitle(child: Text(t.title)),
          description: DCardDescription(child: Text(t.description)),
          action: DCardAction(
            child: _wrappingButton(
              t.signUp,
              () => widget.onNotice('Sign up selected'),
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
                      child: Text(t.email),
                    ),
                    DFieldControl(
                      label: t.email,
                      required: true,
                      child: DInput(
                        controller: _email,
                        focusNode: _emailFocus,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        hintText: t.emailPlaceholder,
                        isRequired: true,
                        validator: (value) =>
                            value != null && value.contains('@')
                            ? null
                            : 'Enter an email address',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DSpacing.xl),
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
                          child: Text(t.password),
                        ),
                        _InlineLink(
                          label: t.forgotPassword,
                          onPressed: () =>
                              widget.onNotice('Password recovery selected'),
                        ),
                      ],
                    ),
                    DFieldControl(
                      label: t.password,
                      required: true,
                      child: DInput(
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: true,
                        isRequired: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        validator: (value) => value != null && value.isNotEmpty
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
    );
  }
}

// DButton labels default to one line; translated labels must wrap at narrow
// widths and large text instead of overflowing the stretched footer.
Widget _wrappingButton(
  String text,
  VoidCallback onPressed, {
  DButtonVariant variant = DButtonVariant.primary,
}) => DButton(
  onPressed: onPressed,
  variant: variant,
  label: Builder(
    builder: (context) => DefaultTextStyle(
      style: DefaultTextStyle.of(context).style,
      child: Text(text),
    ),
  ),
);

// The reference uses an inline anchor here, not a padded Button. Only its
// layout/text are adapted; the accepted DButton owns focus and activation.
class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.onPressed});

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

enum _Scope {
  inherit('Inherit', null),
  ltr('LTR', TextDirection.ltr),
  rtl('RTL', TextDirection.rtl);

  const _Scope(this.label, this.direction);

  final String label;

  /// Null inherits the preview provider.
  final TextDirection? direction;
}

class _LiveDirectionPreview extends StatefulWidget {
  const _LiveDirectionPreview();

  @override
  State<_LiveDirectionPreview> createState() => _LiveDirectionPreviewState();
}

class _LiveDirectionPreviewState extends State<_LiveDirectionPreview> {
  _Scope _scope = _Scope.inherit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DToggleGroup<_Scope>(
        values: [_scope],
        allowEmptySelection: false,
        variant: DToggleVariant.outline,
        size: DToggleSize.small,
        semanticLabel: 'Direction',
        items: [
          for (final scope in _Scope.values)
            DToggleGroupItem(value: scope, child: Text(scope.label)),
        ],
        onChanged: (values) {
          if (values.isNotEmpty) setState(() => _scope = values.single);
        },
      ),
      const SizedBox(height: DSpacing.md),
      DDirection(
        textDirection: _scope.direction,
        child: const _DirectionEditor(),
      ),
    ],
  );
}

class _DirectionEditor extends StatefulWidget {
  const _DirectionEditor();

  @override
  State<_DirectionEditor> createState() => _DirectionEditorState();
}

class _DirectionEditorState extends State<_DirectionEditor> {
  final _name = TextEditingController(text: 'Ada');
  String? _saved;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DirectionSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DirectionReadout(label: 'Current direction'),
        const SizedBox(height: DSpacing.md),
        DInput(controller: _name, labelText: 'Display name'),
        const SizedBox(height: DSpacing.md),
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              label: const Text('Save locally'),
              variant: DButtonVariant.primary,
              onPressed: () => setState(() => _saved = _name.text),
            ),
            DButton(
              label: const Text('Clear'),
              variant: DButtonVariant.outline,
              onPressed: () => setState(() {
                _name.clear();
                _saved = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: DSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(_saved == null ? 'No saved name' : 'Saved: $_saved'),
        ),
      ],
    ),
  );
}

class _NestedDirectionPreview extends StatelessWidget {
  const _NestedDirectionPreview();

  @override
  Widget build(BuildContext context) => const DDirection(
    textDirection: TextDirection.rtl,
    child: _DirectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DirectionReadout(label: 'Outer section'),
          Text('مرحبًا بك'),
          SizedBox(height: DSpacing.md),
          DDirection(
            textDirection: TextDirection.ltr,
            child: _DirectionSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DirectionReadout(label: 'URL island'),
                  SelectableText('https://example.com/topics/42'),
                  SizedBox(height: DSpacing.sm),
                  DDirection(
                    child: _DirectionReadout(label: 'Inherited island'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: DSpacing.md),
          _DirectionReadout(label: 'Outer sibling'),
        ],
      ),
    ),
  );
}

class _DirectionMenuPreview extends StatefulWidget {
  const _DirectionMenuPreview();

  @override
  State<_DirectionMenuPreview> createState() => _DirectionMenuPreviewState();
}

class _DirectionMenuPreviewState extends State<_DirectionMenuPreview> {
  final _focusNode = FocusNode(debugLabel: 'Direction menu trigger');
  String _selection = 'No selection';

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDirection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DirectionReadout(label: 'Inherited direction'),
        const SizedBox(height: DSpacing.md),
        DDropdownMenu(
          content: DDropdownMenuContent(
            semanticLabel: 'Direction menu',
            children: [
              Builder(
                builder: (context) {
                  final direction = DDirection.of(context).name.toUpperCase();
                  return DDropdownMenuItem(
                    onPressed: () => setState(() => _selection = direction),
                    child: Text('Menu direction: $direction'),
                  );
                },
              ),
              DDropdownMenuItem(
                onPressed: () => setState(() => _selection = 'Second action'),
                child: const Text('Second action'),
              ),
            ],
          ),
          child: DDropdownMenuTrigger(
            focusNode: _focusNode,
            builder: (context, menu) => DButton(
              focusNode: menu.focusNode,
              label: const Text('Open direction menu'),
              variant: DButtonVariant.outline,
              hasPopup: true,
              expanded: menu.open,
              onPressed: menu.toggle,
            ),
          ),
        ),
        const SizedBox(height: DSpacing.sm),
        Semantics(liveRegion: true, child: Text('Selected: $_selection')),
      ],
    ),
  );
}

class _DirectionReadout extends StatelessWidget {
  const _DirectionReadout({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        // A matchTextDirection glyph: it points along the reading direction.
        const Icon(Icons.arrow_forward),
        const SizedBox(width: DSpacing.sm),
        Expanded(
          child: Text('$label: ${DDirection.of(context).name.toUpperCase()}'),
        ),
      ],
    ),
  );
}

class _DirectionSurface extends StatelessWidget {
  const _DirectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: tokens.borderRadius,
      ),
      child: child,
    );
  }
}
