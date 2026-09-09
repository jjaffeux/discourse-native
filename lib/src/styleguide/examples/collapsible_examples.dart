import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final collapsibleExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A button that expands or collapses a panel.',
  notes:
      'Root, trigger and content are unstyled Base UI parts. Use open and '
      'onOpenChange for controlled state, or defaultOpen for local state. '
      'Keep mounted retains editors and Form fields; hidden content cannot take '
      'focus or expose semantics. Animation is opt-in and respects reduced motion. '
      'Triggers accept passive children, not nested buttons. Button variants are '
      'example composition, not Collapsible props. Settings uses DInput editing '
      'inside accepted DField composition; the File Tree composes its '
      'Explorer/Outline layers with controlled DTabs. DInput remains the sole '
      'editing and Form owner. Official rendered and native review passed.',
  examples: [
    StyleguideExample(
      title: 'Order details',
      description:
          'Controlled frozen order example, 350px wide. Toggle details.',
      code: _orderCode,
      builder: (_) => const _Order(),
    ),
    StyleguideExample(
      title: 'Basic',
      description:
          'Product details in a 384px Card. Learn More updates local feedback.',
      code: '''DCollapsible(child: Column(children: [
  DCollapsibleTrigger(child: Text('Product details')),
  DCollapsibleContent(child: Text('Additional content')),
]))''',
      builder: (_) => const _Basic(),
    ),
    StyleguideExample(
      title: 'Settings Panel',
      description:
          '320px Card. Reveal two more radius fields; edits survive closing.',
      code: '''DCollapsible(child: Column(children: [
  DCollapsibleTrigger(child: Text('More radius settings')),
  DCollapsibleContent(keepMounted: true,
    child: DInput(initialValue: '0')),
]))''',
      builder: (_) => const _Settings(),
    ),
    StyleguideExample(
      title: 'File Tree',
      description:
          'Independent nested folders. Tab visits visible entries; Enter/Space toggles folders.',
      code: '''DCollapsible(child: Column(children: [
  DCollapsibleTrigger(child: Text('components')),
  DCollapsibleContent(child: Padding(
    padding: EdgeInsetsDirectional.only(start: 20, top: 4),
    child: DCollapsible(child: Column(children: [
      DCollapsibleTrigger(child: Text('ui')),
      DCollapsibleContent(child: Text('button.tsx')),
    ])),
  )),
]))''',
      builder: (_) => const _FileTree(),
    ),
    StyleguideExample(
      title: 'RTL',
      description: 'Frozen Arabic order composition.',
      code:
          "Directionality(textDirection: TextDirection.rtl, child: orderDetails)",
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _Order(arabic: true),
      ),
    ),
    StyleguideExample(
      title: 'Lifecycle and disabled',
      description:
          'Compare lazy disposal and retained edits; toggle animation and disabled state. Form validation/reset is owned by the enclosing Form.',
      code: '''DCollapsible(defaultOpen: true, disabled: disabled,
  child: Column(children: [
    DCollapsibleTrigger(child: Text('Editor')),
    DCollapsibleContent(keepMounted: true,
      duration: Duration(milliseconds: 200),
      child: DInput(initialValue: 'Retained draft')),
  ]))''',
      builder: (_) => const _Lifecycle(),
    ),
  ],
);

const _orderCode = '''bool open = false; // State owned by a StatefulWidget.
DCollapsible(open: open, onOpenChange: (value) => setState(() => open = value),
  child: Column(children: [
    DCollapsibleTrigger(semanticLabel: 'Toggle details', child: Text('Order #4189')),
    Text('Status: Shipped'),
    DCollapsibleContent(child: Text('Shipping address: 100 Market St, San Francisco')),
  ]))''';

TextStyle _text(BuildContext context, {FontWeight weight = FontWeight.w400}) =>
    Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      height: 20 / 14,
      letterSpacing: 0,
      fontWeight: weight,
      color: DTokens.of(context).foreground,
    );

class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.width = 350});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: DefaultTextStyle(style: _text(context), child: child),
    ),
  );
}

