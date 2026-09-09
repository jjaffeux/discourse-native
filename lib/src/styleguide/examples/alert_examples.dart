import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final alertExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A compact callout for user attention.',
  notes:
      'Base-nova Alert, Title, Description and Action. Reference and native review passed. '
      'The only Alert variants are normal and destructive; outline/xs belong to Button. '
      'Actions use the completed DButton owner with extra-small reference geometry and native hit bounds. '
      'Wide actions move below text at narrow widths or large text. '
      'Announcements use a platform live region without moving focus; static history can opt out. '
      'Paragraphs and links compose ordinary Flutter children; paragraph gaps are 16px. '
      'Icons reproduce the Lucide SVG paths without the app icon glyph inset.',
  examples: [
    StyleguideExample(
      title: 'Basic',
      description: 'Original basic example at maximum width 448.',
      code:
          r'''Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: DAlert(icon: const AlertExampleIcon('circle-check'), title: DAlertTitle(child: Text('Account updated successfully')), description: DAlertDescription(child: Text('Your profile information has been saved. Changes will be reflected immediately.')))))''',
      builder: (context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: const DAlert(
            icon: AlertExampleIcon('circle-check'),
            title: DAlertTitle(child: Text('Account updated successfully')),
            description: DAlertDescription(
              child: Text(
                'Your profile information has been saved. Changes will be reflected immediately.',
              ),
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Demo',
      description: 'The two original success and information callouts.',
      code:
          r'''Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: Column(mainAxisSize: MainAxisSize.min, children: [DAlert(icon: const AlertExampleIcon('circle-check'), title: DAlertTitle(child: Text('Payment successful')), description: DAlertDescription(child: Text(r'Your payment of $29.99 has been processed. A receipt has been sent to your email address.'))), const SizedBox(height: 16), DAlert(icon: const AlertExampleIcon('info'), title: DAlertTitle(child: Text('New feature available')), description: DAlertDescription(child: Text('We have added dark mode support. You can enable it in your account settings.')))])))''',
      builder: (context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DAlert(
                icon: AlertExampleIcon('circle-check'),
                title: DAlertTitle(child: Text('Payment successful')),
                description: DAlertDescription(
                  child: Text(
                    r'Your payment of $29.99 has been processed. A receipt has been sent to your email address.',
                  ),
                ),
              ),
              SizedBox(height: 16),
              DAlert(
                icon: AlertExampleIcon('info'),
                title: DAlertTitle(child: Text('New feature available')),
                description: DAlertDescription(
                  child: Text(
                    'We have added dark mode support. You can enable it in your account settings.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Destructive',
      description:
          'Error colors preserve the host palette; icon and text identify the error.',
      code:
          r'''Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: DAlert(variant: DAlertVariant.destructive, icon: const AlertExampleIcon('circle-alert'), title: DAlertTitle(child: Text('Payment failed')), description: DAlertDescription(child: Text('Your payment could not be processed. Please check your payment method and try again.')))))''',
      builder: (context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: const DAlert(
            variant: DAlertVariant.destructive,
            icon: AlertExampleIcon('circle-alert'),
            title: DAlertTitle(child: Text('Payment failed')),
            description: DAlertDescription(
              child: Text(
                'Your payment could not be processed. Please check your payment method and try again.',
              ),
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Action',
      description:
          'Enable toggles local state; Tab then Enter also activates the button.',
      code: r'''// Inside a StatefulWidget; enabled starts false.
DAlert(
  title: DAlertTitle(child: Text(enabled ? 'Dark mode enabled' : 'Dark mode is now available')),
  description: const DAlertDescription(child: Text('Enable it under your profile settings to get started.')),
  action: DAlertAction(child: DButton(size: DButtonSize.extraSmall,
    label: Text(enabled ? 'Disable' : 'Enable'),
    onPressed: () => setState(() => enabled = !enabled))),
)''',
      builder: (context) => const _ActionExample(),
    ),
    StyleguideExample(
      title: 'Custom Colors',
      description:
          'Original amber light/dark custom classes; description keeps the muted token as in the source.',
      code: r'''final dark = Theme.of(context).brightness == Brightness.dark;
DAlert(
  backgroundColor: Color(dark ? 0xff451a03 : 0xfffffbeb),
  borderColor: Color(dark ? 0xff78350f : 0xfffde68a),
  foregroundColor: Color(dark ? 0xfffffbeb : 0xff78350f),
  icon: const AlertExampleIcon('triangle-alert'),
  title: const DAlertTitle(child: Text('Your subscription will expire in 3 days.')),
  description: const DAlertDescription(child: Text('Renew now to avoid service interruption or upgrade to a paid plan to continue using the service.')),
)''',
      builder: (context) => const _CustomColors(),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Original Arabic translations and mirrored icon placement.',
      code:
          r'''Directionality(textDirection: TextDirection.rtl, child: Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: Column(mainAxisSize: MainAxisSize.min, children: [DAlert(icon: const AlertExampleIcon('circle-check'), title: DAlertTitle(child: Text('تم الدفع بنجاح')), description: DAlertDescription(child: Text('تمت معالجة دفعتك البالغة 29.99 دولارًا. تم إرسال إيصال إلى عنوان بريدك الإلكتروني.'))), const SizedBox(height: 16), DAlert(icon: const AlertExampleIcon('info'), title: DAlertTitle(child: Text('ميزة جديدة متاحة')), description: DAlertDescription(child: Text('لقد أضفنا دعم الوضع الداكن. يمكنك تفعيله في إعدادات حسابك.')))]))))''',
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DAlert(
                  icon: AlertExampleIcon('circle-check'),
                  title: DAlertTitle(child: Text('تم الدفع بنجاح')),
                  description: DAlertDescription(
                    child: Text(
                      'تمت معالجة دفعتك البالغة 29.99 دولارًا. تم إرسال إيصال إلى عنوان بريدك الإلكتروني.',
                    ),
                  ),
                ),
                SizedBox(height: 16),
                DAlert(
                  icon: AlertExampleIcon('info'),
                  title: DAlertTitle(child: Text('ميزة جديدة متاحة')),
                  description: DAlertDescription(
                    child: Text(
                      'لقد أضفنا دعم الوضع الداكن. يمكنك تفعيله في إعدادات حسابك.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Description only',
      description: 'A static notice opts out of live announcements.',
      code:
          r'''Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: const DAlert(liveRegion: false, description: DAlertDescription(child: Text('This information remains available for later reference.')))))''',
      builder: (context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: const DAlert(
            liveRegion: false,
            description: DAlertDescription(
              child: Text(
                'This information remains available for later reference.',
              ),
            ),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Rich content',
      description:
          'Caller-owned paragraphs and a keyboard-accessible action compose inside the description.',
      code:
          r'''Align(alignment: AlignmentDirectional.topStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: DAlert(title: const DAlertTitle(child: Text('Before you continue')), description: DAlertDescription(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Keep a copy of your recovery codes.'), const SizedBox(height: 16), const Text('You can regenerate them in your account settings.'), DButton(label: const Text('Copy example code'), variant: DButtonVariant.link, onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Example code copied locally'))))])))))''',
      builder: (context) => Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: DAlert(
            title: const DAlertTitle(child: Text('Before you continue')),
            description: DAlertDescription(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Keep a copy of your recovery codes.'),
                  const SizedBox(height: 16),
                  const Text(
                    'You can regenerate them in your account settings.',
                  ),
                  DButton(
                    label: const Text('Copy example code'),
                    variant: DButtonVariant.link,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Example code copied locally'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ],
);

class _ActionExample extends StatefulWidget {
  const _ActionExample();
  @override
  State<_ActionExample> createState() => _ActionExampleState();
}

class _ActionExampleState extends State<_ActionExample> {
  bool enabled = false;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 448),
    child: DAlert(
      title: DAlertTitle(
        child: Text(
          enabled ? 'Dark mode enabled' : 'Dark mode is now available',
        ),
      ),
      description: const DAlertDescription(
        child: Text('Enable it under your profile settings to get started.'),
      ),
      action: DAlertAction(
        child: DButton(
          size: DButtonSize.extraSmall,
          label: Text(enabled ? 'Disable' : 'Enable'),
          onPressed: () => setState(() => enabled = !enabled),
        ),
      ),
    ),
  );
}

class _CustomColors extends StatelessWidget {
  const _CustomColors();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 448),
      child: DAlert(
        backgroundColor: Color(dark ? 0xff451a03 : 0xfffffbeb),
        borderColor: Color(dark ? 0xff78350f : 0xfffde68a),
        foregroundColor: Color(dark ? 0xfffffbeb : 0xff78350f),
        icon: const AlertExampleIcon('triangle-alert'),
        title: const DAlertTitle(
          child: Text('Your subscription will expire in 3 days.'),
        ),
        description: const DAlertDescription(
          child: Text(
            'Renew now to avoid service interruption or upgrade to a paid plan to continue using the service.',
          ),
        ),
      ),
    );
  }
}

/// Lucide artwork for the reference examples (ISC; see reference manifest).
class AlertExampleIcon extends StatelessWidget {
  const AlertExampleIcon(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _artwork[name]!,
    width: 16,
    height: 16,
    colorFilter: ColorFilter.mode(
      IconTheme.of(context).color!,
      BlendMode.srcIn,
    ),
    excludeFromSemantics: true,
  );
}

const _artwork = <String, String>{
  'circle-check': r'''<svg
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
>
  <circle cx="12" cy="12" r="10" />
  <path d="m16 9-5.5 5.5L8 12" />
</svg>
''',
  'info': r'''<svg
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
>
  <circle cx="12" cy="12" r="10" />
  <path d="M12 16v-4" />
  <path d="M12 8h.01" />
</svg>
''',
  'circle-alert': r'''<svg
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
>
  <circle cx="12" cy="12" r="10" />
  <line x1="12" x2="12" y1="8" y2="12" />
  <line x1="12" x2="12.01" y1="16" y2="16" />
</svg>
''',
  'triangle-alert': r'''<svg
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
>
  <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3" />
  <path d="M12 9v4" />
  <path d="M12 17h.01" />
</svg>
''',
};
