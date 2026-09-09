import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

const _assets = 'packages/discourse_native/src/styleguide/assets/item/';

final itemExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'Content with media, a title, a description, and actions.',
  notes:
      'Source implementation ready; reference/native review pending. Item is '
      'passive unless onPressed is supplied. Link navigation remains caller-owned. '
      'Use Field for editable inputs. Default and sm share padding; sm changes '
      'image and group sizing. Native large text reflows and removes clamps. '
      'At narrow widths content and actions stack. All artwork is bundled from '
      'the reference sources. Button remains baseline; its outline/ghost variants '
      'and round icon buttons await reconciliation. Dropdown Menu is unmerged: '
      'the Dropdown example uses an explicitly temporary MenuAnchor with actual '
      'passive Items. It is not a completed Dropdown Menu port.',
  examples: [
    for (final kind in [
      'Basic',
      'Variant',
      'Size',
      'Icon',
      'Avatar',
      'Image',
      'Group',
      'Header',
      'Link',
      'Dropdown',
      'RTL',
      'Composition',
      'States',
    ])
      StyleguideExample(
        title: kind,
        description: _descriptions[kind]!,
        code: _codes[kind]!,
        builder: (_) => _ItemExample(kind: kind),
      ),
  ],
);

const _descriptions = {
  'Basic':
      'Frozen Basic Item and verified profile link; actions report locally.',
  'Variant': 'Default, outline and muted at the reference 448px width.',
  'Size':
      'Default, sm and xs. Notice the smaller description and zero content gap in xs.',
  'Icon':
      'Security Alert with the reference ShieldAlert artwork and Review action.',
  'Avatar':
      'Evil Rabbit and overlapping team avatars. Invite actions update local status.',
  'Image':
      'Three song links with bundled grayscale reference artwork and trailing duration.',
  'Group':
      'People at 384px, followed by an explicit ItemSeparator composition.',
  'Header':
      'Three model cards with full-width reference photos. Narrow widths reflow the grid.',
  'Link': 'Documentation and external-resource links dispatch local callbacks.',
  'Dropdown':
      'Temporary native menu composition; select a person. Dropdown Menu visuals await its owner.',
  'RTL':
      'Frozen Arabic basic and verified items with directional content and action placement.',
  'Composition':
      'All parts: full-width header/footer, avatar, two content columns and independent action.',
  'States':
      'Enabled and disabled links; a secondary action does not open the row. Tab and Return/Space work independently.',
};

