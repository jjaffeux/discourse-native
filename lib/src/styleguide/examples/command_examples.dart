import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../styleguide_example.dart';

final commandExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Searchable command menus for navigation and quick actions.',
  notes:
      'This is the frozen base-nova/cmdk composition mapped to native Flutter '
      'editing, focus and semantics. DCommand owns query, filtering, highlight '
      'and keyboard navigation; DCommandDialog composes the shared DDialog owner. '
      'Search uses case-insensitive ranked matching across value and keywords, '
      'or accepts a custom score/filtering opt-out for server-owned results. '
      'Arrow, Home/End, modified-arrow and Ctrl-N/P/J/K navigation keeps the '
      'text editor focused; IME composition suppresses command bindings, Return '
      'activates after commit, and highlights scroll into view. Separators hide '
      'while filtering unless alwaysRender is set, and loading states can expose '
      'progress. Borrowed command, text, focus and scroll controllers are never '
      'disposed. Because Flutter cannot inspect arbitrary child text, non-string '
      'values should provide searchValue. '
      'The existing anchored shell action menu now uses these public rows while '
      'retaining its distinct overlay placement and route-result adapter.',
  examples: [
    StyleguideExample(
      title: 'Composition',
      description:
          'Embedded outlined command with icons, disabled state, groups, empty result and shortcuts.',
      code: _compositionCode,
      states: const [
        'Default',
        'Hover',
        'Focused',
        'Selected',
        'Disabled',
        'Empty',
      ],
      builder: (_) => const SizedBox(width: 384, child: _EmbeddedCommand()),
    ),
    StyleguideExample(
      title: 'Basic dialog',
      description:
          'Opens the reference command palette, focuses its native editor and restores trigger focus when closed.',
      code: _dialogCode,
      states: const ['Dialog', 'Focus trap', 'Escape', 'Restoration'],
      builder: (_) => const _DialogCommand(),
    ),
    StyleguideExample(
      title: 'Custom filtering and loading',
      description:
          'Aliases participate in ranking; disabling local filtering supports externally supplied asynchronous results.',
      code: _customCode,
      states: const [
        'Keywords',
        'Custom score',
        'Loading',
        'Progress semantics',
        'Dynamic results',
      ],
      builder: (_) => const SizedBox(width: 384, child: _CustomCommand()),
    ),
    StyleguideExample(
      title: 'Scrollable',
      description:
          'A 288px result viewport keeps the highlighted item visible across many grouped actions.',
      code: _scrollableCode,
      states: const ['Scrollable', 'Keyboard', 'Reduced motion'],
      builder: (_) => const SizedBox(width: 384, child: _ScrollableCommand()),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic query, logical icon and shortcut placement, filtering and selection.',
      code: _rtlCode,
      states: const ['RTL', 'Text scaling', 'Narrow'],
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(width: 384, child: _ArabicCommand()),
      ),
    ),
  ],
);

class _EmbeddedCommand extends StatefulWidget {
  const _EmbeddedCommand();
  @override
  State<_EmbeddedCommand> createState() => _EmbeddedCommandState();
}

