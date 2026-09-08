import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../styleguide_example.dart';

/// In-memory 32px checker artwork: no asset lookup or runtime network dependency.
final avatarExampleImage = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAQklEQVR4nGPYcvgsVqRr7ogVkaqeYdSCUQuGgAXUMgiX+lELRi0YChZQyyBc6kctGLVgKFhALYNwqR+1YNSCIWABAON20kz/K2ydAAAAAElFTkSuQmCC',
  ),
);

final avatarExamples = ComponentExamples(
  description:
      'An image, fallback, and badge for representing a person or group.',
  status: ComponentStatus.implemented,
  notes:
      'Installation: import package:discourse_native/discourse_ui.dart. '
      'Composition: DAvatar(image: DAvatarImage(image: provider), fallback: '
      'DAvatarFallback(child: Text("CN")), badge: DAvatarBadge()). '
      'The provider is supplied by the caller; app networking stays in AvatarImage. '
      'Reference sm/default/lg diameters are 24/32/40px; initials 12/14/14px; '
      'groups overlap 8px and rings are 2px. Circles stay circular independent '
      'of the configured radius; forum adapters may explicitly use rounded squares. '
      'Unconstrained library avatars grow with accessibility text above 100% '
      'so initials remain readable. Fixed app dimensions remain caller-owned. '
      'Checker artwork is embedded local PNG data, identical in both app profiles. '
      'Button and Dropdown Menu are pending catalogue owners: the dropdown '
      'below uses the available DButton and native MenuAnchor/MenuItemButton. '
      'Their ghost/icon/destructive props are not Avatar variants.',
  examples: [
    StyleguideExample(
      title: 'Basic and composition',
      description:
          'A decoded local image, initials when no image is supplied, '
          'and an icon fallback. Named avatars expose one stable identity; '
          'decorative avatars defer naming to adjacent text or the action owner.',
      states: const ['Image', 'Fallback', 'Decorative', 'Composition'],
      code:
          '''// provider is a local MemoryImage or AssetImage supplied by the caller.
DAvatar(
  semanticLabel: 'Community member',
  image: DAvatarImage(image: provider),
  fallback: const DAvatarFallback(child: Text('CN')),
)''',
      builder: (_) => Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DAvatar(
            semanticLabel: 'Community member',
            image: DAvatarImage(image: avatarExampleImage),
            fallback: const DAvatarFallback(child: Text('CN')),
          ),
          const DAvatar(
            semanticLabel: 'Evil Rabbit',
            fallback: DAvatarFallback(child: Text('ER')),
          ),
          const DAvatar(
            decorative: true,
            fallback: DAvatarFallback(child: Icon(Icons.person_outline)),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Badge and badge with icon',
      description:
          'Dot, plus icon and custom count badges. A status name conveys '
          'the dot’s meaning without relying on color. Small reference badges hide icons.',
      states: const ['Dot', 'Icon', 'Count', 'Sizes'],
      code: '''const DAvatar(
  semanticLabel: 'Pranathi',
  fallback: DAvatarFallback(child: Text('PP')),
  badge: DAvatarBadge(semanticLabel: 'Add member', icon: AvatarExamplePlusIcon()),
)

// AvatarExamplePlusIcon uses the local Lucide SVG helper shown below.
$_plusUsage''',
      builder: (context) => Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          DAvatar(
            semanticLabel: 'Online member',
            fallback: const DAvatarFallback(child: Text('ER')),
            badge: DAvatarBadge(
              backgroundColor: DTokens.of(context).primary,
              semanticLabel: 'Online',
            ),
          ),
          for (final size in DAvatarSize.values)
            DAvatar(
              size: size,
              semanticLabel: 'Pranathi',
              fallback: const DAvatarFallback(child: Text('PP')),
              badge: const DAvatarBadge(
                semanticLabel: 'Add member',
                icon: AvatarExamplePlusIcon(),
              ),
            ),
          const DAvatar(
            semanticLabel: 'Notifications',
            fallback: DAvatarFallback(child: Text('CN')),
            badge: DAvatarBadge(
              dimension: 16,
              semanticLabel: '3 unread notifications',
              child: Text('3'),
            ),
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Avatar group, count and icon',
      description:
          'Three identities overlap in reading order. Counts inherit '
          'the explicit group size. Narrow groups wrap, preserving full names '
          'and separate action owners if interactive children are supplied.',
      states: const ['Group', 'Group count', 'Group icon', 'Sizes', 'Narrow'],
      code: '''const DAvatarGroup(children: [
  DAvatar(semanticLabel: 'Chris', fallback: DAvatarFallback(child: Text('CN'))),
  DAvatar(semanticLabel: 'Lee', fallback: DAvatarFallback(child: Text('LR'))),
  DAvatarGroupCount(semanticLabel: '3 more members', child: Text('+3')),
  DAvatarGroupCount(semanticLabel: 'More members', child: AvatarExamplePlusIcon()),
])

$_plusUsage''',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final size in DAvatarSize.values) ...[
            DAvatarGroup(
              size: size,
              children: [
                for (final name in ['CN', 'LR', 'ER'])
                  DAvatar(
                    size: size,
                    semanticLabel: name,
                    fallback: DAvatarFallback(child: Text(name)),
                  ),
                const DAvatarGroupCount(
                  semanticLabel: '3 more members',
                  child: Text('+3'),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          const DAvatarGroup(
            children: [
              DAvatar(
                semanticLabel: 'Chris',
                fallback: DAvatarFallback(child: Text('CN')),
              ),
              DAvatar(
                semanticLabel: 'Lee',
                fallback: DAvatarFallback(child: Text('LR')),
              ),
              DAvatarGroupCount(
                semanticLabel: 'More members',
                child: AvatarExamplePlusIcon(),
              ),
            ],
          ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Sizes',
      description:
          'The same local image and fallback at sm, default and lg. '
          'Use the text-scale control to inspect readable initials at 200%.',
      states: const ['sm', 'default', 'lg', 'Text scaling'],
      code: '''const Wrap(spacing: 8, children: [
  DAvatar(size: DAvatarSize.sm, fallback: DAvatarFallback(child: Text('CN'))),
  DAvatar(fallback: DAvatarFallback(child: Text('CN'))),
  DAvatar(size: DAvatarSize.lg, fallback: DAvatarFallback(child: Text('CN'))),
])''',
      builder: (_) => Wrap(
        spacing: 8,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final size in DAvatarSize.values)
            DAvatar(
              size: size,
              image: DAvatarImage(image: avatarExampleImage),
              semanticLabel: size.name,
              fallback: const DAvatarFallback(child: Text('CN')),
            ),
          for (final size in DAvatarSize.values)
            DAvatar(
              size: size,
              semanticLabel: size.name,
              fallback: const DAvatarFallback(child: Text('CN')),
            ),
        ],
      ),
    ),
    StyleguideExample(
      title: 'Image loading and error',
      description:
          'Switch between local image, absent image, and invalid local '
          'bytes. The fallback returns on failure. Preview settings preserve '
          'this selection; Reset alone reconstructs it. Status is reported below.',
      states: const ['Loading', 'Error', 'Ready', 'Replacement', 'State'],
      code: '''DAvatar(
  semanticLabel: 'Local member',
  image: DAvatarImage(image: provider, onStatusChanged: (status) {
    setState(() => message = status.name);
  }),
  fallback: const DAvatarFallback(
    delay: Duration(milliseconds: 200), child: Text('CN'),
  ),
)''',
      builder: (_) => const _ImageStates(),
    ),
    StyleguideExample(
      title: 'Dropdown',
      description:
          'Tab to the avatar, press Enter, select a local menu action, '
          'or dismiss with Escape/outside click. DButton and MenuAnchor own '
          'focus, keyboard input and restoration. Menu visuals are temporary '
          'pending Dropdown Menu; actions affect only this example.',
      states: const ['Keyboard', 'Focus', 'Menu', 'Composition'],
      code: '''// Own and dispose triggerFocus in the surrounding State.
MenuAnchor(
  childFocusNode: triggerFocus,
  menuChildren: [MenuItemButton(onPressed: openProfile, child: const Text('Profile'))],
  builder: (context, controller, child) => DButton(
    focusNode: triggerFocus,
    semanticLabel: 'Open member menu',
    label: const DAvatar(decorative: true, fallback: DAvatarFallback(child: Text('CN'))),
    onPressed: () => controller.isOpen ? controller.close() : controller.open(),
  ),
)''',
      builder: (_) => const _AvatarMenu(),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'Arabic initials, a trailing status badge and a localized '
          'count. The group starts on the right and overlaps toward the left.',
      states: const ['RTL', 'Arabic', 'Group', 'Badge'],
      code: '''const DDirection(textDirection: TextDirection.rtl, child:
  DAvatarGroup(children: [
    DAvatar(semanticLabel: 'نور', fallback: DAvatarFallback(child: Text('ن')),
      badge: DAvatarBadge(semanticLabel: 'متصل')),
    DAvatar(semanticLabel: 'ليلى', fallback: DAvatarFallback(child: Text('ل'))),
    DAvatarGroupCount(semanticLabel: 'ثلاثة أعضاء آخرين', child: Text('+٣')),
  ]),
)''',
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: DAvatarGroup(
          children: [
            DAvatar(
              semanticLabel: 'نور',
              fallback: DAvatarFallback(child: Text('ن')),
              badge: DAvatarBadge(semanticLabel: 'متصل'),
            ),
            DAvatar(
              semanticLabel: 'ليلى',
              fallback: DAvatarFallback(child: Text('ل')),
            ),
            DAvatarGroupCount(
              semanticLabel: 'ثلاثة أعضاء آخرين',
              child: Text('+٣'),
            ),
          ],
        ),
      ),
    ),
  ],
);

class _ImageStates extends StatefulWidget {
  const _ImageStates();
  @override
  State<_ImageStates> createState() => _ImageStatesState();
}

class _ImageStatesState extends State<_ImageStates> {
  int _selected = 0;
  String _status = 'loading';
  final _invalid = MemoryImage(base64Decode('AA=='));
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DAvatar(
        semanticLabel: 'Local member',
        image: _selected == 1
            ? null
            : DAvatarImage(
                image: _selected == 2 ? _invalid : avatarExampleImage,
                onStatusChanged: (status) {
                  if (_status != status.name) {
                    setState(() => _status = status.name);
                  }
                },
              ),
        fallback: const DAvatarFallback(
          delay: Duration(milliseconds: 200),
          child: Text('CN'),
        ),
      ),
      const SizedBox(height: 12),
      Text('Image: ${_selected == 1 ? 'absent' : _status}'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < 3; i++)
            DButton(
              label: Text(['Ready image', 'No image', 'Broken image'][i]),
              onPressed: () => setState(() => _selected = i),
            ),
        ],
      ),
    ],
  );
}

