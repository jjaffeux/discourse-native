import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../foundation/icons/d_icons.dart';
import '../../foundation/icons/d_native_icons.dart';
import '../../theme/discourse_typography.dart';
import '../styleguide_example.dart';

final dropdownMenuExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A compact action menu with groups, choices, shortcuts, icons, and nested submenus.',
  notes:
      'Ports the complete frozen Base UI/base-nova Dropdown Menu composition. '
      'The shared DPopover owns overlay placement, collision, dismissal, focus '
      'restoration, lifecycle loss, live theme changes, and reduced motion. '
      'Menu rows add directional/Home/End/typeahead navigation and platform-sized '
      'touch targets. Flutter Icon widgets are caller-supplied equivalents of the '
      'reference Lucide slots; applications may use their own icon set. All sample '
      'state is local and resets only when the styleguide example is reset.',
  examples: [
    _example('Composition', _DropdownExampleKind.composition),
    _example('Basic', _DropdownExampleKind.basic),
    _example('Submenu', _DropdownExampleKind.submenu),
    _example('Shortcuts', _DropdownExampleKind.shortcuts),
    _example('Icons', _DropdownExampleKind.icons),
    _example('Checkboxes', _DropdownExampleKind.checkboxes),
    _example('Checkboxes Icons', _DropdownExampleKind.checkboxIcons),
    _example('Radio Group', _DropdownExampleKind.radio),
    _example('Radio Icons', _DropdownExampleKind.radioIcons),
    _example('Destructive', _DropdownExampleKind.destructive),
    _example('Avatar', _DropdownExampleKind.avatar),
    _example('Complex', _DropdownExampleKind.complex),
    _example('RTL', _DropdownExampleKind.rtl),
    StyleguideExample(
      title: 'Profile account',
      description:
          'The same anchored account menu on desktop and touch, with a full-sized avatar, mixed palette colors, and compact toggle indicators.',
      code:
          "DDropdownMenu(content: DDropdownMenuContent(width: 216, sideOffset: 8, align: DPopoverAlign.end, variant: DPopoverVariant.timeline, padding: EdgeInsets.all(7), highlightInitialFocus: false, children: [DDropdownMenuItem(leading: DAvatar(border: false), leadingGap: 10, padding: EdgeInsets.all(8), onPressed: openCard, child: Column(children: [Text('Ty'), Text('@tynaut')])), DDropdownMenuSeparator(inset: true, space: 11), DDropdownMenuCheckboxItem(checked: online, onChanged: setOnline, leading: onlineIcon, leadingGap: 9, indicatorSize: 11, child: Text('Online'))]), child: avatarTrigger)",
      builder: (_) => DDropdownMenu(
        content: DDropdownMenuContent(
          width: 216,
          sideOffset: 8,
          align: DPopoverAlign.end,
          variant: DPopoverVariant.timeline,
          padding: const EdgeInsets.all(7),
          highlightInitialFocus: false,
          children: [
            DDropdownMenuItem(
              leading: const DAvatar(
                border: false,
                fallback: DAvatarFallback(child: Text('T')),
              ),
              leadingGap: 10,
              padding: const EdgeInsets.all(8),
              onPressed: () {},
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ty',
                    style: TextStyle(
                      fontSize: DiscourseTypography.compact,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '@tynaut',
                    style: TextStyle(fontSize: DiscourseTypography.xs),
                  ),
                ],
              ),
            ),
            const DDropdownMenuSeparator(inset: true, space: 11),
            DDropdownMenuCheckboxItem(
              checked: true,
              onChanged: (_) {},
              leadingGap: 9,
              indicatorSize: 11,
              leading: const DIcon(DIcons.toggleOn, size: 13),
              child: const Text('Online'),
            ),
            DDropdownMenuItem(
              variant: DDropdownMenuItemVariant.destructive,
              onPressed: () {},
              child: const Text('Disconnect'),
            ),
          ],
        ),
        child: DDropdownMenuTrigger(
          builder: (context, state) => DButton.iconOnly(
            density: DButtonDensity.avatar,
            shape: DButtonShape.pill,
            focusNode: state.focusNode,
            hasPopup: true,
            expanded: state.open,
            tooltip: 'Profile',
            onPressed: state.toggle,
            icon: const DAvatar(fallback: DAvatarFallback(child: Text('T'))),
          ),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Grouped guide',
      description:
          'A sidebar-style vertical guide groups indented choices beneath a label. The guide follows the reading direction and live palette.',
      code: _guideCode,
      builder: (_) => DDropdownMenu(
        content: DDropdownMenuContent(
          children: [
            const DDropdownMenuLabel(child: Text('Top')),
            DDropdownMenuGroup(
              showGuide: true,
              semanticLabel: 'Top periods',
              children: [
                for (final period in [
                  'Year',
                  'Quarter',
                  'Month',
                  'Week',
                  'Today',
                  'All time',
                ])
                  DDropdownMenuItem(onPressed: () {}, child: Text(period)),
              ],
            ),
          ],
        ),
        child: DDropdownMenuTrigger.button(label: const Text('Top periods')),
      ),
    ),
    StyleguideExample(
      title: 'Custom popup corners',
      description:
          'The popup can use a 12px radius while menu rows retain their Native interaction and focus styling.',
      code:
          "DDropdownMenu(content: DDropdownMenuContent(cornerRadius: 12, children: [DDropdownMenuItem(onPressed: action, child: Text('Latest topics'))]), child: DDropdownMenuTrigger.button(label: Text('Browse tabs')))",
      builder: (_) => DDropdownMenu(
        content: DDropdownMenuContent(
          cornerRadius: 12,
          children: [
            DDropdownMenuItem(
              onPressed: () {},
              child: const Text('Latest topics'),
            ),
          ],
        ),
        child: DDropdownMenuTrigger.button(label: const Text('Browse tabs')),
      ),
    ),
    StyleguideExample(
      title: 'Adaptive sheet on mobile',
      description:
          'A compact menu floats above the home indicator with a grab handle '
          'and no visible title or close button. Desktop keeps its anchored menu.',
      code:
          'DDropdownMenu(sheetOnMobile: true, mobileSheetVariant: DSheetVariant.adaptiveMenu, content: content, child: trigger)',
      builder: (_) => DDropdownMenu(
        sheetOnMobile: true,
        mobileSheetVariant: DSheetVariant.adaptiveMenu,
        content: DDropdownMenuContent(
          semanticLabel: 'Topic actions',
          highlightInitialFocus: false,
          children: [
            for (final label in ['Share topic', 'Flag topic', 'Mark unread'])
              DDropdownMenuItem(onPressed: () {}, child: Text(label)),
          ],
        ),
        child: DDropdownMenuTrigger.button(label: const Text('Topic actions')),
      ),
    ),
    StyleguideExample(
      title: 'Sheet on mobile',
      description:
          'Uses a bottom sheet on mobile platforms and an anchored menu on desktop.',
      code:
          "DDropdownMenu(sheetOnMobile: true, content: content, child: trigger)",
      builder: (_) => DDropdownMenu(
        sheetOnMobile: true,
        content: DDropdownMenuContent(
          semanticLabel: 'Choose feed',
          children: [
            for (final label in ['Latest', 'New', 'Unread', 'Top'])
              DDropdownMenuItem(onPressed: () {}, child: Text(label)),
          ],
        ),
        child: DDropdownMenuTrigger.button(label: const Text('Choose feed')),
      ),
    ),
  ],
);