class _EmbeddedCommandState extends State<_EmbeddedCommand> {
  String _message = 'Choose a command';
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DCommand<String>(
        outlined: true,
        loop: true,
        onSelected: (value) => setState(() => _message = 'Selected $value'),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DCommandInput<String>(),
            DCommandList<String>(
              children: [
                DCommandEmpty(child: Text('No results found.')),
                DCommandGroup<String>(
                  heading: Text('Suggestions'),
                  items: [
                    DCommandItem(
                      value: 'Calendar',
                      leading: Icon(Icons.calendar_today_outlined),
                      child: Text('Calendar'),
                    ),
                    DCommandItem(
                      value: 'Search Emoji',
                      keywords: ['smile', 'emoji'],
                      leading: DIcon(DIcons.faceSmile),
                      child: Text('Search Emoji'),
                    ),
                    DCommandItem(
                      value: 'Calculator',
                      enabled: false,
                      leading: Icon(Icons.calculate_outlined),
                      child: Text('Calculator'),
                    ),
                  ],
                ),
                DCommandSeparator<String>(),
                DCommandGroup<String>(
                  heading: Text('Settings'),
                  items: [
                    DCommandItem(
                      value: 'Profile',
                      leading: DIcon(DIcons.user),
                      trailing: DCommandShortcut(Text('⌘P')),
                      child: Text('Profile'),
                    ),
                    DCommandItem(
                      value: 'Billing',
                      leading: Icon(Icons.credit_card_outlined),
                      trailing: DCommandShortcut(Text('⌘B')),
                      child: Text('Billing'),
                    ),
                    DCommandItem(
                      value: 'Settings',
                      checked: true,
                      leading: DIcon(DIcons.gear),
                      child: Text('Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.sm),
      Text(_message, textAlign: TextAlign.center),
    ],
  );
}

class _DialogCommand extends StatefulWidget {
  const _DialogCommand();
  @override
  State<_DialogCommand> createState() => _DialogCommandState();
}

class _DialogCommandState extends State<_DialogCommand> {
  final _dialog = DDialogController<String>();
  String _result = 'Nothing selected';
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DCommandDialog<String>(
        controller: _dialog,
        trigger: DDialogTrigger(
          builder: (context, open) => DButton(
            variant: DButtonVariant.outline,
            onPressed: open,
            label: const Text('Open Menu'),
          ),
        ),
        onOpenChanged: (details) {
          if (!details.open && details.result != null) {
            setState(() => _result = 'Ran ${details.result}');
          }
        },
        command: DCommand<String>(
          onSelected: _dialog.close,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DCommandInput<String>(),
              DCommandList<String>(
                children: [
                  DCommandEmpty(child: Text('No results found.')),
                  DCommandGroup<String>(
                    heading: Text('Suggestions'),
                    items: [
                      DCommandItem(value: 'Calendar', child: Text('Calendar')),
                      DCommandItem(
                        value: 'Search Emoji',
                        child: Text('Search Emoji'),
                      ),
                      DCommandItem(
                        value: 'Calculator',
                        child: Text('Calculator'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: DSpacing.sm),
      Text(_result),
    ],
  );
  @override
  void dispose() {
    _dialog.dispose();
    super.dispose();
  }
}

class _CustomCommand extends StatefulWidget {
  const _CustomCommand();
  @override
  State<_CustomCommand> createState() => _CustomCommandState();
}

class _CustomCommandState extends State<_CustomCommand> {
  bool _loading = false;
  List<String> _results = const ['General', 'Appearance', 'Notifications'];

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _loading = false;
        _results = const ['Privacy', 'Security', 'Devices'];
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DCommand<String>(
        outlined: true,
        loading: _loading,
        filter: (value, query, keywords) {
          final text = '$value ${keywords.join(' ')}'.toLowerCase();
          return text.contains(query.toLowerCase()) ? 1 : 0;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DCommandInput<String>(placeholder: 'Search settings...'),
            DCommandList<String>(
              children: [
                const DCommandLoading(
                  semanticLabel: 'Fetching settings',
                  child: Text('Fetching settings…'),
                ),
                const DCommandEmpty(child: Text('No matching settings.')),
                DCommandGroup<String>(
                  heading: const Text('Settings'),
                  items: [
                    for (final result in _results)
                      DCommandItem(
                        value: result,
                        keywords: result == 'Appearance'
                            ? const ['theme', 'dark mode']
                            : const [],
                        child: Text(result),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.sm),
      DButton(
        variant: DButtonVariant.outline,
        onPressed: _loading ? null : _refresh,
        label: const Text('Load remote results'),
      ),
    ],
  );
}

class _ScrollableCommand extends StatelessWidget {
  const _ScrollableCommand();
  @override
  Widget build(BuildContext context) => DCommand<String>(
    outlined: true,
    loop: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DCommandInput<String>(),
        DCommandList<String>(
          children: [
            const DCommandEmpty(child: Text('No results found.')),
            for (final section in [
              'Navigation',
              'Actions',
              'View',
              'Account',
            ]) ...[
              DCommandGroup<String>(
                heading: Text(section),
                items: [
                  for (var index = 1; index <= 6; index++)
                    DCommandItem(
                      value: '$section $index',
                      leading: const DIcon(DIcons.circle),
                      trailing: DCommandShortcut(Text('⌘$index')),
                      child: Text('$section action $index'),
                    ),
                ],
              ),
              const DCommandSeparator<String>(),
            ],
          ],
        ),
      ],
    ),
  );
}

class _ArabicCommand extends StatelessWidget {
  const _ArabicCommand();
  @override
  Widget build(BuildContext context) => const DCommand<String>(
    outlined: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DCommandInput<String>(placeholder: 'اكتب أمرًا أو ابحث...'),
        DCommandList<String>(
          children: [
            DCommandEmpty(child: Text('لم يتم العثور على نتائج.')),
            DCommandGroup<String>(
              heading: Text('اقتراحات'),
              items: [
                DCommandItem(
                  value: 'التقويم',
                  leading: Icon(Icons.calendar_today_outlined),
                  child: Text('التقويم'),
                ),
                DCommandItem(
                  value: 'البحث عن الرموز التعبيرية',
                  leading: DIcon(DIcons.faceSmile),
                  child: Text('البحث عن الرموز التعبيرية'),
                ),
              ],
            ),
            DCommandSeparator<String>(),
            DCommandGroup<String>(
              heading: Text('الإعدادات'),
              items: [
                DCommandItem(
                  value: 'الملف الشخصي',
                  trailing: DCommandShortcut(Text('⌘P')),
                  child: Text('الملف الشخصي'),
                ),
                DCommandItem(value: 'الفوترة', child: Text('الفوترة')),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

const _compositionCode = '''DCommand<String>(
  outlined: true,
  loop: true,
  onSelected: run,
  child: Column(children: [
    DCommandInput<String>(),
    DCommandList<String>(children: [
      DCommandEmpty(child: Text('No results found.')),
      DCommandGroup<String>(heading: Text('Suggestions'), items: [
        DCommandItem(value: 'Calendar', child: Text('Calendar')),
      ]),
      DCommandSeparator<String>(),
    ]),
  ]),
)''';

const _dialogCode = '''DCommandDialog<String>(
  controller: dialog,
  trigger: DDialogTrigger(builder: (_, open) =>
    DButton(onPressed: open, label: Text('Open Menu'))),
  command: DCommand<String>(
    onSelected: dialog.close,
    child: Column(children: [DCommandInput<String>(), results]),
  ),
)''';

const _customCode = '''DCommand<String>(
  loading: loading,
  filter: (value, query, keywords) =>
    ('\$value \${keywords.join(' ')}').contains(query) ? 1 : 0,
  child: DCommandList<String>(children: [
    DCommandLoading(child: Text('Fetching…')),
    DCommandGroup<String>(items: remoteItems),
  ]),
)''';

const _scrollableCode = '''DCommandList<String>(
  maxHeight: 288,
  controller: borrowedScrollController,
  children: groupedActions,
)''';

const _rtlCode = '''Directionality(
  textDirection: TextDirection.rtl,
  child: DCommand<String>(child: Column(children: [
    DCommandInput<String>(placeholder: 'اكتب أمرًا أو ابحث...'),
    arabicResults,
  ])),
)''';