// Official Lucide SVGs; source URLs and hashes are in the evidence manifest.
class _Glyph extends StatelessWidget {
  const _Glyph(this.kind, {this.size = 16});
  final String kind;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _glyphs[kind]!,
    width: size,
    height: size,
    excludeFromSemantics: true,
    matchTextDirection: kind == 'right',
    colorFilter: ColorFilter.mode(
      DTokens.of(context).foreground,
      BlendMode.srcIn,
    ),
  );
}

final _glyphs = <String, String>{
  'folder': '''<svg
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
  <path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" />
</svg>
''',
  'file': '''<svg
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
  <path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z" />
  <path d="M14 2v5a1 1 0 0 0 1 1h5" />
</svg>
''',
  'maximize': '''<svg
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
  <path d="M8 3H5a2 2 0 0 0-2 2v3" />
  <path d="M21 8V5a2 2 0 0 0-2-2h-3" />
  <path d="M3 16v3a2 2 0 0 0 2 2h3" />
  <path d="M16 21h3a2 2 0 0 0 2-2v-3" />
</svg>
''',
  'minimize': '''<svg
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
  <path d="M8 3v3a2 2 0 0 1-2 2H3" />
  <path d="M21 8h-3a2 2 0 0 1-2-2V3" />
  <path d="M3 16h3a2 2 0 0 1 2 2v3" />
  <path d="M16 21v-3a2 2 0 0 1 2-2h3" />
</svg>
''',
  'toggle': '''<svg
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
  <path d="m7 15 5 5 5-5" />
  <path d="m7 9 5-5 5 5" />
</svg>
''',
  'right': '''<svg
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
  <path d="m9 18 6-6-6-6" />
</svg>
''',
  'down': '''<svg
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
  <path d="m6 9 6 6 6-6" />
</svg>
''',
  'up': '''<svg
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
  <path d="m18 15-6-6-6 6" />
</svg>
''',
};

class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.label,
    this.icon = 'down',
    this.iconOnly = false,
    this.outlined = false,
    this.small = false,
    this.folder = false,
  });
  final String label;
  final String icon;
  final bool iconOnly, outlined, small, folder;
  @override
  Widget build(BuildContext context) => DCollapsibleTrigger(
    semanticLabel: iconOnly ? label : null,
    builder: (context, state) {
      final t = DTokens.of(context);
      final touch =
          Theme.of(context).platform == TargetPlatform.iOS ||
          Theme.of(context).platform == TargetPlatform.android;
      return Opacity(
        opacity: state.disabled ? 0.5 : 1,
        child: Container(
          constraints: BoxConstraints(
            minHeight: touch
                ? 48
                : small
                ? 28
                : 32,
            minWidth: iconOnly ? (touch ? 48 : 32) : 0,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: iconOnly ? 8 : 10,
            vertical: small ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: state.open
                ? t.muted
                : state.hovered || state.pressed
                ? (Theme.of(context).brightness == Brightness.dark && !outlined
                      ? t.muted.withValues(alpha: t.muted.a * 0.5)
                      : t.muted)
                : outlined
                ? (Theme.of(context).brightness == Brightness.dark
                      ? t.colors.outlineVariant.withValues(
                          alpha: t.colors.outlineVariant.a * 0.3,
                        )
                      : t.background)
                : null,
            borderRadius: BorderRadius.circular(
              small ? (t.radius * 0.8).clamp(0, 12) : t.radius,
            ),
            border: outlined
                ? Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? t.colors.outlineVariant
                        : t.border,
                  )
                : null,
          ),
          child: iconOnly
              ? Center(
                  child: _Glyph(
                    icon == 'maximize' && state.open ? 'minimize' : icon,
                  ),
                )
              : Row(
                  children: [
                    if (folder) ...[
                      _Glyph(state.open ? 'down' : 'right', size: 14),
                      const SizedBox(width: 4),
                      const _Glyph('folder', size: 14),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: _text(context, weight: FontWeight.w500).copyWith(
                          fontSize: small ? 12.8 : 14,
                          height: small ? 20 / 12.8 : 20 / 14,
                        ),
                      ),
                    ),
                    if (!folder) ...[
                      const SizedBox(width: 8),
                      _Glyph(state.open ? 'up' : icon),
                    ],
                  ],
                ),
        ),
      );
    },
  );
}

