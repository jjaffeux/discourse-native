import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

final menubarExamples = ComponentExamples(
  description:
      'A visually persistent in-app command menu with coordinated popup menus.',
  status: ComponentStatus.baseline,
  notes:
      'Installation: import package:discourse_native/discourse_ui.dart. '
      'Composition: DMenubar > DMenubarMenu(trigger + content), with groups, '
      'labels, items, checkbox/radio items, separators, shortcuts and submenus. '
      'The 32px base-nova bar uses 3px padding, a 1px border, 2px trigger gaps '
      'and host-relative lg/sm radii. Top-level focus roves with logical arrows, '
      'Home and End; opening, pointer hover and arrows switch the active popup. '
      'Menus retain Dropdown Menu typeahead, nested Escape boundaries and focus '
      'restoration. Native application/OS menus remain shell-owned. The status '
      'stays baseline until independent official-rendered and native acceptance.',
  examples: [
    StyleguideExample(
      title: 'Composition',
      description:
          'The frozen four-menu browser composition, including disabled, inset, '
          'shortcut, checkbox, radio and nested command states.',
      states: const [
        'Composition',
        'Disabled',
        'Checkbox',
        'Radio',
        'Submenu',
        'Keyboard',
      ],
      code: '''DMenubar(children: [
  DMenubarMenu(
    trigger: DMenubarTrigger(child: Text('File')),
    content: DMenubarContent(children: [
      DMenubarItem(child: Text('New Tab'), trailing: DMenubarShortcut('⌘T')),
      DMenubarSub(
        trigger: DMenubarSubTrigger(child: Text('Share')),
        content: DMenubarSubContent(children: [DMenubarItem(child: Text('Email link'))]),
      ),
    ]),
  ),
])''',
      builder: (_) => const _FullMenubarExample(),
    ),
    StyleguideExample(
      title: 'Checkbox',
      description:
          'Toggleable options retain the menu while updating their leading '
          'check indicator; ordinary commands close it.',
      states: const ['Unchecked', 'Checked', 'Disabled', 'Inset', 'Shortcut'],
      code: '''DMenubarCheckboxItem(
  checked: bookmarks,
  onChanged: (value) => setState(() => bookmarks = value),
  child: const Text('Always Show Bookmarks Bar'),
)''',
      builder: (_) => const _CheckboxMenubarExample(),
    ),
    StyleguideExample(
      title: 'Radio',
      description:
          'Two independently controlled single-select groups preserve focus and '
          'stay open while their selected value changes.',
      states: const ['Radio group', 'Selected', 'Controlled'],
      code: '''DMenubarRadioGroup<String>(
  value: profile,
  onChanged: (value) => setState(() => profile = value),
  children: const [
    DMenubarRadioItem(value: 'andy', child: Text('Andy')),
    DMenubarRadioItem(value: 'benoit', child: Text('Benoit')),
  ],
)''',
      builder: (_) => const _RadioMenubarExample(),
    ),
    StyleguideExample(
      title: 'Submenu',
      description:
          'Logical inline arrows enter and leave nested menus. Escape closes '
          'only the deepest popup and restores its owning row.',
      states: const ['Nested', 'Hover', 'Arrow keys', 'Escape boundary'],
      code: '''DMenubarSub(
  trigger: const DMenubarSubTrigger(child: Text('Share')),
  content: const DMenubarSubContent(children: [
    DMenubarItem(child: Text('Email link')),
    DMenubarItem(child: Text('Messages')),
  ]),
)''',
      builder: (_) => const _SubmenuMenubarExample(),
    ),
    StyleguideExample(
      title: 'With Icons',
      description:
          'The frozen File and More example uses exact 16px Lucide path artwork '
          'and includes the documented destructive command.',
      states: const ['Icons', 'Shortcut', 'Destructive', 'Dark theme'],
      code: '''DMenubarItem(
  leading: MenubarReferenceIcon(MenubarReferenceIcon.file),
  trailing: DMenubarShortcut('⌘N'),
  child: const Text('New File'),
)''',
      builder: (_) => const _IconMenubarExample(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic labels, logical alignment, top-level navigation, popup '
          'placement and submenu chevrons mirror without changing shortcuts.',
      states: const ['Arabic', 'RTL', 'Logical arrows', '200% text', 'Narrow'],
      code: '''Directionality(
  textDirection: TextDirection.rtl,
  child: DMenubar(children: [
    DMenubarMenu(
      trigger: DMenubarTrigger(child: Text('ملف')),
      content: DMenubarContent(align: DPopoverAlign.end, children: [...]),
    ),
  ]),
)''',
      builder: (_) => const _RtlMenubarExample(),
    ),
  ],
);

class _Preview extends StatelessWidget {
  const _Preview({required this.bar, this.status});
  final Widget bar;
  final String? status;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar,
        if (status != null) ...[
          const SizedBox(height: 12),
          Text(status!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

class _FullMenubarExample extends StatefulWidget {
  const _FullMenubarExample();

  @override
  State<_FullMenubarExample> createState() => _FullMenubarExampleState();
}

class _FullMenubarExampleState extends State<_FullMenubarExample> {
  bool bookmarks = false;
  bool fullUrls = true;
  String profile = 'benoit';
  String action = 'Choose a command';

  void select(String value) => setState(() => action = value);

  @override
  Widget build(BuildContext context) => _Preview(
    status: action,
    bar: DMenubar(
      children: [
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('File')),
          content: DMenubarContent(
            children: [
              DMenubarGroup(
                children: [
                  DMenubarItem(
                    onPressed: () => select('New Tab'),
                    trailing: const DMenubarShortcut('⌘T'),
                    child: const Text('New Tab'),
                  ),
                  DMenubarItem(
                    onPressed: () => select('New Window'),
                    trailing: const DMenubarShortcut('⌘N'),
                    child: const Text('New Window'),
                  ),
                  const DMenubarItem(child: Text('New Incognito Window')),
                ],
              ),
              const DMenubarSeparator(),
              DMenubarGroup(
                children: [
                  DMenubarSub(
                    trigger: const DMenubarSubTrigger(child: Text('Share')),
                    content: DMenubarSubContent(
                      children: [
                        DMenubarItem(
                          onPressed: () => select('Email link'),
                          child: const Text('Email link'),
                        ),
                        DMenubarItem(
                          onPressed: () => select('Messages'),
                          child: const Text('Messages'),
                        ),
                        DMenubarItem(
                          onPressed: () => select('Notes'),
                          child: const Text('Notes'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Print'),
                trailing: const DMenubarShortcut('⌘P'),
                child: const Text('Print...'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('Edit')),
          content: DMenubarContent(
            children: [
              DMenubarItem(
                onPressed: () => select('Undo'),
                trailing: const DMenubarShortcut('⌘Z'),
                child: const Text('Undo'),
              ),
              DMenubarItem(
                onPressed: () => select('Redo'),
                trailing: const DMenubarShortcut('⇧⌘Z'),
                child: const Text('Redo'),
              ),
              const DMenubarSeparator(),
              DMenubarSub(
                trigger: const DMenubarSubTrigger(child: Text('Find')),
                content: DMenubarSubContent(
                  children: [
                    DMenubarItem(
                      onPressed: () => select('Search the web'),
                      child: const Text('Search the web'),
                    ),
                    const DMenubarSeparator(),
                    DMenubarItem(
                      onPressed: () => select('Find'),
                      child: const Text('Find...'),
                    ),
                    DMenubarItem(
                      onPressed: () => select('Find Next'),
                      child: const Text('Find Next'),
                    ),
                    DMenubarItem(
                      onPressed: () => select('Find Previous'),
                      child: const Text('Find Previous'),
                    ),
                  ],
                ),
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Cut'),
                child: const Text('Cut'),
              ),
              DMenubarItem(
                onPressed: () => select('Copy'),
                child: const Text('Copy'),
              ),
              DMenubarItem(
                onPressed: () => select('Paste'),
                child: const Text('Paste'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('View')),
          content: DMenubarContent(
            width: 176,
            children: [
              DMenubarCheckboxItem(
                checked: bookmarks,
                onChanged: (value) => setState(() => bookmarks = value),
                child: const Text('Bookmarks Bar'),
              ),
              DMenubarCheckboxItem(
                checked: fullUrls,
                onChanged: (value) => setState(() => fullUrls = value),
                child: const Text('Full URLs'),
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Reload'),
                inset: true,
                trailing: const DMenubarShortcut('⌘R'),
                child: const Text('Reload'),
              ),
              const DMenubarItem(
                inset: true,
                trailing: DMenubarShortcut('⇧⌘R'),
                child: Text('Force Reload'),
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Toggle Fullscreen'),
                inset: true,
                child: const Text('Toggle Fullscreen'),
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Hide Sidebar'),
                inset: true,
                child: const Text('Hide Sidebar'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('Profiles')),
          content: DMenubarContent(
            children: [
              DMenubarRadioGroup<String>(
                value: profile,
                onChanged: (value) => setState(() => profile = value),
                children: const [
                  DMenubarRadioItem(value: 'andy', child: Text('Andy')),
                  DMenubarRadioItem(value: 'benoit', child: Text('Benoit')),
                  DMenubarRadioItem(value: 'luis', child: Text('Luis')),
                ],
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Edit profile'),
                inset: true,
                child: const Text('Edit...'),
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () => select('Add profile'),
                inset: true,
                child: const Text('Add Profile...'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CheckboxMenubarExample extends StatefulWidget {
  const _CheckboxMenubarExample();
  @override
  State<_CheckboxMenubarExample> createState() =>
      _CheckboxMenubarExampleState();
}

class _CheckboxMenubarExampleState extends State<_CheckboxMenubarExample> {
  bool bookmarks = false;
  bool urls = true;
  bool strike = true;
  bool code = false;

  @override
  Widget build(BuildContext context) => _Preview(
    bar: DMenubar(
      children: [
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('View')),
          content: DMenubarContent(
            width: 256,
            children: [
              DMenubarCheckboxItem(
                checked: bookmarks,
                onChanged: (value) => setState(() => bookmarks = value),
                child: const Text('Always Show Bookmarks Bar'),
              ),
              DMenubarCheckboxItem(
                checked: urls,
                onChanged: (value) => setState(() => urls = value),
                child: const Text('Always Show Full URLs'),
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () {},
                inset: true,
                trailing: const DMenubarShortcut('⌘R'),
                child: const Text('Reload'),
              ),
              const DMenubarItem(
                inset: true,
                trailing: DMenubarShortcut('⇧⌘R'),
                child: Text('Force Reload'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('Format')),
          content: DMenubarContent(
            children: [
              DMenubarCheckboxItem(
                checked: strike,
                onChanged: (value) => setState(() => strike = value),
                child: const Text('Strikethrough'),
              ),
              DMenubarCheckboxItem(
                checked: code,
                onChanged: (value) => setState(() => code = value),
                child: const Text('Code'),
              ),
              const DMenubarCheckboxItem(
                checked: false,
                onChanged: null,
                child: Text('Superscript'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RadioMenubarExample extends StatefulWidget {
  const _RadioMenubarExample();
  @override
  State<_RadioMenubarExample> createState() => _RadioMenubarExampleState();
}

class _RadioMenubarExampleState extends State<_RadioMenubarExample> {
  String profile = 'benoit';
  String theme = 'system';

  @override
  Widget build(BuildContext context) => _Preview(
    status: '$profile · $theme',
    bar: DMenubar(
      children: [
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('Profiles')),
          content: DMenubarContent(
            children: [
              DMenubarRadioGroup<String>(
                value: profile,
                onChanged: (value) => setState(() => profile = value),
                children: const [
                  DMenubarRadioItem(value: 'andy', child: Text('Andy')),
                  DMenubarRadioItem(value: 'benoit', child: Text('Benoit')),
                  DMenubarRadioItem(value: 'luis', child: Text('Luis')),
                ],
              ),
              const DMenubarSeparator(),
              DMenubarItem(
                onPressed: () {},
                inset: true,
                child: const Text('Edit...'),
              ),
              DMenubarItem(
                onPressed: () {},
                inset: true,
                child: const Text('Add Profile...'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: const DMenubarTrigger(child: Text('Theme')),
          content: DMenubarContent(
            children: [
              DMenubarRadioGroup<String>(
                value: theme,
                onChanged: (value) => setState(() => theme = value),
                children: const [
                  DMenubarRadioItem(value: 'light', child: Text('Light')),
                  DMenubarRadioItem(value: 'dark', child: Text('Dark')),
                  DMenubarRadioItem(value: 'system', child: Text('System')),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SubmenuMenubarExample extends StatelessWidget {
  const _SubmenuMenubarExample();

  @override
  Widget build(BuildContext context) => const _Preview(
    bar: DMenubar(
      children: [
        DMenubarMenu(
          trigger: DMenubarTrigger(child: Text('File')),
          content: DMenubarContent(
            children: [
              DMenubarSub(
                trigger: DMenubarSubTrigger(child: Text('Share')),
                content: DMenubarSubContent(
                  children: [
                    DMenubarItem(onPressed: _noop, child: Text('Email link')),
                    DMenubarItem(onPressed: _noop, child: Text('Messages')),
                    DMenubarItem(onPressed: _noop, child: Text('Notes')),
                  ],
                ),
              ),
              DMenubarSeparator(),
              DMenubarItem(
                onPressed: _noop,
                trailing: DMenubarShortcut('⌘P'),
                child: Text('Print...'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: DMenubarTrigger(child: Text('Edit')),
          content: DMenubarContent(
            children: [
              DMenubarItem(
                onPressed: _noop,
                trailing: DMenubarShortcut('⌘Z'),
                child: Text('Undo'),
              ),
              DMenubarItem(
                onPressed: _noop,
                trailing: DMenubarShortcut('⇧⌘Z'),
                child: Text('Redo'),
              ),
              DMenubarSeparator(),
              DMenubarSub(
                trigger: DMenubarSubTrigger(child: Text('Find')),
                content: DMenubarSubContent(
                  children: [
                    DMenubarItem(onPressed: _noop, child: Text('Find...')),
                    DMenubarItem(onPressed: _noop, child: Text('Find Next')),
                    DMenubarItem(
                      onPressed: _noop,
                      child: Text('Find Previous'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void _noop() {}

class _IconMenubarExample extends StatelessWidget {
  const _IconMenubarExample();

  @override
  Widget build(BuildContext context) => const _Preview(
    bar: DMenubar(
      children: [
        DMenubarMenu(
          trigger: DMenubarTrigger(child: Text('File')),
          content: DMenubarContent(
            children: [
              DMenubarItem(
                onPressed: _noop,
                leading: MenubarReferenceIcon(MenubarReferenceIcon.file),
                trailing: DMenubarShortcut('⌘N'),
                child: Text('New File'),
              ),
              DMenubarItem(
                onPressed: _noop,
                leading: MenubarReferenceIcon(MenubarReferenceIcon.folder),
                child: Text('Open Folder'),
              ),
              DMenubarSeparator(),
              DMenubarItem(
                onPressed: _noop,
                leading: MenubarReferenceIcon(MenubarReferenceIcon.save),
                trailing: DMenubarShortcut('⌘S'),
                child: Text('Save'),
              ),
            ],
          ),
        ),
        DMenubarMenu(
          trigger: DMenubarTrigger(child: Text('More')),
          content: DMenubarContent(
            children: [
              DMenubarItem(
                onPressed: _noop,
                leading: MenubarReferenceIcon(MenubarReferenceIcon.settings),
                child: Text('Settings'),
              ),
              DMenubarItem(
                onPressed: _noop,
                leading: MenubarReferenceIcon(MenubarReferenceIcon.help),
                child: Text('Help'),
              ),
              DMenubarSeparator(),
              DMenubarItem(
                onPressed: _noop,
                leading: MenubarReferenceIcon(MenubarReferenceIcon.trash),
                variant: DMenubarItemVariant.destructive,
                child: Text('Delete'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RtlMenubarExample extends StatefulWidget {
  const _RtlMenubarExample();
  @override
  State<_RtlMenubarExample> createState() => _RtlMenubarExampleState();
}

class _RtlMenubarExampleState extends State<_RtlMenubarExample> {
  bool urls = true;
  String profile = 'benoit';

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: _Preview(
      bar: DMenubar(
        children: [
          const DMenubarMenu(
            trigger: DMenubarTrigger(child: Text('ملف')),
            content: DMenubarContent(
              align: DPopoverAlign.end,
              children: [
                DMenubarItem(
                  onPressed: _noop,
                  trailing: DMenubarShortcut('⌘T'),
                  child: Text('علامة تبويب جديدة'),
                ),
                DMenubarItem(
                  onPressed: _noop,
                  trailing: DMenubarShortcut('⌘N'),
                  child: Text('نافذة جديدة'),
                ),
                DMenubarItem(child: Text('نافذة التصفح المتخفي الجديدة')),
                DMenubarSeparator(),
                DMenubarSub(
                  trigger: DMenubarSubTrigger(child: Text('مشاركة')),
                  content: DMenubarSubContent(
                    children: [
                      DMenubarItem(
                        onPressed: _noop,
                        child: Text('رابط البريد الإلكتروني'),
                      ),
                      DMenubarItem(onPressed: _noop, child: Text('الرسائل')),
                      DMenubarItem(onPressed: _noop, child: Text('الملاحظات')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          DMenubarMenu(
            trigger: const DMenubarTrigger(child: Text('عرض')),
            content: DMenubarContent(
              align: DPopoverAlign.end,
              width: 176,
              children: [
                DMenubarCheckboxItem(
                  checked: urls,
                  onChanged: (value) => setState(() => urls = value),
                  child: const Text('عناوين URL الكاملة'),
                ),
                const DMenubarItem(
                  onPressed: _noop,
                  inset: true,
                  trailing: DMenubarShortcut('⌘R'),
                  child: Text('إعادة تحميل'),
                ),
              ],
            ),
          ),
          DMenubarMenu(
            trigger: const DMenubarTrigger(child: Text('الملفات الشخصية')),
            content: DMenubarContent(
              align: DPopoverAlign.end,
              children: [
                DMenubarRadioGroup<String>(
                  value: profile,
                  onChanged: (value) => setState(() => profile = value),
                  children: const [
                    DMenubarRadioItem(value: 'andy', child: Text('Andy')),
                    DMenubarRadioItem(value: 'benoit', child: Text('Benoit')),
                    DMenubarRadioItem(value: 'luis', child: Text('Luis')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Exact Lucide artwork used by the frozen icon example (ISC license).
class MenubarReferenceIcon extends StatelessWidget {
  const MenubarReferenceIcon(this.svg, {super.key});
  final String svg;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    return SvgPicture.string(
      svg,
      width: iconTheme.size ?? 16,
      height: iconTheme.size ?? 16,
      theme: SvgTheme(
        currentColor: iconTheme.color ?? DTokens.of(context).foreground,
      ),
      excludeFromSemantics: true,
    );
  }

  static const file =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>';
  static const folder =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/></svg>';
  static const save =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15.2 3a2 2 0 0 1 1.4.6l3.8 3.8a2 2 0 0 1 .6 1.4V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M17 21v-8H7v8"/><path d="M7 3v5h8"/></svg>';
  static const settings =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.09a2 2 0 0 1-1-1.74v-.51a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>';
  static const help =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 1 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>';
  static const trash =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/></svg>';
}