const _codes = {
  'Basic': """DItem(variant: DItemVariant.outline, children: [
  DItemContent(children: [DItemTitle(child: Text('Basic Item')),
    DItemDescription(child: Text('A simple item with title and description.'))]),
  DItemActions(children: [DButton(onPressed: action, label: Text('Action'))]),
])""",
  'Variant': """DItem(variant: DItemVariant.muted, children: [
  DItemMedia(variant: DItemMediaVariant.icon, child: inboxIcon),
  DItemContent(children: [DItemTitle(child: Text('Muted Variant')),
    DItemDescription(child: Text('Muted background for secondary content.'))]),
]) // Also standard and outline.""",
  'Size':
      """DItem(size: DItemSize.xs, variant: DItemVariant.outline, children: [
  DItemMedia(variant: DItemMediaVariant.icon, child: inboxIcon),
  DItemContent(children: [DItemTitle(child: Text('Extra Small Size')),
    DItemDescription(child: Text('The most compact size available.'))]),
]) // Also standard and sm.""",
  'Icon': """DItem(variant: DItemVariant.outline, children: [
  DItemMedia(variant: DItemMediaVariant.icon, child: shieldAlertIcon),
  DItemContent(children: [DItemTitle(child: Text('Security Alert')),
    DItemDescription(child: Text('New login detected from unknown device.'))]),
  DItemActions(children: [DButton(onPressed: review, label: Text('Review'))]),
])""",
  'Avatar': """DItem(variant: DItemVariant.outline, children: [
  DItemMedia(variant: DItemMediaVariant.avatar, child: DAvatar(
    size: DAvatarSize.lg, image: DAvatarImage(image: AssetImage(
      'packages/discourse_native/src/styleguide/assets/item/evilrabbit.png')),
    fallback: DAvatarFallback(child: Text('ER')))),
  DItemContent(children: [DItemTitle(child: Text('Evil Rabbit')),
    DItemDescription(child: Text('Last seen 5 months ago'))]),
  DItemActions(children: [DButton(onPressed: invite, label: Text('Invite'))]),
])""",
  'Image': """DItemGroup(children: songs.map((song) => DItem(
  variant: DItemVariant.outline, link: true, onPressed: () => play(song),
  children: [DItemMedia(variant: DItemMediaVariant.image, child: song.artwork),
    DItemContent(children: [DItemTitle(child: Text(song.title)),
      DItemDescription(child: Text(song.artist))]),
    DItemContent(children: [DItemDescription(child: Text(song.duration))]),
  ],
)).toList())""",
  'Group': """DItemGroup(children: [
  DItem(children: [DItemContent(children: [DItemTitle(child: Text('shadcn'))])]),
  DItemSeparator(),
  DItem(children: [DItemContent(children: [DItemTitle(child: Text('maxleiter'))])]),
])""",
  'Header': """DItem(variant: DItemVariant.outline,
  header: DItemHeader(child: DAspectRatio(ratio: 1, child: Image.asset(
    'packages/discourse_native/src/styleguide/assets/item/model-sm.jpg', fit: BoxFit.cover))),
  children: [DItemContent(children: [DItemTitle(child: Text('v0-1.5-sm')),
    DItemDescription(child: Text('Everyday tasks and UI generation.'))])],
)""",
  'Link': """DItem(link: true, onPressed: openDocumentation, children: [
  DItemContent(children: [DItemTitle(child: Text('Visit our documentation')),
    DItemDescription(child: Text('Learn how to get started with our components.'))]),
  DItemActions(children: [chevronRightIcon]),
])""",
  'Dropdown':
      """// Temporary MenuAnchor until Dropdown Menu merges. Menu owns interaction.
MenuAnchor(menuChildren: [
  MenuItemButton(onPressed: selectPerson, child: SizedBox(width: 192,
    child: DItem(size: DItemSize.xs, padding: EdgeInsets.all(8), children: [
      DItemMedia(child: avatar26),
      DItemContent(spacing: 0, children: [DItemTitle(child: Text('shadcn')),
        DItemDescription(height: 1, child: Text('shadcn@vercel.com'))]),
    ]))),
], builder: (context, controller, child) => DButton(label: Text('Select'),
  onPressed: () => controller.isOpen ? controller.close() : controller.open()))""",
  'RTL': """DDirection(textDirection: TextDirection.rtl, child: DItem(
  variant: DItemVariant.outline, children: [DItemContent(children: [
    DItemTitle(child: Text('عنصر أساسي')),
    DItemDescription(child: Text('عنصر بسيط يحتوي على عنوان ووصف.'))]),
    DItemActions(children: [DButton(onPressed: action, label: Text('إجراء'))]),
  ]))""",
  'Composition': """DItem(variant: DItemVariant.outline,
  header: DItemHeader(child: Text('Project membership')),
  footer: DItemFooter(child: Text('Invited today')),
  children: [DItemMedia(child: avatar),
    DItemContent(children: [DItemTitle(child: Text('Evil Rabbit')),
      DItemDescription(child: Text('Design team'))]),
    DItemContent(children: [DItemDescription(child: Text('Owner'))]),
    DItemActions(children: [DButton(onPressed: manage, label: Text('Manage'))]),
  ])""",
  'States': """DItem(link: true, enabled: enabled, onPressed: open, children: [
  DItemContent(children: [DItemTitle(child: Text('Project'))]),
  DItemActions(children: [DButton(onPressed: save, label: Text('Save'))]),
]) // Disabling the row does not disable independently owned child actions.""",
};

class _ItemExample extends StatefulWidget {
  const _ItemExample({required this.kind});
  final String kind;
  @override
  State<_ItemExample> createState() => _ItemExampleState();
}