class _Order extends StatefulWidget {
  const _Order({this.arabic = false});
  final bool arabic;
  @override
  State<_Order> createState() => _OrderState();
}

class _OrderState extends State<_Order> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.arabic;
    Widget box(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: DTokens.of(context).border),
        borderRadius: BorderRadius.circular(DTokens.of(context).radius * 0.8),
      ),
      child: child,
    );
    Widget muted(String text) => Text(
      text,
      style: _text(
        context,
      ).copyWith(color: DTokens.of(context).mutedForeground),
    );
    Widget detail(String title, String body) => box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _text(context, weight: FontWeight.w500)),
          muted(body),
        ],
      ),
    );
    return _Frame(
      child: DCollapsible(
        open: _open,
        onOpenChange: (v) => setState(() => _open = v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      a ? 'الطلب #4189' : 'Order #4189',
                      style: _text(context, weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const _Trigger(
                    label: 'Toggle details',
                    icon: 'toggle',
                    iconOnly: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            box(
              Row(
                children: [
                  Expanded(child: muted(a ? 'الحالة' : 'Status')),
                  Flexible(
                    child: Text(
                      a ? 'تم الشحن' : 'Shipped',
                      style: _text(context, weight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            DCollapsibleContent(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  spacing: 8,
                  children: [
                    detail(
                      a ? 'عنوان الشحن' : 'Shipping address',
                      '100 Market St, San Francisco',
                    ),
                    detail(
                      a ? 'العناصر' : 'Items',
                      a ? '2x سماعات الاستوديو' : '2x Studio Headphones',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Basic extends StatefulWidget {
  const _Basic();
  @override
  State<_Basic> createState() => _BasicState();
}

class _BasicState extends State<_Basic> {
  bool learned = false;
  @override
  Widget build(BuildContext context) => _Frame(
    width: 384,
    child: DCard(
      children: [
        DCardContent(
          child: DCollapsible(
            child: Builder(
              builder: (context) => DecoratedBox(
                decoration: BoxDecoration(
                  color: DCollapsible.isOpenOf(context)
                      ? DTokens.of(context).muted
                      : null,
                  borderRadius: BorderRadius.circular(
                    DTokens.of(context).radius * 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Trigger(label: 'Product details'),
                    DCollapsibleContent(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            const Text(
                              'This panel can be expanded or collapsed to reveal additional content.',
                            ),
                            DButton(
                              size: DButtonSize.extraSmall,
                              label: const Text('Learn More'),
                              onPressed: () => setState(() => learned = true),
                            ),
                            if (learned)
                              const Text(
                                'Product details are available in this local example.',
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Settings extends StatelessWidget {
  const _Settings();
  Widget fields(String a, String b) => Row(
    spacing: 8,
    children: [
      for (final label in [a, b])
        Expanded(
          child: DInput(
            initialValue: '0',
            keyboardType: TextInputType.number,
            labelText: label,
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => _Frame(
    width: 320,
    child: DCard(
      size: DCardSize.small,
      children: [
        const DCardHeader(
          title: DCardTitle(child: Text('Radius')),
          description: DCardDescription(
            child: Text('Set the corner radius of the element.'),
          ),
        ),
        DCardContent(
          child: DCollapsible(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      fields('Radius X', 'Radius Y'),
                      DCollapsibleContent(
                        keepMounted: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: fields('Radius X end', 'Radius Y end'),
                        ),
                      ),
                    ],
                  ),
                ),
                const _Trigger(
                  label: 'More radius settings',
                  icon: 'maximize',
                  iconOnly: true,
                  outlined: true,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

const _tree = <String, Object>{
  'components': <String, Object>{
    'ui': <String, Object>{
      'button.tsx': '',
      'card.tsx': '',
      'dialog.tsx': '',
      'input.tsx': '',
      'select.tsx': '',
      'table.tsx': '',
    },
    'login-form.tsx': '',
    'register-form.tsx': '',
  },
  'lib': <String, Object>{'utils.ts': '', 'cn.ts': '', 'api.ts': ''},
  'hooks': <String, Object>{
    'use-media-query.ts': '',
    'use-debounce.ts': '',
    'use-local-storage.ts': '',
  },
  'types': <String, Object>{'index.d.ts': '', 'api.d.ts': ''},
  'public': <String, Object>{'favicon.ico': '', 'logo.svg': '', 'images': ''},
  'app.tsx': '',
  'layout.tsx': '',
  'globals.css': '',
  'package.json': '',
  'tsconfig.json': '',
  'README.md': '',
  '.gitignore': '',
};

class _FileTree extends StatefulWidget {
  const _FileTree();
  @override
  State<_FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<_FileTree> {
  bool outline = false;
  String? selected;
  Widget entries(Map<String, Object> items) => Column(
    spacing: 4,
    children: [
      for (final entry in items.entries)
        if (entry.value case final Map<String, Object> children)
          DCollapsible(
            key: ValueKey(entry.key),
            child: Column(
              children: [
                _Trigger(label: entry.key, small: true, folder: true),
                DCollapsibleContent(
                  keepMounted: true,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 20,
                      top: 4,
                    ),
                    child: entries(children),
                  ),
                ),
              ],
            ),
          )
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DButton(
              variant: DButtonVariant.link,
              size: DButtonSize.small,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Glyph('file'),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(entry.key, softWrap: true, maxLines: null),
                  ),
                ],
              ),
              onPressed: () => setState(() => selected = entry.key),
            ),
          ),
    ],
  );
  @override
  Widget build(BuildContext context) => _Frame(
    width: 384,
    child: DCard(
      children: [
        DCardHeader(
          title: DTabs<String>.controlled(
            value: outline ? 'outline' : 'explorer',
            onChanged: (value) {
              if (value != null) setState(() => outline = value == 'outline');
            },
            children: const [
              DTabList<String>(
                children: [
                  DTabTrigger(value: 'explorer', child: Text('Explorer')),
                  DTabTrigger(value: 'outline', child: Text('Outline')),
                ],
              ),
            ],
          ),
        ),
        DCardContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              ExcludeFocus(
                excluding: outline,
                child: Offstage(offstage: outline, child: entries(_tree)),
              ),
              if (outline) const Text('No symbols in the selected file.'),
              if (selected != null) Text('Selected: $selected'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Lifecycle extends StatefulWidget {
  const _Lifecycle();
  @override
  State<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends State<_Lifecycle> {
  final form = GlobalKey<FormState>();
  bool disabled = false, animate = true;
  @override
  Widget build(BuildContext context) => _Frame(
    width: 384,
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Wrap(
            spacing: 8,
            children: [
              DButton(
                label: Text(disabled ? 'Enable' : 'Disable'),
                onPressed: () => setState(() => disabled = !disabled),
              ),
              DButton(
                label: Text(animate ? 'Disable animation' : 'Enable animation'),
                onPressed: () => setState(() => animate = !animate),
              ),
            ],
          ),
          for (final retained in [false, true])
            DCollapsible(
              defaultOpen: true,
              disabled: disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Trigger(label: retained ? 'Retained editor' : 'Lazy editor'),
                  DCollapsibleContent(
                    keepMounted: retained,
                    duration: animate
                        ? const Duration(milliseconds: 200)
                        : Duration.zero,
                    child: DInput(
                      initialValue: retained ? 'Retained draft' : 'Lazy draft',
                      labelText: 'Draft',
                      validator: (value) =>
                          value!.isEmpty ? 'Enter a draft' : null,
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              DButton(
                label: const Text('Validate'),
                onPressed: () => form.currentState!.validate(),
              ),
              DButton(
                label: const Text('Reset'),
                onPressed: () => form.currentState!.reset(),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