StyleguideExample _example(
  String title,
  _DropdownExampleKind kind,
) => StyleguideExample(
  title: title,
  description: switch (kind) {
    _DropdownExampleKind.composition =>
      'The canonical account menu with groups, shortcuts, a submenu, separators, and a disabled API action.',
    _DropdownExampleKind.basic =>
      'Labels, groups, separators, a disabled item, and ordinary actions.',
    _DropdownExampleKind.submenu =>
      'Move diagonally into either nested level without switching sibling menus. Directional keys open submenus; Escape closes the deepest one.',
    _DropdownExampleKind.shortcuts =>
      'Right-aligned keyboard hints remain presentation-only.',
    _DropdownExampleKind.icons =>
      '16px leading icon slots follow the ambient reading direction.',
    _DropdownExampleKind.checkboxes =>
      'Independent controlled toggles stay open while values change.',
    _DropdownExampleKind.checkboxIcons =>
      'Controlled notification toggles combine icons and check indicators.',
    _DropdownExampleKind.radio =>
      'An exclusive controlled panel-position group.',
    _DropdownExampleKind.radioIcons =>
      'An exclusive payment-method group with leading icons.',
    _DropdownExampleKind.destructive =>
      'Destructive color and focus tint distinguish the irreversible action.',
    _DropdownExampleKind.avatar =>
      'A round avatar trigger remains the single button and focus owner.',
    _DropdownExampleKind.complex =>
      'Groups, checks, radios, shortcuts, icons, and three submenu levels.',
    _DropdownExampleKind.rtl =>
      'Arabic labels, logical alignment, mirrored arrows, and reversed directional keys.',
  },
  code: _usageCode,
  builder: (_) => _DropdownMenuExample(kind: kind),
  states: const [
    'hover',
    'focus',
    'disabled',
    'keyboard',
    'touch',
    'RTL',
    'large text',
  ],
);