class _ItemExampleState extends State<_ItemExample> {
  String _status = '';
  void _notice(String value) => setState(() => _status = value);
  Widget _action(String label) => DButton(
    size: DButtonSize.small,
    label: Text(label),
    onPressed: () => _notice('$label selected'),
  );
  Widget _icon(String name, {double size = 16}) => SvgPicture.asset(
    '$_assets$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      DTokens.of(context).foreground,
      BlendMode.srcIn,
    ),
  );
  Widget _avatar(String name, {double dimension = 32}) => DAvatar(
    dimension: dimension,
    image: DAvatarImage(image: AssetImage('$_assets$name.png')),
    fallback: DAvatarFallback(child: Text(name.substring(0, 1).toUpperCase())),
  );
  DItemContent _content(String title, [String? description]) => DItemContent(
    children: [
      DItemTitle(child: Text(title)),
      if (description != null) DItemDescription(child: Text(description)),
    ],
  );
  Widget _basic({bool arabic = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DItem(
        variant: DItemVariant.outline,
        children: [
          _content(
            arabic ? 'عنصر أساسي' : 'Basic Item',
            arabic
                ? 'عنصر بسيط يحتوي على عنوان ووصف.'
                : 'A simple item with title and description.',
          ),
          DItemActions(children: [_action(arabic ? 'إجراء' : 'Action')]),
        ],
      ),
      const SizedBox(height: 24),
      DItem(
        variant: DItemVariant.outline,
        size: DItemSize.sm,
        link: true,
        onPressed: () => _notice('Profile opened'),
        children: [
          DItemMedia(child: _icon('badge-check', size: 20)),
          _content(
            arabic
                ? 'تم التحقق من ملفك الشخصي.'
                : 'Your profile has been verified.',
          ),
          DItemActions(children: [_icon('chevron-right')]),
        ],
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final content = switch (widget.kind) {
      'Basic' => _basic(),
      'RTL' => DDirection(
        textDirection: TextDirection.rtl,
        child: _basic(arabic: true),
      ),
      'Variant' => _spaced([
        for (final entry in [
          (
            DItemVariant.standard,
            'Default Variant',
            'Transparent background with no border.',
          ),
          (
            DItemVariant.outline,
            'Outline Variant',
            'Outlined style with a visible border.',
          ),
          (
            DItemVariant.muted,
            'Muted Variant',
            'Muted background for secondary content.',
          ),
        ])
          DItem(
            variant: entry.$1,
            children: [
              DItemMedia(
                variant: DItemMediaVariant.icon,
                child: _icon('inbox'),
              ),
              _content(entry.$2, entry.$3),
            ],
          ),
      ]),
      'Size' => _spaced([
        for (final entry in [
          (
            DItemSize.standard,
            'Default Size',
            'The standard size for most use cases.',
          ),
          (DItemSize.sm, 'Small Size', 'A compact size for dense layouts.'),
          (
            DItemSize.xs,
            'Extra Small Size',
            'The most compact size available.',
          ),
        ])
          DItem(
            size: entry.$1,
            variant: DItemVariant.outline,
            children: [
              DItemMedia(
                variant: DItemMediaVariant.icon,
                child: _icon('inbox'),
              ),
              _content(entry.$2, entry.$3),
            ],
          ),
      ]),
      'Icon' => DItem(
        variant: DItemVariant.outline,
        children: [
          DItemMedia(
            variant: DItemMediaVariant.icon,
            child: _icon('shield-alert'),
          ),
          _content('Security Alert', 'New login detected from unknown device.'),
          DItemActions(children: [_action('Review')]),
        ],
      ),
      'Avatar' => _spaced([
        DItem(
          variant: DItemVariant.outline,
          children: [
            DItemMedia(
              variant: DItemMediaVariant.avatar,
              child: _avatar('evilrabbit', dimension: 40),
            ),
            _content('Evil Rabbit', 'Last seen 5 months ago'),
            DItemActions(
              children: [
                DButton(
                  size: DButtonSize.small,
                  label: const SizedBox.shrink(),
                  semanticLabel: 'Invite',
                  icon: _icon('plus'),
                  onPressed: () => _notice('Invite selected'),
                ),
              ],
            ),
          ],
        ),
        DItem(
          variant: DItemVariant.outline,
          children: [
            DItemMedia(
              variant: DItemMediaVariant.avatar,
              child: DAvatarGroup(
                children: [
                  for (final person in ['shadcn', 'maxleiter', 'evilrabbit'])
                    _avatar(person),
                ],
              ),
            ),
            _content(
              'No Team Members',
              'Invite your team to collaborate on this project.',
            ),
            DItemActions(children: [_action('Invite')]),
          ],
        ),
      ]),
      'Image' => DItemGroup(
        children: [
          for (final (i, song) in [
            ('Midnight City Lights', 'Neon Dreams', 'Electric Nights', '3:45'),
            (
              'Coffee Shop Conversations',
              'The Morning Brew',
              'Urban Stories',
              '4:05',
            ),
            ('Digital Rain', 'Cyber Symphony', 'Binary Beats', '3:30'),
          ].indexed)
            DItem(
              variant: DItemVariant.outline,
              link: true,
              onPressed: () => _notice('Playing ${song.$1}'),
              children: [
                DItemMedia(
                  variant: DItemMediaVariant.image,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      .2126,
                      .7152,
                      .0722,
                      0,
                      0,
                      .2126,
                      .7152,
                      .0722,
                      0,
                      0,
                      .2126,
                      .7152,
                      .0722,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
                    child: SvgPicture.asset(
                      '${_assets}song-$i.svg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                DItemContent(
                  children: [
                    DItemTitle(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${song.$1} - '),
                            TextSpan(
                              text: song.$3,
                              style: TextStyle(
                                color: DTokens.of(context).mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DItemDescription(child: Text(song.$2)),
                  ],
                ),
                DItemContent(
                  children: [DItemDescription(child: Text(song.$4))],
                ),
              ],
            ),
        ],
      ),
      'Group' => DItemGroup(
        children: [
          for (final person in ['shadcn', 'maxleiter', 'evilrabbit'])
            DItem(
              variant: DItemVariant.outline,
              children: [
                DItemMedia(child: _avatar(person)),
                _content(person, '$person@vercel.com'),
                DItemActions(
                  children: [
                    DButton(
                      label: const SizedBox.shrink(),
                      semanticLabel: 'Invite $person',
                      icon: _icon('plus'),
                      onPressed: () => _notice('Invited $person'),
                    ),
                  ],
                ),
              ],
            ),
          const DItemSeparator(),
          DItem(children: [_content('End of members')]),
        ],
      ),
      'Header' => LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final model in [
              ('sm', 'v0-1.5-sm', 'Everyday tasks and UI generation.'),
              ('lg', 'v0-1.5-lg', 'Advanced thinking or reasoning.'),
              ('mini', 'v0-2.0-mini', 'Open Source model for everyone.'),
            ])
              SizedBox(
                width: constraints.maxWidth < 400
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 32) / 3,
                child: DItem(
                  variant: DItemVariant.outline,
                  header: DItemHeader(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        DTokens.of(context).radius * .6,
                      ),
                      child: DAspectRatio(
                        ratio: 1,
                        child: Image.asset(
                          '${_assets}model-${model.$1}.jpg',
                          fit: BoxFit.cover,
                          semanticLabel: model.$2,
                        ),
                      ),
                    ),
                  ),
                  children: [_content(model.$2, model.$3)],
                ),
              ),
          ],
        ),
      ),
      'Link' => DItemGroup(
        children: [
          DItem(
            link: true,
            onPressed: () => _notice('Documentation opened locally'),
            children: [
              _content(
                'Visit our documentation',
                'Learn how to get started with our components.',
              ),
              DItemActions(children: [_icon('chevron-right')]),
            ],
          ),
          DItem(
            variant: DItemVariant.outline,
            link: true,
            onPressed: () => _notice('External resource selected locally'),
            children: [
              _content(
                'External resource',
                'Opens in a new tab with security attributes.',
              ),
              DItemActions(children: [_icon('external-link')]),
            ],
          ),
        ],
      ),
      'Dropdown' => MenuAnchor(
        menuChildren: [
          for (final person in ['shadcn', 'maxleiter', 'evilrabbit'])
            MenuItemButton(
              onPressed: () => _notice('Selected $person'),
              child: SizedBox(
                width: 192,
                child: DItem(
                  size: DItemSize.xs,
                  padding: const EdgeInsets.all(8),
                  children: [
                    DItemMedia(child: _avatar(person, dimension: 26)),
                    DItemContent(
                      spacing: 0,
                      children: [
                        DItemTitle(child: Text(person)),
                        DItemDescription(
                          height: 1,
                          child: Text('$person@vercel.com'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        builder: (context, controller, _) => DButton(
          label: const Text('Select'),
          icon: _icon('chevron-down'),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
      'Composition' => DItem(
        variant: DItemVariant.outline,
        header: const DItemHeader(child: Text('Project membership')),
        footer: const DItemFooter(child: Text('Invited today')),
        children: [
          DItemMedia(child: _avatar('evilrabbit')),
          _content('Evil Rabbit', 'Design team'),
          const DItemContent(
            children: [DItemDescription(child: Text('Owner'))],
          ),
          DItemActions(children: [_action('Manage')]),
        ],
      ),
      _ => DItemGroup(
        children: [
          for (final enabled in [true, false])
            DItem(
              link: true,
              enabled: enabled,
              variant: DItemVariant.outline,
              onPressed: () => _notice('Project opened'),
              children: [
                _content(
                  enabled ? 'Project' : 'Project unavailable',
                  'Save is an independent action.',
                ),
                DItemActions(children: [_action('Save')]),
              ],
            ),
        ],
      ),
    };
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: switch (widget.kind) {
            'Header' => 576,
            'Icon' || 'Avatar' => 512,
            'Group' => 384,
            _ => 448,
          },
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(_status)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _spaced(List<Widget> children) =>
      DItemGroup(spacing: 24, children: children);
}