class _AvatarMenu extends StatefulWidget {
  const _AvatarMenu();
  @override
  State<_AvatarMenu> createState() => _AvatarMenuState();
}

class _AvatarMenuState extends State<_AvatarMenu> {
  final _focus = FocusNode();
  String _action = 'No action selected';
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MenuAnchor(
        childFocusNode: _focus,
        menuChildren: [
          for (final action in ['Profile', 'Billing', 'Settings', 'Log out'])
            MenuItemButton(
              onPressed: () => setState(() => _action = '$action selected'),
              child: Text(action),
            ),
        ],
        builder: (context, controller, child) => DButton(
          focusNode: _focus,
          semanticLabel: 'Open member menu',
          variant: DButtonVariant.transparent,
          borderRadius: BorderRadius.circular(999),
          label: const DAvatar(
            decorative: true,
            fallback: DAvatarFallback(child: Text('CN')),
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
      const SizedBox(height: 12),
      Text(_action),
    ],
  );
}

/// Exact Lucide plus SVG. ISC/MIT attribution is retained in
/// docs/component-library/evidence/avatar/lucide-LICENSE.txt.
class AvatarExamplePlusIcon extends StatelessWidget {
  const AvatarExamplePlusIcon({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>',
      width: theme.size,
      height: theme.size,
      colorFilter: ColorFilter.mode(theme.color!, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}

const _plusUsage = '''// import 'package:flutter_svg/flutter_svg.dart';
// Lucide plus: ISC/MIT, Lucide Contributors and Cole Bemis.
class AvatarExamplePlusIcon extends StatelessWidget {
  const AvatarExamplePlusIcon({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>',
      width: theme.size, height: theme.size,
      colorFilter: ColorFilter.mode(theme.color!, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}''';