enum _DropdownExampleKind {
  composition,
  basic,
  submenu,
  shortcuts,
  icons,
  checkboxes,
  checkboxIcons,
  radio,
  radioIcons,
  destructive,
  avatar,
  complex,
  rtl,
}

/// Local-state fixture used by styleguide and focused/native review tests.
class _DropdownMenuExample extends StatefulWidget {
  const _DropdownMenuExample({required this.kind});
  final _DropdownExampleKind kind;

  @override
  State<_DropdownMenuExample> createState() => _DropdownMenuExampleState();
}

class _DropdownMenuExampleState extends State<_DropdownMenuExample> {
  bool _statusBar = true;
  final bool _activityBar = false;
  bool _panel = false;
  bool _email = true;
  bool _sms = false;
  bool _push = true;
  String _position = 'bottom';
  String _payment = 'card';
  String _theme = 'light';
  String _status = 'No action selected';

  void _selected(String label) => setState(() => _status = '$label selected');

  Widget _item(
    String label, {
    DIconData? icon,
    String? shortcut,
    bool enabled = true,
    bool destructive = false,
  }) => DDropdownMenuItem(
    onPressed: enabled ? () => _selected(label) : null,
    leading: icon == null ? null : DIcon(icon),
    trailing: shortcut == null ? null : DDropdownMenuShortcut(shortcut),
    variant: destructive
        ? DDropdownMenuItemVariant.destructive
        : DDropdownMenuItemVariant.standard,
    child: Text(label),
  );

  Widget _menu({
    required String triggerLabel,
    required List<Widget> children,
    double width = 160,
    DPopoverAlign align = DPopoverAlign.start,
    Widget? trigger,
  }) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: '$triggerLabel menu',
      width: width,
      align: align,
      children: children,
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) =>
          trigger ??
          DButton(
            label: Text(triggerLabel),
            variant: DButtonVariant.outline,
            hasPopup: true,
            expanded: state.open,
            focusNode: state.focusNode,
            onPressed: state.toggle,
          ),
    ),
  );

  List<Widget> get _basic => [
    const DDropdownMenuLabel(child: Text('My Account')),
    _item('Profile'),
    _item('Billing'),
    _item('Settings'),
    const DDropdownMenuSeparator(),
    _item('GitHub'),
    _item('Support'),
    _item('API', enabled: false),
  ];

  List<Widget> get _submenu => [
    _item('Team'),
    DDropdownMenuSub(
      trigger: const Text('Invite users'),
      width: 128,
      children: [
        _item('Email'),
        _item('Message'),
        DDropdownMenuSub(
          trigger: const Text('More options'),
          children: [
            _item('Calendly'),
            _item('Slack'),
            const DDropdownMenuSeparator(),
            _item('Webhook'),
          ],
        ),
        const DDropdownMenuSeparator(),
        _item('Advanced...'),
      ],
    ),
    _item('New Team', shortcut: '⌘+T'),
  ];

  List<Widget> get _shortcuts => [
    const DDropdownMenuLabel(child: Text('My Account')),
    _item('Profile', shortcut: '⇧⌘P'),
    _item('Billing', shortcut: '⌘B'),
    _item('Settings', shortcut: '⌘S'),
    const DDropdownMenuSeparator(),
    _item('Log out', shortcut: '⇧⌘Q'),
  ];

  List<Widget> get _icons => [
    _item('Profile', icon: DIcons.user),
    _item('Billing', icon: DNativeIcons.creditCard),
    _item('Settings', icon: DIcons.gear),
    const DDropdownMenuSeparator(),
    _item('Log out', icon: DIcons.rightFromBracket, destructive: true),
  ];

  List<Widget> get _checkboxes => [
    const DDropdownMenuLabel(child: Text('Appearance')),
    DDropdownMenuCheckboxItem(
      checked: _statusBar,
      onChanged: (value) => setState(() => _statusBar = value),
      child: const Text('Status Bar'),
    ),
    DDropdownMenuCheckboxItem(
      checked: _activityBar,
      onChanged: null,
      child: const Text('Activity Bar'),
    ),
    DDropdownMenuCheckboxItem(
      checked: _panel,
      onChanged: (value) => setState(() => _panel = value),
      child: const Text('Panel'),
    ),
  ];

  List<Widget> get _checkboxIcons => [
    const DDropdownMenuLabel(child: Text('Notification Preferences')),
    DDropdownMenuCheckboxItem(
      checked: _email,
      onChanged: (value) => setState(() => _email = value),
      leading: const DIcon(DIcons.envelope),
      child: const Text('Email notifications'),
    ),
    DDropdownMenuCheckboxItem(
      checked: _sms,
      onChanged: (value) => setState(() => _sms = value),
      leading: const DIcon(DIcons.comment),
      child: const Text('SMS notifications'),
    ),
    DDropdownMenuCheckboxItem(
      checked: _push,
      onChanged: (value) => setState(() => _push = value),
      leading: const DIcon(DIcons.farBell),
      child: const Text('Push notifications'),
    ),
  ];

  List<Widget> get _radio => [
    const DDropdownMenuLabel(child: Text('Panel Position')),
    DDropdownMenuRadioGroup<String>(
      value: _position,
      onChanged: (value) => setState(() => _position = value),
      children: const [
        DDropdownMenuRadioItem(value: 'top', child: Text('Top')),
        DDropdownMenuRadioItem(value: 'bottom', child: Text('Bottom')),
        DDropdownMenuRadioItem(value: 'right', child: Text('Right')),
      ],
    ),
  ];

  List<Widget> get _radioIcons => [
    const DDropdownMenuLabel(child: Text('Select Payment Method')),
    DDropdownMenuRadioGroup<String>(
      value: _payment,
      onChanged: (value) => setState(() => _payment = value),
      children: const [
        DDropdownMenuRadioItem(
          value: 'card',
          leading: DIcon(DNativeIcons.creditCard),
          child: Text('Credit Card'),
        ),
        DDropdownMenuRadioItem(
          value: 'paypal',
          leading: DIcon(DNativeIcons.wallet),
          child: Text('PayPal'),
        ),
        DDropdownMenuRadioItem(
          value: 'bank',
          leading: DIcon(DNativeIcons.buildingColumns),
          child: Text('Bank Transfer'),
        ),
      ],
    ),
  ];

  List<Widget> get _destructive => [
    _item('Edit', icon: DIcons.pencil),
    _item('Share', icon: DIcons.shareNodes),
    const DDropdownMenuSeparator(),
    _item('Delete', icon: DIcons.trashCan, destructive: true),
  ];

  List<Widget> get _avatar => [
    _item('Account', icon: DIcons.circleCheck),
    _item('Billing', icon: DNativeIcons.creditCard),
    _item('Notifications', icon: DIcons.farBell),
    const DDropdownMenuSeparator(),
    _item('Sign Out', icon: DIcons.rightFromBracket),
  ];

  List<Widget> get _composition => [
    DDropdownMenuGroup(
      children: [
        const DDropdownMenuLabel(child: Text('My Account')),
        _item('Profile', shortcut: '⇧⌘P'),
        _item('Billing', shortcut: '⌘B'),
        _item('Settings', shortcut: '⌘S'),
      ],
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuGroup(
      children: [
        _item('Team'),
        DDropdownMenuSub(
          trigger: const Text('Invite users'),
          children: [
            _item('Email'),
            _item('Message'),
            const DDropdownMenuSeparator(),
            _item('More...'),
          ],
        ),
        _item('New Team', shortcut: '⌘+T'),
      ],
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuGroup(
      children: [
        _item('GitHub'),
        _item('Support'),
        _item('API', enabled: false),
      ],
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuGroup(children: [_item('Log out', shortcut: '⇧⌘Q')]),
  ];

  List<Widget> get _complex => [
    const DDropdownMenuLabel(child: Text('File')),
    _item('New File', icon: DIcons.fileLines, shortcut: '⌘N'),
    _item('New Folder', icon: DNativeIcons.folderPlus, shortcut: '⇧⌘N'),
    DDropdownMenuSub(
      trigger: const Text('Open Recent'),
      leading: const DIcon(DIcons.folderOpen),
      width: 160,
      children: [
        const DDropdownMenuLabel(child: Text('Recent Projects')),
        _item('Project Alpha', icon: DIcons.code),
        _item('Project Beta', icon: DIcons.code),
        DDropdownMenuSub(
          trigger: const Text('More Projects'),
          leading: const DIcon(DIcons.ellipsis),
          width: 144,
          children: [
            _item('Project Gamma', icon: DIcons.code),
            _item('Project Delta', icon: DIcons.code),
          ],
        ),
        const DDropdownMenuSeparator(),
        _item('Browse...', icon: DIcons.folder),
      ],
    ),
    const DDropdownMenuSeparator(),
    _item('Save', icon: DNativeIcons.floppyDisk, shortcut: '⌘S'),
    _item('Export', icon: DIcons.download, shortcut: '⇧⌘E'),
    const DDropdownMenuSeparator(),
    const DDropdownMenuLabel(child: Text('View')),
    DDropdownMenuCheckboxItem(
      checked: _email,
      onChanged: (value) => setState(() => _email = value),
      leading: const DIcon(DNativeIcons.eye),
      child: const Text('Show Sidebar'),
    ),
    DDropdownMenuCheckboxItem(
      checked: _sms,
      onChanged: (value) => setState(() => _sms = value),
      leading: const DIcon(DNativeIcons.tableCellsLarge),
      child: const Text('Show Status Bar'),
    ),
    DDropdownMenuSub(
      trigger: const Text('Theme'),
      leading: const DIcon(DNativeIcons.palette),
      children: [
        const DDropdownMenuLabel(child: Text('Appearance')),
        DDropdownMenuRadioGroup<String>(
          value: _theme,
          onChanged: (value) => setState(() => _theme = value),
          children: const [
            DDropdownMenuRadioItem(
              value: 'light',
              leading: DIcon(DNativeIcons.sun),
              child: Text('Light'),
            ),
            DDropdownMenuRadioItem(
              value: 'dark',
              leading: DIcon(DNativeIcons.moon),
              child: Text('Dark'),
            ),
            DDropdownMenuRadioItem(
              value: 'system',
              leading: DIcon(DIcons.display),
              child: Text('System'),
            ),
          ],
        ),
      ],
    ),
    const DDropdownMenuSeparator(),
    const DDropdownMenuLabel(child: Text('Account')),
    _item('Profile', icon: DIcons.user, shortcut: '⇧⌘P'),
    _item('Billing', icon: DNativeIcons.creditCard),
    DDropdownMenuSub(
      trigger: const Text('Settings'),
      leading: const DIcon(DIcons.gear),
      width: 176,
      children: [
        const DDropdownMenuLabel(child: Text('Preferences')),
        _item('Keyboard Shortcuts', icon: DNativeIcons.keyboard),
        _item('Language', icon: DNativeIcons.language),
        DDropdownMenuSub(
          trigger: const Text('Notifications'),
          leading: const DIcon(DIcons.farBell),
          width: 192,
          children: _checkboxIcons,
        ),
        const DDropdownMenuSeparator(),
        _item('Privacy & Security', icon: DNativeIcons.shieldHalved),
      ],
    ),
    const DDropdownMenuSeparator(),
    _item('Help & Support', icon: DIcons.circleQuestion),
    _item('Documentation', icon: DIcons.fileLines),
    const DDropdownMenuSeparator(),
    _item(
      'Sign Out',
      icon: DIcons.rightFromBracket,
      shortcut: '⇧⌘Q',
      destructive: true,
    ),
  ];

  List<Widget> get _rtl => [
    const DDropdownMenuLabel(child: Text('الحساب')),
    _item('الملف الشخصي', icon: DIcons.user, shortcut: '⇧⌘P'),
    _item('الفوترة', icon: DNativeIcons.creditCard),
    DDropdownMenuSub(
      trigger: const Text('الإعدادات'),
      leading: const DIcon(DIcons.gear),
      width: 144,
      children: [_item('الفريق'), _item('دعوة المستخدمين')],
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuCheckboxItem(
      checked: _statusBar,
      onChanged: (value) => setState(() => _statusBar = value),
      child: const Text('شريط الحالة'),
    ),
    const DDropdownMenuSeparator(),
    _item('تسجيل الخروج', icon: DIcons.rightFromBracket, destructive: true),
  ];

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final menu = switch (kind) {
      _DropdownExampleKind.composition => _menu(
        triggerLabel: 'Open',
        children: _composition,
      ),
      _DropdownExampleKind.basic => _menu(
        triggerLabel: 'Open',
        children: _basic,
      ),
      _DropdownExampleKind.submenu => _menu(
        triggerLabel: 'Open',
        children: _submenu,
      ),
      _DropdownExampleKind.shortcuts => _menu(
        triggerLabel: 'Open',
        children: _shortcuts,
      ),
      _DropdownExampleKind.icons => _menu(
        triggerLabel: 'Open',
        children: _icons,
      ),
      _DropdownExampleKind.checkboxes => _menu(
        triggerLabel: 'Open',
        children: _checkboxes,
      ),
      _DropdownExampleKind.checkboxIcons => _menu(
        triggerLabel: 'Notifications',
        width: 192,
        children: _checkboxIcons,
      ),
      _DropdownExampleKind.radio => _menu(
        triggerLabel: 'Open',
        children: _radio,
      ),
      _DropdownExampleKind.radioIcons => _menu(
        triggerLabel: 'Payment Method',
        width: 224,
        children: _radioIcons,
      ),
      _DropdownExampleKind.destructive => _menu(
        triggerLabel: 'Actions',
        children: _destructive,
      ),
      _DropdownExampleKind.avatar => _menu(
        triggerLabel: 'Account',
        align: DPopoverAlign.end,
        children: _avatar,
        trigger: DButton.iconOnly(
          icon: const DAvatar(fallback: DAvatarFallback(child: Text('LR'))),
          tooltip: 'Open account menu',
          variant: DButtonVariant.ghost,
          borderRadius: BorderRadius.circular(999),
          onPressed: null,
        ),
      ),
      _DropdownExampleKind.complex => _menu(
        triggerLabel: 'Complex Menu',
        width: 176,
        children: _complex,
      ),
      _DropdownExampleKind.rtl => Directionality(
        textDirection: TextDirection.rtl,
        child: _menu(triggerLabel: 'افتح القائمة', children: _rtl),
      ),
    };
    // Avatar needs the trigger builder's live callback; keep the avatar as the
    // button label rather than introducing a second action surface.
    final resolved = kind == _DropdownExampleKind.avatar
        ? DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: 'Account menu',
              align: DPopoverAlign.end,
              children: _avatar,
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => DButton.iconOnly(
                icon: const DAvatar(
                  fallback: DAvatarFallback(child: Text('LR')),
                ),
                tooltip: 'Open account menu',
                variant: DButtonVariant.ghost,
                borderRadius: BorderRadius.circular(999),
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                onPressed: state.toggle,
              ),
            ),
          )
        : menu;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        resolved,
        if (kind != _DropdownExampleKind.composition ||
            _status != 'No action selected') ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_status)),
        ],
      ],
    );
  }
}

const _usageCode = r'''DDropdownMenu(
  content: DDropdownMenuContent(
    width: 160,
    align: DPopoverAlign.start,
    children: [
      DDropdownMenuGroup(children: [
        DDropdownMenuLabel(child: Text('My Account')),
        DDropdownMenuItem(
          onPressed: openProfile,
          trailing: DDropdownMenuShortcut('⇧⌘P'),
          child: Text('Profile'),
        ),
        DDropdownMenuItem(
          onPressed: openBilling,
          trailing: DDropdownMenuShortcut('⌘B'),
          child: Text('Billing'),
        ),
        DDropdownMenuItem(
          onPressed: openSettings,
          trailing: DDropdownMenuShortcut('⌘S'),
          child: Text('Settings'),
        ),
      ]),
      DDropdownMenuSeparator(),
      DDropdownMenuGroup(children: [
        DDropdownMenuItem(onPressed: openTeam, child: Text('Team')),
        DDropdownMenuSub(
          trigger: Text('Invite users'),
          children: [
            DDropdownMenuItem(onPressed: inviteByEmail, child: Text('Email')),
            DDropdownMenuItem(onPressed: inviteByMessage, child: Text('Message')),
            DDropdownMenuSeparator(),
            DDropdownMenuItem(onPressed: showMore, child: Text('More...')),
          ],
        ),
        DDropdownMenuItem(
          onPressed: createTeam,
          trailing: DDropdownMenuShortcut('⌘+T'),
          child: Text('New Team'),
        ),
      ]),
      DDropdownMenuSeparator(),
      DDropdownMenuGroup(children: [
        DDropdownMenuItem(onPressed: openGitHub, child: Text('GitHub')),
        DDropdownMenuItem(onPressed: openSupport, child: Text('Support')),
        DDropdownMenuItem(child: Text('API')),
      ]),
      DDropdownMenuSeparator(),
      DDropdownMenuGroup(children: [
        DDropdownMenuItem(
          onPressed: logOut,
          trailing: DDropdownMenuShortcut('⇧⌘Q'),
          child: Text('Log out'),
        ),
      ]),
    ],
  ),
  child: DDropdownMenuTrigger(
    builder: (context, menu) => DButton(
      label: const Text('Open'),
      variant: DButtonVariant.outline,
      focusNode: menu.focusNode,
      hasPopup: true,
      expanded: menu.open,
      onPressed: menu.toggle,
    ),
  ),
)''';

const _guideCode = """
DDropdownMenuGroup(
  showGuide: true,
  semanticLabel: 'Top periods',
  children: [
    DDropdownMenuItem(onPressed: selectYear, child: Text('Year')),
    DDropdownMenuItem(onPressed: selectMonth, child: Text('Month')),
  ],
)
""";
